import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/map/map_style.dart';
import '../../../core/models/event_model.dart';
import '../../../core/providers/track_appearance_provider.dart';
import '../../../core/services/offline_tile_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/offline_region_utils.dart';
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
  List<OfflineRegionInfo> _regions = const [];

  @override
  void initState() {
    super.initState();
    OfflineTileService.instance.init().then((_) => _refresh());
  }

  Future<void> _refresh() async {
    final size = await OfflineTileService.instance.getCacheSizeBytes();
    final regions = await OfflineTileService.instance.getRegionInfos();
    if (mounted) {
      setState(() {
        _cacheSizeBytes = size;
        _regions = regions;
      });
    }
  }

  Future<void> _downloadEvent(EventModel event) async {
    final bbox = OfflineRegionUtils.eventBoundingBox(event);
    if (bbox == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Evento senza speciali — nessun\'area da scaricare.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    // Scarica per lo stile ATTUALMENTE selezionato in navigazione (Step 49,
    // Parte 2c): stili diversi hanno cache separate, scaricare con uno non
    // rende disponibile l'altro.
    final style = ref.read(trackAppearanceProvider).mapStyle;
    setState(() {
      _downloading = true;
      _done = 0;
      _total = 0;
      _activeDownloadEventId = event.id;
    });
    await OfflineTileService.instance.downloadBoundingBox(
      eventId: event.id,
      eventNome: event.nome,
      styleId: style.id,
      sw: bbox.$1,
      ne: bbox.$2,
      minZoom: 10,
      maxZoom: 17,
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
    await _refresh();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Download completato per ${event.nome} (${style.label}).'),
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
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cache tile eliminata.'),
          backgroundColor: AppColors.success,
        ),
      );
    }
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
      body: SafeArea(bottom: true, child: eventsAsync.when(
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
          final currentStyle = ref.watch(trackAppearanceProvider).mapStyle;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            itemBuilder: (ctx, i) {
              final event = events[i];
              final isActive = _activeDownloadEventId == event.id;
              final eventRegions =
                  _regions.where((r) => r.eventId == event.id).toList();
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
                        '${event.activeSpeciali.where((s) => !s.annullata).length} speciali'
                        '${event.routeB != null ? ' — copre anche il percorso alternativo' : ''}',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                      // Step 49, Parte 1c/2c — stato reale della cache per
                      // questo evento, per stile: senza questo il pilota
                      // non ha modo di sapere se "Scarica mappe" ha
                      // prodotto qualcosa di effettivamente utilizzabile.
                      if (eventRegions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final r in eventRegions)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (r.styleId == currentStyle.id
                                          ? AppColors.accent
                                          : AppColors.border)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: r.styleId == currentStyle.id
                                        ? AppColors.accent
                                        : AppColors.border,
                                  ),
                                ),
                                child: Text(
                                  '${MapStyle.fromId(r.styleId).label} · '
                                  '${r.tileCount} tile · '
                                  'z${r.minZoom}-${r.maxZoom}',
                                  style: TextStyle(
                                    color: r.styleId == currentStyle.id
                                        ? AppColors.accent
                                        : AppColors.textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (eventRegions.isEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Nessuna mappa scaricata per questo evento.',
                          style: TextStyle(
                              color: AppColors.warning, fontSize: 11),
                        ),
                      ] else if (!eventRegions
                          .any((r) => r.styleId == currentStyle.id)) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Non scaricata per lo stile attuale (${currentStyle.label}).',
                          style: const TextStyle(
                              color: AppColors.warning, fontSize: 11),
                        ),
                      ],
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
                            label: Text(
                                'Scarica mappe (${currentStyle.label})',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
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
      ),
    );
  }
}
