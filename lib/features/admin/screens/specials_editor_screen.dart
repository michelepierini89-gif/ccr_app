import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/special_model.dart';
import '../../../core/models/waypoint_model.dart';
import '../../../core/services/gpx_parser.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/admin_provider.dart';
import '../widgets/special_tile.dart';

enum _SelectionMode { none, inizio, fine, controlPoint }

class SpecialsEditorScreen extends ConsumerStatefulWidget {
  final String eventId;
  final ParsedTrack parsedTrack;
  final EventModel event;

  const SpecialsEditorScreen({
    super.key,
    required this.eventId,
    required this.parsedTrack,
    required this.event,
  });

  @override
  ConsumerState<SpecialsEditorScreen> createState() =>
      _SpecialsEditorScreenState();
}

class _SpecialsEditorScreenState extends ConsumerState<SpecialsEditorScreen> {
  late List<SpecialModel> _specials;
  bool _isSaving = false;

  bool _isEditing = false;
  int _editingIndex = -1;
  final _nomeCtrl = TextEditingController();
  int _editingColorIndex = 0;
  int _editingInicioIdx = -1;
  int _editingFineIdx = -1;
  List<int> _editingControlIdxs = [];
  _SelectionMode _selectionMode = _SelectionMode.none;
  int _activeControlPointIdx = -1;

  double? _cachedTotalLength;

  @override
  void initState() {
    super.initState();
    _specials = List.from(widget.event.speciali);
    _cachedTotalLength = _computeTotalLength();
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    super.dispose();
  }

  // ── Geometry helpers ──────────────────────────────────────────────────────

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

  double _computeTotalLength() {
    final pts = widget.parsedTrack.points;
    if (pts.length < 2) return 0.0;
    double total = 0.0;
    for (int i = 1; i < pts.length; i++) {
      total += _haversineMeters(pts[i - 1], pts[i]);
    }
    return total / 1000.0;
  }

  double _sectionLength(int startIdx, int endIdx) {
    final pts = widget.parsedTrack.points;
    final a = min(startIdx, endIdx);
    final b = max(startIdx, endIdx);
    if (a < 0 || b >= pts.length || a == b) return 0.0;
    double total = 0.0;
    for (int i = a; i < b; i++) {
      total += _haversineMeters(pts[i], pts[i + 1]);
    }
    return total / 1000.0;
  }

