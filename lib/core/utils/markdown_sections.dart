/// Parser minimale per documenti markdown "a sezioni" (titolo H1, separatori
/// `---`, sezioni `## `, paragrafi, elenchi puntati `- ` con `**grassetto**`
/// inline). Usato per il Regolamento (testo statico, da NON riscrivere) e
/// per la Guida — entrambi renderizzati con lo stesso widget a sezioni
/// espandibili, vedi [MarkdownSectionsView].
library;

/// Un blocco di contenuto dentro una sezione: paragrafo semplice oppure
/// elenco puntato. Il grassetto `**...**` viene marcato ma non ancora
/// tokenizzato in span — lo fa il widget di rendering.
sealed class MdBlock {}

class MdParagraph implements MdBlock {
  final String text;
  final bool italic;
  const MdParagraph(this.text, {this.italic = false});
}

class MdBulletList implements MdBlock {
  final List<String> items;
  const MdBulletList(this.items);
}

class MdSection {
  final String title;
  final List<MdBlock> blocks;
  const MdSection(this.title, this.blocks);
}

class MdDocument {
  final String title;
  final List<MdSection> sections;
  const MdDocument(this.title, this.sections);
}

MdDocument parseMarkdownSections(String raw) {
  final lines = raw.split('\n');
  String title = '';
  final sections = <MdSection>[];
  String? currentTitle;
  final currentLines = <String>[];

  void flush() {
    if (currentTitle == null) return;
    sections.add(MdSection(currentTitle, _parseBlocks(currentLines)));
    currentLines.clear();
  }

  for (final line in lines) {
    final trimmed = line.trimRight();
    if (trimmed.startsWith('# ') && title.isEmpty) {
      title = trimmed.substring(2).trim();
      continue;
    }
    if (trimmed.trim() == '---') continue;
    if (trimmed.startsWith('## ')) {
      flush();
      currentTitle = trimmed.substring(3).trim();
      continue;
    }
    if (currentTitle != null) currentLines.add(trimmed);
  }
  flush();

  return MdDocument(title, sections);
}

List<MdBlock> _parseBlocks(List<String> lines) {
  final blocks = <MdBlock>[];
  final paragraphBuf = <String>[];
  final bulletBuf = <String>[];

  void flushParagraph() {
    if (paragraphBuf.isEmpty) return;
    final text = paragraphBuf.join(' ').trim();
    if (text.isNotEmpty) {
      final isItalic = text.startsWith('*') &&
          text.endsWith('*') &&
          !text.startsWith('**');
      blocks.add(MdParagraph(
        isItalic ? text.substring(1, text.length - 1) : text,
        italic: isItalic,
      ));
    }
    paragraphBuf.clear();
  }

  void flushBullets() {
    if (bulletBuf.isEmpty) return;
    blocks.add(MdBulletList(List.of(bulletBuf)));
    bulletBuf.clear();
  }

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      flushParagraph();
      continue;
    }
    if (trimmed.startsWith('- ')) {
      flushParagraph();
      bulletBuf.add(trimmed.substring(2).trim());
      continue;
    }
    flushBullets();
    paragraphBuf.add(trimmed);
  }
  flushParagraph();
  flushBullets();

  return blocks;
}
