import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../domain/entities/pptx_content.dart';

/// Parses the PresentationML inside a `.pptx` archive into a [PptxContent].
///
/// A `.pptx` is a ZIP: `ppt/presentation.xml` lists the slides in order, each
/// slide (`ppt/slides/slideN.xml`) is a tree of positioned shapes, and every
/// slide points at a layout which in turn points at a master. Placeholder
/// shapes (titles, body text) usually store only their text on the slide and
/// inherit position, font sizes, alignment and bullets from the matching
/// placeholder on the layout and master, so this parser resolves that chain.
///
/// Not supported: charts, SmartArt without a fallback picture, rotation,
/// image cropping, table styles and embedded fonts.
///
/// As in [DocxParser], element lookups match on the *local* name so documents
/// using unusual namespace prefixes still parse.
class PptxParser {
  /// English Metric Units per logical pixel (914400 EMU/inch ÷ 96 px/inch).
  static const double _emuPerPixel = 9525;

  /// PowerPoint's default slide size (16:9) in EMU.
  static const double _defaultSlideCx = 12192000;
  static const double _defaultSlideCy = 6858000;

  /// The spec default font size, in hundredths of a point.
  static const int _defaultFontSize = 1800;

  PptxContent parse(Uint8List fileBytes) {
    final archive = ZipDecoder().decodeBytes(fileBytes);
    final pkg = _Package({
      for (final f in archive.files)
        if (f.isFile) f.name: f,
    });

    const presentationPath = 'ppt/presentation.xml';
    final presentation = pkg.xml(presentationPath)?.rootElement;
    if (presentation == null) return PptxContent.empty;

    final sldSz = _child(presentation, 'sldSz');
    final slideCx = _double(sldSz, 'cx') ?? _defaultSlideCx;
    final slideCy = _double(sldSz, 'cy') ?? _defaultSlideCy;

    final presRels = pkg.rels(presentationPath);
    final themeRel =
        presRels.values.where((r) => r.isType('theme')).firstOrNull;
    final theme =
        _Theme.parse(themeRel == null ? null : pkg.xml(themeRel.target));

    final slides = <PptxSlide>[];
    final sldIdLst = _child(presentation, 'sldIdLst');
    if (sldIdLst != null) {
      for (final sldId in _children(sldIdLst, 'sldId')) {
        final rel = presRels[_relAttr(sldId, 'id')];
        if (rel == null) continue;
        final slide = _parseSlide(pkg, rel.target, theme);
        if (slide != null) slides.add(slide);
      }
    }

    return PptxContent(
      slideWidth: slideCx / _emuPerPixel,
      slideHeight: slideCy / _emuPerPixel,
      slides: slides,
    );
  }

  // --- Slide / layout / master ----------------------------------------------

  PptxSlide? _parseSlide(_Package pkg, String slidePath, _Theme theme) {
    final slideRoot = pkg.xml(slidePath)?.rootElement;
    final slideTree = _child(slideRoot, 'cSld');
    if (slideRoot == null || slideTree == null) return null;

    final slideRels = pkg.rels(slidePath);
    final layoutPath = slideRels.values
        .where((r) => r.isType('slideLayout'))
        .firstOrNull
        ?.target;
    final layoutRoot =
        layoutPath == null ? null : pkg.xml(layoutPath)?.rootElement;
    final layoutRels =
        layoutPath == null ? <String, _Rel>{} : pkg.rels(layoutPath);

    final masterPath = layoutRels.values
        .where((r) => r.isType('slideMaster'))
        .firstOrNull
        ?.target;
    final masterRoot =
        masterPath == null ? null : pkg.xml(masterPath)?.rootElement;
    final masterRels =
        masterPath == null ? <String, _Rel>{} : pkg.rels(masterPath);

    final master = _MasterInfo.parse(masterRoot, this, theme);
    final base = _Context(
      pkg: pkg,
      theme: theme,
      clrMap: master.clrMap,
      rels: const {},
      master: master,
      layoutPlaceholders: _PlaceholderSet.parse(layoutRoot, this),
    );
    final slideCtx = base.withRels(slideRels);
    final layoutCtx = base.withRels(layoutRels);
    final masterCtx = base.withRels(masterRels);

    // Background: the first of slide → layout → master that defines one.
    final background = _background(slideTree, slideCtx) ??
        _background(_child(layoutRoot, 'cSld'), layoutCtx) ??
        _background(_child(masterRoot, 'cSld'), masterCtx);

    // Decorative shapes from the master and layout are drawn beneath the
    // slide's own, unless the slide or layout opts out (showMasterSp="0").
    final shapes = <PptxShape>[];
    if (_attr(slideRoot, 'showMasterSp') != '0') {
      if (_attr(layoutRoot, 'showMasterSp') != '0') {
        _parseTree(_spTree(masterRoot), masterCtx, _Transform.identity, shapes,
            skipPlaceholders: true);
      }
      _parseTree(_spTree(layoutRoot), layoutCtx, _Transform.identity, shapes,
          skipPlaceholders: true);
    }
    _parseTree(
        _child(slideTree, 'spTree'), slideCtx, _Transform.identity, shapes,
        skipPlaceholders: false);

    return PptxSlide(
      backgroundArgb: background?.$1,
      backgroundImage: background?.$2,
      shapes: shapes,
    );
  }

  XmlElement? _spTree(XmlElement? root) =>
      _child(_child(root, 'cSld'), 'spTree');

