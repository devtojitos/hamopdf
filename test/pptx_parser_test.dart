import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamopdf/data/datasources/pptx_parser.dart';
import 'package:hamopdf/domain/entities/pptx_content.dart';

/// Packs the given parts into an in-memory `.pptx` (ZIP) archive.
Uint8List buildPptx(Map<String, Object> parts) {
  final archive = Archive();
  parts.forEach((name, content) {
    final bytes =
        content is String ? utf8.encode(content) : content as List<int>;
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

const _ns = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';

String _rels(Map<String, (String, String)> rels) =>
    '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '${rels.entries.map((e) => '<Relationship Id="${e.key}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/${e.value.$1}" '
        'Target="${e.value.$2}"/>').join()}'
    '</Relationships>';

String _xfrm(int x, int y, int cx, int cy) =>
    '<a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>';

/// One EMU-per-pixel unit, so test geometry reads in pixels.
const _px = 9525;

/// A minimal presentation: theme, one master, one layout and [slides].
Map<String, Object> _package(List<String> slides, {String? layoutTree}) => {
      'ppt/presentation.xml': '<?xml version="1.0"?><p:presentation $_ns>'
          '<p:sldIdLst>'
          '${[
        for (var i = 0; i < slides.length; i++)
          '<p:sldId id="${256 + i}" r:id="rId${i + 10}"/>'
      ].join()}'
          '</p:sldIdLst>'
          '<p:sldSz cx="${1280 * _px}" cy="${720 * _px}"/>'
          '</p:presentation>',
      'ppt/_rels/presentation.xml.rels': _rels({
        'rId1': ('theme', 'theme/theme1.xml'),
        for (var i = 0; i < slides.length; i++)
          'rId${i + 10}': ('slide', 'slides/slide${i + 1}.xml'),
      }),
      'ppt/theme/theme1.xml':
          '<?xml version="1.0"?><a:theme $_ns><a:themeElements>'
              '<a:clrScheme name="t">'
              '<a:dk1><a:srgbClr val="111111"/></a:dk1>'
              '<a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>'
              '<a:accent1><a:srgbClr val="4472C4"/></a:accent1>'
              '</a:clrScheme></a:themeElements></a:theme>',
      'ppt/slideMasters/slideMaster1.xml': '<?xml version="1.0"?><p:sldMaster $_ns><p:cSld>'
          '<p:bg><p:bgPr><a:solidFill><a:srgbClr val="FAFAFA"/></a:solidFill></p:bgPr></p:bg>'
          '<p:spTree>'
          '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>'
          '<p:spPr>${_xfrm(40 * _px, 20 * _px, 1200 * _px, 100 * _px)}</p:spPr>'
          '<p:txBody><a:bodyPr anchor="ctr"/><a:lstStyle/><a:p/></p:txBody></p:sp>'
          '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Body"/><p:cNvSpPr/><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>'
          '<p:spPr>${_xfrm(40 * _px, 140 * _px, 1200 * _px, 500 * _px)}</p:spPr>'
          '<p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody></p:sp>'
          '</p:spTree></p:cSld>'
          '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1"/>'
          '<p:txStyles>'
          '<p:titleStyle><a:lvl1pPr algn="ctr"><a:defRPr sz="4400"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill></a:defRPr></a:lvl1pPr></p:titleStyle>'
          '<p:bodyStyle><a:lvl1pPr marL="${24 * _px}" indent="-${24 * _px}"><a:buChar char="•"/><a:defRPr sz="2800"/></a:lvl1pPr></p:bodyStyle>'
          '<p:otherStyle><a:lvl1pPr><a:defRPr sz="1800"/></a:lvl1pPr></p:otherStyle>'
          '</p:txStyles></p:sldMaster>',
      'ppt/slideLayouts/slideLayout1.xml':
          '<?xml version="1.0"?><p:sldLayout $_ns><p:cSld><p:spTree>'
              '${layoutTree ?? ''}'
              '</p:spTree></p:cSld></p:sldLayout>',
      'ppt/slideLayouts/_rels/slideLayout1.xml.rels':
          _rels({'rId1': ('slideMaster', '../slideMasters/slideMaster1.xml')}),
      for (var i = 0; i < slides.length; i++) ...{
        'ppt/slides/slide${i + 1}.xml':
            '<?xml version="1.0"?><p:sld $_ns><p:cSld><p:spTree>${slides[i]}</p:spTree></p:cSld></p:sld>',
        'ppt/slides/_rels/slide${i + 1}.xml.rels': _rels({
          'rId1': ('slideLayout', '../slideLayouts/slideLayout1.xml'),
          'rId2': ('image', '../media/image1.png'),
        }),
      },
      'ppt/media/image1.png': [1, 2, 3, 4],
    };

String _placeholder(String ph, String paragraphs, {String spPr = ''}) =>
    '<p:sp><p:nvSpPr><p:cNvPr id="9" name="ph"/><p:cNvSpPr/><p:nvPr>$ph</p:nvPr></p:nvSpPr>'
    '<p:spPr>$spPr</p:spPr><p:txBody><a:bodyPr/><a:lstStyle/>$paragraphs</p:txBody></p:sp>';

void main() {
  final parser = PptxParser();

  test('reads the slide size and slides in presentation order', () {
    final content = parser.parse(buildPptx(_package([
      _placeholder(
          '<p:ph type="title"/>', '<a:p><a:r><a:t>First</a:t></a:r></a:p>'),
      _placeholder(
          '<p:ph type="title"/>', '<a:p><a:r><a:t>Second</a:t></a:r></a:p>'),
    ])));

    expect(content.slideWidth, closeTo(1280, 0.01));
    expect(content.slideHeight, closeTo(720, 0.01));
    expect(content.slides, hasLength(2));
    final second = content.slides[1].shapes.single as PptxTextShape;
    expect(second.paragraphs.single.runs.single.text, 'Second');
  });

  test('a title placeholder inherits position, size, colour and alignment', () {
    final content = parser.parse(buildPptx(_package([
      _placeholder(
          '<p:ph type="title"/>', '<a:p><a:r><a:t>Hello</a:t></a:r></a:p>'),
    ])));

    final slide = content.slides.single;
    expect(slide.backgroundArgb, 0xFFFAFAFA); // from the master
    final title = slide.shapes.single as PptxTextShape;
    expect(title.frame.x, closeTo(40, 0.01));
    expect(title.frame.width, closeTo(1200, 0.01));
    expect(title.anchor, PptxAnchor.middle);

    final paragraph = title.paragraphs.single;
    expect(paragraph.align, PptxAlign.center);
    expect(paragraph.bullet, isNull);
    final run = paragraph.runs.single;
    expect(run.fontSize, closeTo(44 * 4 / 3, 0.01));
    expect(run.colorArgb, 0xFF111111); // tx1 → dk1 through the clrMap
  });

  test('body placeholders get master bullets unless the layout removes them',
      () {
    final content = parser.parse(buildPptx(
      _package([
        _placeholder('<p:ph idx="1"/>',
            '<a:p><a:r><a:t>Bulleted</a:t></a:r></a:p><a:p/>'),
        _placeholder('<p:ph type="subTitle" idx="2"/>',
            '<a:p><a:r><a:t>Subtitle</a:t></a:r></a:p>'),
      ],
          layoutTree: _placeholder(
            '<p:ph type="subTitle" idx="2"/>',
            '',
            spPr: _xfrm(100 * _px, 400 * _px, 1080 * _px, 80 * _px),
          ).replaceFirst('<a:lstStyle/>',
              '<a:lstStyle><a:lvl1pPr><a:buNone/></a:lvl1pPr></a:lstStyle>')),
    ));

    final body = content.slides[0].shapes.single as PptxTextShape;
    expect(body.paragraphs.first.bullet, '•');
    expect(body.paragraphs.first.marginLeft, closeTo(24, 0.01));
    expect(
        body.paragraphs.first.runs.single.fontSize, closeTo(28 * 4 / 3, 0.01));
    expect(body.paragraphs.last.bullet, isNull); // empty line: no bullet

    final subtitle = content.slides[1].shapes.single as PptxTextShape;
    expect(subtitle.frame.y, closeTo(400, 0.01)); // position from the layout
    expect(subtitle.paragraphs.single.bullet, isNull);
  });

  test('numbers auto-numbered paragraphs', () {
    final numbered = [
      for (final t in ['one', 'two', 'three'])
        '<a:p><a:pPr><a:buAutoNum type="alphaLcParenR"/></a:pPr><a:r><a:t>$t</a:t></a:r></a:p>',
    ].join();
    final content = parser.parse(buildPptx(_package([
      '<p:sp><p:nvSpPr><p:cNvPr id="4" name="box"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
          '<p:spPr>${_xfrm(0, 0, 400 * _px, 300 * _px)}</p:spPr>'
          '<p:txBody><a:bodyPr/><a:lstStyle/>$numbered</p:txBody></p:sp>',
    ])));

    final box = content.slides.single.shapes.single as PptxTextShape;
    expect(box.paragraphs.map((p) => p.bullet), ['a)', 'b)', 'c)']);
  });

  test('maps grouped shapes through the group transform', () {
    final content = parser.parse(buildPptx(_package([
      '<p:grpSp><p:nvGrpSpPr><p:cNvPr id="5" name="g"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
          '<p:grpSpPr><a:xfrm><a:off x="${100 * _px}" y="${100 * _px}"/><a:ext cx="${200 * _px}" cy="${200 * _px}"/>'
          '<a:chOff x="0" y="0"/><a:chExt cx="${100 * _px}" cy="${100 * _px}"/></a:xfrm></p:grpSpPr>'
          '<p:sp><p:nvSpPr><p:cNvPr id="6" name="r"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
          '<p:spPr>${_xfrm(50 * _px, 0, 50 * _px, 50 * _px)}'
          '<a:prstGeom prst="ellipse"/><a:solidFill><a:schemeClr val="accent1"><a:lumMod val="50000"/></a:schemeClr></a:solidFill></p:spPr>'
          '</p:sp></p:grpSp>',
    ])));

    final shape = content.slides.single.shapes.single as PptxTextShape;
    expect(shape.frame.x, closeTo(200, 0.01));
    expect(shape.frame.y, closeTo(100, 0.01));
    expect(shape.frame.width, closeTo(100, 0.01));
    expect(shape.geometry, PptxGeometry.ellipse);
    // accent1 #4472C4 at half luminance.
    expect(shape.fillArgb, 0xFF203864);
  });

  test('parses pictures and tables', () {
    final content = parser.parse(buildPptx(_package([
      '<p:pic><p:nvPicPr><p:cNvPr id="7" name="pic"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>'
          '<p:blipFill><a:blip r:embed="rId2"/></p:blipFill>'
          '<p:spPr>${_xfrm(10 * _px, 10 * _px, 64 * _px, 48 * _px)}</p:spPr></p:pic>'
          '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="8" name="t"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>'
          '<p:xfrm><a:off x="0" y="${300 * _px}"/><a:ext cx="${400 * _px}" cy="${80 * _px}"/></p:xfrm>'
          '<a:graphic><a:graphicData><a:tbl>'
          '<a:tblGrid><a:gridCol w="${150 * _px}"/><a:gridCol w="${250 * _px}"/></a:tblGrid>'
          '<a:tr h="${40 * _px}">'
          '<a:tc><a:txBody><a:bodyPr/><a:p><a:r><a:t>A1</a:t></a:r></a:p></a:txBody>'
          '<a:tcPr><a:solidFill><a:srgbClr val="FF0000"/></a:solidFill></a:tcPr></a:tc>'
          '<a:tc><a:txBody><a:bodyPr/><a:p><a:r><a:t>B1</a:t></a:r></a:p></a:txBody></a:tc>'
          '</a:tr></a:tbl></a:graphicData></a:graphic></p:graphicFrame>',
    ])));

    final shapes = content.slides.single.shapes;
    final picture = shapes[0] as PptxImageShape;
    expect(picture.bytes, [1, 2, 3, 4]);
    expect(picture.frame.width, closeTo(64, 0.01));

    final table = shapes[1] as PptxTableShape;
    expect(table.columnWidths[0], closeTo(150, 0.01));
    expect(table.rows.single, hasLength(2));
    expect(table.rows.single[0].fillArgb, 0xFFFF0000);
    expect(table.rows.single[1].paragraphs.single.runs.single.text, 'B1');
  });

  test('returns empty content for a file that is not a presentation', () {
    final content = parser.parse(buildPptx({'word/document.xml': '<x/>'}));
    expect(content.isEmpty, isTrue);
  });
}
