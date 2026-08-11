import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/markdown_sections.dart';

/// Rende un [MdDocument] come sezioni espandibili — usato da Regolamento e
/// Guida. La prima sezione è aperta di default, le altre no. Testo
/// leggibile: paragrafi distanziati, titoli in accent color, elenco
/// puntato con spaziatura generosa e grassetto inline `**...**` supportato.
class MarkdownSectionsView extends StatelessWidget {
  final MdDocument document;
  const MarkdownSectionsView({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < document.sections.length; i++)
          _SectionTile(
            section: document.sections[i],
            initiallyExpanded: i == 0,
          ),
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  final MdSection section;
  final bool initiallyExpanded;
  const _SectionTile({required this.section, required this.initiallyExpanded});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          iconColor: AppColors.accent,
          collapsedIconColor: AppColors.textSecondary,
          title: Text(
            section.title,
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          childrenPadding:
              const EdgeInsets.fromLTRB(16, 0, 16, 18),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final block in section.blocks) _BlockView(block: block),
          ],
        ),
      ),
    );
  }
}

class _BlockView extends StatelessWidget {
  final MdBlock block;
  const _BlockView({required this.block});

  @override
  Widget build(BuildContext context) {
    final block0 = block;
    if (block0 is MdParagraph) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: RichText(
          text: TextSpan(
            children: _inlineSpans(
              block0.text,
              TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                height: 1.55,
                fontStyle:
                    block0.italic ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ),
      );
    }
    if (block0 is MdBulletList) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in block0.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: Icon(Icons.circle,
                          size: 5, color: AppColors.accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          children: _inlineSpans(
                            item,
                            const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// `**testo**` → grassetto, resto invariato.
List<InlineSpan> _inlineSpans(String text, TextStyle base) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(r'\*\*(.+?)\*\*');
  int last = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start), style: base));
    }
    spans.add(TextSpan(
      text: m.group(1),
      style: base.copyWith(fontWeight: FontWeight.bold),
    ));
    last = m.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last), style: base));
  }
  return spans;
}