  /// Reads a `p:bg`. Returns null when [cSld] defines no background, so the
  /// caller can fall back to the next part in the inheritance chain.
  (int?, Uint8List?)? _background(XmlElement? cSld, _Context ctx) {
    final bg = _child(cSld, 'bg');
    if (bg == null) return null;

    final bgPr = _child(bg, 'bgPr');
    if (bgPr != null) {
      final blip = _child(_child(bgPr, 'blipFill'), 'blip');
      if (blip != null) {
        final bytes = ctx.imageBytes(_relAttr(blip, 'embed'));
        if (bytes != null) return (null, bytes);
      }
      return (_fillColor(bgPr, ctx), null);
    }

    // <p:bgRef idx=".."><a:schemeClr val="bg1"/></p:bgRef>: a theme fill style
    // tinted with the given colour. The colour alone is a fair approximation.
    final bgRef = _child(bg, 'bgRef');
    if (bgRef != null) {
      return (_colorOf(bgRef.childElements.firstOrNull, ctx), null);
    }
    return null;
  }

  // --- Shape tree -----------------------------------------------------------

  void _parseTree(
    XmlElement? tree,
    _Context ctx,
    _Transform transform,
    List<PptxShape> out, {
    required bool skipPlaceholders,
  }) {
    if (tree == null) return;
    for (final el in tree.childElements) {
      switch (el.name.local) {
        case 'sp':
          final shape = _parseShape(el, ctx, transform, skipPlaceholders);
          if (shape != null) out.add(shape);
        case 'pic':
          final pic = _parsePicture(el, ctx, transform, skipPlaceholders);
          if (pic != null) out.add(pic);
        case 'cxnSp':
          final line = _parseConnector(el, ctx, transform);
          if (line != null) out.add(line);
        case 'graphicFrame':
          final table = _parseTable(el, ctx, transform);
          if (table != null) out.add(table);
        case 'grpSp':
          if (_isHidden(_child(el, 'nvGrpSpPr'))) continue;
          final xfrm = _child(_child(el, 'grpSpPr'), 'xfrm');
          _parseTree(el, ctx, transform.group(xfrm, this), out,
              skipPlaceholders: skipPlaceholders);
        case 'AlternateContent':
          // Newer content (SmartArt, equations, 3D models) ships a fallback —
          // usually a picture — for readers that do not understand it.
          final fallback = _child(el, 'Fallback');
          _parseTree(fallback, ctx, transform, out,
              skipPlaceholders: skipPlaceholders);
      }
    }
  }

  PptxTextShape? _parseShape(
    XmlElement sp,
    _Context ctx,
    _Transform transform,
    bool skipPlaceholders,
  ) {
    final nvSpPr = _child(sp, 'nvSpPr');
    if (_isHidden(nvSpPr)) return null;

    final ph = _placeholderOf(nvSpPr);
    if (ph != null && skipPlaceholders) return null;

    final inherited = ph == null ? null : ctx.inheritedPlaceholders(ph);
    final spPr = _child(sp, 'spPr');
    final xfrm = _child(spPr, 'xfrm') ??
        inherited?.layout?.xfrm ??
        inherited?.master?.xfrm;
    final frame = transform.rect(xfrm, this);
    if (frame == null) return null;

    final style = _child(sp, 'style');
    final fill = _shapeFill(spPr, style, ctx);
    final line = _shapeLine(spPr, style, ctx);

    final txBody = _child(sp, 'txBody');
    final bodyPrs = [
      _child(txBody, 'bodyPr'),
      inherited?.layout?.bodyPr,
      inherited?.master?.bodyPr,
    ];

    final fontRefColor =
        _colorOf(_child(style, 'fontRef')?.childElements.firstOrNull, ctx);
    final textStyles = _TextStyles([
      _ListStyle.parse(_child(txBody, 'lstStyle'), this, ctx),
      if (fontRefColor != null) _ListStyle.uniformColor(fontRefColor),
      _ListStyle.parse(inherited?.layout?.lstStyle, this, ctx),
      _ListStyle.parse(inherited?.master?.lstStyle, this, ctx),
      ctx.master.textStylesFor(ph),
    ]);

    final fontScale = (_double(
                _child(_child(txBody, 'bodyPr'), 'normAutofit'), 'fontScale') ??
            100000) /
        100000;

    return PptxTextShape(
      frame,
      paragraphs: txBody == null
          ? const []
          : _parseParagraphs(txBody, textStyles, ctx, fontScale),
      geometry: _geometry(spPr),
      anchor: switch (_firstAttr(bodyPrs, 'anchor')) {
        'ctr' => PptxAnchor.middle,
        'b' => PptxAnchor.bottom,
        _ => PptxAnchor.top,
      },
      fillArgb: fill,
      lineArgb: line?.$1,
      lineWidth: line?.$2 ?? 1,
      insetLeft: _emu(_firstAttr(bodyPrs, 'lIns')) ?? 9.6,
      insetTop: _emu(_firstAttr(bodyPrs, 'tIns')) ?? 4.8,
      insetRight: _emu(_firstAttr(bodyPrs, 'rIns')) ?? 9.6,
      insetBottom: _emu(_firstAttr(bodyPrs, 'bIns')) ?? 4.8,
      wrap: _firstAttr(bodyPrs, 'wrap') != 'none',
    );
  }

