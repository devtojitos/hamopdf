import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/markdown_content.dart';
import '../../domain/entities/pdf_document.dart';
import '../home/home_controller.dart';
import 'download_button.dart';

/// Renders a Markdown document as a formatted, readable page.
///
/// The file is parsed into a [MarkdownContent] tree and laid out in a centred
/// reading column, following the app's theme so it stays comfortable in both
/// light and dark mode.
class MarkdownReaderPage extends StatefulWidget {
  final PdfDocument document;

  const MarkdownReaderPage({super.key, required this.document});

  @override
  State<MarkdownReaderPage> createState() => _MarkdownReaderPageState();
}

class _MarkdownReaderPageState extends State<MarkdownReaderPage> {
  /// The unscaled body font size in logical pixels.
  static const double _baseFontSize = 16;
  static const double _maxColumnWidth = 760;
  static const double _columnPadding = 24;

  late Future<MarkdownContent> _contentFuture;
  double _scale = 1.0;

  /// Tap recognizers attached to the link spans of the current build. They own
  /// native resources, so the previous batch is disposed on every rebuild.
  final List<TapGestureRecognizer> _linkRecognizers = [];

  @override
  void initState() {
    super.initState();
    _contentFuture =
        context.read<HomeController>().parseMarkdown(widget.document.path);
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _linkRecognizers) {
      recognizer.dispose();
    }
    _linkRecognizers.clear();
  }

  void _changeScale(double delta) {
    setState(() => _scale = (_scale + delta).clamp(0.7, 2.2));
  }

  /// The app carries no browser dependency, so tapping a link copies it —
  /// the user can paste it wherever they want to open it.
  Future<void> _onLinkTapped(String href) async {
    await Clipboard.setData(ClipboardData(text: href));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Link copied: $href'),
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      body: FutureBuilder<MarkdownContent>(
        future: _contentFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(message: snapshot.error.toString());
          }
          final content = snapshot.data ?? MarkdownContent.empty;
          if (content.isEmpty) {
            return const _ErrorState(message: 'This document is empty.');
          }
          return _buildPage(content);
        },
      ),
    );
  }

  Widget _buildPage(MarkdownContent content) {
    _disposeRecognizers();
    final renderer = _MarkdownRenderer(
      scale: _scale,
      baseFontSize: _baseFontSize,
      theme: Theme.of(context),
      // Images are written relative to the document, so resolve against its
      // own directory.
      baseDirectory: File(widget.document.path).parent.path,
      onLinkTapped: _onLinkTapped,
      registerRecognizer: _linkRecognizers.add,
    );

    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: _columnPadding,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxColumnWidth),
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: renderer.buildBlocks(content.blocks),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Renderer
// ---------------------------------------------------------------------------

/// Converts a [MarkdownContent] tree into Flutter widgets.
class _MarkdownRenderer {
  final double scale;
  final double baseFontSize;
  final ThemeData theme;
  final String baseDirectory;
  final void Function(String href) onLinkTapped;
  final void Function(TapGestureRecognizer) registerRecognizer;

  _MarkdownRenderer({
    required this.scale,
    required this.baseFontSize,
    required this.theme,
    required this.baseDirectory,
    required this.onLinkTapped,
    required this.registerRecognizer,
  });

  ColorScheme get _cs => theme.colorScheme;

  double get _body => baseFontSize * scale;

  List<Widget> buildBlocks(List<MdBlock> blocks) {
    final widgets = <Widget>[];
    for (final block in blocks) {
      widgets.add(switch (block) {
        MdHeading b => _heading(b),
        MdParagraph b => _paragraph(b),
        MdList b => _list(b),
        MdCodeBlock b => _codeBlock(b),
        MdQuote b => _quote(b),
        MdRule _ => _rule(),
        MdTable b => _table(b),
      });
    }
    return widgets;
  }

