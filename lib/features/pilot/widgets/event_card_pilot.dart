import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/models/event_model.dart';
import '../../../core/models/registration_model.dart';
import '../../../core/theme/app_colors.dart';

class EventCardPilot extends StatelessWidget {
  final EventModel event;
  final RegistrationModel? registration;
  final VoidCallback? onTap;
  final VoidCallback? onRegister;

  const EventCardPilot({
    super.key,
    required this.event,
    this.registration,
    this.onTap,
    this.onRegister,
  });

  Color _regStatusColor(RegistrationStatus s) {
    switch (s) {
      case RegistrationStatus.inAttesa:
        return AppColors.warning;
      case RegistrationStatus.approvato:
        return AppColors.success;
      case RegistrationStatus.rifiutato:
        return AppColors.error;
    }
  }

  String _regStatusLabel(RegistrationStatus s) {
    switch (s) {
      case RegistrationStatus.inAttesa:
        return 'IN ATTESA';
      case RegistrationStatus.approvato:
        return 'APPROVATO';
      case RegistrationStatus.rifiutato:
        return 'RIFIUTATO';
    }
  }

  Color get _eventStatusColor {
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

  String get _eventStatusLabel {
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
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _eventStatusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _eventStatusColor),
                    ),
                    child: Text(
                      _eventStatusLabel,
                      style: TextStyle(
                        color: _eventStatusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
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
                  const SizedBox(width: 12),
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
              const SizedBox(height: 12),
              Row(
                children: [
                  if (registration != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _regStatusColor(registration!.stato)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: _regStatusColor(registration!.stato)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            registration!.stato ==
                                    RegistrationStatus.approvato
                                ? Icons.check_circle
                                : registration!.stato ==
                                        RegistrationStatus.rifiutato
                                    ? Icons.cancel
                                    : Icons.hourglass_empty,
                            color:
                                _regStatusColor(registration!.stato),
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _regStatusLabel(registration!.stato),
                            style: TextStyle(
                              color:
                                  _regStatusColor(registration!.stato),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    ElevatedButton(
                      onPressed: onRegister,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Iscriviti',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ],
                  const Spacer(),
                  if (event.speciali.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.route,
                            color: AppColors.textSecondary, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${event.speciali.length} speciali',
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
