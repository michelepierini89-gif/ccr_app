import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/cp_dispute_model.dart';
import '../../../core/models/event_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../pilot/providers/pilot_provider.dart';
import '../providers/admin_provider.dart';
import 'cp_dispute_map_screen.dart';

/// Schermata dedicata alla verifica delle segnalazioni CP (Step 42) —
/// sostituisce il vecchio dialog che accettava/rifiutava l'intera
/// segnalazione in blocco. Ogni CP contestato ha qui accetta/rifiuta
/// indipendenti, un campo per la motivazione e un accesso diretto alla
/// mappa di analisi. "Accetta tutti"/"Rifiuta tutti" restano disponibili
/// come scorciatoia esplicita, non come unica via.
class CpDisputeReviewScreen extends ConsumerWidget {
  final String eventId;
  const CpDisputeReviewScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disputesAsync = ref.watch(cpDisputesStreamProvider(eventId));
    final event = ref.watch(eventStreamProvider(eventId)).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Verifica segnalazioni CP')),
      body: SafeArea(
        bottom: true,
        child: disputesAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.accent)),
          error: (e, _) => Center(
              child: Text('Errore: $e',
                  style: const TextStyle(color: AppColors.error))),
          data: (disputes) {
            if (disputes.isEmpty) {
              return const Center(
                child: Text('Nessuna segnalazione CP per questo evento',
                    style: TextStyle(color: AppColors.textSecondary)),
              );
            }
            final sorted = [...disputes]
              ..sort((a, b) {
                if (a.hasPending != b.hasPending) {
                  return a.hasPending ? -1 : 1;
                }
                return b.timestamp.compareTo(a.timestamp);
              });
            return ListView.builder(
              padding: EdgeInsets.fromLTRB(
                  16, 12, 16, 16 + MediaQuery.paddingOf(context).bottom),
              itemCount: sorted.length,
              itemBuilder: (ctx, i) =>
                  _DisputeCard(dispute: sorted[i], event: event),
            );
          },
        ),
      ),
    );
  }
}

class _DisputeCard extends ConsumerStatefulWidget {
  final CpDisputeModel dispute;
  final EventModel? event;
  const _DisputeCard({required this.dispute, required this.event});

  @override
  ConsumerState<_DisputeCard> createState() => _DisputeCardState();
}

class _DisputeCardState extends ConsumerState<_DisputeCard> {
  final Map<String, TextEditingController> _reasonControllers = {};
  bool _busy = false;

  TextEditingController _reasonCtrl(DisputedCp cp) => _reasonControllers
      .putIfAbsent(cp.cpId, () => TextEditingController(text: cp.decisionReason));

  @override
  void dispose() {
    for (final c in _reasonControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _apply(List<DisputedCp> updatedEntries) async {
    if (widget.event == null || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(firestoreServiceProvider).resolveCpDisputeEntries(
            event: widget.event!,
            disputeId: widget.dispute.id,
            pilotId: widget.dispute.pilotId,
            previousEntries: widget.dispute.missedCps,
            updatedEntries: updatedEntries,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Errore: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _decideOne(DisputedCp cp, CpDisputeStatus status) {
    final reason = _reasonCtrl(cp).text.trim();
    final updated = widget.dispute.missedCps
        .map((c) => c.cpId == cp.cpId
            ? c.copyWith(
                status: status,
                decisionReason: reason.isEmpty ? null : reason)
            : c)
        .toList();
    _apply(updated);
  }

  void _decideAll(CpDisputeStatus status) {
    final updated = widget.dispute.missedCps
        .map((c) => c.copyWith(status: status))
        .toList();
    _apply(updated);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dispute;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: d.hasPending
                ? AppColors.warning.withValues(alpha: 0.5)
                : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${d.pilotName} — ${d.teamName}',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
              if (d.hasPending) ...[
                TextButton(
                  onPressed: widget.event == null || _busy
                      ? null
                      : () => _decideAll(CpDisputeStatus.rejected),
                  child: const Text('Rifiuta tutti',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ),
                TextButton(
                  onPressed: widget.event == null || _busy
                      ? null
                      : () => _decideAll(CpDisputeStatus.accepted),
                  child: const Text('Accetta tutti',
                      style: TextStyle(color: AppColors.success, fontSize: 12)),
                ),
              ],
            ],
          ),
          if (d.pilotNote != null && d.pilotNote!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Nota generale: ${d.pilotNote}',
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 8),
          const Divider(color: AppColors.border, height: 1),
          for (final cp in d.missedCps) ...[
            const SizedBox(height: 10),
            _CpEntryRow(
              cp: cp,
              busy: _busy,
              reasonController: _reasonCtrl(cp),
              onAccept:
                  widget.event == null ? null : () => _decideOne(cp, CpDisputeStatus.accepted),
              onReject:
                  widget.event == null ? null : () => _decideOne(cp, CpDisputeStatus.rejected),
              onOpenMap: widget.event == null
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CpDisputeMapScreen(
                            event: widget.event!,
                            pilotId: d.pilotId,
                            pilotName: d.pilotName,
                            cp: cp,
                          ),
                        ),
                      ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CpEntryRow extends StatelessWidget {
  final DisputedCp cp;
  final bool busy;
  final TextEditingController reasonController;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onOpenMap;

  const _CpEntryRow({
    required this.cp,
    required this.busy,
    required this.reasonController,
    required this.onAccept,
    required this.onReject,
    required this.onOpenMap,
  });

  (String, Color) get _statusBadge => switch (cp.status) {
        CpDisputeStatus.pending => ('IN ATTESA', AppColors.warning),
        CpDisputeStatus.accepted => ('ACCOLTO', AppColors.success),
        CpDisputeStatus.rejected => ('RIFIUTATO', AppColors.error),
      };

  @override
  Widget build(BuildContext context) {
    final (label, color) = _statusBadge;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${cp.specialeNome} — P${cp.position} (${cp.cpNome})',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color),
                ),
                child: Text(label,
                    style: TextStyle(
                        color: color, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            cp.distanceMeters != null
                ? 'Distanza minima traccia-punto: ${cp.distanceMeters!.round()} m'
                : 'Distanza non disponibile',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          if (cp.pilotNote != null && cp.pilotNote!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Nota pilota: ${cp.pilotNote}',
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 6),
          TextField(
            controller: reasonController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 11),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Motivazione della decisione (opzionale)',
              hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: onOpenMap,
                icon: const Icon(Icons.map_outlined, size: 15),
                label: const Text('Mappa di analisi', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
              ),
              const Spacer(),
              TextButton(
                onPressed: busy ? null : onReject,
                child: const Text('Rifiuta',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: busy ? null : onAccept,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(horizontal: 14)),
                child: const Text('Accetta', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
