import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/classifica_model.dart';
import '../../../core/models/event_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../admin/providers/admin_provider.dart';
import '../providers/classifica_provider.dart';

class ClassificaScreen extends ConsumerWidget {
  final String eventId;
  final bool showAppBar;

  const ClassificaScreen({
    super.key,
    required this.eventId,
    this.showAppBar = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventStreamProvider(eventId));
    final classAv = ref.watch(classificaProvider(eventId));

    final event = eventAsync.valueOrNull;
    final isPunti = event?.tipologiaClassifica ==
        TipologiaClassifica.punteggioSpeciale;

    Widget body = classAv.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent)),
      error: (e, _) => Center(
          child: Text('Errore: $e',
              style: const TextStyle(color: AppColors.error))),
      data: (entries) => _ClassificaList(
          entries: entries, isPunti: isPunti, eventId: eventId),
    );

    if (!showAppBar) return body;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Classifica'),
        actions: [
          if (event != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _TipologiaBadge(event.tipologiaClassifica),
            ),
        ],
      ),
      body: body,
    );
  }
}

// ── Main list ─────────────────────────────────────────────────────────────────

class _ClassificaList extends StatelessWidget {
  final List<ClassificaEntry> entries;
  final bool isPunti;
  final String eventId;

  const _ClassificaList({
    required this.entries,
    required this.isPunti,
    required this.eventId,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.leaderboard_outlined,
                color: AppColors.textSecondary, size: 56),
            SizedBox(height: 16),
            Text(
              'Nessun dato disponibile',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'La classifica si aggiornerà quando\ni piloti inizieranno le prove speciali',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Separate active from retired
    final active = entries.where((e) => !e.ritirato).toList();
    final retired = entries.where((e) => e.ritirato).toList();

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      children: [
        // Live update indicator
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                    color: AppColors.accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              const Text(
                'AGGIORNAMENTO IN TEMPO REALE',
                style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // Active entries
        ...active.map((e) => _EntryCard(entry: e, isPunti: isPunti)),

        // Retired section
        if (retired.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.flag, color: AppColors.textSecondary, size: 14),
                SizedBox(width: 6),
                Text(
                  'RITIRATI',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1),
                ),
              ],
            ),
          ),
          ...retired.map((e) => _EntryCard(entry: e, isPunti: isPunti)),
        ],
      ],
    );
  }
}

// ── Entry card ────────────────────────────────────────────────────────────────

class _EntryCard extends StatefulWidget {
  final ClassificaEntry entry;
  final bool isPunti;

  const _EntryCard({required this.entry, required this.isPunti});