  PptxImageShape? _parsePicture(
    XmlElement pic,
    _Context ctx,
    _Transform transform,
    bool skipPlaceholders,
  ) {
    final nvPicPr = _child(pic, 'nvPicPr');
    if (_isHidden(nvPicPr)) return null;

    final ph = _placeholderOf(nvPicPr);
    if (ph != null && skipPlaceholders) return null;
    final inherited = ph == null ? null : ctx.inheritedPlaceholders(ph);

    final xfrm = _child(_child(pic, 'spPr'), 'xfrm') ??
        inherited?.layout?.xfrm ??
        inherited?.master?.xfrm;
    final frame = transform.rect(xfrm, this);
    if (frame == null) return null;

    final blip = _child(_child(pic, 'blipFill'), 'blip');
    final bytes = ctx.imageBytes(_relAttr(blip, 'embed'));
    if (bytes == null) return null;

    return PptxImageShape(frame, bytes);
  }

  /// Straight horizontal / vertical connectors, drawn as thin filled bars.
  /// Diagonal and elbow connectors are skipped.
  PptxTextShape? _parseConnector(
      XmlElement cxn, _Context ctx, _Transform transform) {
    if (_isHidden(_child(cxn, 'nvCxnSpPr'))) return null;
    final spPr = _child(cxn, 'spPr');
    final frame = transform.rect(_child(spPr, 'xfrm'), this);
    if (frame == null) return null;

    final line = _shapeLine(spPr, _child(cxn, 'style'), ctx);
    if (line == null) return null;
    final (color, width) = line;

    const flat = 0.5;
    if (frame.height <= flat) {
      return PptxTextShape(
        PptxRect(frame.x, frame.y - width / 2, frame.width, width),
        paragraphs: const [],
        fillArgb: color,
      );
    }
    if (frame.width <= flat) {
      return PptxTextShape(
        PptxRect(frame.x - width / 2, frame.y, width, frame.height),
        paragraphs: const [],
        fillArgb: color,
      );
    }
    return null;
  }

  PptxTableShape? _parseTable(
      XmlElement frameEl, _Context ctx, _Transform transform) {
    if (_isHidden(_child(frameEl, 'nvGraphicFramePr'))) return null;
    final tbl = frameEl.descendantElements
        .where((e) => e.name.local == 'tbl')
        .firstOrNull;
    if (tbl == null) return null; // a chart, diagram or OLE object

    final frame = transform.rect(_child(frameEl, 'xfrm'), this);
    if (frame == null) return null;

    final columnWidths = [
      for (final col in _children(_child(tbl, 'tblGrid'), 'gridCol'))
        (_double(col, 'w') ?? 0) * transform.scaleX,
    ];
    if (columnWidths.isEmpty) return null;

    final styles = _TextStyles([ctx.master.otherStyle]);
    final rows = <List<PptxTableCell>>[];
    for (final tr in _children(tbl, 'tr')) {
      final cells = <PptxTableCell>[];
      for (final tc in _children(tr, 'tc')) {
        final merged = _attr(tc, 'hMerge') == '1' || _attr(tc, 'vMerge') == '1';
        final txBody = _child(tc, 'txBody');
        cells.add(PptxTableCell(
          paragraphs: txBody == null || merged
              ? const []
              : _parseParagraphs(txBody, styles, ctx, 1),
          fillArgb: _fillColor(_child(tc, 'tcPr'), ctx),
          merged: merged,
        ));
      }
      // Pad short rows so the Table widget gets a uniform column count.
      while (cells.length < columnWidths.length) {
        cells.add(const PptxTableCell(paragraphs: [], merged: true));
      }
      rows.add(cells.take(columnWidths.length).toList());
    }
    if (rows.isEmpty) return null;

    return PptxTableShape(frame, columnWidths: columnWidths, rows: rows);
  }

  // --- Text -----------------------------------------------------------------

  List<PptxParagraph> _parseParagraphs(
    XmlElement txBody,
    _TextStyles styles,
    _Context ctx,
    double fontScale,
  ) {
    final paragraphs = <PptxParagraph>[];
    // Per-level running counters for auto-numbered paragraphs.
    final counters = <int, int>{};

    for (final p in _children(txBody, 'p')) {
      final pPr = _child(p, 'pPr');
      final level = (int.tryParse(_attr(pPr, 'lvl') ?? '') ?? 0).clamp(0, 8);
      final own = pPr == null ? null : _LevelStyle.parse(pPr, this, ctx);
      final resolved = styles.resolve(level, own);

      double sizeOf(_RunStyle s) =>
          _pointsToPx(s.size ?? _defaultFontSize) * fontScale;

      final runs = <PptxTextRun>[];
      for (final el in p.childElements) {
        final local = el.name.local;
        if (local != 'r' && local != 'fld' && local != 'br') continue;

        final rs =
            _RunStyle.parse(_child(el, 'rPr'), this, ctx).orElse(resolved.run);
        runs.add(PptxTextRun(
          local == 'br' ? '\n' : (_child(el, 't')?.innerText ?? ''),
          fontSize: sizeOf(rs),
          bold: rs.bold ?? false,
          italic: rs.italic ?? false,
          underline: rs.underline ?? false,
          strikethrough: rs.strike ?? false,
          colorArgb: rs.color,
        ));
      }

      final endStyle = _RunStyle.parse(_child(p, 'endParaRPr'), this, ctx)
          .orElse(resolved.run);
      final paragraph = PptxParagraph(
        runs: runs,
        align: switch (resolved.align) {
          'ctr' => PptxAlign.center,
          'r' => PptxAlign.right,
          'just' || 'dist' => PptxAlign.justify,
          _ => PptxAlign.left,
        },
        marginLeft: resolved.marginLeft ?? 0,
        indent: resolved.indent ?? 0,
        emptySize: sizeOf(endStyle),
      );

      // PowerPoint draws no bullet on an empty paragraph, and an empty line
      // does not break a numbered sequence.
      if (paragraph.isBlank) {
        paragraphs.add(paragraph);
        continue;
      }

      counters.removeWhere((l, _) => l > level);
      final bullet = resolved.bullet;
      String? bulletText;
      if (bullet is _CharBullet) {
        counters.remove(level);
        bulletText = bullet.char;
      } else if (bullet is _AutoNumBullet) {
        final n = (counters[level] ?? bullet.startAt - 1) + 1;
        counters[level] = n;
        bulletText = _autoNumber(bullet.scheme, n);
      } else {
        counters.remove(level);
      }

      paragraphs.add(PptxParagraph(
        runs: paragraph.runs,
        align: paragraph.align,
        bullet: bulletText,
        marginLeft: paragraph.marginLeft,
        indent: paragraph.indent,
        emptySize: paragraph.emptySize,
      ));
    }
    return paragraphs;
  }

