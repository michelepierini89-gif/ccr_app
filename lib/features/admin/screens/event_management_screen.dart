import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/waypoint_model.dart';
import '../../../core/services/gpx_parser.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/firebase_error_handler.dart';
import '../../../core/utils/gpx_utils.dart';
import '../../map/screens/track_map_screen.dart';
import '../providers/admin_provider.dart';
import '../widgets/special_tile.dart';
import 'registrations_screen.dart';
import 'live_tracking_screen.dart';
import 'specials_editor_screen.dart';
import 'starting_order_screen.dart';
import '../../classifica/screens/classifica_screen.dart';
import '../../timing/screens/timing_screen.dart';

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
    _tabController = TabController(length: 5, vsync: this);
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(text,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                  overflow: TextOverflow.ellipsis),
            ),
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
      case EventStatus.archiviata:
        return AppColors.textSecondary;
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
      case EventStatus.archiviata:
        return 'ARCHIVIATA';
    }
  }

  Future<void> _deleteEvent(BuildContext context, EventModel event) async {
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Elimina evento',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Vuoi eliminare "${event.nome}"? Questa azione non può essere annullata.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continua',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (first != true || !context.mounted) return;

    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Conferma eliminazione',
            style: TextStyle(color: AppColors.error)),
        content: const Text(
          'Sei sicuro? L\'evento e tutti i suoi dati verranno eliminati definitivamente.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error),
            child: const Text('Elimina definitivamente'),
          ),
        ],
      ),
    );
    if (second != true || !context.mounted) return;

    try {
      await ref.read(firestoreServiceProvider).deleteEvent(event.id);
      if (context.mounted) context.go('/admin');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(FirebaseErrorHandler.getMessage(e)),
          backgroundColor: AppColors.error,
        ));
      }
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
              content: Text(FirebaseErrorHandler.getMessage(e)),
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
          content: Text(FirebaseErrorHandler.getMessage(e)),
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
          content: Text(FirebaseErrorHandler.getMessage(e)),
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
            actions: [
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'Penalità evento',
                onPressed: () =>
                    context.push('/admin/event/${event.id}/penalty-settings'),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                tooltip: 'Elimina evento',
                onPressed: () => _deleteEvent(context, event),
              ),
            ],
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
                _buildLockedTab('Classifica', event.stato == EventStatus.bozza),
                _buildLockedTab('Tempi', event.stato == EventStatus.bozza),
              ],
            ),
          ),
          body: Column(
            children: [
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
                        if (event.stato == EventStatus.archiviata)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppColors.textSecondary
                                      .withValues(alpha: 0.35)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.archive_outlined,
                                    size: 13,
                                    color: AppColors.textSecondary),
                                SizedBox(width: 4),
                                Text(
                                  'ARCHIVIATA',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          DropdownButton<EventStatus>(
                            value: event.stato,
                            dropdownColor: AppColors.cardBackground,
                            style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                            underline: const SizedBox(),
                            items: EventStatus.values
                                .where(
                                    (s) => s != EventStatus.archiviata)
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
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      StartingOrderScreen(event: event),
                                ),
                              ),
                              icon: const Icon(Icons.flag_circle_outlined,
                                  color: AppColors.accent),
                              label: const Text('Ordine di partenza',
                                  style: TextStyle(color: AppColors.accent)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: AppColors.accent),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: RegistrationsScreen(
                            eventId: event.id,
                            minSquadra: event.minSquadra,
                            maxSquadra: event.maxSquadra,
                          ),
                        ),
                      ],
                    ),
                    LiveTrackingScreen(eventId: event.id),
                    ClassificaScreen(
                        eventId: event.id, showAppBar: false),
                    TimingScreen(
                        eventId: event.id, adminView: true),
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

// ── Tracciato tab ─────────────────────────────────────────────────────────────

class _TracciatoTab extends ConsumerStatefulWidget {
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
  ConsumerState<_TracciatoTab> createState() => _TracciatoTabState();
}

class _TracciatoTabState extends ConsumerState<_TracciatoTab> {
  double? _totalLength;
  int _minSquadra = 1;
  int _maxSquadra = 4;
  TipologiaClassifica _tipologia = TipologiaClassifica.sommaTempi;
  int _maxRaceTimeH = 4;
  int _maxRaceTimeM = 30;
  Timer? _squadraDebounce;
  Timer? _tipologiaDebounce;
  Timer? _maxRaceDebounce;