  int? _indexFromId(String id) {
    final m = RegExp(r'track_pt_(\d+)$').firstMatch(id);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  int _ensureTrackIdx(WaypointModel wp) {
    final parsed = _indexFromId(wp.id);
    if (parsed != null) return parsed;
    final pts = widget.parsedTrack.points;
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

  void _reclampControlPoints() {
    if (_editingInicioIdx < 0 || _editingFineIdx < 0) return;
    final lo = min(_editingInicioIdx, _editingFineIdx);
    final hi = max(_editingInicioIdx, _editingFineIdx);
    for (var i = 0; i < _editingControlIdxs.length; i++) {
      _editingControlIdxs[i] = _editingControlIdxs[i].clamp(lo, hi);
    }
  }

  int _nearestTrackIdx(LatLng tapped) {
    final pts = widget.parsedTrack.points;
    var minDist = double.infinity;
    var minIdx = 0;
    for (var i = 0; i < pts.length; i++) {
      final dlat = tapped.latitude - pts[i].latitude;
      final dlng = tapped.longitude - pts[i].longitude;
      final d = dlat * dlat + dlng * dlng;
      if (d < minDist) {
        minDist = d;
        minIdx = i;
      }
    }
    return minIdx;
  }

  WaypointModel _waypointFromIdx(int idx, WaypointType type) {
    final pt = widget.parsedTrack.points[idx];
    return WaypointModel(
      id: 'track_pt_$idx',
      nome:
          '${pt.latitude.toStringAsFixed(5)}, ${pt.longitude.toStringAsFixed(5)}',
      lat: pt.latitude,
      lng: pt.longitude,
      type: type,
    );
  }

  Color _contrastColor(Color c) {
    final hsl = HSLColor.fromColor(c);
    final newHue = (hsl.hue + 180.0) % 360.0;
    return HSLColor.fromAHSL(1.0, newHue, 0.9, 0.55).toColor();
  }

  // ── Editing lifecycle ─────────────────────────────────────────────────────

  void _startAdd() {
    final ptCount = widget.parsedTrack.points.length;
    setState(() {
      _isEditing = true;
      _editingIndex = -1;
      _editingColorIndex = _specials.length % AppColors.specialColors.length;
      _nomeCtrl.text = 'PS${_specials.length + 1}';
      _editingInicioIdx = ptCount > 0 ? 0 : -1;
      _editingFineIdx = ptCount > 1 ? ptCount - 1 : -1;
      _editingControlIdxs = [];
      _selectionMode = _SelectionMode.none;
      _activeControlPointIdx = -1;
    });
  }

  void _startEdit(int index) {
    final s = _specials[index];
    setState(() {
      _isEditing = true;
      _editingIndex = index;
      _editingColorIndex = s.colorIndex;
      _nomeCtrl.text = s.nome;
      _editingInicioIdx =
          widget.parsedTrack.points.isNotEmpty ? _ensureTrackIdx(s.waypointInizio) : -1;
      _editingFineIdx =
          widget.parsedTrack.points.isNotEmpty ? _ensureTrackIdx(s.waypointFine) : -1;
      _editingControlIdxs =
          s.controlPoints.map(_ensureTrackIdx).toList();
      _selectionMode = _SelectionMode.none;
      _activeControlPointIdx = -1;
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _editingIndex = -1;
      _editingInicioIdx = -1;
      _editingFineIdx = -1;
      _editingControlIdxs = [];
      _selectionMode = _SelectionMode.none;
      _activeControlPointIdx = -1;
      _nomeCtrl.clear();
    });
  }

  void _confirmEditing() {
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) return;
    final ptCount = widget.parsedTrack.points.length;
    if (_editingInicioIdx < 0 || _editingFineIdx < 0 || ptCount == 0) return;
    if (_editingFineIdx <= _editingInicioIdx) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('La fine deve essere successiva all\'inizio'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    for (var i = 0; i < _specials.length; i++) {
      if (i == _editingIndex) continue;
      final s = _specials[i];
      final sA = _ensureTrackIdx(s.waypointInizio);
      final sB = _ensureTrackIdx(s.waypointFine);
      final lo = min(sA, sB);
      final hi = max(sA, sB);
      if (_editingInicioIdx < hi && lo < _editingFineIdx) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Il range si sovrappone con "${s.nome}"'),
          backgroundColor: AppColors.error,
        ));
        return;
      }
    }

    final inizio = _waypointFromIdx(_editingInicioIdx, WaypointType.inizio);
    final fine = _waypointFromIdx(_editingFineIdx, WaypointType.fine);
    final controlPoints = _editingControlIdxs
        .where((idx) => idx >= 0 && idx < ptCount)
        .map((idx) => _waypointFromIdx(idx, WaypointType.intermedio))
        .toList();

    final special = SpecialModel(
      id: _editingIndex >= 0
          ? _specials[_editingIndex].id
          : const Uuid().v4(),
      nome: nome,
      colorIndex: _editingColorIndex,
      waypointInizio: inizio,
      waypointFine: fine,
      controlPoints: controlPoints,
      ordine: _editingIndex >= 0
          ? _specials[_editingIndex].ordine
          : _specials.length,
    );

