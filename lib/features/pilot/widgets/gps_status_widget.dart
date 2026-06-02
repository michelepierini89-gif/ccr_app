import 'package:flutter/material.dart';
import '../../../core/services/gps_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/location_utils.dart';

class GpsStatusWidget extends StatelessWidget {
  final GpsService gpsService;

  const GpsStatusWidget({super.key, required this.gpsService});

  Color get _modeColor {
    switch (gpsService.mode) {
      case GpsMode.idle:
        return AppColors.textSecondary;
      case GpsMode.transfer:
        return AppColors.textSecondary;
      case GpsMode.inSpecial:
        return AppColors.accent;
      case GpsMode.nearWaypoint:
        return AppColors.warning;
    }
  }

  String get _modeLabel {
    switch (gpsService.mode) {
      case GpsMode.idle:
        return 'INATTIVO';
      case GpsMode.transfer:
        return 'TRASFERIMENTO';
      case GpsMode.inSpecial:
        return 'IN SPECIALE';
      case GpsMode.nearWaypoint:
        return 'WAYPOINT VICINO';
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = gpsService.lastPosition;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Accuracy indicator
          if (pos != null) ...[
            Icon(
              pos.accuracy <= 10
                  ? Icons.gps_fixed
                  : pos.accuracy <= 30
                      ? Icons.gps_not_fixed
                      : Icons.gps_off,
              color: pos.accuracy <= 10
                  ? AppColors.success
                  : pos.accuracy <= 30
                      ? AppColors.warning
                      : AppColors.error,
              size: 18,
            ),
            const SizedBox(width: 4),
            Text(
              '±${pos.accuracy.toStringAsFixed(0)}m',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(width: 12),
          ],
          // Mode badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _modeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _modeColor),
            ),
            child: Text(
              _modeLabel,
              style: TextStyle(
                color: _modeColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const Spacer(),
          // Last update
          if (pos != null) ...[
            const Icon(Icons.access_time,
                color: AppColors.textSecondary, size: 14),
            const SizedBox(width: 4),
            Text(
              LocationUtils.formatTimestamp(DateTime.now()),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
