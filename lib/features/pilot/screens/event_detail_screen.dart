import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/models/special_model.dart';
import '../../../core/models/team_model.dart';
import '../../../core/services/gpx_parser.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../admin/providers/admin_provider.dart';
import '../../map/screens/track_map_screen.dart';
import '../providers/pilot_provider.dart';

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
          child: Text('Errore: $e',
              style: const TextStyle(color: AppColors.error)),
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
            !_isLoadingTrack) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _autoLoadTrack(event.trackUrl!));
        }

        final trackPoints = _parsedTrack?.points ?? const [];
        final showMap = event.speciali.isNotEmpty || event.trackUrl != null;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(event.nome),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                            specials: event.speciali,
                            waypoints: event.speciali
                                .expand((s) =>
                                    [s.waypointInizio, s.waypointFine])
                                .toList(),
                            interactive: false,
                          ),
                        ),
                  const Divider(height: 1, color: AppColors.border),
                ],

                // Specials
                if (event.speciali.isNotEmpty) ...[
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
                      children: event.speciali.map((s) {
                        final kmLen = _specialLengthKm(s, trackPoints);
                        final cpCount = s.controlPoints.length;
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
                  maxSquadra: event.maxSquadra,
                ),
              ],
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
  final int maxSquadra;

  const _PilotRegistrationSection({
    required this.eventId,
    required this.maxSquadra,
  });

  @override
  ConsumerState<_PilotRegistrationSection> createState() =>
      _PilotRegistrationSectionState();
}

class _PilotRegistrationSectionState
    extends ConsumerState<_PilotRegistrationSection> {
  bool _isLoading = false;

  Future<void> _joinTeamAndRegister(
      TeamModel team, String userId, String nome, String cognome) async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(firestoreServiceProvider);
      await service.joinTeam(widget.eventId, team.id, userId);
      await service.registerForEvent(
        eventId: widget.eventId,
        userId: userId,
        nome: nome,
        cognome: cognome,
        squadraId: team.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Richiesta di iscrizione inviata all\'admin!'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createTeamAndRegister(
      String teamName, String userId, String nome, String cognome) async {
    if (teamName.trim().isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final service = ref.read(firestoreServiceProvider);
      final team = TeamModel(
        id: '',
        nome: teamName.trim(),
        membriIds: [userId],
        createdBy: userId,
        eventId: widget.eventId,
      );
      final teamId = await service.createTeam(team);
      await service.registerForEvent(
        eventId: widget.eventId,
        userId: userId,
        nome: nome,
        cognome: cognome,
        squadraId: teamId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Squadra creata e richiesta inviata all\'admin!'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showCreateTeamDialog(
      String userId, String nome, String cognome) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Nuova squadra',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Nome squadra',
            labelStyle: const TextStyle(color: AppColors.textSecondary),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide:
                  const BorderSide(color: AppColors.accent, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Crea'),
          ),
        ],
      ),
    );
    if (confirmed == true && ctrl.text.trim().isNotEmpty) {
      await _createTeamAndRegister(ctrl.text, userId, nome, cognome);
    }
    ctrl.dispose();
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
                                child: Text(
                                  _statusLabel(reg.stato),
                                  style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.w600),
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
                            error: (e2, st) => const SizedBox(),
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
                        // GPS button for approved pilots
                        if (reg.stato == RegistrationStatus.approvato) ...[
                          const SizedBox(height: 16),
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
                        ],
                      ],
                    );
                  }

                  // ── Not registered: show team list ───────────────────
                  return teamsAsync.when(
                    loading: () => const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accent)),
                    error: (e, _) => const SizedBox(),
                    data: (teams) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (teams.isNotEmpty) ...[
                          const Text(
                            'Squadre disponibili',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...teams.map((team) {
                            final isFull =
                                team.membriIds.length >= widget.maxSquadra;
                            final freeSpots =
                                widget.maxSquadra - team.membriIds.length;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isFull
                                    ? AppColors.background
                                    : AppColors.cardBackground,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: isFull
                                        ? AppColors.border
                                            .withValues(alpha: 0.4)
                                        : AppColors.border),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  Icons.group,
                                  color: isFull
                                      ? AppColors.textSecondary
                                          .withValues(alpha: 0.4)
                                      : AppColors.textSecondary,
                                  size: 22,
                                ),
                                title: Text(
                                  team.nome,
                                  style: TextStyle(
                                    color: isFull
                                        ? AppColors.textSecondary
                                            .withValues(alpha: 0.5)
                                        : AppColors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Text(
                                  isFull
                                      ? '${team.membriIds.length}/${widget.maxSquadra} · Squadra al completo'
                                      : '${team.membriIds.length}/${widget.maxSquadra} · $freeSpots post${freeSpots == 1 ? "o libero" : "i liberi"}',
                                  style: TextStyle(
                                    color: isFull
                                        ? AppColors.textSecondary
                                            .withValues(alpha: 0.4)
                                        : AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: isFull
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: AppColors.border
                                              .withValues(alpha: 0.3),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'Piena',
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      )
                                    : ElevatedButton(
                                        onPressed: _isLoading
                                            ? null
                                            : () =>
                                                _joinTeamAndRegister(
                                                  team,
                                                  user.id,
                                                  user.nome,
                                                  user.cognome,
                                                ),
                                        style: ElevatedButton.styleFrom(
                                          minimumSize: Size.zero,
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 14,
                                                  vertical: 8),
                                          tapTargetSize:
                                              MaterialTapTargetSize
                                                  .shrinkWrap,
                                        ),
                                        child: const Text('Unisciti',
                                            style:
                                                TextStyle(fontSize: 12)),
                                      ),
                              ),
                            );
                          }),
                          const SizedBox(height: 12),
                          const Divider(color: AppColors.border),
                          const SizedBox(height: 12),
                        ],
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: _isLoading
                                ? null
                                : () => _showCreateTeamDialog(
                                      user.id,
                                      user.nome,
                                      user.cognome,
                                    ),
                            icon: const Icon(Icons.group_add),
                            label: const Text('Crea nuova squadra'),
                          ),
                        ),
                        if (_isLoading) ...[
                          const SizedBox(height: 16),
                          const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.accent),
                          ),
                        ],
                      ],
                    ),
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
      ],
    ),
  );
  }
}