  @override
  void initState() {
    super.initState();
    _minSquadra = widget.event.minSquadra;
    _maxSquadra = widget.event.maxSquadra;
    _tipologia = widget.event.tipologiaClassifica;
    _maxRaceTimeH = widget.event.maxRaceTimeMinutes ~/ 60;
    _maxRaceTimeM = widget.event.maxRaceTimeMinutes % 60;
    _totalLength = _computeTotalLength();
  }

  @override
  void didUpdateWidget(_TracciatoTab old) {
    super.didUpdateWidget(old);
    if (old.parsedTrack != widget.parsedTrack) {
      setState(() => _totalLength = _computeTotalLength());
    }
    if (_squadraDebounce == null || !_squadraDebounce!.isActive) {
      if (widget.event.minSquadra != _minSquadra ||
          widget.event.maxSquadra != _maxSquadra) {
        setState(() {
          _minSquadra = widget.event.minSquadra;
          _maxSquadra = widget.event.maxSquadra;
        });
      }
    }
    if (_tipologiaDebounce == null || !_tipologiaDebounce!.isActive) {
      if (widget.event.tipologiaClassifica != _tipologia) {
        setState(() => _tipologia = widget.event.tipologiaClassifica);
      }
    }
    if (_maxRaceDebounce == null || !_maxRaceDebounce!.isActive) {
      final h = widget.event.maxRaceTimeMinutes ~/ 60;
      final m = widget.event.maxRaceTimeMinutes % 60;
      if (h != _maxRaceTimeH || m != _maxRaceTimeM) {
        setState(() {
          _maxRaceTimeH = h;
          _maxRaceTimeM = m;
        });
      }
    }
  }

  @override
  void dispose() {
    _squadraDebounce?.cancel();
    _tipologiaDebounce?.cancel();
    _maxRaceDebounce?.cancel();
    super.dispose();
  }

  // ── Geometry helpers ───────────────────────────────────────────────────────

  double _haversineMeters(LatLng a, LatLng b) {
    const R = 6371000.0;
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final sinDLat = sin(dLat / 2);
    final sinDLng = sin(dLng / 2);
    final aVal =
        sinDLat * sinDLat + cos(lat1) * cos(lat2) * sinDLng * sinDLng;
    return R * 2 * atan2(sqrt(aVal), sqrt(1 - aVal));
  }

  double? _computeTotalLength() {
    final pts = widget.parsedTrack?.points;
    if (pts == null || pts.length < 2) return null;
    double total = 0.0;
    for (int i = 1; i < pts.length; i++) {
      total += _haversineMeters(pts[i - 1], pts[i]);
    }
    return total / 1000.0;
  }

  double _sectionLength(int startIdx, int endIdx) {
    final pts = widget.parsedTrack!.points;
    final a = min(startIdx, endIdx);
    final b = max(startIdx, endIdx);
    if (a < 0 || b >= pts.length || a == b) return 0.0;
    double total = 0.0;
    for (int i = a; i < b; i++) {
      total += _haversineMeters(pts[i], pts[i + 1]);
    }
    return total / 1000.0;
  }

  int _ensureTrackIdx(WaypointModel wp) {
    final m = RegExp(r'track_pt_(\d+)$').firstMatch(wp.id);
    if (m != null) return int.tryParse(m.group(1)!) ?? 0;
    final pts = widget.parsedTrack!.points;
    var minDist = double.infinity;
    var minIdx = 0;
    for (var i = 0; i < pts.length; i++) {
      final dlat = wp.lat - pts[i].latitude;
      final dlng = wp.lng - pts[i].longitude;
      final d = dlat * dlat + dlng * dlng;
      if (d < minDist) {
        minDist = d;
        minIdx = i;
      }
    }
    return minIdx;
  }

  // ── Debounced saves ────────────────────────────────────────────────────────

