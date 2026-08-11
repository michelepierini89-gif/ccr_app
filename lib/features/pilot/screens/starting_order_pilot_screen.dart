import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/models/event_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../admin/providers/admin_provider.dart';
import '../providers/pilot_provider.dart';

class StartingOrderPilotScreen extends ConsumerWidget {
  final String eventId;
  const StartingOrderPilotScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventStreamProvider(eventId));
    final regAsync = ref.watch(myRegistrationStreamProvider(eventId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        title: eventAsync.when(
          data: (ev) => Text(
            ev != null ? 'Partenza — ${ev.nome}' : 'Ordine di partenza',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
            overflow: TextOverflow.ellipsis,
          ),
          loading: () => const Text('Ordine di partenza',
              style: TextStyle(color: AppColors.textPrimary)),
          error: (_, _) => const Text('Ordine di partenza',
              style: TextStyle(color: AppColors.textPrimary)),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SafeArea(bottom: true, child: eventAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.accent)),
        error: (e, _) => Center(
          child: Text('Errore: $e',
              style: const TextStyle(color: AppColors.error)),
        ),
        data: (event) {
          if (event == null) {
            return const Center(
              child: Text('Evento non trovato',
                  style: TextStyle(color: AppColors.textSecondary)),
            );
          }

          final slots = [...event.startingOrder]
            ..sort((a, b) => a.orderNumber.compareTo(b.orderNumber));

          final myTeamName = regAsync.valueOrNull?.teamName?.trim().toLowerCase();

          // Find pilot's own slot
          final mySlot = myTeamName != null
              ? slots.cast<StartingSlot?>().firstWhere(
                    (s) => s!.teamName.trim().toLowerCase() == myTeamName,
                    orElse: () => null,
                  )
              : null;

          if (slots.isEmpty) {
            return _EmptyPlaceholder();
          }

          return Column(
            children: [
              // Sticky banner for pilot's slot
              if (mySlot != null)
                _MySlotBanner(slot: mySlot),

              Expanded(
                child: ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: slots.length,
                  itemBuilder: (context, index) {
                    final slot = slots[index];
                    final isMe =
                        slot.teamName.trim().toLowerCase() == myTeamName;
                    return _SlotRow(slot: slot, isMe: isMe);
                  },
                ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }
}

// ── Slot row ─────────────────────────────────────────────────────────────────

class _SlotRow extends StatelessWidget {
  final StartingSlot slot;
  final bool isMe;

  const _SlotRow({required this.slot, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(slot.startTime.toLocal());

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isMe
            ? AppColors.accent.withValues(alpha: 0.10)
            : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: isMe ? AppColors.accent : Colors.transparent,
            width: 4,
          ),
          top: BorderSide(color: isMe ? AppColors.accent.withValues(alpha: 0.3) : AppColors.border),
          right: BorderSide(color: isMe ? AppColors.accent.withValues(alpha: 0.3) : AppColors.border),
          bottom: BorderSide(color: isMe ? AppColors.accent.withValues(alpha: 0.3) : AppColors.border),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Order number badge
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isMe
                    ? AppColors.accent.withValues(alpha: 0.18)
                    : AppColors.background,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '${slot.orderNumber}',
                style: TextStyle(
                  color: isMe ? AppColors.accent : AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Team name
            Expanded(
              child: Text(
                slot.teamName,
                style: TextStyle(
                  color: isMe ? AppColors.textPrimary : AppColors.textSecondary,
                  fontWeight:
                      isMe ? FontWeight.bold : FontWeight.normal,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            // Start time
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule,
                  size: 14,
                  color: isMe ? AppColors.accent : AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  timeStr,
                  style: TextStyle(
                    color: isMe ? AppColors.accent : AppColors.textSecondary,
                    fontWeight:
                        isMe ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sticky banner ─────────────────────────────────────────────────────────────

class _MySlotBanner extends StatelessWidget {
  final StartingSlot slot;
  const _MySlotBanner({required this.slot});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(slot.startTime.toLocal());
    return Container(
      width: double.infinity,
      color: AppColors.accent.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          const Text('🏁', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14),
                children: [
                  const TextSpan(text: 'La tua squadra parte alle '),
                  TextSpan(
                    text: timeStr,
                    style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
                  ),
                  TextSpan(
                    text: '  (n° ${slot.orderNumber})',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty placeholder ─────────────────────────────────────────────────────────

class _EmptyPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time,
                size: 64,
                color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 20),
            const Text(
              "L'organizzatore non ha ancora pubblicato l'ordine di partenza",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