    setState(() {
      if (_editingIndex >= 0) {
        _specials[_editingIndex] = special;
      } else {
        _specials.add(special);
      }
    });
    _cancelEditing();
  }

  void _deleteSpeciale(int index) {
    setState(() {
      _specials.removeAt(index);
      for (var i = 0; i < _specials.length; i++) {
        _specials[i] = _specials[i].copyWith(ordine: i);
      }
      if (_editingIndex == index) _cancelEditing();
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final updated = widget.event.copyWith(speciali: _specials);
      await ref.read(firestoreServiceProvider).updateEvent(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speciali salvate con successo!'),
          backgroundColor: AppColors.success,
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Map interactions ──────────────────────────────────────────────────────

  void _onMapTap(LatLng latlng) {
    if (_selectionMode == _SelectionMode.none) return;
    if (widget.parsedTrack.points.isEmpty) return;
    final idx = _nearestTrackIdx(latlng);
    setState(() {
      switch (_selectionMode) {
        case _SelectionMode.inizio:
          _editingInicioIdx = idx;
          _reclampControlPoints();
          break;
        case _SelectionMode.fine:
          _editingFineIdx = idx;
          _reclampControlPoints();
          break;
        case _SelectionMode.controlPoint:
          final clampedIdx =
              (_editingInicioIdx >= 0 && _editingFineIdx > _editingInicioIdx)
                  ? idx.clamp(_editingInicioIdx, _editingFineIdx)
                  : idx;
          if (_activeControlPointIdx >= 0 &&
              _activeControlPointIdx < _editingControlIdxs.length) {
            _editingControlIdxs[_activeControlPointIdx] = clampedIdx;
          } else {
            _editingControlIdxs.add(clampedIdx);
          }
          break;
        case _SelectionMode.none:
          break;
      }
      _selectionMode = _SelectionMode.none;
      _activeControlPointIdx = -1;
    });
  }

  // ── Map overlays ──────────────────────────────────────────────────────────

  List<Polyline> _buildPolylines() {
    final polylines = <Polyline>[];
    final pts = widget.parsedTrack.points;

    if (pts.isNotEmpty) {
      polylines.add(Polyline(
        points: pts,
        color: AppColors.accent,
        strokeWidth: 3,
      ));
    }

    for (var i = 0; i < _specials.length; i++) {
      if (i == _editingIndex) continue;
      final s = _specials[i];
      if (pts.isEmpty) continue;
      final startIdx = _ensureTrackIdx(s.waypointInizio);
      final endIdx = _ensureTrackIdx(s.waypointFine);
      final a = min(startIdx, endIdx);
      final b = max(startIdx, endIdx);
      if (b < pts.length) {
        polylines.add(Polyline(
          points: pts.sublist(a, b + 1),
          color: s.color,
          strokeWidth: 4,
        ));
      }
    }

    if (_isEditing && _editingInicioIdx >= 0 && _editingFineIdx >= 0) {
      final editColor = AppColors
          .specialColors[_editingColorIndex % AppColors.specialColors.length];
      final a = min(_editingInicioIdx, _editingFineIdx);
      final b = max(_editingInicioIdx, _editingFineIdx);
      if (b < pts.length) {
        polylines.add(Polyline(
          points: pts.sublist(a, b + 1),
          color: editColor,
          strokeWidth: 5,
        ));
      }
    }

    return polylines;
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    final pts = widget.parsedTrack.points;

    for (var i = 0; i < _specials.length; i++) {
      if (i == _editingIndex) continue;
      final s = _specials[i];
      markers
        ..add(_markerAt(s.waypointInizio.latLng, s.color, s.nome,
            icon: Icons.play_arrow))
        ..add(_markerAt(s.waypointFine.latLng, s.color, '',
            icon: Icons.stop));
      final contrast = _contrastColor(s.color);
      for (var j = 0; j < s.controlPoints.length; j++) {
        markers.add(
            _controlMarkerAt(s.controlPoints[j].latLng, contrast, 'P${j + 1}'));
      }
    }

    if (_isEditing) {
      final editColor = AppColors
          .specialColors[_editingColorIndex % AppColors.specialColors.length];
      if (_editingInicioIdx >= 0 && _editingInicioIdx < pts.length) {
        markers.add(_markerAt(
            pts[_editingInicioIdx], editColor, 'Inizio',
            icon: Icons.play_arrow, large: true));
      }
      if (_editingFineIdx >= 0 && _editingFineIdx < pts.length) {
        markers.add(_markerAt(pts[_editingFineIdx], editColor, 'Fine',
            icon: Icons.stop, large: true));
      }
      final contrast = _contrastColor(editColor);
      for (var j = 0; j < _editingControlIdxs.length; j++) {
        final idx = _editingControlIdxs[j];
        if (idx >= 0 && idx < pts.length) {
          final isActive = _selectionMode == _SelectionMode.controlPoint &&
              _activeControlPointIdx == j;
          markers.add(_controlMarkerAt(pts[idx], contrast, 'P${j + 1}',
              active: isActive));
        }
      }
    }

    return markers;
  }

  Marker _markerAt(LatLng point, Color color, String label,
      {IconData icon = Icons.circle, bool large = false}) {
    final size = large ? 32.0 : 22.0;
    return Marker(
      point: point,
      width: size + 8,
      height: size + 20,
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4), blurRadius: 4)
              ],
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.5),
          ),
          if (label.isNotEmpty)
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    shadows: [Shadow(color: Colors.black, blurRadius: 2)])),
        ],
      ),
    );
  }

  Marker _controlMarkerAt(LatLng point, Color color, String label,
      {bool active = false}) {
    final size = active ? 28.0 : 22.0;
    return Marker(
      point: point,
      width: size + 4,
      height: size + 4,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border:
              Border.all(color: Colors.white, width: active ? 3 : 2),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: active ? 10 : 4)
          ],
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.3,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  MapOptions get _mapOptions {
    final pts = widget.parsedTrack.points;
    final isSelecting = _selectionMode != _SelectionMode.none;
    final tapHandler =
        isSelecting ? (TapPosition _, LatLng ll) => _onMapTap(ll) : null;

    if (pts.isNotEmpty) {
      return MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(pts),
          padding: const EdgeInsets.all(32),
        ),
        onTap: tapHandler,
      );
    }
    return MapOptions(
      initialCenter: const LatLng(44.0, 11.0),
      initialZoom: 13,
      onTap: tapHandler,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Gestisci Speciali'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: AppColors.accent, strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save, color: AppColors.accent),
              onPressed: _save,
              tooltip: 'Salva speciali',
            ),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        if (isWide) {
          final ctrlWidth = constraints.maxWidth * 0.4;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: ctrlWidth,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildControlsPanel(),
                ),
              ),
              Expanded(child: _buildMap()),
            ],
          );
        }
        final mapH = (constraints.maxWidth * 0.75).clamp(220.0, 400.0);
        return Column(
          children: [
            SizedBox(height: mapH, child: _buildMap()),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _buildControlsPanel(),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildMap() {
    final isSelecting = _selectionMode != _SelectionMode.none;
    String bannerText = '';
    if (isSelecting) {
      if (_selectionMode == _SelectionMode.inizio) {
        bannerText = 'Clicca sulla traccia per selezionare l\'INIZIO';
      } else if (_selectionMode == _SelectionMode.fine) {
        bannerText = 'Clicca sulla traccia per selezionare la FINE';
      } else {
        final num = _activeControlPointIdx >= 0
            ? _activeControlPointIdx + 1
            : _editingControlIdxs.length + 1;
        bannerText = 'Clicca sulla traccia per posizionare P$num';
      }
    }

    return Stack(
      children: [
        MouseRegion(
          cursor: isSelecting
              ? SystemMouseCursors.precise
              : MouseCursor.defer,
          child: FlutterMap(
            options: _mapOptions,
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.ccr.ccr_app',
              ),
              PolylineLayer(polylines: _buildPolylines()),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),
        ),
        if (isSelecting)
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.cardBackground.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.accent),
              ),
              child: Text(bannerText,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                  textAlign: TextAlign.center),
            ),
          ),
      ],
    );
  }

  Widget _buildControlsPanel() {
    final pts = widget.parsedTrack.points;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_cachedTotalLength != null && _cachedTotalLength! > 0) ...[
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.route,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  'Traccia: ${_cachedTotalLength!.toStringAsFixed(1)} km',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${pts.length} pt)',
                  style: const TextStyle(
                      color: AppColors.border, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_isEditing) _buildEditingPanel() else _buildSpecialsList(),
      ],
    );
  }

  Widget _buildSpecialsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Text('Speciali',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              onPressed: _startAdd,
              icon: const Icon(Icons.add, color: AppColors.accent),
              label: const Text('Aggiungi',
                  style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_specials.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Nessuna speciale.\nPremi "Aggiungi" per crearne una.',
                style: TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...List.generate(
            _specials.length,
            (i) => SpecialTile(
              special: _specials[i],
              lengthKm: widget.parsedTrack.points.isNotEmpty
                  ? _sectionLength(
                      _ensureTrackIdx(_specials[i].waypointInizio),
                      _ensureTrackIdx(_specials[i].waypointFine))
                  : null,
              onEdit: () => _startEdit(i),
              onDelete: () => _deleteSpeciale(i),
            ),
          ),
      ],
    );
  }

  Widget _buildEditingPanel() {
    final pts = widget.parsedTrack.points;
    final editColor = AppColors
        .specialColors[_editingColorIndex % AppColors.specialColors.length];
    final hasPts = pts.isNotEmpty;
    final hasRange = _editingInicioIdx >= 0 &&
        _editingFineIdx >= 0 &&
        _editingFineIdx > _editingInicioIdx;
    final specialLen = hasPts && hasRange
        ? _sectionLength(_editingInicioIdx, _editingFineIdx)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              _editingIndex >= 0 ? 'Modifica speciale' : 'Nuova speciale',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close,
                  color: AppColors.textSecondary, size: 20),
              onPressed: _cancelEditing,
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Name
        TextField(
          controller: _nomeCtrl,
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Nome speciale',
            labelStyle:
                const TextStyle(color: AppColors.textSecondary),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                  color: AppColors.accent, width: 2),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),

        // Colors
        Row(
          children: [
            const Text('Colore:',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(width: 8),
            ...List.generate(AppColors.specialColors.length, (i) =>
              GestureDetector(
                onTap: () => setState(() => _editingColorIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: AppColors.specialColors[i],
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _editingColorIndex == i
                          ? Colors.white
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
              )),
          ],
        ),
        const SizedBox(height: 12),

        // Special length badge
        if (specialLen != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: editColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: editColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.straighten, size: 14, color: editColor),
                const SizedBox(width: 6),
                Text(
                  'Lunghezza speciale: ${specialLen.toStringAsFixed(2)} km',
                  style: TextStyle(
                      color: editColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

        // Inizio slider
        _buildSliderSection(
          label: 'INIZIO',
          color: AppColors.success,
          currentIdx: _editingInicioIdx,
          totalPts: pts.length,
          isMapActive: _selectionMode == _SelectionMode.inizio,
          onSliderChanged: hasPts
              ? (v) => setState(() {
                    _editingInicioIdx = v;
                    _selectionMode = _SelectionMode.none;
                    _reclampControlPoints();
                  })
              : null,
          onMapClick: hasPts
              ? () => setState(() {
                    _selectionMode =
                        _selectionMode == _SelectionMode.inizio
                            ? _SelectionMode.none
                            : _SelectionMode.inizio;
                    _activeControlPointIdx = -1;
                  })
              : null,
        ),
        const SizedBox(height: 6),

        // Fine slider
        _buildSliderSection(
          label: 'FINE',
          color: AppColors.error,
          currentIdx: _editingFineIdx,
          totalPts: pts.length,
          isMapActive: _selectionMode == _SelectionMode.fine,
          onSliderChanged: hasPts
              ? (v) => setState(() {
                    _editingFineIdx = v;
                    _selectionMode = _SelectionMode.none;
                    _reclampControlPoints();
                  })
              : null,
          onMapClick: hasPts
              ? () => setState(() {
                    _selectionMode =
                        _selectionMode == _SelectionMode.fine
                            ? _SelectionMode.none
                            : _SelectionMode.fine;
                    _activeControlPointIdx = -1;
                  })
              : null,
        ),
        const SizedBox(height: 6),
        if (_editingInicioIdx >= 0 &&
            _editingFineIdx >= 0 &&
            _editingFineIdx <= _editingInicioIdx) ...[
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border:
                  Border.all(color: AppColors.error.withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 14, color: AppColors.error),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'La fine deve essere successiva all\'inizio',
                    style: TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 8),

        // Control points
        _buildControlPointsSection(editColor, pts, hasPts),
        const SizedBox(height: 14),

        // Confirm
        ElevatedButton(
          onPressed: (_nomeCtrl.text.trim().isNotEmpty && hasRange)
              ? _confirmEditing
              : null,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              minimumSize: const Size(0, 44)),
          child: Text(
              _editingIndex >= 0 ? 'Salva modifiche' : 'Aggiungi speciale'),
        ),
      ],
    );
  }

  Widget _buildSliderSection({
    required String label,
    required Color color,
    required int currentIdx,
    required int totalPts,
    required bool isMapActive,
    required ValueChanged<int>? onSliderChanged,
    required VoidCallback? onMapClick,
  }) {
    final hasValue = currentIdx >= 0 && totalPts > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.5)),
            const Spacer(),
            if (hasValue)
              Text(
                '${currentIdx + 1} / $totalPts',
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontFamily: 'monospace'),
              ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onMapClick,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isMapActive
                      ? color.withValues(alpha: 0.15)
                      : AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: isMapActive ? color : AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isMapActive ? Icons.touch_app : Icons.map_outlined,
                      size: 13,
                      color: isMapActive
                          ? color
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isMapActive ? 'Clicca...' : 'Mappa',
                      style: TextStyle(
                          fontSize: 11,
                          color: isMapActive
                              ? color
                              : AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (totalPts > 0)
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: color,
              inactiveTrackColor: AppColors.border,
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.2),
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 8),
              trackHeight: 3,
              showValueIndicator: ShowValueIndicator.onlyForDiscrete,
            ),
            child: Slider(
              value:
                  currentIdx >= 0 ? currentIdx.toDouble() : 0.0,
              min: 0,
              max: (totalPts - 1).toDouble(),
              label: hasValue ? '${currentIdx + 1}/$totalPts' : '–',
              onChanged: onSliderChanged != null
                  ? (v) => onSliderChanged(v.round())
                  : null,
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              'Carica un file GPX per abilitare lo slider.',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _buildControlPointsSection(
      Color editColor, List<LatLng> pts, bool hasPts) {
    final contrast = _contrastColor(editColor);
    final canAdd = _editingControlIdxs.length < 10;
    final cpLo =
        (_editingInicioIdx >= 0 && _editingFineIdx > _editingInicioIdx)
            ? _editingInicioIdx
            : 0;
    final cpHi =
        (_editingFineIdx > _editingInicioIdx && pts.isNotEmpty)
            ? _editingFineIdx
            : (pts.isNotEmpty ? pts.length - 1 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              'Punti di controllo (${_editingControlIdxs.length}/10)',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (canAdd && hasPts)
              TextButton.icon(
                style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                onPressed: () {
                  setState(() {
                    _editingControlIdxs.add(cpLo);
                  });
                },
                icon: Icon(Icons.add_location, size: 14, color: contrast),
                label: Text('Aggiungi',
                    style: TextStyle(color: contrast, fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (_editingControlIdxs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Min 1 punto consigliato per la validazione GPS.',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
            ),
          ),
        ...List.generate(_editingControlIdxs.length, (j) {
          final cpIdx = _editingControlIdxs[j];
          final isActive =
              _selectionMode == _SelectionMode.controlPoint &&
                  _activeControlPointIdx == j;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                      color: contrast, shape: BoxShape.circle),
                  child: Center(
                    child: Text('P${j + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${cpIdx + 1} / ${pts.length}',
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10,
                                fontFamily: 'monospace'),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => setState(() {
                              if (isActive) {
                                _selectionMode = _SelectionMode.none;
                                _activeControlPointIdx = -1;
                              } else {
                                _selectionMode =
                                    _SelectionMode.controlPoint;
                                _activeControlPointIdx = j;
                              }
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? contrast.withValues(alpha: 0.2)
                                    : AppColors.cardBackground,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: isActive
                                        ? contrast
                                        : AppColors.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isActive
                                        ? Icons.touch_app
                                        : Icons.map_outlined,
                                    size: 12,
                                    color: isActive
                                        ? contrast
                                        : AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    isActive ? 'Clicca...' : 'Mappa',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: isActive
                                            ? contrast
                                            : AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: contrast,
                          inactiveTrackColor: AppColors.border,
                          thumbColor: contrast,
                          overlayColor: contrast.withValues(alpha: 0.2),
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6),
                          trackHeight: 2,
                        ),
                        child: Slider(
                          value: cpIdx.clamp(cpLo, cpHi).toDouble(),
                          min: cpLo.toDouble(),
                          max: cpHi.toDouble(),
                          onChanged: (v) => setState(() {
                            _editingControlIdxs[j] = v.round();
                            _selectionMode = _SelectionMode.none;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline,
                      color: AppColors.error, size: 18),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => setState(() {
                    _editingControlIdxs.removeAt(j);
                    if (_activeControlPointIdx >=
                        _editingControlIdxs.length) {
                      _activeControlPointIdx = -1;
                      _selectionMode = _SelectionMode.none;
                    }
                  }),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