  void _onSquadraChanged() {
    _squadraDebounce?.cancel();
    _squadraDebounce = Timer(const Duration(milliseconds: 800), () {
      ref
          .read(firestoreServiceProvider)
          .updateEvent(widget.event
              .copyWith(minSquadra: _minSquadra, maxSquadra: _maxSquadra))
          .catchError((e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(FirebaseErrorHandler.getMessage(e)),
            backgroundColor: AppColors.error,
          ));
        }
      });
    });
  }

  void _onMaxRaceTimeChanged() {
    _maxRaceDebounce?.cancel();
    _maxRaceDebounce = Timer(const Duration(milliseconds: 800), () {
      final totalMinutes = _maxRaceTimeH * 60 + _maxRaceTimeM;
      if (totalMinutes < 30) return;
      ref
          .read(firestoreServiceProvider)
          .updateEvent(widget.event
              .copyWith(maxRaceTimeMinutes: totalMinutes))
          .catchError((e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(FirebaseErrorHandler.getMessage(e)),
            backgroundColor: AppColors.error,
          ));
        }
      });
    });
  }

  void _onTipologiaChanged(TipologiaClassifica t) {
    setState(() => _tipologia = t);
    _tipologiaDebounce?.cancel();
    _tipologiaDebounce = Timer(const Duration(milliseconds: 800), () {
      ref
          .read(firestoreServiceProvider)
          .updateEvent(
              widget.event.copyWith(tipologiaClassifica: _tipologia))
          .catchError((e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(FirebaseErrorHandler.getMessage(e)),
            backgroundColor: AppColors.error,
          ));
        }
      });
    });
  }

  // ── Fuel point ─────────────────────────────────────────────────────────────

  Future<void> _showFuelPointDialog() async {
    final pts = widget.parsedTrack?.points ?? [];
    final result = await showDialog<LatLng>(
      context: context,
      builder: (_) => _FuelPointDialog(
        trackPoints: pts,
        initial: widget.event.fuelPoint?.latLng,
      ),
    );
    if (result == null || !mounted) return;
    final wp = WaypointModel(
      id: 'fuel_point',
      nome: 'Punto ristoro',
      lat: result.latitude,
      lng: result.longitude,
      type: WaypointType.intermedio,
    );
    try {
      await ref
          .read(firestoreServiceProvider)
          .updateEvent(widget.event.copyWith(fuelPoint: wp));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Errore salvataggio: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Future<void> _removeFuelPoint() async {
    try {
      await ref
          .read(firestoreServiceProvider)
          .updateEvent(widget.event.copyWith(clearFuelPoint: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(FirebaseErrorHandler.getMessage(e)),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  // ── Map widget ─────────────────────────────────────────────────────────────

  Widget _mapWidget() {
    if (widget.parsedTrack != null) {
      return TrackMapScreen(
        trackPoints: widget.parsedTrack!.points,
        specials: widget.event.speciali,
        waypoints: [
          ...widget.parsedTrack!.waypoints,
          ...widget.event.speciali
              .expand((s) => [s.waypointInizio, s.waypointFine]),
        ],
        fuelPoint: widget.event.fuelPoint,
        dangerPoints: widget.event.dangerPoints,
        interactive: true,
      );
    }
    return Container(
      color: AppColors.cardBackground,
      child: Center(
        child: widget.uploadingTrack
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.accent),
                  SizedBox(height: 12),
                  Text('Caricamento tracciato...',
                      style: TextStyle(color: AppColors.textSecondary)),
                ],
              )
            : widget.trackAvailable
                // URL present but parse failed
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 40),
                      const SizedBox(height: 12),
                      const Text('Errore caricamento',
                          style: TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: widget.onPickTrack,
                        child: const Text('Carica manualmente',
                            style: TextStyle(color: AppColors.accent)),
                      ),
                    ],
                  )
                // No track at all
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map_outlined,
                          color: AppColors.textSecondary, size: 48),
                      SizedBox(height: 8),
                      Text('Nessun tracciato',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
      ),
    );
  }

  // ── Controls column ────────────────────────────────────────────────────────

  Widget _buildControlsColumn() {
    final parsedTrack = widget.parsedTrack;
    final event = widget.event;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Track actions ──
        ElevatedButton.icon(
          onPressed: parsedTrack != null ? widget.onManageSpecials : null,
          icon: const Icon(Icons.edit_location_alt),
          label: const Text('Gestisci Speciali'),
          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 52)),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: widget.uploadingTrack ? null : widget.onPickTrack,
          icon: const Icon(Icons.upload_file),
          label: Text(parsedTrack != null
              ? 'Sostituisci tracciato'
              : 'Carica tracciato GPX/KML'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
        ),

        // ── Track stats ──
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
                const Icon(Icons.route,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text('${parsedTrack.points.length} punti GPS',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                if (_totalLength != null) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '${_totalLength!.toStringAsFixed(1)} km totali',
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],

        // ── Punto ristoro ──
        const SizedBox(height: 16),
        _SectionLabel('Punto ristoro'),
        const SizedBox(height: 8),
        if (event.fuelPoint != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.local_gas_station,
                    color: Colors.amber.shade600, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${event.fuelPoint!.lat.toStringAsFixed(5)}, '
                    '${event.fuelPoint!.lng.toStringAsFixed(5)}',
                    style: TextStyle(
                        color: Colors.amber.shade200, fontSize: 11),
                  ),
                ),
                InkWell(
                  onTap: _showFuelPointDialog,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.edit,
                        size: 16, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: _removeFuelPoint,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close,
                        size: 16, color: AppColors.error),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        OutlinedButton.icon(
          onPressed: _showFuelPointDialog,
          icon: Icon(Icons.local_gas_station,
              color: Colors.amber.shade600, size: 18),
          label: Text(
            event.fuelPoint != null
                ? 'Modifica punto ristoro'
                : 'Aggiungi punto ristoro',
            style: TextStyle(color: Colors.amber.shade600),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.amber.withValues(alpha: 0.5)),
            minimumSize: const Size(0, 44),
          ),
        ),

        // ── Configurazione evento ──
        const SizedBox(height: 20),
        _SectionLabel('Dimensione squadra'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StepperField(
                label: 'Minimo',
                value: _minSquadra,
                min: 1,
                max: _maxSquadra,
                onChanged: (v) {
                  setState(() => _minSquadra = v);
                  _onSquadraChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StepperField(
                label: 'Massimo',
                value: _maxSquadra,
                min: _minSquadra,
                max: 4,
                onChanged: (v) {
                  setState(() => _maxSquadra = v);
                  _onSquadraChanged();
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),
        _SectionLabel('Tipologia punteggio'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButton<TipologiaClassifica>(
            value: _tipologia,
            isExpanded: true,
            dropdownColor: AppColors.cardBackground,
            underline: const SizedBox(),
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 13),
            items: TipologiaClassifica.values
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(t.label,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 13)),
                    ))
                .toList(),
            onChanged: (t) {
              if (t != null) _onTipologiaChanged(t);
            },
          ),
        ),

        // ── Tempo massimo gara ──
        const SizedBox(height: 16),
        _SectionLabel('Tempo massimo gara'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StepperField(
                label: 'Ore',
                value: _maxRaceTimeH,
                min: 0,
                max: 12,
                onChanged: (v) {
                  setState(() => _maxRaceTimeH = v);
                  _onMaxRaceTimeChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StepperField(
                label: 'Min (×5)',
                value: _maxRaceTimeM,
                min: 0,
                max: 55,
                step: 5,
                onChanged: (v) {
                  setState(() => _maxRaceTimeM = v);
                  _onMaxRaceTimeChanged();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${_maxRaceTimeH}h ${_maxRaceTimeM.toString().padLeft(2, '0')}min'
          ' — ${_maxRaceTimeH * 60 + _maxRaceTimeM} min totali',
          style: const TextStyle(color: AppColors.accent, fontSize: 11),
        ),

        // ── Specials list ──
        if (event.speciali.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              const Text('Speciali',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              if (_totalLength != null) ...[
                const Spacer(),
                Text(
                  '${event.speciali.length} prove',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ...event.speciali.map((s) {
            double? len;
            var dangerCount = 0;
            if (parsedTrack != null && parsedTrack.points.isNotEmpty) {
              final a = _ensureTrackIdx(s.waypointInizio);
              final b = _ensureTrackIdx(s.waypointFine);
              len = _sectionLength(a, b);
              dangerCount = GpxUtils.countDangerPointsInSpecial(
                  s, event.dangerPoints, parsedTrack.points);
            }
            return SpecialTile(special: s, lengthKm: len, dangerCount: dangerCount);
          }),
        ],
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final isWide = constraints.maxWidth >= 600;
      final mapSide = isWide
          ? (constraints.maxWidth * 0.6).clamp(200.0, 700.0)
          : constraints.maxWidth;
      // Map height for mobile: compact when no track, full when available
      final mapH = widget.trackAvailable
          ? (constraints.maxWidth * 0.75).clamp(220.0, 420.0)
          : 160.0;

      if (!isWide) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: mapSide, height: mapH, child: _mapWidget()),
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildControlsColumn()),
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
              child: _buildControlsColumn(),
            ),
          ),
          SizedBox(width: mapSide, height: mapSide, child: _mapWidget()),
        ],
      );
    });
  }
}