  /// Formats [n] in a `buAutoNum` scheme such as `arabicPeriod` → "3." or
  /// `alphaLcParenR` → "c)".
  String _autoNumber(String scheme, int n) {
    final String core;
    if (scheme.startsWith('alphaLc')) {
      core = _alpha(n).toLowerCase();
    } else if (scheme.startsWith('alphaUc')) {
      core = _alpha(n);
    } else if (scheme.startsWith('romanLc')) {
      core = _roman(n).toLowerCase();
    } else if (scheme.startsWith('romanUc')) {
      core = _roman(n);
    } else {
      core = '$n';
    }
    if (scheme.endsWith('ParenBoth')) return '($core)';
    if (scheme.endsWith('ParenR')) return '$core)';
    if (scheme.endsWith('Plain')) return core;
    return '$core.';
  }

  String _alpha(int n) {
    var out = '';
    for (var v = n; v > 0; v = (v - 1) ~/ 26) {
      out = String.fromCharCode(65 + (v - 1) % 26) + out;
    }
    return out;
  }

  String _roman(int n) {
    const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    const symbols = [
      'M',
      'CM',
      'D',
      'CD',
      'C',
      'XC',
      'L',
      'XL',
      'X',
      'IX',
      'V',
      'IV',
      'I'
    ];
    var out = '';
    var v = n.clamp(1, 3999);
    for (var i = 0; i < values.length; i++) {
      while (v >= values[i]) {
        out += symbols[i];
        v -= values[i];
      }
    }
    return out;
  }

  // --- Fills, lines, geometry -----------------------------------------------

  /// The shape fill: explicit `spPr` fill first, then the theme style
  /// reference (`p:style/a:fillRef`) that PowerPoint gives inserted shapes.
  int? _shapeFill(XmlElement? spPr, XmlElement? style, _Context ctx) {
    if (_child(spPr, 'noFill') != null) return null;
    final explicit = _fillColor(spPr, ctx);
    if (explicit != null) return explicit;
    final fillRef = _child(style, 'fillRef');
    if (fillRef == null || _attr(fillRef, 'idx') == '0') return null;
    return _colorOf(fillRef.childElements.firstOrNull, ctx);
  }

  /// The outline as (colour, width in px), or null when there is none.
  (int, double)? _shapeLine(XmlElement? spPr, XmlElement? style, _Context ctx) {
    final ln = _child(spPr, 'ln');
    if (_child(ln, 'noFill') != null) return null;
    final width = _emu(_attr(ln, 'w')) ?? 1;

    var color = _fillColor(ln, ctx);
    if (color == null) {
      final lnRef = _child(style, 'lnRef');
      if (lnRef != null && _attr(lnRef, 'idx') != '0') {
        color = _colorOf(lnRef.childElements.firstOrNull, ctx);
      }
    }
    return color == null ? null : (color, math.max(width, 0.75));
  }

  /// A solid colour for the fill under [parent]: `a:solidFill`, or the first
  /// stop of an `a:gradFill` as an approximation.
  int? _fillColor(XmlElement? parent, _Context ctx) {
    final solid = _child(parent, 'solidFill');
    if (solid != null) return _colorOf(solid.childElements.firstOrNull, ctx);
    final grad = _child(parent, 'gradFill');
    if (grad != null) {
      final stop = _child(_child(grad, 'gsLst'), 'gs');
      return _colorOf(stop?.childElements.firstOrNull, ctx);
    }
    return null;
  }

  PptxGeometry _geometry(XmlElement? spPr) =>
      switch (_attr(_child(spPr, 'prstGeom'), 'prst')) {
        'ellipse' => PptxGeometry.ellipse,
        'roundRect' => PptxGeometry.roundRect,
        _ => PptxGeometry.rect,
      };

  // --- Colours --------------------------------------------------------------

  /// Resolves a DrawingML colour element (`a:srgbClr`, `a:schemeClr`, …) and
  /// its modifiers (`lumMod`, `tint`, `alpha`, …) to 0xAARRGGBB.
  int? _colorOf(XmlElement? el, _Context ctx) {
    if (el == null) return null;
    final val = _attr(el, 'val');
    final int? rgb = switch (el.name.local) {
      'srgbClr' => val == null ? null : int.tryParse(val, radix: 16),
      'sysClr' => int.tryParse(_attr(el, 'lastClr') ?? '', radix: 16),
      'schemeClr' => ctx.theme.colors[ctx.clrMap[val] ?? val],
      'prstClr' => _presetColors[val],
      _ => null,
    };
    if (rgb == null) return null;
    return _applyModifiers(rgb, el);
  }

