import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/models/event_model.dart';
import '../../../core/theme/app_colors.dart';

class EventCardAdmin extends StatelessWidget {
  final EventModel event;
  final int? pilotCount;
  final VoidCallback? onTap;

  const EventCardAdmin({
    super.key,
    required this.event,
    this.pilotCount,
    this.onTap,
  });

  Color get _statusColor {
    switch (event.stato) {
      case EventStatus.bozza:
        return AppColors.textSecondary;
      case EventStatus.aperto:
        return AppColors.success;
      case EventStatus.inCorso:
        return AppColors.accent;
      case EventStatus.concluso:
        return AppColors.warning;
    }
  }

  String get _statusLabel {
    switch (event.stato) {
      case EventStatus.bozza:
        return 'BOZZA';
      case EventStatus.aperto:
        return 'APERTO';
      case EventStatus.inCorso:
        return 'IN CORSO';
      case EventStatus.concluso:
        return 'CONCLUSO';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      event.nome,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _statusColor, width: 1),
                    ),
                    child: Text(
                      _statusLabel,
                      style: TextStyle(
                        color: _statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today,
                      color: AppColors.textSecondary, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('dd/MM/yyyy').format(event.data),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.location_on,
                      color: AppColors.textSecondary, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      event.luogo,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (pilotCount != null || event.speciali.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (pilotCount != null) ...[
                      const Icon(Icons.people,
                          color: AppColors.textSecondary, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '$pilotCount piloti',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(width: 16),
                    ],
                    const Icon(Icons.route,
                        color: AppColors.textSecondary, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${event.speciali.length} speciali',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
