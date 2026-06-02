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

  @override
  void initState() {
    super.initState();
    _specials = List.from(widget.event.speciali);
  }

  Future<void> _addSpeciale() async {
    final result = await showDialog<SpecialModel>(
      context: context,
      builder: (ctx) => _AddSpecialDialog(
        waypoints: widget.parsedTrack.waypoints,
        ordine: _specials.length,
        existingSpecials: _specials,
      ),
    );
    if (result != null) {
      setState(() => _specials.add(result));
    }
  }

  Future<void> _editSpeciale(int index) async {
    final result = await showDialog<SpecialModel>(
      context: context,
      builder: (ctx) => _AddSpecialDialog(
        waypoints: widget.parsedTrack.waypoints,
        ordine: _specials[index].ordine,
        existingSpecials: _specials,
        editing: _specials[index],
      ),
    );
    if (result != null) {
      setState(() => _specials[index] = result);
    }
  }

  void _deleteSpeciale(int index) {
    setState(() => _specials.removeAt(index));
    // Re-number ordine
    setState(() {
      for (int i = 0; i < _specials.length; i++) {
        _specials[i] = _specials[i].copyWith(ordine: i);
      }
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

  LatLng get _mapCenter {
    final pts = widget.parsedTrack.points;
    if (pts.isNotEmpty) {
      final avgLat =
          pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
      final avgLng =
          pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
      return LatLng(avgLat, avgLng);
    }
    final wpts = widget.parsedTrack.waypoints;
    if (wpts.isNotEmpty) {
      return wpts.first.latLng;
    }
    return const LatLng(44.0, 11.0);
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];
    for (final wp in widget.parsedTrack.waypoints) {
      Color color = AppColors.textSecondary;
      for (final s in _specials) {
        if (s.waypointInizio.id == wp.id) {
          color = AppColors.success;
          break;
        }
        if (s.waypointFine.id == wp.id) {
          color = AppColors.error;
          break;
        }
      }
      markers.add(Marker(
        point: wp.latLng,
        width: 44,
        height: 44,
        child: Column(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.flag, color: Colors.white, size: 14),
            ),
            Text(
              wp.nome,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  shadows: [Shadow(color: Colors.black, blurRadius: 2)]),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ));
    }

    final polylines = <Polyline>[];
    if (widget.parsedTrack.points.isNotEmpty) {
      polylines.add(Polyline(
          points: widget.parsedTrack.points,
          color: Colors.white38,
          strokeWidth: 2));
    }
    for (final s in _specials) {
      polylines.add(Polyline(
        points: [s.waypointInizio.latLng, s.waypointFine.latLng],
        color: s.color,
        strokeWidth: 4,
      ));
    }

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
          // Map
          SizedBox(
            height: 260,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _mapCenter,
                initialZoom: 13,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.ccr.ccr_app',
                ),
                PolylineLayer(polylines: polylines),
                MarkerLayer(markers: markers),
              ],
            ),
          ),
          // Specials list
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                  onPressed: _addSpeciale,
                  icon: const Icon(Icons.add, color: AppColors.accent),
                  label: const Text('Aggiungi',
                      style: TextStyle(color: AppColors.accent)),
                ),
              ],
            ),
          ),
          Expanded(
            child: _specials.isEmpty
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
                      onEdit: () => _editSpeciale(i),
                      onDelete: () => _deleteSpeciale(i),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// Dialog to add or edit a special
class _AddSpecialDialog extends StatefulWidget {
  final List<WaypointModel> waypoints;
  final int ordine;
  final List<SpecialModel> existingSpecials;
  final SpecialModel? editing;

  const _AddSpecialDialog({
    required this.waypoints,
    required this.ordine,
    required this.existingSpecials,
    this.editing,
  });

  @override
  State<_AddSpecialDialog> createState() => _AddSpecialDialogState();
}

class _AddSpecialDialogState extends State<_AddSpecialDialog> {
  final _nomeCtrl = TextEditingController();
  int _colorIndex = 0;
  WaypointModel? _inizio;
  WaypointModel? _fine;

  @override
  void initState() {
    super.initState();
    if (widget.editing != null) {
      final e = widget.editing!;
      _nomeCtrl.text = e.nome;
      _colorIndex = e.colorIndex;
      try {
        _inizio = widget.waypoints
            .firstWhere((w) => w.id == e.waypointInizio.id);
      } catch (_) {
        _inizio = e.waypointInizio;
      }
      try {
        _fine = widget.waypoints
            .firstWhere((w) => w.id == e.waypointFine.id);
      } catch (_) {
        _fine = e.waypointFine;
      }
    } else {
      _colorIndex = widget.ordine % AppColors.specialColors.length;
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBackground,
      title: Text(
        widget.editing != null ? 'Modifica Speciale' : 'Aggiungi Speciale',
        style: const TextStyle(color: AppColors.textPrimary),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _nomeCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Nome speciale',
                labelStyle: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Colore',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: List.generate(
                AppColors.specialColors.length,
                (i) => GestureDetector(
                  onTap: () => setState(() => _colorIndex = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 32,
                    height: 32,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: AppColors.specialColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _colorIndex == i
                            ? Colors.white
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Waypoint Inizio',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 4),
            _WaypointDropdown(
              waypoints: widget.waypoints,
              selected: _inizio,
              hint: 'Seleziona inizio',
              onChanged: (w) => setState(() => _inizio = w),
              accentColor: AppColors.success,
            ),
            const SizedBox(height: 12),
            const Text('Waypoint Fine',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 4),
            _WaypointDropdown(
              waypoints: widget.waypoints,
              selected: _fine,
              hint: 'Seleziona fine',
              onChanged: (w) => setState(() => _fine = w),
              accentColor: AppColors.error,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () {
            if (_nomeCtrl.text.trim().isEmpty) return;
            if (_inizio == null || _fine == null) return;
            final result = SpecialModel(
              id: widget.editing?.id ?? const Uuid().v4(),
              nome: _nomeCtrl.text.trim(),
              colorIndex: _colorIndex,
              waypointInizio: _inizio!,
              waypointFine: _fine!,
              ordine: widget.ordine,
            );
            Navigator.pop(context, result);
          },
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent),
          child: Text(widget.editing != null ? 'Salva' : 'Aggiungi'),
        ),
      ],
    );
  }
}

class _WaypointDropdown extends StatelessWidget {
  final List<WaypointModel> waypoints;
  final WaypointModel? selected;
  final String hint;
  final void Function(WaypointModel?) onChanged;
  final Color accentColor;

  const _WaypointDropdown({
    required this.waypoints,
    required this.selected,
    required this.hint,
    required this.onChanged,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    if (waypoints.isEmpty) {
      return const Text(
        'Nessun waypoint disponibile. Carica un file GPX.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      );
    }
    return DropdownButtonFormField<WaypointModel>(
      initialValue: selected,
      hint: Text(hint,
          style: const TextStyle(color: AppColors.textSecondary)),
      dropdownColor: AppColors.cardBackground,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accentColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accentColor.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accentColor, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: waypoints
          .map((w) => DropdownMenuItem(
                value: w,
                child: Text(w.nome,
                    style: const TextStyle(color: AppColors.textPrimary)),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}