  int _applyModifiers(int rgb, XmlElement el) {
    var r = ((rgb >> 16) & 0xFF) / 255;
    var g = ((rgb >> 8) & 0xFF) / 255;
    var b = (rgb & 0xFF) / 255;
    var alpha = 1.0;
    double? lumMod;
    double? lumOff;

    for (final m in el.childElements) {
      final v = (int.tryParse(_attr(m, 'val') ?? '') ?? 100000) / 100000;
      switch (m.name.local) {
        case 'alpha':
          alpha = v;
        case 'lumMod':
          lumMod = v;
        case 'lumOff':
          lumOff = v;
        case 'shade':
          r *= v;
          g *= v;
          b *= v;
        case 'tint':
          r += (1 - r) * (1 - v);
          g += (1 - g) * (1 - v);
          b += (1 - b) * (1 - v);
      }
    }

    if (lumMod != null || lumOff != null) {
      final hsl = _toHsl(r, g, b);
      final l = (hsl.$3 * (lumMod ?? 1) + (lumOff ?? 0)).clamp(0.0, 1.0);
      (r, g, b) = _fromHsl(hsl.$1, hsl.$2, l);
    }

    int byte(double c) => (c.clamp(0.0, 1.0) * 255).round();
    return (byte(alpha) << 24) | (byte(r) << 16) | (byte(g) << 8) | byte(b);
  }

  (double, double, double) _toHsl(double r, double g, double b) {
    final maxC = math.max(r, math.max(g, b));
    final minC = math.min(r, math.min(g, b));
    final l = (maxC + minC) / 2;
    if (maxC == minC) return (0, 0, l);
    final d = maxC - minC;
    final s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC);
    final double h;
    if (maxC == r) {
      h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
    } else if (maxC == g) {
      h = ((b - r) / d + 2) / 6;
    } else {
      h = ((r - g) / d + 4) / 6;
    }
    return (h, s, l);
  }

  (double, double, double) _fromHsl(double h, double s, double l) {
    if (s == 0) return (l, l, l);
    double hue(double p, double q, double t) {
      if (t < 0) t += 1;
      if (t > 1) t -= 1;
      if (t < 1 / 6) return p + (q - p) * 6 * t;
      if (t < 1 / 2) return q;
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
      return p;
    }

    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    return (hue(p, q, h + 1 / 3), hue(p, q, h), hue(p, q, h - 1 / 3));
  }

  static const Map<String, int> _presetColors = {
    'black': 0x000000,
    'white': 0xFFFFFF,
    'red': 0xFF0000,
    'green': 0x008000,
    'blue': 0x0000FF,
    'yellow': 0xFFFF00,
    'gray': 0x808080,
    'grey': 0x808080,
  };

  // --- Small helpers --------------------------------------------------------

  /// The `p:ph` element of a shape's non-visual properties, if it has one.
  XmlElement? _placeholderOf(XmlElement? nvPr) =>
      _child(_child(nvPr, 'nvPr'), 'ph');

  bool _isHidden(XmlElement? nvPr) {
    final hidden = _attr(_child(nvPr, 'cNvPr'), 'hidden');
    return hidden == '1' || hidden == 'true';
  }

  double _pointsToPx(num hundredthsOfPoint) => hundredthsOfPoint / 100 * 4 / 3;

  double? _emu(String? value) {
    final v = double.tryParse(value ?? '');
    return v == null ? null : v / _emuPerPixel;
  }

  String? _firstAttr(List<XmlElement?> elements, String local) {
    for (final el in elements) {
      final v = _attr(el, local);
      if (v != null) return v;
    }
    return null;
  }

  double? _double(XmlElement? el, String local) =>
      double.tryParse(_attr(el, local) ?? '');

  XmlElement? _child(XmlElement? parent, String local) {
    if (parent == null) return null;
    for (final c in parent.childElements) {
      if (c.name.local == local) return c;
    }
    return null;
  }

  Iterable<XmlElement> _children(XmlElement? parent, String local) =>
      parent?.childElements.where((c) => c.name.local == local) ?? const [];

  String? _attr(XmlElement? el, String local) {
    if (el == null) return null;
    for (final a in el.attributes) {
      if (a.name.local == local) return a.value;
    }
    return null;
  }

  /// A namespaced relationship attribute such as `r:id` / `r:embed`. Unlike
  /// [_attr] this skips unprefixed attributes, because `p:sldId` carries both a
  /// numeric `id` and the `r:id` we want.
  String? _relAttr(XmlElement? el, String local) {
    if (el == null) return null;
    for (final a in el.attributes) {
      if (a.name.local == local && a.name.prefix != null) return a.value;
    }
    return null;
  }
}

// -----------------------------------------------------------------------------
// Package access
// -----------------------------------------------------------------------------

/// The ZIP entries, with cached XML parsing and relationship resolution.
class _Package {
  final Map<String, ArchiveFile> files;
  final _xmlCache = <String, XmlDocument?>{};
  final _relsCache = <String, Map<String, _Rel>>{};

  _Package(this.files);

  XmlDocument? xml(String path) => _xmlCache.putIfAbsent(path, () {
        final file = files[path];
        if (file == null) return null;
        try {
          return XmlDocument.parse(
              utf8.decode(file.content as List<int>, allowMalformed: true));
        } catch (_) {
          return null;
        }
      });

