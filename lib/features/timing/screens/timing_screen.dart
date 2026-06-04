import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/classifica_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/csv_export.dart';
import '../../auth/providers/auth_provider.dart';
import '../../classifica/providers/classifica_provider.dart';
import '../../pilot/providers/pilot_provider.dart';

class TimingScreen extends ConsumerStatefulWidget {
  final String eventId;
  final bool adminView;

  const TimingScreen({
    super.key,
    required this.eventId,
    this.adminView = false,
  });

  @override
  ConsumerState<TimingScreen> createState() => _TimingScreenState();
}

class _TimingScreenState extends ConsumerState<TimingScreen> {
  Future<void> _onRefresh() async {
    ref.invalidate(classificaProvider(widget.eventId));
  }

  @override
  Widget build(BuildContext context) {
    final classAv = ref.watch(classificaProvider(widget.eventId));

    return classAv.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent)),
      error: (e, _) => Center(
          child: Text('Errore: $e',
              style: const TextStyle(color: AppColors.error))),
      data: (entries) {
        if (widget.adminView) {
          return _AdminTimingView(
              eventId: widget.eventId,
              entries: entries,
              onRefresh: _onRefresh);
        }
        return _PilotTimingView(
            eventId: widget.eventId,
            entries: entries,
            onRefresh: _onRefresh);
      },
    );
  }
}

// ── Admin view ─────────────────────────────────────────────────────────────────

class _AdminTimingView extends ConsumerWidget {
  final String eventId;
  final List<ClassificaEntry> entries;
  final Future<void> Function() onRefresh;

  const _AdminTimingView({
    required this.eventId,
    required this.entries,
    required this.onRefresh,
  });

  String _buildCsv() {
    final buf = StringBuffer();
    buf.writeln('Posizione,Squadra,Piloti,Speciali completate,Tempo totale');
    for (final e in entries) {
      final piloti = e.membriNomi.join(' / ');
      final pos = e.ritirato ? 'RIT' : (e.posizione == 0 ? 'NC' : '${e.posizione}');
      buf.writeln(
          '$pos,"${e.teamNome}","$piloti",${e.specialiCompletati.length}/${e.totaleSpeciali},${e.tempoTotaleFormatted}');
      for (final s in e.specialiCompletati) {
        buf.writeln(',,,${s.specialeNome},${s.tempoFormatted},${s.controlPointsOk ? "CP OK" : "CP MANCANTI"}');
      }
    }
    return buf.toString();
  }

  void _exportCsv(BuildContext context) async {
    try {
      await downloadCsvFile('tempi_$eventId.csv', _buildCsv());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('CSV scaricato'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Errore export: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_off, color: AppColors.textSecondary, size: 48),
            SizedBox(height: 12),
            Text('Nessun tempo registrato',
                style: TextStyle(color: AppColors.textSecondary)),
            SizedBox(height: 6),
            Text('I tempi appariranno quando i piloti completano le speciali',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          color: AppColors.cardBackground,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Text(
                '${entries.length} concorrenti',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _exportCsv(context),
                icon: const Icon(Icons.download, size: 16,
                    color: AppColors.accent),
                label: const Text('CSV',
                    style: TextStyle(
                        color: AppColors.accent, fontSize: 13)),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.cardBackground,
            onRefresh: onRefresh,
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              itemCount: entries.length,
              itemBuilder: (ctx, i) =>
                  _TimingEntryCard(entry: entries[i]),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Pilot view ─────────────────────────────────────────────────────────────────

class _PilotTimingView extends ConsumerWidget {
  final String eventId;
  final List<ClassificaEntry> entries;
  final Future<void> Function() onRefresh;

  const _PilotTimingView({
    required this.eventId,
    required this.entries,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserModelProvider);
    final regAsync = ref.watch(myRegistrationStreamProvider(eventId));

    final userId = userAsync.valueOrNull?.id;
    final squadraId = regAsync.valueOrNull?.squadraId;

    ClassificaEntry? myEntry;
    for (final e in entries) {
      if (squadraId != null && e.entryId == squadraId) {
        myEntry = e;
        break;
      }
      if (userId != null && e.entryId == userId) {
        myEntry = e;
        break;
      }
    }

    if (myEntry == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_off, color: AppColors.textSecondary, size: 48),
            SizedBox(height: 12),
            Text('Nessun tempo disponibile',
                style: TextStyle(color: AppColors.textSecondary)),
            SizedBox(height: 6),
            Text(
                'I tuoi tempi appariranno dopo aver completato le speciali',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    final entry = myEntry;
    final totalSpeciali = entry.totaleSpeciali;
    final completate = entry.specialiCompletati.length;

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.cardBackground,
      onRefresh: onRefresh,
      child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryCard(entry: entry),
          const SizedBox(height: 16),
          Text(
            'Prove speciali ($completate/$totalSpeciali)',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (entry.specialiCompletati.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: const Center(
                child: Text('Nessuna speciale completata',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ...entry.specialiCompletati.map(
              (s) => _SpecialTimingRow(special: s),
            ),
        ],
      ),
      ),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _TimingEntryCard extends StatefulWidget {
  final ClassificaEntry entry;
  const _TimingEntryCard({required this.entry});

  @override
  State<_TimingEntryCard> createState() => _TimingEntryCardState();
}

class _TimingEntryCardState extends State<_TimingEntryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final posColor = e.ritirato
        ? AppColors.error
        : e.posizione == 1
            ? const Color(0xFFFFD700)
            : AppColors.textSecondary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: e.ritirato
              ? AppColors.error.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(
                      e.ritirato
                          ? 'RIT'
                          : e.posizione == 0
                              ? 'NC'
                              : '${e.posizione}°',
                      style: TextStyle(
                          color: posColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.teamNome,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (e.membriNomi.length > 1)
                          Text(
                            e.membriNomi.join(' · '),
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        e.tempoTotaleFormatted,
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        '${e.specialiCompletati.length}/${e.totaleSpeciali} PS',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textSecondary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded && e.specialiCompletati.isNotEmpty) ...[
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                children: e.specialiCompletati
                    .map((s) => _SpecialTimingRow(special: s))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final ClassificaEntry entry;
  const _SummaryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final posColor = entry.ritirato
        ? AppColors.error
        : entry.posizione == 1
            ? const Color(0xFFFFD700)
            : AppColors.accent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: posColor),
      ),
      child: Row(
        children: [
          Column(
            children: [
              Text(
                entry.ritirato
                    ? 'RIT'
                    : entry.posizione == 0
                        ? 'NC'
                        : '${entry.posizione}°',
                style: TextStyle(
                  color: posColor,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'posizione',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(width: 20),
          const VerticalDivider(color: AppColors.border, width: 1),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.teamNome,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.tempoTotaleFormatted,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecialTimingRow extends StatelessWidget {
  final SpecialTempo special;
  const _SpecialTimingRow({required this.special});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            special.controlPointsOk
                ? Icons.check_circle
                : Icons.warning_amber_rounded,
            color: special.controlPointsOk
                ? AppColors.success
                : AppColors.warning,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              special.specialeNome,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
          Text(
            special.tempoFormatted,
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          if (!special.controlPointsOk) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.5)),
              ),
              child: const Text(
                'CP!',
                style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 9,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
