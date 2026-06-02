import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/gps_point_model.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/admin_provider.dart';

class LiveTrackingScreen extends ConsumerWidget {
  final String eventId;
  const LiveTrackingScreen({super.key, required this.eventId});

  Color _pilotColor(int index) {
    return AppColors.specialColors[index % AppColors.specialColors.length];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackingAsync = ref.watch(liveTrackingProvider(eventId));

    return trackingAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent)),
      error: (e, _) => Center(
          child: Text('Errore: $e',
              style: const TextStyle(color: AppColors.error))),
      data: (pilots) {
        final markers = <Marker>[];
        for (int i = 0; i < pilots.length; i++) {
          final p = pilots[i];
          final color = _pilotColor(i);
          markers.add(Marker(
            point: LatLng(p.lat, p.lng),
            width: 60,
            height: 60,
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.person,
                      color: Colors.white, size: 18),
                ),
                Text(
                  p.userId.length > 6
                      ? p.userId.substring(0, 6)
                      : p.userId,
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 2)
                    ],
                  ),
                ),
              ],
            ),
          ));
        }

        final center = pilots.isNotEmpty
            ? LatLng(pilots.first.lat, pilots.first.lng)
            : const LatLng(44.0, 11.0);

        return Column(
          children: [
            Expanded(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 13,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.ccr.ccr_app',
                  ),
                  MarkerLayer(markers: markers),
                ],
              ),
            ),
            if (pilots.isNotEmpty)
              Container(
                color: AppColors.cardBackground,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${pilots.length} piloti in tracciamento',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 60,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: pilots.length,
                        itemBuilder: (ctx, i) => _PilotChip(
                          pilot: pilots[i],
                          color: _pilotColor(i),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (pilots.isEmpty)
              Container(
                color: AppColors.cardBackground,
                padding: const EdgeInsets.all(24),
                child: const Center(
                  child: Text(
                    'Nessun pilota in tracciamento',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PilotChip extends StatelessWidget {
  final GpsPointModel pilot;
  final Color color;

  const _PilotChip({required this.pilot, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            pilot.userId.length > 8
                ? pilot.userId.substring(0, 8)
                : pilot.userId,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold),
          ),
          if (pilot.specialeId != null)
            Text(
              pilot.specialeId!,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 9),
            ),
        ],
      ),
    );
  }
}
