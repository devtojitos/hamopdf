import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../domain/entities/docx_content.dart';

/// Parses the OOXML inside a `.docx` archive into a [DocxContent] tree.
///
/// A `.docx` file is a ZIP whose main content is `word/document.xml`. This
/// parser walks that XML (plus `numbering.xml`, the relationship file and the
/// `word/media/` folder) and reconstructs paragraphs, runs, lists, tables and
/// inline images with their formatting — everything a plain-text extractor
/// discards.
///
/// Element lookups match on the *local* name (ignoring the namespace prefix) so
/// the parser is robust to documents that use a prefix other than `w:`.
class DocxParser {
  /// English Metric Units per logical pixel (914400 EMU/inch ÷ 96 px/inch).
  static const double _emuPerPixel = 9525;

  DocxContent parse(Uint8List fileBytes) {
    final archive = ZipDecoder().decodeBytes(fileBytes);
    final files = <String, ArchiveFile>{
      for (final f in archive.files) f.name: f,
    };

    final documentFile = files['word/document.xml'];
    if (documentFile == null) return DocxContent.empty;

    final rels = _parseRelationships(files);
    final numbering = _parseNumbering(files);

    final doc = XmlDocument.parse(_utf8(documentFile));
    final body = _child(doc.rootElement, 'body');
    if (body == null) return DocxContent.empty;

    final ctx = _ParseContext(files: files, rels: rels, numbering: numbering);
    final blocks = _parseBlocks(body, ctx);
    return DocxContent(blocks);
  }

  // --- Block level ----------------------------------------------------------

  List<DocxBlock> _parseBlocks(XmlElement parent, _ParseContext ctx) {
    final blocks = <DocxBlock>[];
    for (final el in parent.childElements) {
      switch (el.name.local) {
        case 'p':
          blocks.add(_parseParagraph(el, ctx));
        case 'tbl':
          blocks.add(_parseTable(el, ctx));
      }
    }
    return blocks;
  }

  DocxParagraph _parseParagraph(XmlElement p, _ParseContext ctx) {
    final pPr = _child(p, 'pPr');

    var align = DocxAlign.left;
    var headingLevel = 0;
    DocxListMarker? listMarker;
    var listLevel = 0;

    if (pPr != null) {
      final jc = _attr(_child(pPr, 'jc'), 'val');
      align = switch (jc) {
        'center' => DocxAlign.center,
        'right' || 'end' => DocxAlign.right,
        'both' || 'distribute' || 'justify' => DocxAlign.justify,
        _ => DocxAlign.left,
      };

      headingLevel = _headingLevelOf(_attr(_child(pPr, 'pStyle'), 'val'));

      final numPr = _child(pPr, 'numPr');
      if (numPr != null) {
        final numId = _attr(_child(numPr, 'numId'), 'val');
        listLevel = int.tryParse(_attr(_child(numPr, 'ilvl'), 'val') ?? '') ?? 0;
        if (numId != null) {
          listMarker = ctx.numbering.markerFor(numId, listLevel);
        }
      }
    }

    final inlines = <DocxInline>[];
    for (final el in p.childElements) {
      switch (el.name.local) {
        case 'r':
          _parseRun(el, inlines, ctx);
        case 'hyperlink':
          // Links carry their own runs; render them as ordinary text.
          for (final r in _children(el, 'r')) {
            _parseRun(r, inlines, ctx);
          }
      }
    }

    return DocxParagraph(
      inlines: inlines,
      align: align,
      headingLevel: headingLevel,
      listMarker: listMarker,
      listLevel: listLevel,
    );
  }

  DocxTable _parseTable(XmlElement tbl, _ParseContext ctx) {
    final rows = <List<DocxTableCell>>[];
    for (final tr in _children(tbl, 'tr')) {
      final cells = <DocxTableCell>[];
      for (final tc in _children(tr, 'tc')) {
        cells.add(DocxTableCell(_parseBlocks(tc, ctx)));
      }
      if (cells.isNotEmpty) rows.add(cells);
    }
    return DocxTable(rows);
  }

  // --- Run / inline level ---------------------------------------------------

