/// A parsed Markdown document, as an ordered list of block-level elements.
///
/// Like [DocxContent], the model is deliberately framework-free (no Flutter
/// imports): the parser in the data layer produces it, and the presentation
/// layer maps it to widgets.
class MarkdownContent {
  final List<MdBlock> blocks;

  const MarkdownContent(this.blocks);

  static const MarkdownContent empty = MarkdownContent([]);

  bool get isEmpty => blocks.isEmpty;
}

/// Cell alignment for a table column (from the `---:` delimiter row).
enum MdAlign { left, center, right }

/// The marker style of a list.
enum MdListMarker { bullet, number }

/// Base type for block-level content.
sealed class MdBlock {}

/// A heading, `#` through `######`.
class MdHeading extends MdBlock {
  /// 1-6, matching the number of leading `#` characters.
  final int level;
  final List<MdInline> inlines;

  MdHeading({required this.level, required this.inlines});
}

/// A run of body text.
class MdParagraph extends MdBlock {
  final List<MdInline> inlines;

  MdParagraph(this.inlines);
}

/// A bulleted or numbered list.
class MdList extends MdBlock {
  final MdListMarker marker;

  /// The number the first item counts from (`3.` starts an ordered list at 3).
  final int start;
  final List<MdListItem> items;

  MdList({required this.marker, required this.items, this.start = 1});
}

/// One list item. Items hold blocks so they can nest lists and code.
class MdListItem {
  final List<MdBlock> blocks;

  /// Non-null for GitHub task list items (`- [ ]` / `- [x]`).
  final bool? checked;

  MdListItem(this.blocks, {this.checked});
}

/// A fenced or indented code block.
class MdCodeBlock extends MdBlock {
  final String text;

  /// The info string after the opening fence (`dart`, `json`, …), if any.
  final String? language;

  MdCodeBlock(this.text, {this.language});
}

/// A `>` blockquote, holding its own block-level content.
class MdQuote extends MdBlock {
  final List<MdBlock> blocks;

  MdQuote(this.blocks);
}

/// A thematic break (`---`, `***`, `___`).
class MdRule extends MdBlock {}

/// A pipe table with a header row and zero or more body rows.
class MdTable extends MdBlock {
  final List<List<MdInline>> header;
  final List<List<List<MdInline>>> rows;
  final List<MdAlign> alignments;

  MdTable({
    required this.header,
    required this.rows,
    required this.alignments,
  });
}

/// Base type for inline content inside a block.
sealed class MdInline {}

/// A styled span of text.
class MdTextSpan extends MdInline {
  final String text;
  final bool bold;
  final bool italic;
  final bool strikethrough;
  final bool code;

  /// Set when the span is a link; holds the destination.
  final String? href;

  MdTextSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
    this.code = false,
    this.href,
  });
}

/// An image reference, `![alt](src)`.
///
/// [src] is kept as written in the document; the renderer resolves it relative
/// to the file's own directory (or loads it over the network for URLs).
class MdImageSpan extends MdInline {
  final String src;
  final String alt;

  MdImageSpan({required this.src, this.alt = ''});
}

/// A hard line break inside a paragraph (two trailing spaces or a `\`).
class MdLineBreak extends MdInline {}