  @override
  State<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<_EntryCard> {
  bool _expanded = false;

  Color get _posColor {
    if (widget.entry.ritirato) return AppColors.textSecondary;
    return switch (widget.entry.posizione) {
      1 => const Color(0xFFFFD700),
      2 => const Color(0xFFC0C0C0),
      3 => const Color(0xFFCD7F32),
      _ => AppColors.textSecondary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final borderColor = e.isLive
        ? AppColors.accent.withValues(alpha: 0.6)
        : AppColors.border;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: e.isLive
            ? [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  blurRadius: 8,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
      child: Column(
        children: [
          // Main row
          InkWell(
            onTap: e.specialiCompletati.isNotEmpty
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Position badge
                  _PosBadge(
                      posizione: e.posizione,
                      color: _posColor,
                      ritirato: e.ritirato),
                  const SizedBox(width: 12),

                  // Name block
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.teamNome,
                                style: TextStyle(
                                  color: e.ritirato
                                      ? AppColors.textSecondary
                                      : AppColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (e.isLive)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.accent
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.accent),
                                ),
                                child: const Text('LIVE',
                                    style: TextStyle(
                                        color: AppColors.accent,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1)),
                              ),
                          ],
                        ),
                        if (e.membriNomi.length > 1 ||
                            e.membriNomi.first != e.teamNome) ...[
                          const SizedBox(height: 2),
                          Text(
                            e.membriNomi.join(' · '),
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        _SpecialiProgress(
                          completati: e.specialiCompletati.length,
                          totale: e.totaleSpeciali,
                          ritirato: e.ritirato,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Score / time
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (e.ritirato)
                        const Text('RIT.',
                            style: TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.bold,
                                fontSize: 14))
                      else if (widget.isPunti && e.punteggioTotale > 0)
                        Text(
                          '${e.punteggioTotale} pt',
                          style: TextStyle(
                            color: _posColor == AppColors.textSecondary
                                ? AppColors.textPrimary
                                : _posColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      else if (!widget.isPunti && e.tempoTotale != Duration.zero)
                        Text(
                          e.tempoTotaleFormatted,
                          style: TextStyle(
                            color: _posColor == AppColors.textSecondary
                                ? AppColors.textPrimary
                                : _posColor,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        )
                      else
                        const Text('—',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 16)),
                      if (e.specialiCompletati.isNotEmpty)
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: AppColors.textSecondary,
                          size: 16,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Expanded special breakdown
          if (_expanded && e.specialiCompletati.isNotEmpty)
            Container(
              decoration: const BoxDecoration(
                border: Border(
                    top: BorderSide(color: AppColors.border, width: 0.5)),
              ),
              child: Column(
                children: e.specialiCompletati
                    .map((s) => _SpecialRow(
                          special: s,
                          isPunti: widget.isPunti,
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _PosBadge extends StatelessWidget {
  final int posizione;
  final Color color;
  final bool ritirato;

  const _PosBadge(
      {required this.posizione, required this.color, required this.ritirato});

  @override
  Widget build(BuildContext context) {
    if (ritirato) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
        ),
        child: const Icon(Icons.flag, color: AppColors.error, size: 18),
      );
    }
    if (posizione == 0) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.border.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.hourglass_empty,
            color: AppColors.textSecondary, size: 16),
      );
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: posizione <= 3 ? 0.2 : 0.1),
        shape: BoxShape.circle,
        border: Border.all(
            color: color.withValues(alpha: posizione <= 3 ? 0.8 : 0.4)),
      ),
      child: Center(
        child: posizione == 1
            ? Icon(Icons.emoji_events, color: color, size: 18)
            : Text(
                '$posizione',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 14),
              ),
      ),
    );
  }
}

class _SpecialiProgress extends StatelessWidget {
  final int completati;
  final int totale;
  final bool ritirato;

  const _SpecialiProgress(
      {required this.completati,
      required this.totale,
      required this.ritirato});

  @override
  Widget build(BuildContext context) {
    if (totale == 0) return const SizedBox();
    final color = ritirato
        ? AppColors.textSecondary
        : completati == totale
            ? AppColors.success
            : completati > 0
                ? AppColors.warning
                : AppColors.textSecondary;

    return Row(
      children: [
        // progress dots
        ...List.generate(
          totale,
          (i) => Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: i < completati
                  ? color
                  : color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$completati/$totale SS',
          style: TextStyle(color: color, fontSize: 11),
        ),
      ],
    );
  }
}

class _SpecialRow extends StatelessWidget {
  final SpecialTempo special;
  final bool isPunti;

  const _SpecialRow({required this.special, required this.isPunti});

  void _showMissedCpsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.warning, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${special.specialeNome} — CP mancati',
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: special.missedCpPositions
              .map((pos) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.cancel_outlined,
                            color: AppColors.warning, size: 14),
                        const SizedBox(width: 8),
                        Text(
                          'P$pos non rilevato',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Chiudi',
                style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 48), // align with card content
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: Text(
                'SS${special.ordine + 1}',
                style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 9,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              special.specialeNome,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!special.controlPointsOk)
            GestureDetector(
              onTap: () => _showMissedCpsDialog(context),
              child: const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.warning_amber_rounded,
                    color: AppColors.warning, size: 14),
              ),
            ),
          Text(
            special.tempoFormatted,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _TipologiaBadge extends StatelessWidget {
  final TipologiaClassifica tipo;
  const _TipologiaBadge(this.tipo);

  @override
  Widget build(BuildContext context) {
    final label = tipo == TipologiaClassifica.sommaTempi ? 'TEMPI' : 'PUNTI';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: const TextStyle(
            color: AppColors.accent,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1),
      ),
    );
  }
}
