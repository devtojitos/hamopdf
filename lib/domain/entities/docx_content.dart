import 'dart:typed_data';

/// A parsed `.docx` document, as an ordered list of block-level elements.
///
/// The model is deliberately framework-free (no Flutter imports): the parser in
/// the data layer produces it, and the presentation layer maps it to widgets.
class DocxContent {
  final List<DocxBlock> blocks;

  const DocxContent(this.blocks);

  static const DocxContent empty = DocxContent([]);

  bool get isEmpty => blocks.isEmpty;
}

/// Paragraph text alignment (maps to `w:jc`).
enum DocxAlign { left, center, right, justify }

/// The marker style for a list paragraph (from `w:numFmt`).
enum DocxListMarker { bullet, number }

/// Vertical alignment of a run (`w:vertAlign`): normal, super- or subscript.
enum DocxVerticalAlign { baseline, superscript, subscript }

/// Base type for block-level content: paragraphs and tables.
sealed class DocxBlock {}

/// A single paragraph: a run of inline pieces sharing alignment / list / heading
/// context.
class DocxParagraph extends DocxBlock {
  final List<DocxInline> inlines;
  final DocxAlign align;

  /// 0 for body text, 1-6 for `Heading1`..`Heading6`.
  final int headingLevel;

  /// Non-null when this paragraph is a list item.
  final DocxListMarker? listMarker;

  /// Indentation level of the list item (0 = top level).
  final int listLevel;

  DocxParagraph({
    required this.inlines,
    this.align = DocxAlign.left,
    this.headingLevel = 0,
    this.listMarker,
    this.listLevel = 0,
  });

  bool get isHeading => headingLevel > 0;
  bool get isListItem => listMarker != null;

  /// True when the paragraph carries no visible content (blank spacer line).
  bool get isBlank =>
      inlines.every((i) => i is DocxTextRun && i.text.trim().isEmpty);
}

/// A table: a list of rows, each a list of cells.
class DocxTable extends DocxBlock {
  final List<List<DocxTableCell>> rows;

  DocxTable(this.rows);
}

/// A table cell holds its own block-level content (paragraphs, nested tables).
class DocxTableCell {
  final List<DocxBlock> blocks;

  DocxTableCell(this.blocks);
}

/// Base type for inline content inside a paragraph: text runs and images.
sealed class DocxInline {}

/// A styled span of text (`w:r` + `w:rPr`).
class DocxTextRun extends DocxInline {
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;

  /// Foreground colour as 0xAARRGGBB, or null to inherit.
  final int? colorArgb;

  /// Highlight/background colour as 0xAARRGGBB, or null for none.
  final int? highlightArgb;

  /// Font size in logical pixels, or null to inherit the base size.
  final double? fontSize;

  final DocxVerticalAlign vAlign;

  DocxTextRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.colorArgb,
    this.highlightArgb,
    this.fontSize,
    this.vAlign = DocxVerticalAlign.baseline,
  });
}

/// An inline embedded image (`w:drawing` / `w:pict`).
class DocxImageRun extends DocxInline {
  final Uint8List bytes;

  /// Intended display size in logical pixels (from the drawing extent), if known.
  final double? width;
  final double? height;

  DocxImageRun(this.bytes, {this.width, this.height});
}
