import 'dart:typed_data';

/// A parsed `.pptx` presentation: the slide size plus every slide's shapes.
///
/// Like [DocxContent], the model is framework-free: the parser in the data
/// layer produces it and the presentation layer maps it to widgets. All
/// geometry is in logical pixels on a canvas of [slideWidth] × [slideHeight];
/// the reader scales that canvas to fit the screen.
class PptxContent {
  final double slideWidth;
  final double slideHeight;
  final List<PptxSlide> slides;

  const PptxContent({
    required this.slideWidth,
    required this.slideHeight,
    required this.slides,
  });

  /// 16:9 at 96 dpi, PowerPoint's default slide size.
  static const PptxContent empty =
      PptxContent(slideWidth: 1280, slideHeight: 720, slides: []);

  bool get isEmpty => slides.isEmpty;
}

/// One slide: its background and its shapes, back to front.
///
/// Shapes inherited from the slide layout and master (logos, decorative bars)
/// are already merged in, so [shapes] is everything that is drawn.
class PptxSlide {
  /// Solid background colour as 0xAARRGGBB, or null for white.
  final int? backgroundArgb;

  /// Background picture, stretched over the whole slide, if any.
  final Uint8List? backgroundImage;

  final List<PptxShape> shapes;

  const PptxSlide({
    this.backgroundArgb,
    this.backgroundImage,
    required this.shapes,
  });
}

/// A rectangle on the slide canvas, in logical pixels.
class PptxRect {
  final double x;
  final double y;
  final double width;
  final double height;

  const PptxRect(this.x, this.y, this.width, this.height);
}

/// Base type for anything drawn on a slide.
sealed class PptxShape {
  final PptxRect frame;

  const PptxShape(this.frame);
}

/// The outline of an auto shape. Unsupported presets fall back to [rect].
enum PptxGeometry { rect, roundRect, ellipse }

/// Vertical placement of the text inside its shape (`a:bodyPr@anchor`).
enum PptxAnchor { top, middle, bottom }

/// Paragraph alignment (`a:pPr@algn`).
enum PptxAlign { left, center, right, justify }

/// A shape or text box (`p:sp`): an optional fill / outline plus text.
class PptxTextShape extends PptxShape {
  final List<PptxParagraph> paragraphs;
  final PptxGeometry geometry;
  final PptxAnchor anchor;

  /// Fill and outline colours as 0xAARRGGBB, or null for none.
  final int? fillArgb;
  final int? lineArgb;
  final double lineWidth;

  /// Inner padding between the shape edge and its text, in logical pixels.
  final double insetLeft;
  final double insetTop;
  final double insetRight;
  final double insetBottom;

  /// False when the text box is set not to wrap (`a:bodyPr@wrap="none"`).
  final bool wrap;

  const PptxTextShape(
    super.frame, {
    required this.paragraphs,
    this.geometry = PptxGeometry.rect,
    this.anchor = PptxAnchor.top,
    this.fillArgb,
    this.lineArgb,
    this.lineWidth = 1,
    this.insetLeft = 9.6,
    this.insetTop = 4.8,
    this.insetRight = 9.6,
    this.insetBottom = 4.8,
    this.wrap = true,
  });

  bool get hasText => paragraphs.any((p) => !p.isBlank);
}

/// A picture (`p:pic`), stretched to its frame.
class PptxImageShape extends PptxShape {
  final Uint8List bytes;

  const PptxImageShape(super.frame, this.bytes);
}

/// A table (`a:tbl` inside a `p:graphicFrame`).
class PptxTableShape extends PptxShape {
  /// Width of each grid column in logical pixels.
  final List<double> columnWidths;
  final List<List<PptxTableCell>> rows;

  const PptxTableShape(super.frame,
      {required this.columnWidths, required this.rows});
}

class PptxTableCell {
  final List<PptxParagraph> paragraphs;
  final int? fillArgb;

  /// True for cells swallowed by a neighbour's horizontal / vertical merge;
  /// they are laid out but left empty.
  final bool merged;

  const PptxTableCell({
    required this.paragraphs,
    this.fillArgb,
    this.merged = false,
  });
}

/// A paragraph of text with its resolved list / indent formatting.
class PptxParagraph {
  final List<PptxTextRun> runs;
  final PptxAlign align;

  /// Bullet text to draw before the paragraph ("•", "1.", "a)"), or null.
  final String? bullet;

  /// Left margin of the text and first-line indent (negative = hanging), in
  /// logical pixels.
  final double marginLeft;
  final double indent;

  /// Font size used for an empty paragraph, so blank lines keep their height.
  final double emptySize;

  const PptxParagraph({
    required this.runs,
    this.align = PptxAlign.left,
    this.bullet,
    this.marginLeft = 0,
    this.indent = 0,
    this.emptySize = 24,
  });

  bool get isBlank => runs.every((r) => r.text.trim().isEmpty);
}

/// A styled span of text (`a:r` + `a:rPr`), with inherited styles resolved.
class PptxTextRun {
  final String text;

  /// Font size in logical pixels.
  final double fontSize;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;

  /// Text colour as 0xAARRGGBB, or null for black.
  final int? colorArgb;

  const PptxTextRun(
    this.text, {
    required this.fontSize,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.colorArgb,
  });
}