  void _parseRun(XmlElement r, List<DocxInline> out, _ParseContext ctx) {
    final rPr = _child(r, 'rPr');

    final bold = _boolProp(rPr, 'b');
    final italic = _boolProp(rPr, 'i');
    final strike = _boolProp(rPr, 'strike');

    final uVal = rPr == null ? null : _attr(_child(rPr, 'u'), 'val');
    final underline = uVal != null && uVal != 'none';

    final colorArgb = _hexColor(_attr(_child(rPr, 'color'), 'val'));
    final highlightArgb = _highlightColor(_attr(_child(rPr, 'highlight'), 'val'));

    final szHalfPoints = int.tryParse(_attr(_child(rPr, 'sz'), 'val') ?? '');
    // Half-points → points; treat points ≈ logical pixels for on-screen reading.
    final fontSize = szHalfPoints != null ? szHalfPoints / 2.0 : null;

    final vAlign = switch (_attr(_child(rPr, 'vertAlign'), 'val')) {
      'superscript' => DocxVerticalAlign.superscript,
      'subscript' => DocxVerticalAlign.subscript,
      _ => DocxVerticalAlign.baseline,
    };

    DocxTextRun textRun(String text) => DocxTextRun(
          text,
          bold: bold,
          italic: italic,
          underline: underline,
          strikethrough: strike,
          colorArgb: colorArgb,
          highlightArgb: highlightArgb,
          fontSize: fontSize,
          vAlign: vAlign,
        );

    for (final el in r.childElements) {
      switch (el.name.local) {
        case 't':
          out.add(textRun(el.innerText));
        case 'tab':
          out.add(textRun('\t'));
        case 'br':
        case 'cr':
          out.add(textRun('\n'));
        case 'drawing':
        case 'pict':
        case 'object':
          final image = _parseImage(el, ctx);
          if (image != null) out.add(image);
      }
    }
  }

  DocxImageRun? _parseImage(XmlElement el, _ParseContext ctx) {
    // The image reference id lives on an <a:blip r:embed="..."> (DrawingML) or a
    // <v:imagedata r:id="..."> (legacy VML). Search descendants for either.
    String? relId;
    XmlElement? extent;
    for (final d in el.descendantElements) {
      final local = d.name.local;
      if (local == 'blip' || local == 'imagedata') {
        relId ??= _attr(d, 'embed') ?? _attr(d, 'id') ?? _attr(d, 'link');
      } else if (local == 'extent') {
        extent ??= d;
      }
    }
    if (relId == null) return null;

    final target = ctx.rels[relId];
    if (target == null) return null;

    final bytes = ctx.mediaBytes(target);
    if (bytes == null) return null;

    double? width;
    double? height;
    if (extent != null) {
      final cx = double.tryParse(_attr(extent, 'cx') ?? '');
      final cy = double.tryParse(_attr(extent, 'cy') ?? '');
      if (cx != null) width = cx / _emuPerPixel;
      if (cy != null) height = cy / _emuPerPixel;
    }

    return DocxImageRun(bytes, width: width, height: height);
  }

  // --- Side files -----------------------------------------------------------

  Map<String, String> _parseRelationships(Map<String, ArchiveFile> files) {
    final file = files['word/_rels/document.xml.rels'];
    if (file == null) return const {};
    final doc = XmlDocument.parse(_utf8(file));
    final map = <String, String>{};
    for (final rel in doc.rootElement.childElements) {
      final id = _attr(rel, 'Id');
      final target = _attr(rel, 'Target');
      if (id != null && target != null) map[id] = target;
    }
    return map;
  }

