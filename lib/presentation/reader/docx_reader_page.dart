import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/docx_content.dart';
import '../../domain/entities/pdf_document.dart';
import '../home/home_controller.dart';
import 'download_button.dart';

/// Renders a `.docx` document as a formatted, Word-like page.
///
/// The document is parsed into a [DocxContent] tree (headings, styled runs,
/// lists, tables and inline images) and laid out on a white "page" floating on
/// a grey canvas, mirroring how the file looks in a word processor.
class DocxReaderPage extends StatefulWidget {
  final PdfDocument document;

  const DocxReaderPage({super.key, required this.document});

  @override
  State<DocxReaderPage> createState() => _DocxReaderPageState();
}

class _DocxReaderPageState extends State<DocxReaderPage> {
  /// The unscaled body font size in logical pixels.
  static const double _baseFontSize = 16;
  static const double _maxPageWidth = 820;
  static const double _pagePadding = 56;

  late Future<DocxContent> _contentFuture;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _contentFuture =
        context.read<HomeController>().parseDocx(widget.document.path);
  }

  void _changeScale(double delta) {
    setState(() => _scale = (_scale + delta).clamp(0.7, 2.2));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canvasColor = isDark ? const Color(0xFF2A2A2E) : const Color(0xFFE9E9EC);

    return Scaffold(
      backgroundColor: canvasColor,
      appBar: AppBar(
        title: Text(
          widget.document.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.text_decrease),
            tooltip: 'Smaller text',
            onPressed: () => _changeScale(-0.1),
          ),
          IconButton(
            icon: const Icon(Icons.text_increase),
            tooltip: 'Larger text',
            onPressed: () => _changeScale(0.1),
          ),
          DownloadButton(document: widget.document),
        ],
      ),
      body: FutureBuilder<DocxContent>(
        future: _contentFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(message: snapshot.error.toString());
          }
          final content = snapshot.data ?? DocxContent.empty;
          if (content.isEmpty) {
            return const _ErrorState(
              message: 'This document appears to be empty or contains no '
                  'readable content.',
            );
          }
          return _buildPage(content);
        },
      ),
    );
  }

  Widget _buildPage(DocxContent content) {
    final renderer = _DocxRenderer(scale: _scale, baseFontSize: _baseFontSize);
    final contentWidth = _maxPageWidth - _pagePadding * 2;

    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxPageWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(_pagePadding),
                child: DefaultTextStyle.merge(
                  // Force dark text on the always-white page, even in dark mode.
                  style: const TextStyle(color: Color(0xFF1A1A1A)),
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children:
                          renderer.buildBlocks(content.blocks, contentWidth),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Converts a [DocxContent] tree into Flutter widgets.
class _DocxRenderer {
  final double scale;
  final double baseFontSize;

  _DocxRenderer({required this.scale, required this.baseFontSize});

  /// Builds a list of block widgets, tracking ordered-list numbering as it goes.
  List<Widget> buildBlocks(List<DocxBlock> blocks, double availableWidth) {
    final widgets = <Widget>[];
    // Per-level running counters for numbered lists.
    final counters = <int, int>{};

    for (final block in blocks) {
      if (block is DocxParagraph) {
        if (!block.isListItem) counters.clear();
        widgets.add(_paragraph(block, counters, availableWidth));
      } else if (block is DocxTable) {
        counters.clear();
        widgets.add(_table(block, availableWidth));
      }
    }
    return widgets;
  }

  Widget _paragraph(
    DocxParagraph p,
    Map<int, int> counters,
    double availableWidth,
  ) {
    if (p.isBlank && !p.isListItem) {
      // Preserve blank lines as vertical spacing.
      return SizedBox(height: baseFontSize * 0.7 * scale);
    }

    final paraBaseSize = _headingSize(p.headingLevel);
    final spans = <InlineSpan>[];
    for (final inline in p.inlines) {
      if (inline is DocxTextRun) {
        spans.add(_textSpan(inline, paraBaseSize, p.isHeading));
      } else if (inline is DocxImageRun) {
        spans.add(_imageSpan(inline, availableWidth));
      }
    }

    final richText = Text.rich(
      TextSpan(children: spans),
      textAlign: _textAlign(p.align),
    );

    final topGap = p.isHeading ? 18.0 * scale : 4.0 * scale;
    final bottomGap = p.isHeading ? 8.0 * scale : 8.0 * scale;

    Widget body = richText;
    if (p.isListItem) {
      body = _listItem(p, richText, counters);
    }

    return Padding(
      padding: EdgeInsets.only(top: topGap, bottom: bottomGap),
      child: body,
    );
  }

  Widget _listItem(DocxParagraph p, Widget richText, Map<int, int> counters) {
    final indent = 24.0 * scale * (p.listLevel + 1);
    final String marker;
    if (p.listMarker == DocxListMarker.number) {
      counters[p.listLevel] = (counters[p.listLevel] ?? 0) + 1;
      // Reset deeper levels once a shallower item advances.
      counters.removeWhere((level, _) => level > p.listLevel);
      counters[p.listLevel] = counters[p.listLevel] ?? 1;
      marker = '${counters[p.listLevel]}.';
    } else {
      marker = p.listLevel == 0 ? '•' : '◦';
    }

    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24 * scale,
            child: Text(
              marker,
              style: TextStyle(fontSize: baseFontSize * scale, height: 1.4),
            ),
          ),
          Expanded(child: richText),
        ],
      ),
    );
  }

  Widget _table(DocxTable table, double availableWidth) {
    if (table.rows.isEmpty) return const SizedBox.shrink();
    final columnCount =
        table.rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    final cellWidth = availableWidth / columnCount;
    final border = BorderSide(color: Colors.grey.shade400, width: 1);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10 * scale),
      child: Table(
        border: TableBorder.symmetric(inside: border, outside: border),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          for (final row in table.rows)
            TableRow(
              children: [
                for (var c = 0; c < columnCount; c++)
                  Padding(
                    padding: EdgeInsets.all(8 * scale),
                    child: c < row.length
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children:
                                buildBlocks(row[c].blocks, cellWidth - 16),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  InlineSpan _textSpan(DocxTextRun run, double paraBaseSize, bool isHeading) {
    var size = (run.fontSize ?? paraBaseSize) * scale;
    if (run.vAlign != DocxVerticalAlign.baseline) size *= 0.75;

    final decorations = <TextDecoration>[
      if (run.underline) TextDecoration.underline,
      if (run.strikethrough) TextDecoration.lineThrough,
    ];

    return TextSpan(
      text: run.text,
      style: TextStyle(
        fontSize: size,
        height: 1.4,
        fontWeight:
            (run.bold || isHeading) ? FontWeight.bold : FontWeight.normal,
        fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
        color: run.colorArgb != null ? Color(run.colorArgb!) : null,
        backgroundColor:
            run.highlightArgb != null ? Color(run.highlightArgb!) : null,
        decoration: decorations.isEmpty
            ? TextDecoration.none
            : TextDecoration.combine(decorations),
      ),
    );
  }

  InlineSpan _imageSpan(DocxImageRun image, double availableWidth) {
    final maxWidth = availableWidth;
    double? width = image.width == null ? null : image.width! * scale;
    double? height = image.height == null ? null : image.height! * scale;
    // Scale down oversized images to fit the page, preserving aspect ratio.
    if (width != null && width > maxWidth) {
      if (height != null) height *= maxWidth / width;
      width = maxWidth;
    }

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Image.memory(
          image.bytes,
          width: width,
          height: height,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  double _headingSize(int level) => switch (level) {
        1 => baseFontSize * 2.0,
        2 => baseFontSize * 1.6,
        3 => baseFontSize * 1.35,
        4 => baseFontSize * 1.2,
        5 || 6 => baseFontSize * 1.1,
        _ => baseFontSize,
      };

  TextAlign _textAlign(DocxAlign align) => switch (align) {
        DocxAlign.center => TextAlign.center,
        DocxAlign.right => TextAlign.right,
        DocxAlign.justify => TextAlign.justify,
        DocxAlign.left => TextAlign.left,
      };
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
            Icon(Icons.description_outlined,
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
