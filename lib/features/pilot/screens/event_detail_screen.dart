import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/models/special_model.dart';
import '../../../core/models/team_model.dart';
import '../../../core/providers/offline_provider.dart';
import '../../../core/services/gpx_parser.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/gpx_utils.dart';
import '../../../core/utils/time_format_utils.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../auth/providers/auth_provider.dart';
import '../../admin/providers/admin_provider.dart';
import '../../map/danger_marker_icon.dart';
import '../../map/screens/track_map_screen.dart';
import '../../timing/screens/timing_screen.dart';
import '../providers/pilot_provider.dart';
import '../providers/training_stats_provider.dart';
import 'diagnostic_logs_screen.dart';
import 'race_result_screen.dart';

class EventDetailScreen extends ConsumerStatefulWidget {
  final String eventId;
  const EventDetailScreen({super.key, required this.eventId});

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  ParsedTrack? _parsedTrack;
  bool _isLoadingTrack = false;
  String? _loadedTrackUrl;

  Future<void> _autoLoadTrack(String url) async {
    if (_isLoadingTrack) return;
    setState(() {
      _isLoadingTrack = true;
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
    } catch (_) {
      if (mounted) setState(() => _loadedTrackUrl = null);
    } finally {
      if (mounted) setState(() => _isLoadingTrack = false);
    }
  }

  int? _indexFromId(String id) {
    final m = RegExp(r'track_pt_(\d+)$').firstMatch(id);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  double _haversineKm(LatLng a, LatLng b) {
    const R = 6371.0;
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

  int _nearestIdx(LatLng point, List<LatLng> pts) {
    var minDist = double.infinity;
    var minIdx = 0;
    for (var i = 0; i < pts.length; i++) {
      final dlat = point.latitude - pts[i].latitude;
      final dlng = point.longitude - pts[i].longitude;
      final d = dlat * dlat + dlng * dlng;
      if (d < minDist) {
        minDist = d;
        minIdx = i;
      }
    }
    return minIdx;
  }

  Widget _buildEventSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: double.infinity, height: 28),
          const SizedBox(height: 14),
          SkeletonBox(width: 200, height: 14),
          const SizedBox(height: 8),
          SkeletonBox(width: 150, height: 14),
          const SizedBox(height: 24),
          SkeletonBox(width: double.infinity, height: 200, radius: 12),
          const SizedBox(height: 24),
          SkeletonBox(width: 140, height: 20),
          const SizedBox(height: 12),
          SkeletonBox(width: double.infinity, height: 50, radius: 10),
          const SizedBox(height: 8),
          SkeletonBox(width: double.infinity, height: 50, radius: 10),
          const SizedBox(height: 8),
          SkeletonBox(width: double.infinity, height: 50, radius: 10),
        ],
      ),
    );
  }

  double? _specialLengthKm(SpecialModel s, List<LatLng> pts) {
    if (pts.isEmpty) return null;
    final startIdx = _indexFromId(s.waypointInizio.id) ??
        _nearestIdx(s.waypointInizio.latLng, pts);
    final endIdx = _indexFromId(s.waypointFine.id) ??
        _nearestIdx(s.waypointFine.latLng, pts);
    final a = min(startIdx, endIdx).clamp(0, pts.length - 1);
    final b = max(startIdx, endIdx).clamp(0, pts.length - 1);
    if (a >= b) return null;
    double total = 0.0;
    for (var i = a; i < b; i++) {
      total += _haversineKm(pts[i], pts[i + 1]);
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventStreamProvider(widget.eventId));

    return eventAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          title: const Text('Caricamento...'),
        ),
        body: _buildEventSkeleton(),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          title: const Text('Errore'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    color: AppColors.error, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'Impossibile caricare l\'evento',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Controlla la connessione e riprova.',
                  style: TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () =>
                      ref.invalidate(eventStreamProvider(widget.eventId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Riprova'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
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

        if (event.activeTrackUrl != null &&
            _parsedTrack == null &&
            _loadedTrackUrl != event.activeTrackUrl &&
            !_isLoadingTrack) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _autoLoadTrack(event.activeTrackUrl!));
        }

        final trackPoints = _parsedTrack?.points ?? const [];
        final showMap = event.activeSpeciali.isNotEmpty || event.activeTrackUrl != null;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(event.nome),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
          ),
          body: SafeArea(
            bottom: true,
            child: RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.cardBackground,
            onRefresh: () async {
              setState(() {
                _parsedTrack = null;
                _loadedTrackUrl = null;
              });
              if (event.activeTrackUrl != null) {
                await _autoLoadTrack(event.activeTrackUrl!);
              }
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Percorso alternativo (10/08/2026, Parte 4) — se è attiva
                // la variante B, il pilota deve capirlo SENZA doverlo
                // cercare: banner ben visibile in cima, prima di qualunque
                // altro contenuto.
                if (event.isRouteBActive)
                  _RouteBActiveBanner(
                    label: event.activeLabel,
                    changedAt: event.lastRouteChangeAt,
                  ),
                // Event header
                Container(
                  color: AppColors.cardBackground,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.nome,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              color: AppColors.textSecondary, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('EEEE d MMMM yyyy', 'it')
                                .format(event.data),
                            style: const TextStyle(
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              color: AppColors.textSecondary, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            event.luogo,
                            style: const TextStyle(
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      if (event.descrizione.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          event.descrizione,
                          style: const TextStyle(
                              color: AppColors.textSecondary, height: 1.5),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),

                // Track map
                if (showMap) ...[
                  _isLoadingTrack
                      ? Container(
                          height: 220,
                          color: AppColors.cardBackground,
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(
                                    color: AppColors.accent),
                                SizedBox(height: 8),
                                Text('Caricamento tracciato...',
                                    style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                        )
                      : SizedBox(
                          height: 220,
                          child: TrackMapScreen(
                            trackPoints: trackPoints,
                            specials: event.activeSpeciali,
                            waypoints: event.activeSpeciali
                                .expand((s) =>
                                    [s.waypointInizio, s.waypointFine])
                                .toList(),
                            fuelPoint: event.activeFuelPoint,
                            dangerPoints: event.activeDangerPoints,
                          ),
                        ),
                  const Divider(height: 1, color: AppColors.border),
                ],

                // Specials
                if (event.activeSpeciali.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: const Text(
                      'Prove Speciali',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: event.activeSpeciali.map((s) {
                        final kmLen = _specialLengthKm(s, trackPoints);
                        final cpCount = s.controlPoints.length;
                        final dangerCount = trackPoints.isNotEmpty
                            ? GpxUtils.countDangerPointsInSpecial(
                                s, event.activeDangerPoints, trackPoints)
                            : 0;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: s.color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: s.color.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                    color: s.color, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.nome,
                                      style: TextStyle(
                                        color: s.color,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (kmLen != null || cpCount > 0)
                                      Text(
                                        [
                                          if (kmLen != null)
                                            '${kmLen.toStringAsFixed(1)} km',
                                          if (cpCount > 0)
                                            '$cpCount punt${cpCount == 1 ? "o" : "i"} di controllo',
                                        ].join(' · '),
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    if (dangerCount > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const DangerMarkerIcon(size: 16),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Pericoli: $dangerCount',
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: AppColors.border),
                ],

                // Pilot registration section
                _PilotRegistrationSection(
                  eventId: widget.eventId,
                  eventNome: event.nome,
                  maxSquadra: event.maxSquadra,
                  isArchived: event.stato == EventStatus.archiviata,
                  isTraining: event.isAllenamento,
                ),
              ],
            ),
          ),
          ),
          ),
        );
      },
    );
  }
}

// ── Pilot registration section ────────────────────────────────────────────────

class _PilotRegistrationSection extends ConsumerStatefulWidget {
  final String eventId;
  final String eventNome;
  final int maxSquadra;
  final bool isArchived;
  final bool isTraining;

  const _PilotRegistrationSection({
    required this.eventId,
    required this.eventNome,
    required this.maxSquadra,
    this.isArchived = false,
    this.isTraining = false,
  });

  @override
  ConsumerState<_PilotRegistrationSection> createState() =>
      _PilotRegistrationSectionState();
}

class _PilotRegistrationSectionState
    extends ConsumerState<_PilotRegistrationSection> {
  bool _isLoading = false;
  bool _savedOffline = false;

  Future<void> _doRegister({
    required String userId,
    required String nome,
    required String cognome,
    TeamModel? existingTeam,
    String? newTeamName,
  }) async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(firestoreServiceProvider);
      String? squadraId;
      String? teamName;

      if (existingTeam != null) {
        await service.joinTeam(widget.eventId, existingTeam.id, userId);
        squadraId = existingTeam.id;
        teamName = existingTeam.nome;
      } else if (newTeamName != null && newTeamName.trim().isNotEmpty) {
        final team = TeamModel(
          id: '',
          nome: newTeamName.trim(),
          membriIds: [userId],
          createdBy: userId,
          eventId: widget.eventId,
        );
        squadraId = await service.createTeam(team);
        teamName = newTeamName.trim();
      }

      await service.registerForEvent(
        eventId: widget.eventId,
        userId: userId,
        nome: nome,
        cognome: cognome,
        squadraId: squadraId,
        teamName: teamName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Richiesta di iscrizione inviata all\'organizzatore!'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      // Nome squadra duplicato: mostra errore, non mettere in coda offline.
      if (e is Exception && e.toString().contains('team_name_exists')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
              'Esiste già una squadra con questo nome. '
              'Scegli un nome diverso o unisciti alla squadra esistente.',
            ),
            backgroundColor: AppColors.error,
            duration: Duration(seconds: 5),
          ));
        }
        return;
      }
      final queue = ref.read(offlineQueueProvider);
      if (existingTeam != null) {
        await queue.queueJoinTeam(
          eventId: widget.eventId,
          teamId: existingTeam.id,
          userId: userId,
        );
      }
      await queue.queueRegistration(
        eventId: widget.eventId,
        userId: userId,
        nome: nome,
        cognome: cognome,
        squadraId: existingTeam?.id,
        teamName: existingTeam?.nome ?? newTeamName?.trim(),
        createdAt: DateTime.now(),
      );
      if (mounted) setState(() => _savedOffline = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openRegistrationDialog(String userId, String nome,
      String cognome, String? preferredTeamName) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _RegistrationDialog(
        eventId: widget.eventId,
        eventNome: widget.eventNome,
        maxSquadra: widget.maxSquadra,
        userId: userId,
        userNome: nome,
        userCognome: cognome,
        preferredTeamName: preferredTeamName,
        onConfirm: (existingTeam, newTeamName) async {
          Navigator.of(ctx).pop();
          await _doRegister(
            userId: userId,
            nome: nome,
            cognome: cognome,
            existingTeam: existingTeam,
            newTeamName: newTeamName,
          );
        },
      ),
    );
  }

  Color _statusColor(RegistrationStatus s) => switch (s) {
        RegistrationStatus.inAttesa => AppColors.warning,
        RegistrationStatus.approvato => AppColors.success,
        RegistrationStatus.rifiutato => AppColors.error,
      };

  String _statusLabel(RegistrationStatus s) => switch (s) {
        RegistrationStatus.inAttesa => 'In attesa di approvazione',
        RegistrationStatus.approvato => 'Iscrizione approvata',
        RegistrationStatus.rifiutato => 'Iscrizione rifiutata',
      };

  IconData _statusIcon(RegistrationStatus s) => switch (s) {
        RegistrationStatus.inAttesa => Icons.hourglass_empty,
        RegistrationStatus.approvato => Icons.check_circle,
        RegistrationStatus.rifiutato => Icons.cancel,
      };

  @override
  Widget build(BuildContext context) {
    final regAsync =
        ref.watch(myRegistrationStreamProvider(widget.eventId));
    final teamsAsync = ref.watch(teamsProvider(widget.eventId));
    final userAsync = ref.watch(currentUserModelProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: AppColors.border),
          const SizedBox(height: 16),
          const Text(
            'Iscrizione',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_savedOffline) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cloud_off, color: AppColors.warning, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Iscrizione salvata offline — verrà inviata automaticamente quando la connessione sarà ripristinata.',
                      style: TextStyle(
                          color: AppColors.warning, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          userAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent)),
            error: (e, _) => const SizedBox(),
            data: (user) {
              if (user == null) return const SizedBox();
              return regAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.accent)),
                error: (e, _) => const SizedBox(),
                data: (reg) {
                  // ── Registered: show status ──────────────────────────
                  if (reg != null) {
                    final color = _statusColor(reg.stato);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: color),
                          ),
                          child: Row(
                            children: [
                              Icon(_statusIcon(reg.stato),
                                  color: color, size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _statusLabel(reg.stato),
                                      style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    if (reg.teamName != null)
                                      Text(
                                        'Squadra: ${reg.teamName}',
                                        style: TextStyle(
                                            color: color.withValues(
                                                alpha: 0.7),
                                            fontSize: 12),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Team info
                        if (reg.squadraId != null) ...[
                          const SizedBox(height: 12),
                          teamsAsync.when(
                            loading: () => const SizedBox(),
                            error: (e2, _) => const SizedBox(),
                            data: (teams) {
                              final team = teams
                                  .where((t) => t.id == reg.squadraId)
                                  .firstOrNull;
                              if (team == null) return const SizedBox();
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.cardBackground,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AppColors.border),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.group,
                                        color: AppColors.textSecondary,
                                        size: 16),
                                    const SizedBox(width: 8),
                                    Text(
                                      team.nome,
                                      style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${team.membriIds.length}/${widget.maxSquadra}',
                                      style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                        // Rifiniture Step 47 — miglior tempo personale e
                        // record squadra per PS, direttamente in pagina
                        // (senza passare dalle Statistiche): è
                        // l'informazione principale in un allenamento.
                        if (widget.isTraining &&
                            reg.stato == RegistrationStatus.approvato &&
                            reg.squadraId != null) ...[
                          const SizedBox(height: 12),
                          _TrainingBestTimesCard(eventId: widget.eventId),
                        ],
                        // GPS button for approved pilots
                        if (reg.stato == RegistrationStatus.approvato) ...[
                          const SizedBox(height: 16),
                          if (widget.isArchived)
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton.icon(
                                // Un allenamento chiuso non ha un "risultato
                                // di gara" (RaceResultScreen legge
                                // raceStatus/pilotTrack, mai scritti da un
                                // tentativo) — porta invece allo storico
                                // tentativi.
                                onPressed: () => widget.isTraining
                                    ? context.push(
                                        '/pilot/event/${widget.eventId}/attempts')
                                    : Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => RaceResultScreen(
                                              eventId: widget.eventId),
                                        ),
                                      ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const Icon(Icons.map_outlined),
                                label: const Text(
                                  'VEDI RISULTATI',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      letterSpacing: 1),
                                ),
                              ),
                            )
                          else
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton.icon(
                                onPressed: () => context.push(
                                    '/pilot/gps?eventId=${widget.eventId}'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const Icon(Icons.gps_fixed),
                                label: const Text(
                                  'AVVIA GPS',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      letterSpacing: 1),
                                ),
                              ),
                            ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (ctx) => Scaffold(
                                    appBar: AppBar(
                                        title:
                                            const Text('I miei tempi')),
                                    backgroundColor: AppColors.background,
                                    body: SafeArea(
                                      bottom: true,
                                      child: TimingScreen(
                                          eventId: widget.eventId,
                                          adminView: false),
                                    ),
                                  ),
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                    color: AppColors.accent
                                        .withValues(alpha: 0.6)),
                                foregroundColor: AppColors.accent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.timer, size: 18),
                              label: const Text('I MIEI TEMPI',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5)),
                            ),
                          ),
                          // Storico tentativi + log tecnici (punti 2/3 del
                          // test sul campo 22/08/2026) — solo allenamento,
                          // raggiungibile anche a evento chiuso da tempo
                          // (nessuna condizione su isArchived qui sotto).
                          if (widget.isTraining) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: OutlinedButton.icon(
                                onPressed: () => context.push(
                                    '/pilot/event/${widget.eventId}/attempts'),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                      color: AppColors.accent
                                          .withValues(alpha: 0.6)),
                                  foregroundColor: AppColors.accent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const Icon(Icons.history, size: 18),
                                label: const Text('I MIEI TENTATIVI',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5)),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: OutlinedButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const DiagnosticLogsScreen(),
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppColors.border),
                                  foregroundColor: AppColors.textSecondary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const Icon(Icons.bug_report_outlined,
                                    size: 18),
                                label: const Text('LOG TECNICI',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5)),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: OutlinedButton.icon(
                              onPressed: () => context.push(
                                '/pilot/event/${widget.eventId}/starting-order'),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                    color: AppColors.accent
                                        .withValues(alpha: 0.6)),
                                foregroundColor: AppColors.accent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.flag_outlined, size: 18),
                              label: const Text('PARTENZA',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5)),
                            ),
                          ),
                        ],
                      ],
                    );
                  }

                  // ── Not registered: single register button ───────────
                  if (widget.isArchived) return const SizedBox();
                  return Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading
                              ? null
                              : () => _openRegistrationDialog(
                                    user.id,
                                    user.nome,
                                    user.cognome,
                                    user.preferredTeamName,
                                  ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white),
                                )
                              : const Icon(Icons.how_to_reg),
                          label: const Text(
                            'ISCRIVITI',
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                letterSpacing: 1),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          // Classifica button — always visible
          const SizedBox(height: 8),
          const Divider(color: AppColors.border),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: () =>
                  context.push('/pilot/event/${widget.eventId}/classifica'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                    color: AppColors.accent.withValues(alpha: 0.6)),
                foregroundColor: AppColors.accent,
              ),
              icon: const Icon(Icons.leaderboard, size: 18),
              label: const Text('CLASSIFICA',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ),
          ),
          // Regolamento contestuale — apre con i dati di QUESTO evento già
          // popolati in cima (Step 42), a differenza della voce nel
          // profilo che mostra il solo regolamento generale.
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: () => context
                  .push('/pilot/event/${widget.eventId}/regolamento'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
                foregroundColor: AppColors.textSecondary,
              ),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('REGOLAMENTO',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Rifiniture Step 47: miglior tempo personale + record squadra ───────────────

/// Mostrato nella pagina evento di un allenamento (non nelle Statistiche,
/// dove esisteva già solo il tempo personale): per PS, il miglior tempo
/// PERSONALE del pilota ([trainingStatsProvider], già scritto allo Step 47)
/// e il record di SQUADRA fra tutti i tentativi completati di tutti i
/// membri ([myTrainingTeamBestProvider], nuovo qui, riusa
/// `TrainingClassificaEngine` mai collegato a nessuna UI finora).
class _TrainingBestTimesCard extends ConsumerWidget {
  final String eventId;
  const _TrainingBestTimesCard({required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(eventProvider(eventId)).valueOrNull;
    if (event == null) return const SizedBox();

    final myBestAsync = ref.watch(trainingStatsProvider);
    final teamEntryAsync = ref.watch(myTrainingTeamBestProvider(eventId));
    final myStats = myBestAsync.valueOrNull
        ?.where((s) => s.eventId == eventId)
        .firstOrNull;
    final teamEntry = teamEntryAsync.valueOrNull;

    final specialiIds = <String>{
      ...?myStats?.migliorTempoPersonalePerPs.keys,
      ...?teamEntry?.bestBySpecialId.keys,
    };
    // Nessun tentativo completato ancora — niente da mostrare (evita una
    // card vuota sopra il pulsante GPS prima della prima PS).
    if (specialiIds.isEmpty) return const SizedBox();

    // Nome PS da ENTRAMBE le varianti percorso (un tentativo può essere
    // stato corso su A o su B, vedi AttemptModel.routeVariantId) — non solo
    // quella attualmente attiva sull'evento.
    final orderedIds = <String>[];
    for (final variant in [
      event.routeAAsVariant,
      if (event.routeB != null) event.routeB!,
    ]) {
      for (final s in variant.speciali) {
        if (specialiIds.contains(s.id) && !orderedIds.contains(s.id)) {
          orderedIds.add(s.id);
        }
      }
    }
    final nomeById = <String, String>{
      for (final variant in [
        event.routeAAsVariant,
        if (event.routeB != null) event.routeB!,
      ])
        for (final s in variant.speciali) s.id: s.nome,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emoji_events_outlined,
                  color: AppColors.accent, size: 18),
              SizedBox(width: 8),
              Text('I miei tempi',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          for (final id in orderedIds)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(nomeById[id] ?? id,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        myStats?.migliorTempoPersonalePerPs[id] != null
                            ? TimeFormatUtils.formatRaceTime(
                                myStats!.migliorTempoPersonalePerPs[id]!)
                            : '—',
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                      if (teamEntry?.bestBySpecialId[id] != null)
                        Text(
                          'Squadra: ${TimeFormatUtils.formatRaceTime(teamEntry!.bestBySpecialId[id]!.tempo.tempo)}'
                          ' (${teamEntry.bestBySpecialId[id]!.userName})',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── 2-step registration dialog ────────────────────────────────────────────────

class _RegistrationDialog extends ConsumerStatefulWidget {
  final String eventId;
  final String eventNome;
  final int maxSquadra;
  final String userId;
  final String userNome;
  final String userCognome;
  final String? preferredTeamName;
  final Future<void> Function(TeamModel? existingTeam, String? newTeamName)
      onConfirm;

  const _RegistrationDialog({
    required this.eventId,
    required this.eventNome,
    required this.maxSquadra,
    required this.userId,
    required this.userNome,
    required this.userCognome,
    this.preferredTeamName,
    required this.onConfirm,
  });

  @override
  ConsumerState<_RegistrationDialog> createState() =>
      _RegistrationDialogState();
}

class _RegistrationDialogState extends ConsumerState<_RegistrationDialog> {
  int _step = 0;
  TeamModel? _selectedTeam;
  String? _newTeamName;
  bool _isCreatingNew = false;
  final _teamNameCtrl = TextEditingController();
  bool _confirming = false;
  bool _suggestionApplied = false;

  @override
  void initState() {
    super.initState();
    // Pre-seleziona/pre-compila la squadra preferita del pilota appena
    // arrivano i dati delle squadre già iscritte all'evento (una sola volta).
    ref.listenManual(teamsProvider(widget.eventId), (prev, next) {
      final teams = next.valueOrNull;
      if (teams != null) _applyPreferredSuggestion(teams);
    }, fireImmediately: true);
  }

  void _applyPreferredSuggestion(List<TeamModel> teams) {
    if (_suggestionApplied) return;
    final preferred = widget.preferredTeamName?.trim();
    if (preferred == null || preferred.isEmpty) {
      _suggestionApplied = true;
      return;
    }
    final match = teams
        .where((t) => t.nome.trim().toLowerCase() == preferred.toLowerCase())
        .firstOrNull;
    setState(() {
      _suggestionApplied = true;
      if (match != null && match.membriIds.length < widget.maxSquadra) {
        _selectedTeam = match;
        _isCreatingNew = false;
      } else if (match == null) {
        _isCreatingNew = true;
        _newTeamName = preferred;
        _teamNameCtrl.text = preferred;
      }
    });
  }

  @override
  void dispose() {
    _teamNameCtrl.dispose();
    super.dispose();
  }

  String get _chosenTeamLabel {
    if (_isCreatingNew) {
      return _newTeamName?.isNotEmpty == true
          ? _newTeamName!
          : '(nuova squadra)';
    }
    return _selectedTeam?.nome ?? '';
  }

  Widget _buildStep0(List<TeamModel> teams) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Scegli la tua squadra',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Seleziona una squadra esistente o creane una nuova.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),
        if (teams.isEmpty)
          const Text(
            'Nessuna squadra ancora — crea la prima!',
            style: TextStyle(
                color: AppColors.textSecondary, fontStyle: FontStyle.italic),
          )
        else ...[
          ...teams.map((team) {
            final isFull =
                team.membriIds.length >= widget.maxSquadra;
            final free = widget.maxSquadra - team.membriIds.length;
            final isPreferred = widget.preferredTeamName != null &&
                team.nome.trim().toLowerCase() ==
                    widget.preferredTeamName!.trim().toLowerCase();
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isFull
                    ? AppColors.background
                    : AppColors.cardBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isPreferred
                      ? AppColors.warning
                      : isFull
                          ? AppColors.border.withValues(alpha: 0.4)
                          : AppColors.border,
                ),
              ),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.group,
                    color: isFull
                        ? AppColors.textSecondary.withValues(alpha: 0.4)
                        : AppColors.textSecondary,
                    size: 20),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        team.nome,
                        style: TextStyle(
                          color: isFull
                              ? AppColors.textSecondary.withValues(alpha: 0.5)
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isPreferred) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.warning),
                        ),
                        child: const Text(
                          '⭐ Preferita',
                          style: TextStyle(
                              color: AppColors.warning,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Text(
                  isFull
                      ? '${team.membriIds.length}/${widget.maxSquadra} · Al completo'
                      : '${team.membriIds.length}/${widget.maxSquadra} · $free post${free == 1 ? "o" : "i"} liberi',
                  style: TextStyle(
                    color: isFull
                        ? AppColors.textSecondary.withValues(alpha: 0.4)
                        : AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                trailing: isFull
                    ? const Text('Piena',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 11))
                    : ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _selectedTeam = team;
                            _isCreatingNew = false;
                            _newTeamName = null;
                            _step = 1;
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Scegli',
                            style: TextStyle(fontSize: 12)),
                      ),
              ),
            );
          }),
          const Divider(color: AppColors.border, height: 20),
        ],
        // Create new team option
        if (!_isCreatingNew)
          OutlinedButton.icon(
            onPressed: () => setState(() => _isCreatingNew = true),
            icon: const Icon(Icons.group_add, size: 18),
            label: const Text('Crea nuova squadra'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: BorderSide(
                  color: AppColors.accent.withValues(alpha: 0.6)),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nome della nuova squadra',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: _teamNameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'es. Team Rossi',
                  hintStyle:
                      const TextStyle(color: AppColors.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(
                        color: AppColors.accent, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                onChanged: (v) => setState(() => _newTeamName = v),
              ),
              if (widget.preferredTeamName != null &&
                  _newTeamName?.trim().toLowerCase() ==
                      widget.preferredTeamName!.trim().toLowerCase())
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, color: AppColors.warning, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        'Nome dalla tua squadra preferita',
                        style: TextStyle(
                            color: AppColors.warning.withValues(alpha: 0.9),
                            fontSize: 11,
                            fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _isCreatingNew = false;
                      _teamNameCtrl.clear();
                      _newTeamName = null;
                    }),
                    child: const Text('Annulla',
                        style:
                            TextStyle(color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: (_newTeamName?.trim().isNotEmpty == true)
                        ? () {
                            setState(() {
                              _selectedTeam = null;
                              _step = 1;
                            });
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white),
                    child: const Text('Continua'),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildStep1() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Conferma iscrizione',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _buildSummaryRow(
            Icons.flag, 'Evento', widget.eventNome),
        const SizedBox(height: 10),
        _buildSummaryRow(
            Icons.group, 'Squadra', _chosenTeamLabel),
        const SizedBox(height: 10),
        _buildSummaryRow(
            Icons.badge,
            'Pilota',
            '${widget.userNome} ${widget.userCognome}'),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.accent, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'La richiesta sarà in attesa di approvazione da parte dell\'organizzatore.',
                  style: TextStyle(
                      color: AppColors.accent, fontSize: 11, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 16),
          const SizedBox(width: 10),
          Text('$label: ',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teamsAsync = ref.watch(teamsProvider(widget.eventId));

    return Dialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Step indicator
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  _StepDot(active: _step == 0, done: _step > 0, label: '1'),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: _step > 0
                          ? AppColors.accent
                          : AppColors.border,
                    ),
                  ),
                  _StepDot(active: _step == 1, done: false, label: '2'),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Squadra',
                      style: TextStyle(
                          color: _step == 0
                              ? AppColors.accent
                              : AppColors.textSecondary,
                          fontSize: 10)),
                  Text('Conferma',
                      style: TextStyle(
                          color: _step == 1
                              ? AppColors.accent
                              : AppColors.textSecondary,
                          fontSize: 10)),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 16),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: _step == 0
                    ? teamsAsync.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: CircularProgressIndicator(
                                color: AppColors.accent),
                          ),
                        ),
                        error: (e, _) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text('Errore caricamento squadre: $e',
                              style: const TextStyle(
                                  color: AppColors.error)),
                        ),
                        data: _buildStep0,
                      )
                    : _buildStep1(),
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _confirming
                        ? null
                        : () {
                            if (_step == 1) {
                              setState(() {
                                _step = 0;
                                _selectedTeam = null;
                              });
                            } else {
                              Navigator.of(context).pop();
                            }
                          },
                    child: Text(
                      _step == 0 ? 'Annulla' : 'Indietro',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  if (_step == 1) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _confirming
                          ? null
                          : () async {
                              setState(() => _confirming = true);
                              await widget.onConfirm(
                                _isCreatingNew ? null : _selectedTeam,
                                _isCreatingNew ? _newTeamName : null,
                              );
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                      icon: _confirming
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send, size: 16),
                      label: const Text('Invia richiesta'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final bool active;
  final bool done;
  final String label;
  const _StepDot(
      {required this.active, required this.done, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: active
            ? AppColors.accent
            : done
                ? AppColors.success
                : AppColors.border,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: done
            ? const Icon(Icons.check, color: Colors.white, size: 14)
            : Text(label,
                style: TextStyle(
                    color: active ? Colors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
      ),
    );
  }
}

/// Percorso alternativo (10/08/2026, Parte 4) — banner ben visibile in cima
/// alla pagina evento quando è attiva la variante B, con label e data
/// dell'ultimo cambio: il pilota deve capirlo subito, senza cercarlo nella
/// mappa o nell'elenco speciali.
class _RouteBActiveBanner extends StatelessWidget {
  final String label;
  final DateTime? changedAt;
  const _RouteBActiveBanner({required this.label, this.changedAt});

  @override
  Widget build(BuildContext context) {
    final dateLabel = changedAt == null
        ? ''
        : ' — cambiato il '
            '${changedAt!.day.toString().padLeft(2, '0')}/'
            '${changedAt!.month.toString().padLeft(2, '0')}/'
            '${changedAt!.year} alle '
            '${changedAt!.hour.toString().padLeft(2, '0')}:'
            '${changedAt!.minute.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      color: AppColors.warning.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Percorso modificato: la manifestazione si svolgerà sul '
              '$label.$dateLabel',
              style: const TextStyle(
                  color: AppColors.warning,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