  Uint8List? bytes(String path) {
    final file = files[path];
    if (file == null) return null;
    return Uint8List.fromList(file.content as List<int>);
  }

  /// The relationships of [partPath], keyed by id, with targets resolved to
  /// archive paths (`../media/image1.png` → `ppt/media/image1.png`).
  Map<String, _Rel> rels(String partPath) =>
      _relsCache.putIfAbsent(partPath, () {
        final slash = partPath.lastIndexOf('/');
        final dir = slash < 0 ? '' : partPath.substring(0, slash);
        final name = partPath.substring(slash + 1);
        final doc = xml('${dir.isEmpty ? '' : '$dir/'}_rels/$name.rels');
        if (doc == null) return const {};

        final map = <String, _Rel>{};
        for (final rel in doc.rootElement.childElements) {
          final id = rel.getAttribute('Id');
          final target = rel.getAttribute('Target');
          if (id == null || target == null) continue;
          if (rel.getAttribute('TargetMode') == 'External') continue;
          map[id] = _Rel(rel.getAttribute('Type') ?? '', _resolve(dir, target));
        }
        return map;
      });

  static String _resolve(String dir, String target) {
    if (target.startsWith('/')) return target.substring(1);
    final parts = dir.split('/').where((s) => s.isNotEmpty).toList();
    for (final segment in target.split('/')) {
      if (segment == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (segment.isNotEmpty && segment != '.') {
        parts.add(segment);
      }
    }
    return parts.join('/');
  }
}

class _Rel {
  final String type;
  final String target;

  const _Rel(this.type, this.target);

  /// Relationship types are URIs ending in the kind, e.g. `.../slideLayout`.
  bool isType(String kind) => type.endsWith('/$kind');
}

/// The colour scheme of `ppt/theme/themeN.xml`: `dk1`, `lt1`, `accent1`, …
class _Theme {
  final Map<String, int> colors;

  const _Theme(this.colors);

  static _Theme parse(XmlDocument? doc) {
    final scheme = doc?.descendantElements
        .where((e) => e.name.local == 'clrScheme')
        .firstOrNull;
    if (scheme == null) return const _Theme({});

    final colors = <String, int>{};
    for (final slot in scheme.childElements) {
      final color = slot.childElements.firstOrNull;
      if (color == null) continue;
      final hex = color.name.local == 'sysClr'
          ? color.getAttribute('lastClr')
          : color.getAttribute('val');
      final value = int.tryParse(hex ?? '', radix: 16);
      if (value != null) colors[slot.name.local] = value;
    }
    return _Theme(colors);
  }
}

// -----------------------------------------------------------------------------
// Inheritance: placeholders and text styles
// -----------------------------------------------------------------------------

/// Per-part state threaded through the parse.
class _Context {
  final _Package pkg;
  final _Theme theme;

  /// Master colour map: logical names (`tx1`, `bg1`) → theme slots (`dk1`).
  final Map<String, String> clrMap;

  /// Relationships of the part currently being parsed (for images).
  final Map<String, _Rel> rels;

  final _MasterInfo master;
  final _PlaceholderSet layoutPlaceholders;

  const _Context({
    required this.pkg,
    required this.theme,
    required this.clrMap,
    required this.rels,
    required this.master,
    required this.layoutPlaceholders,
  });

  _Context withRels(Map<String, _Rel> rels) => _Context(
        pkg: pkg,
        theme: theme,
        clrMap: clrMap,
        rels: rels,
        master: master,
        layoutPlaceholders: layoutPlaceholders,
      );

  Uint8List? imageBytes(String? relId) {
    final rel = rels[relId];
    return rel == null ? null : pkg.bytes(rel.target);
  }

  /// The layout and master placeholders a slide placeholder [ph] inherits from.
  ({_Placeholder? layout, _Placeholder? master}) inheritedPlaceholders(
      XmlElement ph) {
    final type = ph.getAttribute('type');
    final idx = ph.getAttribute('idx');
    final layout =
        layoutPlaceholders.find(type, idx, _PlaceholderSet.layoutKind);
    final masterPh = master.placeholders
        .find(layout?.type ?? type, null, _PlaceholderSet.normalizeType);
    return (layout: layout, master: masterPh);
  }
}

/// A placeholder shape on a layout or master.
class _Placeholder {
  final String? type;
  final String? idx;
  final XmlElement? xfrm;
  final XmlElement? bodyPr;
  final XmlElement? lstStyle;

  const _Placeholder(
      this.type, this.idx, this.xfrm, this.bodyPr, this.lstStyle);
}

class _PlaceholderSet {
  final List<_Placeholder> items;

  const _PlaceholderSet(this.items);

  static _PlaceholderSet parse(XmlElement? root, PptxParser p) {
    final tree = p._spTree(root);
    if (tree == null) return const _PlaceholderSet([]);
    final items = <_Placeholder>[];
    for (final el in tree.childElements) {
      final nv = p._child(el, el.name.local == 'pic' ? 'nvPicPr' : 'nvSpPr');
      final ph = p._placeholderOf(nv);
      if (ph == null) continue;
      final txBody = p._child(el, 'txBody');
      items.add(_Placeholder(
        ph.getAttribute('type'),
        ph.getAttribute('idx'),
        p._child(p._child(el, 'spPr'), 'xfrm'),
        p._child(txBody, 'bodyPr'),
        p._child(txBody, 'lstStyle'),
      ));
    }
    return _PlaceholderSet(items);
  }

