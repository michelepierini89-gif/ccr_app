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

enum _SelectionMode { none, inizio, fine }

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

class _SpecialsEditorScreenState
    extends ConsumerState<SpecialsEditorScreen> {
  late List<SpecialModel> _specials;
  bool _isSaving = false;

  // Inline editing state
  bool _isEditing = false;
  int _editingIndex = -1;
  final _nomeCtrl = TextEditingController();
  int _editingColorIndex = 0;
  WaypointModel? _editingInizio;
  WaypointModel? _editingFine;
  _SelectionMode _selectionMode = _SelectionMode.none;

  @override
  void initState() {
    super.initState();
    _specials = List.from(widget.event.speciali);
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    super.dispose();
  }

  // --- Nearest track point (squared Euclidean — fast for 5000+ pts) ---
  WaypointModel _nearestTrackPoint(LatLng tapped) {
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
    final pt = pts[minIdx];
    return WaypointModel(
      id: 'track_pt_$minIdx',
      nome:
          '${pt.latitude.toStringAsFixed(5)}, ${pt.longitude.toStringAsFixed(5)}',
      lat: pt.latitude,
      lng: pt.longitude,
      type: WaypointType.intermedio,
    );
  }

  void _onMapTap(LatLng latlng) {
    if (_selectionMode == _SelectionMode.none) return;
    if (widget.parsedTrack.points.isEmpty) return;
    final wp = _nearestTrackPoint(latlng);
    setState(() {
      if (_selectionMode == _SelectionMode.inizio) {
        _editingInizio = wp;
      } else {
        _editingFine = wp;
      }
      _selectionMode = _SelectionMode.none;
    });
  }

  // --- Editing lifecycle ---
  void _startAdd() {
    setState(() {
      _isEditing = true;
      _editingIndex = -1;
      _editingColorIndex = _specials.length % AppColors.specialColors.length;
      _nomeCtrl.text = 'PS${_specials.length + 1}';
      _editingInizio = null;
      _editingFine = null;
      _selectionMode = _SelectionMode.none;
    });
  }

  void _startEdit(int index) {
    final s = _specials[index];
    setState(() {
      _isEditing = true;
      _editingIndex = index;
      _editingColorIndex = s.colorIndex;
      _nomeCtrl.text = s.nome;
      _editingInizio = s.waypointInizio;
      _editingFine = s.waypointFine;
      _selectionMode = _SelectionMode.none;
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _editingIndex = -1;
      _editingInizio = null;
      _editingFine = null;
      _selectionMode = _SelectionMode.none;
      _nomeCtrl.clear();
    });
  }

  void _confirmEditing() {
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty || _editingInizio == null || _editingFine == null) return;
    final special = SpecialModel(
      id: _editingIndex >= 0
          ? _specials[_editingIndex].id
          : const Uuid().v4(),
      nome: nome,
      colorIndex: _editingColorIndex,
      waypointInizio: _editingInizio!,
      waypointFine: _editingFine!,
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

  // --- Map options ---
  MapOptions get _mapOptions {
    final hasPts = widget.parsedTrack.points.isNotEmpty;
    final tapHandler = _selectionMode != _SelectionMode.none
        ? (TapPosition _, LatLng ll) => _onMapTap(ll)
        : null;

    if (hasPts) {
      return MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(widget.parsedTrack.points),
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

  // --- Build map markers ---
  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Existing specials (excluding the one being edited)
    for (var i = 0; i < _specials.length; i++) {
      if (i == _editingIndex) continue;
      final s = _specials[i];
      markers.add(_markerAt(s.waypointInizio.latLng, s.color, s.nome,
          icon: Icons.play_arrow));
      markers.add(
          _markerAt(s.waypointFine.latLng, s.color, '', icon: Icons.stop));
    }

    // Current editing markers
    final editColor = _isEditing
        ? AppColors.specialColors[
            _editingColorIndex % AppColors.specialColors.length]
        : null;
    if (_editingInizio != null && editColor != null) {
      markers.add(_markerAt(
          _editingInizio!.latLng, editColor, 'Inizio',
          icon: Icons.play_arrow, large: true));
    }
    if (_editingFine != null && editColor != null) {
      markers.add(_markerAt(
          _editingFine!.latLng, editColor, 'Fine',
          icon: Icons.stop, large: true));
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
            Text(
              label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  shadows: [Shadow(color: Colors.black, blurRadius: 2)]),
            ),
        ],
      ),
    );
  }

  // --- Polylines ---
  List<Polyline> _buildPolylines() {
    final polylines = <Polyline>[];
    if (widget.parsedTrack.points.isNotEmpty) {
      polylines.add(Polyline(
          points: widget.parsedTrack.points,
          color: AppColors.accent,
          strokeWidth: 3));
    }
    for (var i = 0; i < _specials.length; i++) {
      if (i == _editingIndex) continue;
      final s = _specials[i];
      polylines.add(Polyline(
        points: [s.waypointInizio.latLng, s.waypointFine.latLng],
        color: s.color,
        strokeWidth: 4,
      ));
    }
    // Current editing special polyline
    if (_editingInizio != null && _editingFine != null) {
      final c = AppColors.specialColors[
          _editingColorIndex % AppColors.specialColors.length];
      polylines.add(Polyline(
        points: [_editingInizio!.latLng, _editingFine!.latLng],
        color: c,
        strokeWidth: 4,
      ));
    }
    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    final isSelecting = _selectionMode != _SelectionMode.none;

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
      body: Column(
        children: [
          // --- Map ---
          SizedBox(
            height: 280,
            child: Stack(
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
                // Selection mode banner
                if (isSelecting)
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.accent),
                      ),
                      child: Text(
                        'Clicca sulla traccia per selezionare il punto di '
                        '${_selectionMode == _SelectionMode.inizio ? "inizio" : "fine"}',
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // --- Inline editing panel ---
          if (_isEditing) _buildEditingPanel(),

          // --- Specials list header ---
          if (!_isEditing)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  const Text(
                    'Speciali',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _startAdd,
                    icon: const Icon(Icons.add, color: AppColors.accent),
                    label: const Text('Aggiungi',
                        style: TextStyle(color: AppColors.accent)),
                  ),
                ],
              ),
            ),

          // --- Specials list ---
          Expanded(
            child: _specials.isEmpty && !_isEditing
                ? const Center(
                    child: Text(
                      'Nessuna speciale.\nPremi "Aggiungi" per crearne una.',
                      style: TextStyle(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _specials.length,
                    itemBuilder: (ctx, i) => SpecialTile(
                      special: _specials[i],
                      onEdit: () => _startEdit(i),
                      onDelete: () => _deleteSpeciale(i),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditingPanel() {
    final hasPts = widget.parsedTrack.points.isNotEmpty;
    return Container(
      color: AppColors.cardBackground,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Nome + colori
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nomeCtrl,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    labelText: 'Nome speciale',
                    labelStyle:
                        const TextStyle(color: AppColors.textSecondary),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: AppColors.accent, width: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Color picker
              Row(
                children: List.generate(
                  AppColors.specialColors.length,
                  (i) => GestureDetector(
                    onTap: () => setState(() => _editingColorIndex = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.only(left: 6),
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
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Inizio selector
          _buildPointSelector(
            label: 'Inizio',
            waypoint: _editingInizio,
            mode: _SelectionMode.inizio,
            color: AppColors.success,
            enabled: hasPts,
          ),
          const SizedBox(height: 8),
          // Fine selector
          _buildPointSelector(
            label: 'Fine',
            waypoint: _editingFine,
            mode: _SelectionMode.fine,
            color: AppColors.warning,
            enabled: hasPts,
          ),
          if (!hasPts)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Carica un file GPX per selezionare i punti sulla traccia.',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ),
          const SizedBox(height: 12),
          // Actions
          Row(
            children: [
              TextButton(
                onPressed: _cancelEditing,
                child: const Text('Annulla',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: (_editingInizio != null &&
                        _editingFine != null &&
                        _nomeCtrl.text.trim().isNotEmpty)
                    ? _confirmEditing
                    : null,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent),
                child: Text(
                    _editingIndex >= 0 ? 'Salva modifiche' : 'Aggiungi'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPointSelector({
    required String label,
    required WaypointModel? waypoint,
    required _SelectionMode mode,
    required Color color,
    required bool enabled,
  }) {
    final isActive = _selectionMode == mode;
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: OutlinedButton.icon(
            onPressed: enabled
                ? () => setState(() {
                      _selectionMode =
                          isActive ? _SelectionMode.none : mode;
                    })
                : null,
            icon: Icon(
              isActive ? Icons.my_location : Icons.add_location_alt,
              size: 16,
              color: isActive ? AppColors.accent : color,
            ),
            label: Text(
              isActive ? 'Clicca sulla mappa...' : 'Seleziona $label',
              style: TextStyle(
                  fontSize: 13,
                  color: isActive ? AppColors.accent : color),
            ),
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              side: BorderSide(
                  color: isActive ? AppColors.accent : color, width: 1.5),
            ),
          ),
        ),
        if (waypoint != null) ...[
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              '${waypoint.lat.toStringAsFixed(5)}, ${waypoint.lng.toStringAsFixed(5)}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}
