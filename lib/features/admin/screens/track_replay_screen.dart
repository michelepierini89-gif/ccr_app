import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/providers/offline_provider.dart';
import '../../../core/services/gpx_parser.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/track_replay_service.dart';
import '../../../core/services/track_smoother.dart';
import '../../../core/services/waypoint_detector.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/admin_provider.dart';

enum _ReplaySource { firestore, csv, gpx }

/// Schermata admin "Replay traccia" (Parte 1D): banco di replay per
/// validare timing/filtri GPS senza uscire sul campo, riusando tracce già
/// registrate (Firestore, log diagnostico CSV, o un GPX importato).
class TrackReplayScreen extends ConsumerStatefulWidget {
  const TrackReplayScreen({super.key});

  @override
  ConsumerState<TrackReplayScreen> createState() => _TrackReplayScreenState();
}

class _TrackReplayScreenState extends ConsumerState<TrackReplayScreen> {
  _ReplaySource _source = _ReplaySource.firestore;
  ReplaySpeed _speed = ReplaySpeed.fast;

  String? _selectedEventId;
  String? _selectedUserId;

  String? _importedFileName;
  String? _importedContent;

  bool _running = false;
  String _progressLabel = '';
  double _progress = 0;

  List<RawTrackSample>? _samples;
  EventModel? _loadedEvent;
  List<LatLng> _referenceTrack = [];
  List<ReplayConfigResult>? _results;
  String? _error;

