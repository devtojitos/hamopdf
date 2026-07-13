import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamopdf/data/datasources/docx_parser.dart';
import 'package:hamopdf/domain/entities/docx_content.dart';

/// Packs the given `word/*` XML parts into an in-memory `.docx` (ZIP) archive.
Uint8List buildDocx(Map<String, String> parts) {
  final archive = Archive();
  parts.forEach((name, xml) {
    final bytes = utf8.encode(xml);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

const _documentOpen =
    '<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>';
const _documentClose = '</w:body></w:document>';

void main() {
  final parser = DocxParser();

  test('parses headings, bold and alignment', () {
    final bytes = buildDocx({
      'word/document.xml': '$_documentOpen'
          '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
          '<w:r><w:t>Title</w:t></w:r></w:p>'
          '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
          '<w:r><w:rPr><w:b/></w:rPr><w:t>Bold centered</w:t></w:r></w:p>'
          '$_documentClose',
    });

    final content = parser.parse(bytes);
    expect(content.blocks, hasLength(2));

    final heading = content.blocks[0] as DocxParagraph;
    expect(heading.headingLevel, 1);
    expect((heading.inlines.single as DocxTextRun).text, 'Title');

    final para = content.blocks[1] as DocxParagraph;
    expect(para.align, DocxAlign.center);
    expect((para.inlines.single as DocxTextRun).bold, isTrue);
  });

  test('parses a numbered vs bulleted list from numbering.xml', () {
    final bytes = buildDocx({
      'word/document.xml': '$_documentOpen'
          '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr>'
          '<w:r><w:t>Bulleted</w:t></w:r></w:p>'
          '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="2"/></w:numPr></w:pPr>'
          '<w:r><w:t>Numbered</w:t></w:r></w:p>'
          '$_documentClose',
      'word/numbering.xml':
          '<?xml version="1.0"?><w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
              '<w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/></w:lvl></w:abstractNum>'
              '<w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0"><w:numFmt w:val="decimal"/></w:lvl></w:abstractNum>'
              '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
              '<w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>'
              '</w:numbering>',
    });

    final content = parser.parse(bytes);
    final bullet = content.blocks[0] as DocxParagraph;
    final numbered = content.blocks[1] as DocxParagraph;
    expect(bullet.listMarker, DocxListMarker.bullet);
    expect(numbered.listMarker, DocxListMarker.number);
  });

  test('parses a table into rows and cells', () {
    final bytes = buildDocx({
      'word/document.xml': '$_documentOpen'
          '<w:tbl>'
          '<w:tr><w:tc><w:p><w:r><w:t>A1</w:t></w:r></w:p></w:tc>'
          '<w:tc><w:p><w:r><w:t>B1</w:t></w:r></w:p></w:tc></w:tr>'
          '<w:tr><w:tc><w:p><w:r><w:t>A2</w:t></w:r></w:p></w:tc>'
          '<w:tc><w:p><w:r><w:t>B2</w:t></w:r></w:p></w:tc></w:tr>'
          '</w:tbl>'
          '$_documentClose',
    });

    final content = parser.parse(bytes);
    final table = content.blocks.single as DocxTable;
    expect(table.rows, hasLength(2));
    expect(table.rows[0], hasLength(2));

    final cell = table.rows[0][0].blocks.single as DocxParagraph;
    expect((cell.inlines.single as DocxTextRun).text, 'A1');
  });

  test('resolves an inline image via relationships and media', () {
    final imageBytes = Uint8List.fromList([1, 2, 3, 4]);
    final archive = Archive();
    void add(String name, List<int> data) =>
        archive.addFile(ArchiveFile(name, data.length, data));

    add(
      'word/document.xml',
      utf8.encode('$_documentOpen'
          '<w:p><w:r><w:drawing>'
          '<wp:inline xmlns:wp="ns"><wp:extent cx="952500" cy="952500"/>'
          '<a:blip xmlns:a="ns2" r:embed="rId5" xmlns:r="ns3"/>'
          '</wp:inline></w:drawing></w:r></w:p>'
          '$_documentClose'),
    );
    add(
      'word/_rels/document.xml.rels',
      utf8.encode(
          '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId5" Type="image" Target="media/image1.png"/>'
          '</Relationships>'),
    );
    add('word/media/image1.png', imageBytes);

    final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
    final content = parser.parse(bytes);
    final para = content.blocks.single as DocxParagraph;
    final image = para.inlines.single as DocxImageRun;
    expect(image.bytes, imageBytes);
    // 952500 EMU / 9525 = 100 logical px.
    expect(image.width, 100);
  });
}
