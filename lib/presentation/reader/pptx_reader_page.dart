import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/pdf_document.dart';
import '../../domain/entities/pptx_content.dart';
import '../home/home_controller.dart';
import 'download_button.dart';
import 'share_button.dart';

/// Renders a `.pptx` presentation as a scrolling column of slides.
///
/// Each slide is laid out at its native size (shapes positioned exactly as in
/// the file) and then scaled as a whole to the screen width, so text, pictures
/// and spacing keep their proportions on any device.
class PptxReaderPage extends StatefulWidget {
  final PdfDocument document;

  const PptxReaderPage({super.key, required this.document});

  @override
  State<PptxReaderPage> createState() => _PptxReaderPageState();
}

class _PptxReaderPageState extends State<PptxReaderPage> {
  static const double _maxSlideWidth = 960;

  late Future<PptxContent> _contentFuture;

  @override
  void initState() {
    super.initState();
    _contentFuture =
        context.read<HomeController>().parsePptx(widget.document.path);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canvasColor =
        isDark ? const Color(0xFF2A2A2E) : const Color(0xFFE9E9EC);

    return Scaffold(
      backgroundColor: canvasColor,
      appBar: AppBar(
        title: Text(
          widget.document.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          ShareButton(document: widget.document),
          DownloadButton(document: widget.document),
        ],
      ),
      body: FutureBuilder<PptxContent>(
        future: _contentFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(message: snapshot.error.toString());
          }
          final content = snapshot.data ?? PptxContent.empty;
          if (content.isEmpty) {
            return const _ErrorState(
              message: 'This presentation appears to be empty or contains no '
                  'readable slides.',
            );
          }
          return _buildSlides(content);
        },
      ),
    );
  }

  Widget _buildSlides(PptxContent content) {
    final total = content.slides.length;
    return Scrollbar(
      child: SelectionArea(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          itemCount: total,
          itemBuilder: (context, i) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxSlideWidth),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SlideView(
                      slide: content.slides[i],
                      width: content.slideWidth,
                      height: content.slideHeight,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${i + 1} / $total',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One slide: laid out on a [width] × [height] canvas, then scaled to fit.
class _SlideView extends StatelessWidget {
  final PptxSlide slide;
  final double width;
  final double height;

  const _SlideView({
    required this.slide,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: width / height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: width,
              height: height,
              // Slide text is sized in absolute points; the system font scale
              // would push it out of its boxes, and the app theme's colours do
              // not apply to a slide's fixed palette.
              child: MediaQuery.withNoTextScaling(
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 24,
                    height: 1.15,
                  ),
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned.fill(child: _background()),
                      for (final shape in slide.shapes) _shape(shape),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _background() {
    final color = Color(slide.backgroundArgb ?? 0xFFFFFFFF);
    final image = slide.backgroundImage;
    if (image == null) return ColoredBox(color: color);
    return ColoredBox(
      color: color,
      child: Image.memory(
        image,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _shape(PptxShape shape) {
    final f = shape.frame;
    return switch (shape) {
      PptxTextShape() => Positioned(
          left: f.x,
          top: f.y,
          width: f.width,
          height: f.height,
          child: _TextShapeView(shape: shape),
        ),
      PptxImageShape() => Positioned(
          left: f.x,
          top: f.y,
          width: f.width,
          height: f.height,
          child: Image.memory(
            shape.bytes,
            fit: BoxFit.fill,
            // EMF/WMF and other formats Flutter cannot decode are skipped.
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      // Tables grow to fit their rows, so they get no fixed height.
      PptxTableShape() => Positioned(
          left: f.x,
          top: f.y,
          width: f.width,
          child: _TableView(table: shape),
        ),
    };
  }
}

class _TextShapeView extends StatelessWidget {
  final PptxTextShape shape;

  const _TextShapeView({required this.shape});

  @override
  Widget build(BuildContext context) {
    final fill = shape.fillArgb == null ? null : Color(shape.fillArgb!);
    final border = shape.lineArgb == null
        ? null
        : Border.all(color: Color(shape.lineArgb!), width: shape.lineWidth);

    final decoration = switch (shape.geometry) {
      PptxGeometry.ellipse =>
        BoxDecoration(color: fill, border: border, shape: BoxShape.circle),
      PptxGeometry.roundRect => BoxDecoration(
          color: fill,
          border: border,
          borderRadius:
              BorderRadius.circular(0.16667 * _shortestSide(shape.frame)),
        ),
      PptxGeometry.rect => BoxDecoration(color: fill, border: border),
    };

    Widget? text;
    if (shape.hasText) {
      final verticalAlign = switch (shape.anchor) {
        PptxAnchor.top => -1.0,
        PptxAnchor.middle => 0.0,
        PptxAnchor.bottom => 1.0,
      };
      final column = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            shape.wrap ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
        children: _paragraphWidgets(shape.paragraphs, wrap: shape.wrap),
      );

      // Text in PowerPoint may spill past its box; OverflowBox lets it do the
      // same instead of throwing a layout overflow.
      text = Padding(
        padding: EdgeInsets.fromLTRB(shape.insetLeft, shape.insetTop,
            shape.insetRight, shape.insetBottom),
        child: OverflowBox(
          minHeight: 0,
          maxHeight: double.infinity,
          maxWidth: shape.wrap ? null : double.infinity,
          alignment: Alignment(
              shape.wrap ? 0 : _horizontalAlign(shape.paragraphs),
              verticalAlign),
          child: column,
        ),
      );
    }

    return DecoratedBox(
      decoration: decoration,
      child: text ?? const SizedBox.expand(),
    );
  }

  double _shortestSide(PptxRect r) => r.width < r.height ? r.width : r.height;

  double _horizontalAlign(List<PptxParagraph> paragraphs) =>
      switch (paragraphs.firstOrNull?.align) {
        PptxAlign.center => 0,
        PptxAlign.right => 1,
        _ => -1,
      };
}

class _TableView extends StatelessWidget {
  final PptxTableShape table;

  const _TableView({required this.table});

  @override
  Widget build(BuildContext context) {
    final border = BorderSide(color: Colors.grey.shade500, width: 1);
    return Table(
      border: TableBorder.all(color: border.color, width: border.width),
      columnWidths: {
        for (var i = 0; i < table.columnWidths.length; i++)
          i: FixedColumnWidth(table.columnWidths[i]),
      },
      children: [
        for (final row in table.rows)
          TableRow(
            children: [
              for (final cell in row)
                Container(
                  color: cell.fillArgb == null ? null : Color(cell.fillArgb!),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9.6, vertical: 4.8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _paragraphWidgets(cell.paragraphs),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Lays out paragraphs with their bullets and indents. With [wrap] off the
/// lines get unbounded width and keep their natural length.
List<Widget> _paragraphWidgets(List<PptxParagraph> paragraphs,
    {bool wrap = true}) {
  return [
    for (final p in paragraphs) _paragraph(p, wrap),
  ];
}

Widget _paragraph(PptxParagraph p, bool wrap) {
  if (p.isBlank) {
    // Keep empty lines at the height they have in PowerPoint.
    return SizedBox(height: p.emptySize * 1.15);
  }

  final text = Text.rich(
    TextSpan(children: [for (final run in p.runs) _span(run)]),
    textAlign: switch (p.align) {
      PptxAlign.center => TextAlign.center,
      PptxAlign.right => TextAlign.right,
      PptxAlign.justify => TextAlign.justify,
      PptxAlign.left => TextAlign.left,
    },
  );

  final bullet = p.bullet;
  if (bullet == null) {
    return Padding(
      padding: EdgeInsets.only(left: p.marginLeft),
      child: text,
    );
  }

  // A hanging indent (negative `indent`) is where the bullet sits; fall back
  // to a width proportional to the text when the file gives none.
  final firstRun = p.runs.first;
  final bulletWidth = p.indent < 0 ? -p.indent : firstRun.fontSize * 1.2;
  final bulletLeft = math.max(0.0, p.marginLeft - bulletWidth);

  return Padding(
    padding: EdgeInsets.only(left: bulletLeft),
    child: Row(
      mainAxisSize: wrap ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: bulletWidth,
          child: Text(
            bullet,
            style: TextStyle(
              fontSize: firstRun.fontSize,
              color: firstRun.colorArgb == null
                  ? null
                  : Color(firstRun.colorArgb!),
            ),
          ),
        ),
        wrap ? Flexible(child: text) : text,
      ],
    ),
  );
}

InlineSpan _span(PptxTextRun run) {
  final decorations = <TextDecoration>[
    if (run.underline) TextDecoration.underline,
    if (run.strikethrough) TextDecoration.lineThrough,
  ];
  return TextSpan(
    text: run.text,
    style: TextStyle(
      fontSize: run.fontSize,
      fontWeight: run.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
      color: run.colorArgb == null ? null : Color(run.colorArgb!),
      decoration: decorations.isEmpty
          ? TextDecoration.none
          : TextDecoration.combine(decorations),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.slideshow_outlined,
                size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
