import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/event_model.dart';
import '../../../core/services/offline_tile_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../pilot/providers/pilot_provider.dart';

class OfflineMapsScreen extends ConsumerStatefulWidget {
  const OfflineMapsScreen({super.key});

  @override
  ConsumerState<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends ConsumerState<OfflineMapsScreen> {
  bool _downloading = false;
  int _done = 0;
  int _total = 0;
  int _cacheSizeBytes = 0;
  String? _activeDownloadEventId;

  @override
  void initState() {
    super.initState();
    OfflineTileService.instance.init().then((_) => _refreshCacheSize());
  }

  Future<void> _refreshCacheSize() async {
    final size = await OfflineTileService.instance.getCacheSizeBytes();
    if (mounted) setState(() => _cacheSizeBytes = size);
  }

  Future<void> _downloadEvent(EventModel event) async {
    final bbox = _eventBbox(event);
    if (bbox == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Evento senza speciali — nessun\'area da scaricare.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    setState(() {
      _downloading = true;
      _done = 0;
      _total = 0;
      _activeDownloadEventId = event.id;
    });
    await OfflineTileService.instance.downloadBoundingBox(
      sw: bbox.$1,
      ne: bbox.$2,
      minZoom: 10,
      maxZoom: 16,
      onProgress: (done, total) {
        if (mounted) setState(() { _done = done; _total = total; });
      },
    );
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _activeDownloadEventId = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    await _refreshCacheSize();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Download completato per ${event.nome}.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _clearCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Cancella cache tile',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
            'Tutti i tile scaricati verranno eliminati. Continuare?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ANNULLA',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('CANCELLA',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await OfflineTileService.instance.clearCache();
    await _refreshCacheSize();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cache tile eliminata.'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  /// Returns (SW, NE) bounding box with 10 km padding around all special waypoints.
  (LatLng, LatLng)? _eventBbox(EventModel event) {
    final lats = <double>[];
    final lons = <double>[];
    for (final s in event.speciali) {
      if (s.annullata) continue;
      lats.addAll([s.waypointInizio.lat, s.waypointFine.lat]);
      lons.addAll([s.waypointInizio.lng, s.waypointFine.lng]);
      for (final cp in s.controlPoints) {
        lats.add(cp.lat);
        lons.add(cp.lng);
      }
    }
    if (lats.isEmpty) return null;
    const pad = 0.09; // ~10 km
    final sw = LatLng(
        lats.reduce((a, b) => a < b ? a : b) - pad,
        lons.reduce((a, b) => a < b ? a : b) - pad);
    final ne = LatLng(
        lats.reduce((a, b) => a > b ? a : b) + pad,
        lons.reduce((a, b) => a > b ? a : b) + pad);
    return (sw, ne);
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(openEventsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Mappe offline',
            style: TextStyle(color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          if (_cacheSizeBytes > 0)
            TextButton.icon(
              onPressed: _downloading ? null : _clearCache,
              icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
              label: Text(_fmtBytes(_cacheSizeBytes),
                  style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ),
        ],
      ),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Errore: $e',
              style: const TextStyle(color: AppColors.error)),
        ),
        data: (events) {
          if (events.isEmpty) {
            return const Center(
              child: Text('Nessun evento disponibile.',
                  style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            itemBuilder: (ctx, i) {
              final event = events[i];
              final isActive = _activeDownloadEventId == event.id;
              return Card(
                color: AppColors.cardBackground,
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.nome,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(
                        '${event.speciali.where((s) => !s.annullata).length} speciali',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                      if (isActive && _downloading) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: _total > 0 ? _done / _total : null,
                          backgroundColor:
                              AppColors.border.withValues(alpha: 0.3),
                          color: AppColors.accent,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _total > 0
                              ? 'Download: $_done / $_total tile'
                              : 'Preparazione...',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _downloading
                                ? null
                                : () => _downloadEvent(event),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.download, size: 18),
                            label: const Text('Scarica mappe',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
