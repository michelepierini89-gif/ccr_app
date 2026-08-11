import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/classifica_model.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/penalty_settings_model.dart';
import '../../../core/services/gpx_parser.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/markdown_sections.dart';
import '../../../core/widgets/markdown_sections_view.dart';
import '../../admin/providers/admin_provider.dart';

/// Regolamento della manifestazione — testo statico (asset, disponibile
/// offline) reso come sezioni espandibili. Con [eventId] mostra in cima i
/// dati reali di quell'evento (Step 42); senza, è il solo regolamento
/// generale (accesso da profilo pilota).
class RegolamentoScreen extends ConsumerStatefulWidget {
  final String? eventId;
  const RegolamentoScreen({super.key, this.eventId});

  @override
  ConsumerState<RegolamentoScreen> createState() => _RegolamentoScreenState();
}

class _RegolamentoScreenState extends ConsumerState<RegolamentoScreen> {
  MdDocument? _doc;
  String? _loadError;
  double? _specialsTotalKm;
  String? _trackUrlLoaded;
  PenaltySettingsModel? _penalties;

  @override
  void initState() {
    super.initState();
    _loadDoc();
  }

  Future<void> _loadDoc() async {
    try {
      final raw =
          await rootBundle.loadString('assets/docs/regolamento_ccr.md');
      if (mounted) setState(() => _doc = parseMarkdownSections(raw));
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  Future<void> _maybeLoadEventExtras(EventModel event) async {
    if (widget.eventId == null) return;
    if (_penalties == null) {
      ref
          .read(firestoreServiceProvider)
          .getEffectivePenaltySettings(widget.eventId!)
          .then((p) {
        if (mounted) setState(() => _penalties = p);
      }).ignore();
    }
    final url = event.activeTrackUrl;
    if (url == null || url == _trackUrlLoaded) return;
    _trackUrlLoaded = url;
    try {
      final bytes = await StorageService().downloadTrack(url);
      final content = utf8.decode(bytes);
      final parsed = url.contains('.kml')
          ? GpxParser.parseKml(content)
          : GpxParser.parseGpx(content);
      final km = _computeSpecialsTotalKm(event, parsed.points);
      if (mounted) setState(() => _specialsTotalKm = km);
    } catch (_) {
      // Silenzioso: la lunghezza PS è un dato accessorio, il regolamento
      // resta consultabile anche senza tracciato scaricabile.
    }
  }

  // Stesso algoritmo Haversine su indici più vicini usato altrove nell'app
  // (vedi _TracciatoTabState._haversineMeters/_sectionLength in
  // event_management_screen.dart) per restare coerenti con i km mostrati
  // lì all'admin.
  double _haversineMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final sinDLat = sin(dLat / 2);
    final sinDLng = sin(dLng / 2);
    final aVal =
        sinDLat * sinDLat + cos(lat1) * cos(lat2) * sinDLng * sinDLng;
    return r * 2 * atan2(sqrt(aVal), sqrt(1 - aVal));
  }

  int _nearestIndex(List<LatLng> pts, double lat, double lng) {
    var minDist = double.infinity;
    var minIdx = 0;
    for (var i = 0; i < pts.length; i++) {
      final dLat = lat - pts[i].latitude;
      final dLng = lng - pts[i].longitude;
      final d = dLat * dLat + dLng * dLng;
      if (d < minDist) {
        minDist = d;
        minIdx = i;
      }
    }
    return minIdx;
  }

  double _computeSpecialsTotalKm(EventModel event, List<LatLng> pts) {
    if (pts.length < 2) return 0;
    double total = 0;
    for (final s in event.activeSpeciali) {
      if (s.annullata) continue;
      final aIdx = _nearestIndex(pts, s.waypointInizio.lat, s.waypointInizio.lng);
      final bIdx = _nearestIndex(pts, s.waypointFine.lat, s.waypointFine.lng);
      final lo = aIdx < bIdx ? aIdx : bIdx;
      final hi = aIdx < bIdx ? bIdx : aIdx;
      for (int i = lo; i < hi; i++) {
        total += _haversineMeters(pts[i], pts[i + 1]);
      }
    }
    return total / 1000.0;
  }

  @override
  Widget build(BuildContext context) {
    final eventId = widget.eventId;
    final eventAsync =
        eventId != null ? ref.watch(eventStreamProvider(eventId)) : null;
    final event = eventAsync?.valueOrNull;
    if (event != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeLoadEventExtras(event));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Regolamento')),
      body: SafeArea(
        bottom: true,
        child: _loadError != null
            ? Center(
                child: Text(
                    'Impossibile caricare il regolamento: $_loadError',
                    style: const TextStyle(color: AppColors.error)),
              )
            : _doc == null
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.accent))
                : SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(16, 16, 16,
                        16 + MediaQuery.paddingOf(context).bottom),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (event != null) ...[
                          if ((event.disposizioniParticolari ?? '')
                              .trim()
                              .isNotEmpty)
                            _DisposizioniCard(
                                text: event.disposizioniParticolari!.trim()),
                          _DatiEventoCard(
                            event: event,
                            penalties: _penalties,
                            specialsTotalKm: _specialsTotalKm,
                          ),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          _doc!.title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        MarkdownSectionsView(document: _doc!),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _DisposizioniCard extends StatelessWidget {
  final String text;
  const _DisposizioniCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.campaign_outlined, color: AppColors.accent, size: 18),
              SizedBox(width: 8),
              Text('Disposizioni particolari',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(text,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }
}

class _DatiEventoCard extends StatelessWidget {
  final EventModel event;
  final PenaltySettingsModel? penalties;
  final double? specialsTotalKm;

  const _DatiEventoCard({
    required this.event,
    required this.penalties,
    required this.specialsTotalKm,
  });

  @override
  Widget build(BuildContext context) {
    final speciali =
        event.activeSpeciali.where((s) => !s.annullata).toList();
    final isPunti =
        event.tipologiaClassifica == TipologiaClassifica.punteggioSpeciale;
    final h = event.maxRaceTimeMinutes ~/ 60;
    final m = event.maxRaceTimeMinutes % 60;
    final dangerCount = event.activeDangerPoints.length;
    final speedZoneCount = event.activeSpeedZones.length;

    final rows = <(String, String)>[
      ('Squadra', '${event.minSquadra}–${event.maxSquadra} piloti'),
      if (speciali.isNotEmpty)
        (
          'Prove speciali',
          specialsTotalKm != null
              ? '${speciali.length} · ${specialsTotalKm!.toStringAsFixed(1)} km totali'
              : '${speciali.length}',
        ),
      ('Tempo massimo', '${h}h ${m.toString().padLeft(2, '0')}min'),
      ('Classifica', event.tipologiaClassifica.label),
      if (penalties != null) ...[
        (
          'Penalità CP mancati',
          '1: ${PenaltySettingsModel.formatSeconds(penalties!.cp1Mancato)}'
              ' · 2: ${PenaltySettingsModel.formatSeconds(penalties!.cp2Mancati)}'
              ' · 3+: ${PenaltySettingsModel.formatSeconds(penalties!.cp3oPiuMancati)}',
        ),
        (
          'Penalità squadra',
          'Ritiro compagno: ${PenaltySettingsModel.formatSeconds(penalties!.ritiroCompagno)}'
              ' · Pilota mancante: ${PenaltySettingsModel.formatSeconds(penalties!.pilotaMancante)}',
        ),
        if (speedZoneCount > 0)
          (
            'Penalità zona velocità',
            PenaltySettingsModel.formatSeconds(
                penalties!.speedZonePenaltySeconds),
          ),
      ],
      if (dangerCount > 0) ('Punti di pericolo', '$dangerCount'),
      if (speedZoneCount > 0)
        ('Zone a velocità controllata', '$speedZoneCount'),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_outlined, color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Dati evento — ${event.nome}',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(row.$1,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11.5)),
                  ),
                  Expanded(
                    child: Text(row.$2,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          if (isPunti) ...[
            const SizedBox(height: 4),
            const Text('Tabella punti per posizione',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 11.5)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (int i = 0; i < kChampionshipPoints.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      '${i + 1}° ${kChampionshipPoints[i]}pt',
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
