import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/gps_point_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/admin_provider.dart';

class LiveTrackingScreen extends ConsumerWidget {
  final String eventId;
  const LiveTrackingScreen({super.key, required this.eventId});

  static const _onlineThreshold = Duration(seconds: 60);

  bool _isOnline(GpsPointModel p) =>
      DateTime.now().difference(p.timestamp) < _onlineThreshold;

  Color _pilotColor(int index) =>
      AppColors.specialColors[index % AppColors.specialColors.length];

  String _pilotLabel(GpsPointModel p, List<RegistrationModel> regs) {
    try {
      final reg = regs.firstWhere((r) => r.userId == p.userId);
      return '${reg.nome} ${reg.cognome[0]}.';
    } catch (_) {
      return p.userId.length > 6 ? p.userId.substring(0, 6) : p.userId;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackingAsync = ref.watch(liveTrackingProvider(eventId));
    final regsAsync = ref.watch(registrationsProvider(eventId));

    return trackingAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent)),
      error: (e, _) => Center(
          child: Text('Errore: $e',
              style: const TextStyle(color: AppColors.error))),
      data: (pilots) {
        final regs = regsAsync.valueOrNull ?? [];
        final onlinePilots = pilots.where(_isOnline).toList();
        final offlinePilots = pilots.where((p) => !_isOnline(p)).toList();

        final markers = <Marker>[];
        for (int i = 0; i < pilots.length; i++) {
          final p = pilots[i];
          final online = _isOnline(p);
          final color = online ? _pilotColor(i) : AppColors.textSecondary;
          final label = _pilotLabel(p, regs);
          markers.add(Marker(
            point: LatLng(p.lat, p.lng),
            width: 70,
            height: 64,
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: online
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            )
                          ]
                        : null,
                  ),
                  child: Icon(
                    online ? Icons.person : Icons.person_off,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: online ? color : AppColors.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ));
        }

        final mapCenter = onlinePilots.isNotEmpty
            ? LatLng(onlinePilots.first.lat, onlinePilots.first.lng)
            : pilots.isNotEmpty
                ? LatLng(pilots.first.lat, pilots.first.lng)
                : const LatLng(44.0, 11.0);

        return Column(
          children: [
            // Stats bar
            Container(
              color: AppColors.cardBackground,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  _StatChip(
                    icon: Icons.circle,
                    color: AppColors.success,
                    label: '${onlinePilots.length} online',
                  ),
                  const SizedBox(width: 12),
                  _StatChip(
                    icon: Icons.circle,
                    color: AppColors.textSecondary,
                    label: '${offlinePilots.length} offline',
                  ),
                  const Spacer(),
                  Text(
                    '${pilots.length} piloti totali',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            // Map
            Expanded(
              child: pilots.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.gps_off,
                              color: AppColors.textSecondary, size: 48),
                          SizedBox(height: 12),
                          Text(
                            'Nessun pilota in tracciamento',
                            style:
                                TextStyle(color: AppColors.textSecondary),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'I piloti appariranno qui quando\navviano la registrazione GPS',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : FlutterMap(
                      options: MapOptions(
                        initialCenter: mapCenter,
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
            // Pilot chips
            if (pilots.isNotEmpty)
              Container(
                color: AppColors.cardBackground,
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  height: 66,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: pilots.length,
                    itemBuilder: (ctx, i) => _PilotChip(
                      pilot: pilots[i],
                      label: _pilotLabel(pilots[i], regs),
                      color: _isOnline(pilots[i])
                          ? _pilotColor(i)
                          : AppColors.textSecondary,
                      online: _isOnline(pilots[i]),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _StatChip(
      {required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 10),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _PilotChip extends StatelessWidget {
  final GpsPointModel pilot;
  final String label;
  final Color color;
  final bool online;

  const _PilotChip({
    required this.pilot,
    required this.label,
    required this.color,
    required this.online,
  });

  String _elapsed() {
    final diff = DateTime.now().difference(pilot.timestamp);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s fa';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m fa';
    return '${diff.inHours}h fa';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: online ? AppColors.success : AppColors.textSecondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Text(
            _elapsed(),
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 9),
          ),
        ],
      ),
    );
  }
}