  /// Matches by index first (how PowerPoint links body placeholders), then by
  /// type as folded by [kindOf] (how titles, dates and footers are linked).
  _Placeholder? find(
      String? type, String? idx, String Function(String?) kindOf) {
    if (idx != null) {
      for (final ph in items) {
        if (ph.idx == idx) return ph;
      }
    }
    final kind = kindOf(type);
    for (final ph in items) {
      if (kindOf(ph.type) == kind) return ph;
    }
    return null;
  }

  /// Type equivalence on a layout: a subtitle or picture placeholder is its
  /// own slot there, so only the spellings of "title" and "content" merge.
  static String layoutKind(String? type) => switch (type) {
        'title' || 'ctrTitle' => 'title',
        null || 'body' || 'obj' => 'body',
        _ => type,
      };

  /// Folds placeholder types onto the few slots a master defines.
  static String normalizeType(String? type) => switch (type) {
        'title' || 'ctrTitle' => 'title',
        null || 'body' || 'obj' || 'subTitle' => 'body',
        _ => type,
      };
}

/// What every slide inherits from its master.
class _MasterInfo {
  final Map<String, String> clrMap;
  final _PlaceholderSet placeholders;
  final _ListStyle titleStyle;
  final _ListStyle bodyStyle;
  final _ListStyle otherStyle;

  const _MasterInfo(this.clrMap, this.placeholders, this.titleStyle,
      this.bodyStyle, this.otherStyle);

  static _MasterInfo parse(XmlElement? root, PptxParser p, _Theme theme) {
    final clrMapEl = p._child(root, 'clrMap');
    final clrMap = <String, String>{
      for (final a in clrMapEl?.attributes ?? const <XmlAttribute>[])
        a.name.local: a.value,
    };

    // Text styles hold colours too, so they need a context with the theme and
    // colour map — but no placeholders or rels, which they never reference.
    final ctx = _Context(
      pkg: _Package(const {}),
      theme: theme,
      clrMap: clrMap,
      rels: const {},
      master: const _MasterInfo({}, _PlaceholderSet([]), _ListStyle.none,
          _ListStyle.none, _ListStyle.none),
      layoutPlaceholders: const _PlaceholderSet([]),
    );
    final txStyles = p._child(root, 'txStyles');
    return _MasterInfo(
      clrMap,
      _PlaceholderSet.parse(root, p),
      _ListStyle.parse(p._child(txStyles, 'titleStyle'), p, ctx),
      _ListStyle.parse(p._child(txStyles, 'bodyStyle'), p, ctx),
      _ListStyle.parse(p._child(txStyles, 'otherStyle'), p, ctx),
    );
  }

  /// Titles use the title style, other placeholders the body style, and plain
  /// text boxes (and dates / footers / slide numbers) the "other" style.
  _ListStyle textStylesFor(XmlElement? ph) {
    if (ph == null) return otherStyle;
    return switch (_PlaceholderSet.normalizeType(ph.getAttribute('type'))) {
      'title' => titleStyle,
      'body' => bodyStyle,
      _ => otherStyle,
    };
  }
}

/// Bullet kinds from `a:buNone` / `a:buChar` / `a:buAutoNum`.
sealed class _Bullet {
  const _Bullet();
}

class _NoBullet extends _Bullet {
  const _NoBullet();
}

class _CharBullet extends _Bullet {
  final String char;
  const _CharBullet(this.char);
}

class _AutoNumBullet extends _Bullet {
  final String scheme;
  final int startAt;
  const _AutoNumBullet(this.scheme, this.startAt);
}

/// Character formatting; null fields inherit from the next style in the chain.
class _RunStyle {
  final double? size;
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final bool? strike;
  final int? color;

  const _RunStyle(
      {this.size,
      this.bold,
      this.italic,
      this.underline,
      this.strike,
      this.color});

  static const _RunStyle none = _RunStyle();

  /// Reads an `a:rPr`, `a:defRPr` or `a:endParaRPr`.
  static _RunStyle parse(XmlElement? el, PptxParser p, _Context ctx) {
    if (el == null) return none;
    bool? flag(String name) {
      final v = el.getAttribute(name);
      return v == null ? null : (v == '1' || v == 'true');
    }

    final u = el.getAttribute('u');
    final strike = el.getAttribute('strike');
    return _RunStyle(
      size: double.tryParse(el.getAttribute('sz') ?? ''),
      bold: flag('b'),
      italic: flag('i'),
      underline: u == null ? null : u != 'none',
      strike: strike == null ? null : strike != 'noStrike',
      color: p._fillColor(el, ctx),
    );
  }

  _RunStyle orElse(_RunStyle fallback) => _RunStyle(
        size: size ?? fallback.size,
        bold: bold ?? fallback.bold,
        italic: italic ?? fallback.italic,
        underline: underline ?? fallback.underline,
        strike: strike ?? fallback.strike,
        color: color ?? fallback.color,
      );
}

/// Paragraph formatting for one outline level (`a:lvlNpPr` or `a:pPr`).
class _LevelStyle {
  final String? align;
  final _Bullet? bullet;
  final double? marginLeft;
  final double? indent;
  final _RunStyle run;

  const _LevelStyle(
      {this.align,
      this.bullet,
      this.marginLeft,
      this.indent,
      this.run = _RunStyle.none});