// ── Fuel point dialog ─────────────────────────────────────────────────────────

class _FuelPointDialog extends StatefulWidget {
  final List<LatLng> trackPoints;
  final LatLng? initial;

  const _FuelPointDialog({required this.trackPoints, this.initial});

  @override
  State<_FuelPointDialog> createState() => _FuelPointDialogState();
}

class _FuelPointDialogState extends State<_FuelPointDialog> {
  LatLng? _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial;
  }

  void _onMapTap(LatLng ll) {
    if (widget.trackPoints.isEmpty) {
      setState(() => _picked = ll);
      return;
    }
    final snapped = GpxUtils.snapToTrack(ll, widget.trackPoints);
    final distance = GpxUtils.distanceToTrack(ll, snapped);
    if (distance > AppConstants.trackSnapMaxDistanceMeters) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Il punto deve essere vicino al percorso'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    setState(() => _picked = snapped);
  }

  MapOptions get _mapOptions {
    if (widget.trackPoints.isNotEmpty) {
      return MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(widget.trackPoints),
          padding: const EdgeInsets.all(32),
        ),
        onTap: (_, ll) => _onMapTap(ll),
      );
    }
    return MapOptions(
      initialCenter: const LatLng(44.0, 11.0),
      initialZoom: 13,
      onTap: (_, ll) => _onMapTap(ll),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return Dialog(
      backgroundColor: AppColors.background,
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        height: screenH * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Icon(Icons.local_gas_station,
                      color: Colors.amber.shade600, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Punto ristoro',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _picked == null
                    ? 'Clicca sulla mappa per posizionare il punto ristoro'
                    : 'Punto selezionato — clicca di nuovo per spostarlo',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            // Map
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.precise,
                child: FlutterMap(
                  options: _mapOptions,
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.ccr.ccr_app',
                    ),
                    if (widget.trackPoints.isNotEmpty)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: widget.trackPoints,
                          color: AppColors.accent,
                          strokeWidth: 3,
                        ),
                      ]),
                    if (_picked != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: _picked!,
                          width: 44,
                          height: 52,
                          child: Column(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade700,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.amber
                                            .withValues(alpha: 0.6),
                                        blurRadius: 8)
                                  ],
                                ),
                                child: const Icon(Icons.local_gas_station,
                                    color: Colors.white, size: 20),
                              ),
                              const Text('Ristoro',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      shadows: [
                                        Shadow(
                                            color: Colors.black54,
                                            blurRadius: 2)
                                      ])),
                            ],
                          ),
                        ),
                      ]),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            // Actions
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Annulla'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _picked != null
                          ? () => Navigator.of(context).pop(_picked)
                          : null,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent),
                      child: const Text('Conferma'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3),
      );
}

class _StepperField extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final void Function(int) onChanged;

  const _StepperField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.step = 1,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: value > min ? () => onChanged(value - step) : null,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value > min
                        ? AppColors.accent.withValues(alpha: 0.15)
                        : AppColors.border,
                  ),
                  child: Icon(Icons.remove,
                      size: 16,
                      color: value > min
                          ? AppColors.accent
                          : AppColors.textSecondary),
                ),
              ),
              Text('$value',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              InkWell(
                onTap: value < max ? () => onChanged(value + step) : null,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value < max
                        ? AppColors.accent.withValues(alpha: 0.15)
                        : AppColors.border,
                  ),
                  child: Icon(Icons.add,
                      size: 16,
                      color: value < max
                          ? AppColors.accent
                          : AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
