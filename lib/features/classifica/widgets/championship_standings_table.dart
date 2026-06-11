import 'package:flutter/material.dart';
import '../../../core/models/classifica_model.dart';
import '../../../core/models/event_model.dart';
import '../../../core/theme/app_colors.dart';

/// Tabella classifica di campionato: Pos | Squadra | Punti totali, con
/// dettaglio per gara espandibile al tap. Usata sia in admin che lato pilota.
class ChampionshipStandingsTable extends StatefulWidget {
  final List<ChampionshipTeamStanding> teams;
  final Color color;
  final String? highlightTeamId;

  const ChampionshipStandingsTable({
    super.key,
    required this.teams,
    required this.color,
    this.highlightTeamId,
  });

  @override
  State<ChampionshipStandingsTable> createState() =>
      _ChampionshipStandingsTableState();
}

class _ChampionshipStandingsTableState
    extends State<ChampionshipStandingsTable> {
  final Set<String> _expanded = {};

  Color? _podiumColor(int pos) => switch (pos) {
        1 => const Color(0xFFFFD700),
        2 => const Color(0xFFC0C0C0),
        3 => const Color(0xFFCD7F32),
        _ => null,
      };

  IconData _podiumIcon(int pos) => switch (pos) {
        1 => Icons.emoji_events,
        2 => Icons.workspace_premium,
        _ => Icons.military_tech,
      };

  String _tipologiaBadge(TipologiaClassifica t) => switch (t) {
        TipologiaClassifica.sommaTempi => 'Gara a tempi',
        TipologiaClassifica.punteggioSpeciale => 'Gara a punti',
      };

  @override
  Widget build(BuildContext context) {
    final teams = widget.teams;
    if (teams.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.leaderboard_outlined,
                color: widget.color.withValues(alpha: 0.5), size: 64),
            const SizedBox(height: 16),
            const Text('Nessun dato disponibile',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
                'I punti appariranno qui al termine delle gare del campionato.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (teams.length >= 3) ...[
          const Text('Podio',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildPodium(teams.take(3).toList()),
          const SizedBox(height: 20),
        ],
        const Text('Classifica completa',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...teams.map((t) {
          final podiumColor = _podiumColor(t.posizione);
          final isMine = widget.highlightTeamId != null &&
              t.teamId == widget.highlightTeamId;
          final expanded = _expanded.contains(t.teamId);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isMine
                  ? const Color(0xFFe53e1e).withValues(alpha: 0.12)
                  : AppColors.cardBackground,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isMine
                    ? const Color(0xFFe53e1e)
                    : (podiumColor != null
                        ? podiumColor.withValues(alpha: 0.5)
                        : AppColors.border),
              ),
            ),
            child: Column(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() {
                    if (expanded) {
                      _expanded.remove(t.teamId);
                    } else {
                      _expanded.add(t.teamId);
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: podiumColor != null
                              ? Icon(_podiumIcon(t.posizione),
                                  color: podiumColor, size: 20)
                              : Text(
                                  '${t.posizione}',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                        ),
                        Expanded(
                          child: Text(t.teamNome,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                        ),
                        Text(
                          '${t.totalPoints} pt',
                          style: TextStyle(
                            color: podiumColor ?? AppColors.accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          expanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                if (expanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: t.races.map((r) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.eventNome,
                                      style: TextStyle(
                                        color: r.dropped
                                            ? AppColors.textSecondary
                                            : AppColors.textPrimary,
                                        fontSize: 13,
                                        decoration: r.dropped
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                    Container(
                                      margin:
                                          const EdgeInsets.only(top: 2),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppColors.background,
                                        borderRadius:
                                            BorderRadius.circular(4),
                                        border: Border.all(
                                            color: AppColors.border),
                                      ),
                                      child: Text(
                                        _tipologiaBadge(r.tipologia),
                                        style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 10),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${r.points} pt',
                                style: TextStyle(
                                  color: r.dropped
                                      ? AppColors.textSecondary
                                      : AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  decoration: r.dropped
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPodium(List<ChampionshipTeamStanding> top) {
    final medals = [
      const Color(0xFFFFD700),
      const Color(0xFFC0C0C0),
      const Color(0xFFCD7F32),
    ];
    final heights = [80.0, 60.0, 50.0];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: top.asMap().entries.map((e) {
        final idx = e.key;
        final t = e.value;
        final c = medals[idx.clamp(0, 2)];
        final h = heights[idx.clamp(0, 2)];
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                Text(t.teamNome,
                    style: TextStyle(
                        color: c, fontSize: 11, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('${t.totalPoints} pt',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 10)),
                const SizedBox(height: 4),
                Container(
                  height: h,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.2),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8)),
                    border: Border.all(color: c.withValues(alpha: 0.6)),
                  ),
                  child: Center(
                    child: Text(
                      '${idx + 1}°',
                      style: TextStyle(
                          color: c, fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
