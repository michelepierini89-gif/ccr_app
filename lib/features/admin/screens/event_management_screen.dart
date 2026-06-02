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
  bool _uploadingTrack = false;
  ParsedTrack? _parsedTrack;

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

    setState(() => _uploadingTrack = true);
    try {
      final content = utf8.decode(bytes);
      final ext = (picked.extension ?? 'gpx').toLowerCase();
      final parsed = ext == 'gpx'
          ? GpxParser.parseGpx(content)
          : GpxParser.parseKml(content);

      // Upload to storage
      final url = await StorageService().uploadTrack(event.id, bytes, ext);
      await ref.read(firestoreServiceProvider).updateEvent(
            event.copyWith(trackUrl: url),
          );
      setState(() => _parsedTrack = parsed);

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
      if (mounted) setState(() => _uploadingTrack = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<EventModel?>(
      stream: ref
          .watch(firestoreServiceProvider)
          .getEvents()
          .map((list) =>
              list.where((e) => e.id == widget.eventId).isNotEmpty
                  ? list.firstWhere((e) => e.id == widget.eventId)
                  : null),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body:
                Center(child: CircularProgressIndicator(color: AppColors.accent)),
          );
        }
        final event = snap.data;
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
              tabs: const [
                Tab(text: 'Tracciato'),
                Tab(text: 'Iscrizioni'),
                Tab(text: 'Live'),
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
                      uploadingTrack: _uploadingTrack,
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
                    RegistrationsScreen(eventId: event.id),
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!trackAvailable) ...[
            const SizedBox(height: 48),
            Center(
              child: Column(
                children: [
                  const Icon(Icons.map_outlined,
                      color: AppColors.textSecondary, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Nessun tracciato caricato',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Carica un file GPX o KML',
                    style:
                        TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  if (uploadingTrack)
                    const CircularProgressIndicator(
                        color: AppColors.accent)
                  else
                    ElevatedButton.icon(
                      onPressed: onPickTrack,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Carica tracciato GPX/KML'),
                    ),
                ],
              ),
            ),
          ] else ...[
            if (parsedTrack != null) ...[
              SizedBox(
                height: 300,
                child: TrackMapScreen(
                  trackPoints: parsedTrack!.points,
                  specials: event.speciali,
                  waypoints: parsedTrack!.waypoints,
                  interactive: true,
                ),
              ),
            ] else ...[
              Container(
                height: 200,
                color: AppColors.cardBackground,
                child: const Center(
                  child: Text(
                    'Tracciato caricato su server.\nRicarica il file per visualizzarlo.',
                    style: TextStyle(
                        color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onManageSpecials,
                          icon: const Icon(Icons.edit_location_alt),
                          label: const Text('Gestisci Speciali'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: uploadingTrack ? null : onPickTrack,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Sostituisci'),
                      ),
                    ],
                  ),
                  if (event.speciali.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Speciali',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ...event.speciali.map((s) => SpecialTile(special: s)),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
