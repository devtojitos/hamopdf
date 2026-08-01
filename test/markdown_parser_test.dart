import 'package:flutter_test/flutter_test.dart';
import 'package:hamopdf/data/datasources/markdown_parser.dart';
import 'package:hamopdf/domain/entities/markdown_content.dart';

void main() {
  const parser = MarkdownParser();

  /// Flattens the text of a block's inline spans, ignoring styling.
  String textOf(List<MdInline> inlines) => inlines
      .map((i) => switch (i) {
            MdTextSpan t => t.text,
            MdLineBreak _ => '\n',
            MdImageSpan i => '![${i.alt}](${i.src})',
          })
      .join();

  group('headings', () {
    test('parses ATX headings at every level', () {
      final content = parser.parse('# One\n\n### Three\n\n###### Six');
      final headings = content.blocks.cast<MdHeading>();

      expect(headings.map((h) => h.level), [1, 3, 6]);
      expect(headings.map((h) => textOf(h.inlines)), ['One', 'Three', 'Six']);
    });

    test('parses setext headings', () {
      final content = parser.parse('Title\n=====\n\nSubtitle\n---');
      final headings = content.blocks.cast<MdHeading>();

      expect(headings.map((h) => h.level), [1, 2]);
      expect(headings.map((h) => textOf(h.inlines)), ['Title', 'Subtitle']);
    });

    test('strips optional closing hashes', () {
      final content = parser.parse('## Middle ##');
      expect(textOf((content.blocks.single as MdHeading).inlines), 'Middle');
    });
  });

  group('inline styling', () {
    test('parses bold, italic and combined emphasis', () {
      final content = parser.parse('**b** and *i* and ***both***');
      final spans =
          (content.blocks.single as MdParagraph).inlines.cast<MdTextSpan>();

      final bold = spans.firstWhere((s) => s.text == 'b');
      expect(bold.bold, isTrue);
      expect(bold.italic, isFalse);

      final italic = spans.firstWhere((s) => s.text == 'i');
      expect(italic.italic, isTrue);
      expect(italic.bold, isFalse);

      final both = spans.firstWhere((s) => s.text == 'both');
      expect(both.bold, isTrue);
      expect(both.italic, isTrue);
    });

    test('nests emphasis inside strong', () {
      final content = parser.parse('**bold _and italic_**');
      final spans =
          (content.blocks.single as MdParagraph).inlines.cast<MdTextSpan>();

      final nested = spans.firstWhere((s) => s.text == 'and italic');
      expect(nested.bold, isTrue);
      expect(nested.italic, isTrue);
    });

    test('leaves underscores inside words alone', () {
      final content = parser.parse('some_variable_name');
      expect(
        textOf((content.blocks.single as MdParagraph).inlines),
        'some_variable_name',
      );
    });

    test('parses code spans without further styling', () {
      final content = parser.parse('run `a * b` now');
      final spans =
          (content.blocks.single as MdParagraph).inlines.cast<MdTextSpan>();

      final code = spans.firstWhere((s) => s.code);
      expect(code.text, 'a * b');
      expect(code.italic, isFalse);
    });

    test('parses strikethrough', () {
      final content = parser.parse('~~gone~~');
      final span =
          (content.blocks.single as MdParagraph).inlines.single as MdTextSpan;
      expect(span.text, 'gone');
      expect(span.strikethrough, isTrue);
    });

    test('honours backslash escapes', () {
      final content = parser.parse(r'not \*emphasised\*');
      final spans =
          (content.blocks.single as MdParagraph).inlines.cast<MdTextSpan>();
      expect(textOf(spans), 'not *emphasised*');
      expect(spans.every((s) => !s.italic), isTrue);
    });

    test('leaves unmatched delimiters as literal text', () {
      final content = parser.parse('2 * 3 * 4 = 24');
      expect(
        textOf((content.blocks.single as MdParagraph).inlines),
        '2 * 3 * 4 = 24',
      );
    });
  });

  group('links and images', () {
    test('parses an inline link', () {
      final content = parser.parse('see [the docs](https://example.com/x)');
      final spans =
          (content.blocks.single as MdParagraph).inlines.cast<MdTextSpan>();

      final link = spans.firstWhere((s) => s.href != null);
      expect(link.text, 'the docs');
      expect(link.href, 'https://example.com/x');
    });

    test('drops a link title', () {
      final content = parser.parse('[x](https://example.com "A title")');
      final link = (content.blocks.single as MdParagraph).inlines.single
          as MdTextSpan;
      expect(link.href, 'https://example.com');
    });

    test('parses an autolink', () {
      final content = parser.parse('<https://example.com>');
      final link = (content.blocks.single as MdParagraph).inlines.single
          as MdTextSpan;
      expect(link.href, 'https://example.com');
      expect(link.text, 'https://example.com');
    });

    test('parses an image with alt text', () {
      final content = parser.parse('![a cat](cats/tabby.png)');
      final image =
          (content.blocks.single as MdParagraph).inlines.single as MdImageSpan;
      expect(image.alt, 'a cat');
      expect(image.src, 'cats/tabby.png');
    });
  });

  group('lists', () {
    test('parses a bullet list', () {
      final content = parser.parse('- one\n- two\n- three');
      final list = content.blocks.single as MdList;

      expect(list.marker, MdListMarker.bullet);
      expect(list.items.length, 3);
      expect(
        list.items.map((i) => textOf((i.blocks.single as MdParagraph).inlines)),
        ['one', 'two', 'three'],
      );
    });

    test('parses an ordered list and its start number', () {
      final content = parser.parse('3. three\n4. four');
      final list = content.blocks.single as MdList;

      expect(list.marker, MdListMarker.number);
      expect(list.start, 3);
      expect(list.items.length, 2);
    });

    test('parses nested lists', () {
      final content = parser.parse('- outer\n  - inner\n  - inner two');
      final outer = content.blocks.single as MdList;

      expect(outer.items.length, 1);
      final nested = outer.items.single.blocks.last as MdList;
      expect(nested.items.length, 2);
      expect(
        textOf((nested.items.first.blocks.single as MdParagraph).inlines),
        'inner',
      );
    });

    test('parses task list checkboxes', () {
      final content = parser.parse('- [x] done\n- [ ] todo');
      final list = content.blocks.single as MdList;

      expect(list.items.map((i) => i.checked), [true, false]);
      expect(
        textOf((list.items.first.blocks.single as MdParagraph).inlines),
        'done',
      );
    });

    test('does not treat a thematic break as a bullet', () {
      final content = parser.parse('---');
      expect(content.blocks.single, isA<MdRule>());
    });
  });

  group('code blocks', () {
    test('parses a fenced block with a language', () {
      final content = parser.parse('```dart\nvoid main() {}\n```');
      final block = content.blocks.single as MdCodeBlock;

      expect(block.language, 'dart');
      expect(block.text, 'void main() {}');
    });

    test('leaves markdown inside a fence untouched', () {
      final content = parser.parse('```\n# not a heading\n**not bold**\n```');
      final block = content.blocks.single as MdCodeBlock;
      expect(block.text, '# not a heading\n**not bold**');
    });

    test('parses an indented code block', () {
      final content = parser.parse('text\n\n    indented code\n\nmore');
      final block = content.blocks[1] as MdCodeBlock;
      expect(block.text, 'indented code');
    });
  });

  group('blockquotes and tables', () {
    test('parses a blockquote with nested blocks', () {
      final content = parser.parse('> ## Quoted\n> body text');
      final quote = content.blocks.single as MdQuote;

      expect(quote.blocks.first, isA<MdHeading>());
      expect(
        textOf((quote.blocks.last as MdParagraph).inlines),
        'body text',
      );
    });

    test('parses a pipe table with alignments', () {
      final content = parser.parse(
        '| Name | Qty | Price |\n'
        '| :--- | :-: | ----: |\n'
        '| Nut  | 2   | 0.10  |\n'
        '| Bolt | 10  | 0.25  |',
      );
      final table = content.blocks.single as MdTable;

      expect(table.header.map(textOf), ['Name', 'Qty', 'Price']);
      expect(table.alignments, [MdAlign.left, MdAlign.center, MdAlign.right]);
      expect(table.rows.length, 2);
      expect(table.rows.first.map(textOf), ['Nut', '2', '0.10']);
    });
  });

  group('paragraphs', () {
    test('joins soft-wrapped lines with a space', () {
      final content = parser.parse('one\ntwo');
      expect(textOf((content.blocks.single as MdParagraph).inlines), 'one two');
    });

    test('treats two trailing spaces as a hard break', () {
      final content = parser.parse('one  \ntwo');
      final inlines = (content.blocks.single as MdParagraph).inlines;
      expect(inlines.any((i) => i is MdLineBreak), isTrue);
    });

    test('splits paragraphs on a blank line', () {
      final content = parser.parse('first\n\nsecond');
      expect(content.blocks.length, 2);
      expect(content.blocks.every((b) => b is MdParagraph), isTrue);
    });

    test('lets a heading interrupt a paragraph', () {
      final content = parser.parse('text\n# Heading');
      expect(content.blocks.first, isA<MdParagraph>());
      expect(content.blocks.last, isA<MdHeading>());
    });

    test('handles an empty document', () {
      expect(parser.parse('').isEmpty, isTrue);
      expect(parser.parse('\n\n  \n').isEmpty, isTrue);
    });

    test('normalises CRLF line endings', () {
      final content = parser.parse('# Title\r\n\r\nbody');
      expect(content.blocks.first, isA<MdHeading>());
      expect(textOf((content.blocks.last as MdParagraph).inlines), 'body');
    });
  });
}
