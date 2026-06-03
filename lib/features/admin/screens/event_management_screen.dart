import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/models/event_model.dart';
import '../../../core/services/gpx_parser.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../map/screens/track_map_screen.dart';
import '../providers/admin_provider.dart';
import '../widgets/special_tile.dart';
import 'registrations_screen.dart';
import 'live_tracking_screen.dart';
import 'specials_editor_screen.dart';

class EventManagementScreen extends ConsumerStatefulWidget {
  final String eventId;
  const EventManagementScreen({super.key, required this.eventId});

  @override
  ConsumerState<EventManagementScreen> createState() =>
      _EventManagementScreenState();
}

class _EventManagementScreenState
    extends ConsumerState<EventManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isTrackLoading = false;
  ParsedTrack? _parsedTrack;
  String? _loadedTrackUrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Tab _buildLockedTab(String text, bool locked) {
    if (!locked) return Tab(text: text);
    return Tab(
      child: Tooltip(
        message: 'Pubblica l\'evento per attivare questa sezione',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(width: 4),
            const Icon(Icons.lock_outline,
                size: 11, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Color _statusColor(EventStatus s) {
    switch (s) {
      case EventStatus.bozza:
        return AppColors.textSecondary;
      case EventStatus.aperto:
        return AppColors.success;
      case EventStatus.inCorso:
        return AppColors.accent;
      case EventStatus.concluso:
        return AppColors.warning;
    }
  }

  String _statusLabel(EventStatus s) {
    switch (s) {
      case EventStatus.bozza:
        return 'BOZZA';
      case EventStatus.aperto:
        return 'APERTO';
      case EventStatus.inCorso:
        return 'IN CORSO';
      case EventStatus.concluso:
        return 'CONCLUSO';
    }
  }

  Future<void> _updateStatus(
      BuildContext context, EventModel event, EventStatus newStatus) async {
    try {
      await ref
          .read(firestoreServiceProvider)
          .updateEvent(event.copyWith(stato: newStatus));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Errore: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _autoLoadTrack(String url) async {
    if (_isTrackLoading) return;
    setState(() {
      _isTrackLoading = true;
      _loadedTrackUrl = url;
    });
    try {
      final bytes = await StorageService().downloadTrack(url);
      final content = utf8.decode(bytes);
      final ext = url.contains('track.kml') ? 'kml' : 'gpx';
      final parsed = ext == 'gpx'
          ? GpxParser.parseGpx(content)
          : GpxParser.parseKml(content);
      if (mounted) setState(() => _parsedTrack = parsed);
    } catch (e) {
      if (mounted) {
        setState(() => _loadedTrackUrl = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Errore caricamento tracciato: $e'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Riprova',
            textColor: Colors.white,
            onPressed: () => _autoLoadTrack(url),
          ),
        ));
      }
    } finally {
      if (mounted) setState(() => _isTrackLoading = false);
    }
  }

  Future<void> _pickAndUploadTrack(
      BuildContext context, EventModel event) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx', 'kml'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) return;

    setState(() => _isTrackLoading = true);
    try {
      final content = utf8.decode(bytes);
      final ext = (picked.extension ?? 'gpx').toLowerCase();
      final parsed = ext == 'gpx'
          ? GpxParser.parseGpx(content)
          : GpxParser.parseKml(content);

      final url = await StorageService().uploadTrack(event.id, bytes, ext);
      await ref.read(firestoreServiceProvider).updateEvent(
            event.copyWith(trackUrl: url),
          );
      if (mounted) {
        setState(() {
          _parsedTrack = parsed;
          _loadedTrackUrl = url;
        });
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tracciato caricato con successo!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore caricamento tracciato: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isTrackLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventStreamProvider(widget.eventId));

    return eventAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
            child: CircularProgressIndicator(color: AppColors.accent)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child:
              Text('Errore: $e', style: const TextStyle(color: AppColors.error)),
        ),
      ),
      data: (event) {
        if (event == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            body: const Center(
              child: Text('Evento non trovato',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          );
        }

        // Auto-load track from Storage when URL is available but track not yet parsed
        if (event.trackUrl != null &&
            _parsedTrack == null &&
            _loadedTrackUrl != event.trackUrl &&
            !_isTrackLoading) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _autoLoadTrack(event.trackUrl!));
        }

        final statusColor = _statusColor(event.stato);
        final trackAvailable =
            _parsedTrack != null || event.trackUrl != null;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(event.nome),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            bottom: TabBar(
              controller: _tabController,
              onTap: (index) {
                if (index > 0 && event.stato == EventStatus.bozza) {
                  WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _tabController.animateTo(0));
                }
              },
              tabs: [
                const Tab(text: 'Tracciato'),
                _buildLockedTab('Iscrizioni', event.stato == EventStatus.bozza),
                _buildLockedTab('Live', event.stato == EventStatus.bozza),
              ],
            ),
          ),
          body: Column(
            children: [
              // Event header
              Container(
                color: AppColors.cardBackground,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.calendar_today,
                                      color: AppColors.textSecondary,
                                      size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    DateFormat('dd/MM/yyyy')
                                        .format(event.data),
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13),
                                  ),
                                  const SizedBox(width: 12),
                                  const Icon(Icons.location_on,
                                      color: AppColors.textSecondary,
                                      size: 14),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      event.luogo,
                                      style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Status dropdown
                        DropdownButton<EventStatus>(
                          value: event.stato,
                          dropdownColor: AppColors.cardBackground,
                          style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                          underline: const SizedBox(),
                          items: EventStatus.values
                              .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(
                                      _statusLabel(s),
                                      style: TextStyle(
                                        color: _statusColor(s),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (s) {
                            if (s != null && s != event.stato) {
                              _updateStatus(context, event, s);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // --- Tracciato tab ---
                    _TracciatoTab(
                      event: event,
                      parsedTrack: _parsedTrack,
                      trackAvailable: trackAvailable,
                      uploadingTrack: _isTrackLoading,
                      onPickTrack: () =>
                          _pickAndUploadTrack(context, event),
                      onManageSpecials: () {
                        if (_parsedTrack != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SpecialsEditorScreen(
                                eventId: event.id,
                                parsedTrack: _parsedTrack!,
                                event: event,
                              ),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Carica prima un tracciato GPX/KML'),
                            ),
                          );
                        }
                      },
                    ),
                    // --- Iscrizioni tab ---
                    RegistrationsScreen(
                      eventId: event.id,
                      minSquadra: event.minSquadra,
                      maxSquadra: event.maxSquadra,
                    ),
                    // --- Live tab ---
                    LiveTrackingScreen(eventId: event.id),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TracciatoTab extends StatelessWidget {
  final EventModel event;
  final ParsedTrack? parsedTrack;
  final bool trackAvailable;
  final bool uploadingTrack;
  final VoidCallback onPickTrack;
  final VoidCallback onManageSpecials;

  const _TracciatoTab({
    required this.event,
    required this.parsedTrack,
    required this.trackAvailable,
    required this.uploadingTrack,
    required this.onPickTrack,
    required this.onManageSpecials,
  });

  Widget _mapWidget() => parsedTrack != null
      ? TrackMapScreen(
          trackPoints: parsedTrack!.points,
          specials: event.speciali,
          waypoints: parsedTrack!.waypoints,
          interactive: true,
        )
      : Container(
          color: AppColors.cardBackground,
          child: Center(
            child: uploadingTrack
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: AppColors.accent),
                      SizedBox(height: 12),
                      Text('Caricamento tracciato...',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 40),
                      const SizedBox(height: 12),
                      const Text('Errore caricamento',
                          style: TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: onPickTrack,
                        child: const Text('Carica manualmente',
                            style: TextStyle(color: AppColors.accent)),
                      ),
                    ],
                  ),
          ),
        );

  Widget _controlsColumn() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: parsedTrack != null ? onManageSpecials : null,
            icon: const Icon(Icons.edit_location_alt),
            label: const Text('Gestisci Speciali'),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 52)),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: uploadingTrack ? null : onPickTrack,
            icon: const Icon(Icons.upload_file),
            label: Text(parsedTrack != null
                ? 'Sostituisci tracciato'
                : 'Carica tracciato GPX/KML'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
          ),
          if (parsedTrack != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.route, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text('${parsedTrack!.points.length} punti GPS',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ],
          // Event details
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(Icons.group,
                    'Squadra: ${event.minSquadra}–${event.maxSquadra} persone'),
                const SizedBox(height: 6),
                _InfoRow(Icons.leaderboard, event.tipologiaClassifica.label),
              ],
            ),
          ),
          if (event.speciali.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Speciali',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...event.speciali.map((s) => SpecialTile(special: s)),
          ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (!trackAvailable) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.map_outlined,
                color: AppColors.textSecondary, size: 64),
            const SizedBox(height: 16),
            const Text('Nessun tracciato caricato',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Carica un file GPX o KML',
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            if (uploadingTrack)
              const CircularProgressIndicator(color: AppColors.accent)
            else
              ElevatedButton.icon(
                onPressed: onPickTrack,
                icon: const Icon(Icons.upload_file),
                label: const Text('Carica tracciato GPX/KML'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 52)),
              ),
          ],
        ),
      );
    }

    return LayoutBuilder(builder: (ctx, constraints) {
      final isWide = constraints.maxWidth >= 600;
      final mapSide = isWide
          ? (constraints.maxWidth * 0.6).clamp(200.0, 700.0)
          : constraints.maxWidth;

      if (!isWide) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: mapSide, height: mapSide, child: _mapWidget()),
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: _controlsColumn()),
            ],
          ),
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: constraints.maxWidth - mapSide,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _controlsColumn(),
            ),
          ),
          SizedBox(width: mapSide, height: mapSide, child: _mapWidget()),
        ],
      );
    });
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ),
        ],
      );
}