  Future<void> _pickFile(List<String> extensions) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) return;
    setState(() {
      _importedFileName = picked.name;
      _importedContent = utf8.decode(bytes);
      _results = null;
      _error = null;
    });
  }

  Future<List<LatLng>> _loadReferenceTrack(EventModel event) async {
    if (event.trackUrl == null) return [];
    try {
      final bytes = await StorageService().downloadTrack(event.trackUrl!);
      final content = utf8.decode(bytes);
      return event.trackUrl!.contains('.kml')
          ? GpxParser.parseKml(content).points
          : GpxParser.parseGpx(content).points;
    } catch (_) {
      return [];
    }
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _results = null;
      _progress = 0;
      _progressLabel = 'Caricamento traccia…';
    });

    try {
      final svc = ref.read(firestoreServiceProvider);
      List<RawTrackSample> samples;
      EventModel? event;

      if (_source == _ReplaySource.firestore) {
        if (_selectedEventId == null || _selectedUserId == null) {
          throw Exception('Seleziona evento e pilota');
        }
        samples =
            await TrackReplayService.loadFromFirestore(svc, _selectedEventId!, _selectedUserId!);
        if (samples.length < 2) {
          throw Exception(
              'Nessuna traccia grezza completa salvata per questo pilota '
              '(serve pilotTrackFull, salvata a fine gara dalle build con '
              'log diagnostico — le sessioni concluse prima non ce l\'hanno)');
        }
        event = await svc.getEvent(_selectedEventId!);
      } else if (_source == _ReplaySource.csv) {
        if (_importedContent == null) throw Exception('Importa un CSV');
        samples = TrackReplayService.loadFromDiagnosticCsv(_importedContent!);
        if (samples.length < 2) {
          throw Exception('Nessun fix GPS accettato trovato nel CSV');
        }
        if (_selectedEventId != null) {
          event = await svc.getEvent(_selectedEventId!);
        }
      } else {
        if (_importedContent == null) throw Exception('Importa un GPX');
        samples = TrackReplayService.loadFromGpx(_importedContent!);
        if (samples.length < 2) {
          throw Exception(
              'Nessun punto con timestamp trovato nel GPX (serve <time> per '
              'punto, non solo lat/lng)');
        }
        if (_selectedEventId != null) {
          event = await svc.getEvent(_selectedEventId!);
        }
      }

      final referenceTrack =
          event != null ? await _loadReferenceTrack(event) : <LatLng>[];
      final specials =
          event?.speciali.where((s) => !s.annullata).toList() ?? const [];
      if (specials.isEmpty) {
        throw Exception(
            'Seleziona anche l\'evento di riferimento (per le speciali e la '
            'traccia GPX) — necessario anche per CSV/GPX importati');
      }

      final results = await TrackReplayService.runComparison(
        samples: samples,
        specials: specials,
        referenceTrack: referenceTrack,
        firestoreService: svc,
        prefs: ref.read(sharedPreferencesProvider),
        speed: _speed,
        onProgress: (configNome, i, total) {
          if (!mounted) return;
          setState(() {
            _progressLabel = '$configNome — $i/$total';
            _progress = total == 0 ? 0 : i / total;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _samples = samples;
        _loadedEvent = event;
        _referenceTrack = referenceTrack;
        _results = results;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _exportCsv() async {
    final results = _results;
    if (results == null) return;
    final csv = TrackReplayService.exportComparisonCsv(results);
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(utf8.encode(csv),
            name: 'replay_confronto.csv', mimeType: 'text/csv'),
      ],
      subject: 'CCR — confronto replay traccia',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Replay traccia',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Sorgente'),
            _sourceSelector(),
            const SizedBox(height: 16),
            _eventPicker(),
            if (_source == _ReplaySource.firestore) ...[
              const SizedBox(height: 12),
              _pilotPicker(),
            ],
            if (_source != _ReplaySource.firestore) ...[
              const SizedBox(height: 12),
              _filePickerRow(),
            ],
            const SizedBox(height: 16),
            _sectionTitle('Velocità'),
            _speedSelector(),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _running ? null : _run,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _running
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Esegui confronto',
                        style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            if (_running) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: AppColors.border,
                color: AppColors.accent,
              ),
              const SizedBox(height: 6),
              Text(_progressLabel,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error),
                ),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.error)),
              ),
            ],
            if (_results != null) ...[
              const SizedBox(height: 24),
              _sectionTitle('Mappa'),
              SizedBox(height: 320, child: _buildMap()),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _sectionTitle('Risultati')),
                  TextButton.icon(
                    onPressed: _exportCsv,
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Esporta CSV'),
                  ),
                ],
              ),
              _buildResultsTable(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
      );

  Widget _sourceSelector() {
    return SegmentedButton<_ReplaySource>(
      segments: const [
        ButtonSegment(
            value: _ReplaySource.firestore,
            label: Text('Firestore'),
            icon: Icon(Icons.cloud_outlined, size: 16)),
        ButtonSegment(
            value: _ReplaySource.csv,
            label: Text('Log CSV'),
            icon: Icon(Icons.description_outlined, size: 16)),
        ButtonSegment(
            value: _ReplaySource.gpx,
            label: Text('GPX'),
            icon: Icon(Icons.route_outlined, size: 16)),
      ],
      selected: {_source},
      onSelectionChanged: (s) => setState(() {
        _source = s.first;
        _results = null;
        _error = null;
      }),
    );
  }

  Widget _eventPicker() {
    final eventsAsync = ref.watch(adminEventsProvider);
    return eventsAsync.when(
      data: (events) => DropdownButtonFormField<String>(
        initialValue: _selectedEventId,
        decoration: InputDecoration(
          labelText: _source == _ReplaySource.firestore
              ? 'Evento'
              : 'Evento di riferimento (speciali + tracciato GPX)',
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        dropdownColor: AppColors.cardBackground,
        items: events
            .map((e) => DropdownMenuItem(value: e.id, child: Text(e.nome)))
            .toList(),
        onChanged: (v) => setState(() {
          _selectedEventId = v;
          _selectedUserId = null;
          _results = null;
        }),
      ),
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const Text('Errore caricamento eventi',
          style: TextStyle(color: AppColors.error)),
    );
  }

  Widget _pilotPicker() {
    final eventId = _selectedEventId;
    if (eventId == null) return const SizedBox.shrink();
    final regsAsync = ref.watch(registrationsProvider(eventId));
    return regsAsync.when(
      data: (regs) {
        final approved = regs
            .where((r) => r.stato == RegistrationStatus.approvato)
            .toList();
        return DropdownButtonFormField<String>(
          initialValue: _selectedUserId,
          decoration: InputDecoration(
            labelText: 'Pilota',
            labelStyle: const TextStyle(color: AppColors.textSecondary),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          dropdownColor: AppColors.cardBackground,
          items: approved
              .map((r) => DropdownMenuItem(
                  value: r.userId, child: Text(r.nomeCompleto)))
              .toList(),
          onChanged: (v) => setState(() {
            _selectedUserId = v;
            _results = null;
          }),
        );
      },
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const Text('Errore caricamento iscrizioni',
          style: TextStyle(color: AppColors.error)),
    );
  }

  Widget _filePickerRow() {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: () => _pickFile(
              _source == _ReplaySource.csv ? ['csv'] : ['gpx']),
          icon: const Icon(Icons.upload_file, size: 16),
          label: Text(_source == _ReplaySource.csv
              ? 'Importa log CSV'
              : 'Importa GPX'),
        ),
        const SizedBox(width: 12),
        if (_importedFileName != null)
          Expanded(
            child: Text(_importedFileName!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
      ],
    );
  }

  Widget _speedSelector() {
    return DropdownButtonFormField<ReplaySpeed>(
      initialValue: _speed,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dropdownColor: AppColors.cardBackground,
      items: const [
        DropdownMenuItem(value: ReplaySpeed.fast, child: Text('Veloce')),
        DropdownMenuItem(
            value: ReplaySpeed.x2, child: Text('Tempo reale 2×')),
        DropdownMenuItem(
            value: ReplaySpeed.x5, child: Text('Tempo reale 5×')),
        DropdownMenuItem(
            value: ReplaySpeed.x10, child: Text('Tempo reale 10×')),
      ],
      onChanged: (v) => setState(() => _speed = v ?? ReplaySpeed.fast),
    );
  }

  // ── Mappa ────────────────────────────────────────────────────────────────

  Widget _buildMap() {
    final samples = _samples;
    if (samples == null || samples.isEmpty) return const SizedBox.shrink();
    final trackPoints = samples.map((s) => LatLng(s.lat, s.lng)).toList();
    final center = trackPoints[trackPoints.length ~/ 2];

    // Porte virtuali delle speciali (per la config "Porta + raggio",
    // rappresentativa del comportamento attuale) — stessa attachGates usata
    // in GpsService, solo per il disegno.
    final gateSegments = <Polyline>[];
    final event = _loadedEvent;
    if (event != null) {
      for (final s in event.speciali.where((s) => !s.annullata)) {
        for (final wp in [s.waypointInizio, s.waypointFine]) {
          final gate = WaypointDetector.buildGate(wp, _referenceTrack);
          if (gate == null) continue;
          gateSegments.add(Polyline(
            points: [gate.gateA, gate.gateB],
            color: Colors.yellow,
            strokeWidth: 3,
          ));
        }
      }
    }

    // Marcatori di attraversamento: config "Porta + raggio" (indice 1),
    // posizionati sul campione più vicino nel tempo al timestamp calcolato.
    final markers = <Marker>[];
    final gateRadiusResult = _results
        ?.where((r) => r.configNome == TrackReplayService.configGateRadius)
        .firstOrNull;
    if (gateRadiusResult != null) {
      for (final sp in gateRadiusResult.speciali) {
        for (final (ts, label, method) in [
          (sp.ingressoTs, '${sp.specialeNome} IN', sp.metodoIngresso),
          (sp.uscitaTs, '${sp.specialeNome} FINE', sp.metodoUscita),
        ]) {
          if (ts == null) continue;
          final nearest = _nearestSample(samples, ts);
          if (nearest == null) continue;
          markers.add(Marker(
            point: LatLng(nearest.lat, nearest.lng),
            width: 90,
            height: 40,
            child: Column(
              children: [
                Icon(Icons.flag,
                    color: method == 'gate' ? AppColors.success : Colors.orange,
                    size: 18),
                Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 9)),
              ],
            ),
          ));
        }
      }
    }

    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 15),
      children: [
        TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
        if (_referenceTrack.isNotEmpty)
          PolylineLayer(polylines: [
            Polyline(
                points: _referenceTrack,
                color: Colors.red.withValues(alpha: 0.5),
                strokeWidth: 3),
          ]),
        PolylineLayer(polylines: [
          Polyline(points: trackPoints, color: Colors.blue, strokeWidth: 4),
        ]),
        PolylineLayer(polylines: gateSegments),
        MarkerLayer(markers: markers),
      ],
    );
  }

  RawTrackSample? _nearestSample(List<RawTrackSample> samples, DateTime ts) {
    RawTrackSample? nearest;
    int? bestDiff;
    for (final s in samples) {
      final diff = (s.timestamp.difference(ts).inMilliseconds).abs();
      if (bestDiff == null || diff < bestDiff) {
        bestDiff = diff;
        nearest = s;
      }
    }
    return nearest;
  }

  // ── Tabella risultati ────────────────────────────────────────────────────

  Widget _buildResultsTable() {
    final results = _results;
    if (results == null) return const SizedBox.shrink();

    // Nomi/ordine delle speciali (dalla prima config con dati).
    final specialiOrder = <String, String>{};
    for (final cfg in results) {
      for (final sp in cfg.speciali) {
        specialiOrder.putIfAbsent(sp.specialeId, () => sp.specialeNome);
      }
    }

    final baseline = results
        .where((r) => r.configNome == TrackReplayService.configRadiusOnly)
        .firstOrNull;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor:
            WidgetStateProperty.all(AppColors.cardBackground),
        columns: [
          const DataColumn(label: Text('Speciale')),
          for (final cfg in results) DataColumn(label: Text(cfg.configNome)),
          const DataColumn(label: Text('Δ ms (vs raggio)')),
        ],
        rows: [
          for (final entry in specialiOrder.entries)
            DataRow(cells: [
              DataCell(Text(entry.value)),
              for (final cfg in results)
                DataCell(_cellForSpecial(cfg, entry.key)),
              DataCell(_diffCell(baseline, results, entry.key)),
            ]),
          for (final cfg in results) ...[
            DataRow(cells: [
              DataCell(Text('${cfg.configNome} — porte scattate',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11))),
              for (final c in results)
                DataCell(Text(c == cfg ? '${cfg.gateCount}' : '')),
              const DataCell(Text('')),
            ]),
            // Fix 1 (09/08/2026) — checkpoint agganciati su totale
            // configurati, per confrontare prima/dopo il fix del
            // rilevamento su traiettoria.
            if (cfg.cpTotal > 0)
              DataRow(cells: [
                DataCell(Text('${cfg.configNome} — checkpoint agganciati',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11))),
                for (final c in results)
                  DataCell(Text(
                      c == cfg ? '${cfg.cpPassedCount}/${cfg.cpTotal}' : '')),
                const DataCell(Text('')),
              ]),
          ],
        ],
      ),
    );
  }

  Widget _cellForSpecial(ReplayConfigResult cfg, String specialeId) {
    final sp = cfg.speciali.where((s) => s.specialeId == specialeId).firstOrNull;
    if (sp == null || sp.tempo == null) {
      return const Text('—', style: TextStyle(color: AppColors.textSecondary));
    }
    final tempo = _fmtDuration(sp.tempo!);
    final metodo = sp.metodoIngresso == 'gate' || sp.metodoUscita == 'gate'
        ? 'porta'
        : 'raggio';
    final fraction = sp.fractionTIngresso ?? sp.fractionTUscita;
    final dist = sp.distanzaIngressoM ?? sp.distanzaUscitaM;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(tempo, style: const TextStyle(color: AppColors.textPrimary)),
        Text(
          fraction != null && dist != null
              ? '$metodo · t=${fraction.toStringAsFixed(2)} · d=${dist.toStringAsFixed(1)}m'
              : metodo,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
        ),
      ],
    );
  }

  Widget _diffCell(ReplayConfigResult? baseline,
      List<ReplayConfigResult> results, String specialeId) {
    if (baseline == null) return const Text('');
    final base =
        baseline.speciali.where((s) => s.specialeId == specialeId).firstOrNull;
    final gateRadius = results
        .where((r) => r.configNome == TrackReplayService.configGateRadius)
        .firstOrNull
        ?.speciali
        .where((s) => s.specialeId == specialeId)
        .firstOrNull;
    if (base?.tempo == null || gateRadius?.tempo == null) {
      return const Text('—', style: TextStyle(color: AppColors.textSecondary));
    }
    final diffMs =
        gateRadius!.tempo!.inMilliseconds - base!.tempo!.inMilliseconds;
    return Text('${diffMs >= 0 ? '+' : ''}$diffMs ms',
        style: TextStyle(
            color: diffMs == 0 ? AppColors.textSecondary : AppColors.warning));
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final cs = (d.inMilliseconds % 1000) ~/ 10;
    return '${m}m ${s.toString().padLeft(2, '0')}.${cs.toString().padLeft(2, '0')}s';
  }
}