  _Numbering _parseNumbering(Map<String, ArchiveFile> files) {
    final file = files['word/numbering.xml'];
    if (file == null) return const _Numbering({}, {});
    final doc = XmlDocument.parse(_utf8(file));

    // abstractNumId -> (ilvl -> numFmt)
    final abstractFormats = <String, Map<int, String>>{};
    for (final abs in _children(doc.rootElement, 'abstractNum')) {
      final absId = _attr(abs, 'abstractNumId');
      if (absId == null) continue;
      final levels = <int, String>{};
      for (final lvl in _children(abs, 'lvl')) {
        final ilvl = int.tryParse(_attr(lvl, 'ilvl') ?? '');
        final fmt = _attr(_child(lvl, 'numFmt'), 'val');
        if (ilvl != null && fmt != null) levels[ilvl] = fmt;
      }
      abstractFormats[absId] = levels;
    }

    // numId -> abstractNumId
    final numToAbstract = <String, String>{};
    for (final num in _children(doc.rootElement, 'num')) {
      final numId = _attr(num, 'numId');
      final absId = _attr(_child(num, 'abstractNumId'), 'val');
      if (numId != null && absId != null) numToAbstract[numId] = absId;
    }

    return _Numbering(numToAbstract, abstractFormats);
  }

  // --- Small helpers --------------------------------------------------------

  int _headingLevelOf(String? styleVal) {
    if (styleVal == null) return 0;
    final match = RegExp(r'heading\s*([1-9])', caseSensitive: false)
        .firstMatch(styleVal.replaceAll('-', ' '));
    if (match == null) return 0;
    return int.parse(match.group(1)!).clamp(1, 6);
  }

  /// A boolean run property is "on" unless it explicitly says off.
  bool _boolProp(XmlElement? rPr, String name) {
    if (rPr == null) return false;
    final el = _child(rPr, name);
    if (el == null) return false;
    final val = _attr(el, 'val');
    return val == null || val == 'true' || val == '1' || val == 'on';
  }

  int? _hexColor(String? hex) {
    if (hex == null || hex.toLowerCase() == 'auto') return null;
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return null;
    return 0xFF000000 | value;
  }

  int? _highlightColor(String? name) {
    if (name == null || name == 'none') return null;
    return _highlightColors[name];
  }

  static const Map<String, int> _highlightColors = {
    'yellow': 0xFFFFFF00,
    'green': 0xFF00FF00,
    'cyan': 0xFF00FFFF,
    'magenta': 0xFFFF00FF,
    'blue': 0xFF0000FF,
    'red': 0xFFFF0000,
    'darkBlue': 0xFF000080,
    'darkCyan': 0xFF008080,
    'darkGreen': 0xFF008000,
    'darkMagenta': 0xFF800080,
    'darkRed': 0xFF800000,
    'darkYellow': 0xFF808000,
    'darkGray': 0xFF808080,
    'lightGray': 0xFFC0C0C0,
    'black': 0xFF000000,
    'white': 0xFFFFFFFF,
  };

  String _utf8(ArchiveFile file) => utf8.decode(file.content as List<int>);

  XmlElement? _child(XmlElement? parent, String local) {
    if (parent == null) return null;
    for (final c in parent.childElements) {
      if (c.name.local == local) return c;
    }
    return null;
  }

  Iterable<XmlElement> _children(XmlElement parent, String local) =>
      parent.childElements.where((c) => c.name.local == local);

  String? _attr(XmlElement? el, String local) {
    if (el == null) return null;
    for (final a in el.attributes) {
      if (a.name.local == local) return a.value;
    }
    return null;
  }
}

/// Shared state threaded through the recursive parse.
class _ParseContext {
  final Map<String, ArchiveFile> files;
  final Map<String, String> rels;
  final _Numbering numbering;

  _ParseContext({
    required this.files,
    required this.rels,
    required this.numbering,
  });

  /// Resolves a relationship [target] (relative to `word/`) to its file bytes.
  Uint8List? mediaBytes(String target) {
    final normalized = target.startsWith('/')
        ? target.substring(1)
        : 'word/$target';
    final file = files[normalized] ?? files[target];
    if (file == null) return null;
    return Uint8List.fromList(file.content as List<int>);
  }
}

/// Resolves list markers from the numbering definitions.
class _Numbering {
  final Map<String, String> _numToAbstract;
  final Map<String, Map<int, String>> _abstractFormats;

  const _Numbering(this._numToAbstract, this._abstractFormats);

  DocxListMarker markerFor(String numId, int level) {
    final absId = _numToAbstract[numId];
    final fmt = absId == null ? null : _abstractFormats[absId]?[level];
    return fmt == 'bullet' ? DocxListMarker.bullet : DocxListMarker.number;
  }
}