  Widget _heading(MdHeading h) {
    final size = _body * _headingScale(h.level);
    // H1 and H2 get an underline, as they do on GitHub.
    final underlined = h.level <= 2;

    return Padding(
      padding: EdgeInsets.only(top: 24 * scale, bottom: 8 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: _spans(h.inlines, size, bold: true),
            ),
          ),
          if (underlined) ...[
            SizedBox(height: 6 * scale),
            Divider(height: 1, thickness: 1, color: _cs.outlineVariant),
          ],
        ],
      ),
    );
  }

  Widget _paragraph(MdParagraph p) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6 * scale),
      child: Text.rich(TextSpan(children: _spans(p.inlines, _body))),
    );
  }

  Widget _list(MdList list) {
    final children = <Widget>[];

    for (var i = 0; i < list.items.length; i++) {
      final item = list.items[i];
      final Widget marker;

      if (item.checked != null) {
        marker = Icon(
          item.checked! ? Icons.check_box : Icons.check_box_outline_blank,
          size: _body,
          color: item.checked! ? _cs.primary : _cs.outline,
        );
      } else if (list.marker == MdListMarker.number) {
        marker = Text(
          '${list.start + i}.',
          style: TextStyle(fontSize: _body, height: 1.5, color: _cs.outline),
        );
      } else {
        marker = Text(
          '•',
          style: TextStyle(fontSize: _body, height: 1.5, color: _cs.outline),
        );
      }

      children.add(Padding(
        padding: EdgeInsets.only(bottom: 2 * scale),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28 * scale,
              child: Padding(
                // Nudge the marker onto the first line's baseline.
                padding: EdgeInsets.only(top: 6 * scale),
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: EdgeInsets.only(right: 8 * scale),
                    child: marker,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: buildBlocks(item.blocks),
              ),
            ),
          ],
        ),
      ));
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _codeBlock(MdCodeBlock block) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8 * scale),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: _cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (block.language != null)
              Padding(
                padding: EdgeInsets.fromLTRB(12 * scale, 8 * scale, 12 * scale, 0),
                child: Text(
                  block.language!,
                  style: TextStyle(
                    fontSize: _body * 0.75,
                    color: _cs.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            // Long lines scroll sideways rather than wrapping, so code keeps
            // its shape.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.all(12 * scale),
              child: Text(
                block.text,
                style: TextStyle(
                  fontFamily: _monoFamily,
                  fontFamilyFallback: _monoFallback,
                  fontSize: _body * 0.9,
                  height: 1.45,
                  color: _cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quote(MdQuote quote) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8 * scale),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: _cs.primary.withValues(alpha: 0.5), width: 4),
          ),
        ),
        padding: EdgeInsets.only(left: 14 * scale),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: _cs.onSurfaceVariant),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: buildBlocks(quote.blocks),
          ),
        ),
      ),
    );
  }

  Widget _rule() => Padding(
        padding: EdgeInsets.symmetric(vertical: 16 * scale),
        child: Divider(height: 1, thickness: 1, color: _cs.outlineVariant),
      );

  Widget _table(MdTable table) {
    final border = BorderSide(color: _cs.outlineVariant, width: 1);

    Widget cell(List<MdInline> inlines, int column, {required bool header}) {
      final align = column < table.alignments.length
          ? table.alignments[column]
          : MdAlign.left;
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
        child: Text.rich(
          TextSpan(children: _spans(inlines, _body, bold: header)),
          textAlign: switch (align) {
            MdAlign.center => TextAlign.center,
            MdAlign.right => TextAlign.right,
            MdAlign.left => TextAlign.left,
          },
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10 * scale),
      // Wide tables scroll sideways rather than squashing their columns.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.symmetric(inside: border, outside: border),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(color: _cs.surfaceContainerHighest),
              children: [
                for (var c = 0; c < table.header.length; c++)
                  cell(table.header[c], c, header: true),
              ],
            ),
            for (final row in table.rows)
              TableRow(
                children: [
                  for (var c = 0; c < table.header.length; c++)
                    cell(c < row.length ? row[c] : const [], c, header: false),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Inline spans
  // ---------------------------------------------------------------------------

  List<InlineSpan> _spans(
    List<MdInline> inlines,
    double size, {
    bool bold = false,
  }) {
    final spans = <InlineSpan>[];
    for (final inline in inlines) {
      switch (inline) {
        case MdTextSpan t:
          spans.add(_textSpan(t, size, forceBold: bold));
        case MdImageSpan i:
          spans.add(_imageSpan(i));
        case MdLineBreak _:
          spans.add(const TextSpan(text: '\n'));
      }
    }
    return spans;
  }

  InlineSpan _textSpan(MdTextSpan run, double size, {bool forceBold = false}) {
    final isLink = run.href != null;
    final decorations = <TextDecoration>[
      if (run.strikethrough) TextDecoration.lineThrough,
      if (isLink) TextDecoration.underline,
    ];

    final style = TextStyle(
      fontSize: run.code ? size * 0.9 : size,
      height: 1.55,
      fontWeight: (run.bold || forceBold) ? FontWeight.bold : FontWeight.normal,
      fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
      fontFamily: run.code ? _monoFamily : null,
      fontFamilyFallback: run.code ? _monoFallback : null,
      color: isLink ? _cs.primary : _cs.onSurface,
      backgroundColor: run.code ? _cs.surfaceContainerHighest : null,
      decoration: decorations.isEmpty
          ? TextDecoration.none
          : TextDecoration.combine(decorations),
      decorationColor: isLink ? _cs.primary : null,
    );

    if (!isLink) return TextSpan(text: run.text, style: style);

    final href = run.href!;
    final recognizer = TapGestureRecognizer()..onTap = () => onLinkTapped(href);
    registerRecognizer(recognizer);

    return TextSpan(
      text: run.text,
      style: style,
      recognizer: recognizer,
      semanticsLabel: '${run.text}, link to $href',
    );
  }

  InlineSpan _imageSpan(MdImageSpan image) {
    final src = image.src;
    // Only local images are supported — remote ones would need a network
    // dependency the app deliberately does not carry.
    final isRemote = src.startsWith('http://') ||
        src.startsWith('https://') ||
        src.startsWith('data:');

    if (isRemote) return _imagePlaceholder(image);

    final file = File(
      src.startsWith('/') ? src : '$baseDirectory${Platform.pathSeparator}$src',
    );
    if (!file.existsSync()) return _imagePlaceholder(image);

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 6 * scale),
        child: Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  /// Shows the alt text for an image that cannot be loaded.
  InlineSpan _imagePlaceholder(MdImageSpan image) {
    final label = image.alt.isEmpty ? image.src : image.alt;
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
        decoration: BoxDecoration(
          color: _cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined, size: _body, color: _cs.outline),
            SizedBox(width: 6 * scale),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: _body * 0.85, color: _cs.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _headingScale(int level) => switch (level) {
        1 => 1.9,
        2 => 1.55,
        3 => 1.3,
        4 => 1.15,
        5 => 1.05,
        _ => 1.0,
      };

  // Flutter ships no bundled monospace font, so name the platform ones.
  static const String _monoFamily = 'monospace';
  static const List<String> _monoFallback = [
    'Menlo',
    'Consolas',
    'Roboto Mono',
    'Courier New',
  ];
}

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

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
            Icon(Icons.article_outlined,
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