  static _LevelStyle parse(XmlElement el, PptxParser p, _Context ctx) {
    _Bullet? bullet;
    if (p._child(el, 'buNone') != null) {
      bullet = const _NoBullet();
    } else if (p._child(el, 'buAutoNum') case final auto?) {
      bullet = _AutoNumBullet(
        auto.getAttribute('type') ?? 'arabicPeriod',
        int.tryParse(auto.getAttribute('startAt') ?? '') ?? 1,
      );
    } else if (p._child(el, 'buChar') case final ch?) {
      // Symbol fonts map private glyphs onto ordinary letters ("§", "Ø"), which
      // would show up as those letters; a plain dot reads far better.
      final font = p._attr(p._child(el, 'buFont'), 'typeface') ?? '';
      final symbolFont = font.contains('Wingdings') || font.contains('Symbol');
      final char = ch.getAttribute('char');
      bullet =
          _CharBullet(symbolFont || char == null || char.isEmpty ? '•' : char);
    }

    return _LevelStyle(
      align: el.getAttribute('algn'),
      bullet: bullet,
      marginLeft: p._emu(el.getAttribute('marL')),
      indent: p._emu(el.getAttribute('indent')),
      run: _RunStyle.parse(p._child(el, 'defRPr'), p, ctx),
    );
  }
}

/// A list style: formatting per outline level 0-8.
class _ListStyle {
  final Map<int, _LevelStyle> levels;

  const _ListStyle(this.levels);

  static const _ListStyle none = _ListStyle({});

  /// The same text colour at every level (from a shape's `a:fontRef`).
  factory _ListStyle.uniformColor(int color) => _ListStyle({
        for (var i = 0; i < 9; i++)
          i: _LevelStyle(run: _RunStyle(color: color)),
      });

  static final _levelName = RegExp(r'^lvl([1-9])pPr$');

  static _ListStyle parse(XmlElement? el, PptxParser p, _Context ctx) {
    if (el == null) return none;
    final levels = <int, _LevelStyle>{};
    for (final child in el.childElements) {
      final match = _levelName.firstMatch(child.name.local);
      if (match == null) continue;
      levels[int.parse(match.group(1)!) - 1] = _LevelStyle.parse(child, p, ctx);
    }
    return _ListStyle(levels);
  }
}

/// An inheritance chain of list styles, most specific first.
class _TextStyles {
  final List<_ListStyle> chain;

  const _TextStyles(this.chain);

  /// Resolves the effective style for a paragraph at [level], with its own
  /// `a:pPr` ([own]) taking precedence over everything inherited.
  _LevelStyle resolve(int level, _LevelStyle? own) {
    final styles = [
      if (own != null) own,
      for (final list in chain)
        if (list.levels[level] case final s?) s,
    ];

    T? first<T>(T? Function(_LevelStyle s) pick) {
      for (final s in styles) {
        final v = pick(s);
        if (v != null) return v;
      }
      return null;
    }

    var run = _RunStyle.none;
    for (final s in styles) {
      run = run.orElse(s.run);
    }

    return _LevelStyle(
      align: first((s) => s.align),
      bullet: first((s) => s.bullet),
      marginLeft: first((s) => s.marginLeft),
      indent: first((s) => s.indent),
      run: run,
    );
  }
}

/// Maps shape coordinates (EMU, possibly inside nested groups) to slide pixels.
class _Transform {
  final double offX;
  final double offY;
  final double scaleX;
  final double scaleY;

  const _Transform(this.offX, this.offY, this.scaleX, this.scaleY);

  static const _Transform identity = _Transform(
      0, 0, 1 / PptxParser._emuPerPixel, 1 / PptxParser._emuPerPixel);

  /// Converts an `a:xfrm` (`a:off` + `a:ext`) to a slide rectangle.
  PptxRect? rect(XmlElement? xfrm, PptxParser p) {
    final off = p._child(xfrm, 'off');
    final ext = p._child(xfrm, 'ext');
    if (off == null || ext == null) return null;
    final x = p._double(off, 'x') ?? 0;
    final y = p._double(off, 'y') ?? 0;
    final cx = p._double(ext, 'cx') ?? 0;
    final cy = p._double(ext, 'cy') ?? 0;
    return PptxRect(
      offX + x * scaleX,
      offY + y * scaleY,
      math.max(cx * scaleX, 0),
      math.max(cy * scaleY, 0),
    );
  }

  /// The transform for children of a group whose `a:xfrm` maps its child
  /// space (`chOff` / `chExt`) onto its own frame (`off` / `ext`).
  _Transform group(XmlElement? xfrm, PptxParser p) {
    final off = p._child(xfrm, 'off');
    final ext = p._child(xfrm, 'ext');
    final chOff = p._child(xfrm, 'chOff');
    final chExt = p._child(xfrm, 'chExt');
    if (off == null || ext == null || chOff == null || chExt == null) {
      return this;
    }

    double ratio(String extAttr, XmlElement e, XmlElement ce) {
      final child = p._double(ce, extAttr) ?? 0;
      return child == 0 ? 1 : (p._double(e, extAttr) ?? 0) / child;
    }

    final sx = ratio('cx', ext, chExt);
    final sy = ratio('cy', ext, chExt);
    final ox = (p._double(off, 'x') ?? 0) - (p._double(chOff, 'x') ?? 0) * sx;
    final oy = (p._double(off, 'y') ?? 0) - (p._double(chOff, 'y') ?? 0) * sy;
    return _Transform(
      offX + ox * scaleX,
      offY + oy * scaleY,
      scaleX * sx,
      scaleY * sy,
    );
  }
}
