import '../../domain/entities/markdown_content.dart';

/// A self-contained Markdown parser covering the CommonMark subset people
/// actually write, plus the common GitHub extensions.
///
/// Supported: ATX and setext headings, paragraphs, fenced and indented code,
/// blockquotes, nested ordered/unordered lists, task lists, thematic breaks,
/// pipe tables, and the inline set (emphasis, strong, strikethrough, code
/// spans, links, autolinks, images, hard line breaks, backslash escapes).
///
/// Deliberately dependency-free — see [MarkdownContent] for the model it
/// produces.
class MarkdownParser {
  const MarkdownParser();

  MarkdownContent parse(String source) {
    // Normalise line endings and expand tabs so indent maths stays simple.
    final text = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = text.split('\n').map(_expandTabs).toList();
    return MarkdownContent(_parseBlocks(lines));
  }

  // ---------------------------------------------------------------------------
  // Block level
  // ---------------------------------------------------------------------------

  static final _atxHeading = RegExp(r'^ {0,3}(#{1,6})(?:\s+(.*?))?\s*#*\s*$');
  static final _thematicBreak = RegExp(r'^ {0,3}((\*\s*){3,}|(-\s*){3,}|(_\s*){3,})$');
  static final _fence = RegExp(r'^( {0,3})(`{3,}|~{3,})\s*([^`]*)$');
  static final _blockquote = RegExp(r'^ {0,3}> ?(.*)$');
  static final _listItem = RegExp(r'^( {0,3})([-*+]|(\d{1,9})[.)])(\s+|$)(.*)$');
  static final _setext = RegExp(r'^ {0,3}(=+|-+)\s*$');
  static final _tableDelimiter =
      RegExp(r'^ {0,3}\|?(\s*:?-{1,}:?\s*\|)+(\s*:?-{1,}:?\s*)\|?\s*$');
  static final _taskMarker = RegExp(r'^\[([ xX])\]\s+(.*)$');

  List<MdBlock> _parseBlocks(List<String> lines) {
    final blocks = <MdBlock>[];
    var i = 0;

    while (i < lines.length) {
      final line = lines[i];

      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      // Fenced code block.
      final fence = _fence.firstMatch(line);
      if (fence != null) {
        i = _readFencedCode(lines, i, fence, blocks);
        continue;
      }

      // Thematic break must be tested before the list item rule, since `---`
      // and `***` also match a bullet marker.
      if (_thematicBreak.hasMatch(line)) {
        blocks.add(MdRule());
        i++;
        continue;
      }

      // ATX heading.
      final heading = _atxHeading.firstMatch(line);
      if (heading != null) {
        blocks.add(MdHeading(
          level: heading.group(1)!.length,
          inlines: _parseInlines(heading.group(2)?.trim() ?? ''),
        ));
        i++;
        continue;
      }

      // Blockquote.
      if (_blockquote.hasMatch(line)) {
        i = _readBlockquote(lines, i, blocks);
        continue;
      }

      // List.
      if (_listItem.hasMatch(line)) {
        i = _readList(lines, i, blocks);
        continue;
      }

      // Pipe table: a header row followed by a delimiter row.
      if (line.contains('|') &&
          i + 1 < lines.length &&
          _tableDelimiter.hasMatch(lines[i + 1])) {
        i = _readTable(lines, i, blocks);
        continue;
      }

      // Indented code block (4+ spaces, outside any list context).
      if (line.startsWith('    ')) {
        i = _readIndentedCode(lines, i, blocks);
        continue;
      }

      // Otherwise: a paragraph, running until a blank line or the start of
      // another block.
      i = _readParagraph(lines, i, blocks);
    }

    return blocks;
  }

  int _readFencedCode(
      List<String> lines, int start, RegExpMatch open, List<MdBlock> out) {
    final indent = open.group(1)!.length;
    final marker = open.group(2)!;
    final info = open.group(3)!.trim();
    final fenceChar = marker[0];

    final body = <String>[];
    var i = start + 1;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      // A closing fence is at least as long as the opener, same character.
      if (trimmed.startsWith(fenceChar * marker.length) &&
          trimmed.replaceAll(fenceChar, '').trim().isEmpty) {
        i++;
        break;
      }
      // Strip up to the opening fence's indentation, preserving deeper indents.
      body.add(_stripIndent(line, indent));
      i++;
    }

    out.add(MdCodeBlock(
      body.join('\n'),
      language: info.isEmpty ? null : info.split(RegExp(r'\s+')).first,
    ));
    return i;
  }

  int _readIndentedCode(List<String> lines, int start, List<MdBlock> out) {
    final body = <String>[];
    var i = start;
    var lastContent = start;

    while (i < lines.length) {
      final line = lines[i];
      if (line.startsWith('    ')) {
        body.add(line.substring(4));
        lastContent = i;
        i++;
      } else if (line.trim().isEmpty) {
        body.add('');
        i++;
      } else {
        break;
      }
    }

    // Drop trailing blank lines that belong to the document, not the block.
    final kept = body.sublist(0, lastContent - start + 1);
    out.add(MdCodeBlock(kept.join('\n')));
    return lastContent + 1;
  }

  int _readBlockquote(List<String> lines, int start, List<MdBlock> out) {
    final inner = <String>[];
    var i = start;

    while (i < lines.length) {
      final match = _blockquote.firstMatch(lines[i]);
      if (match != null) {
        inner.add(match.group(1)!);
        i++;
      } else if (lines[i].trim().isNotEmpty && inner.isNotEmpty) {
        // Lazy continuation: an unmarked line still belongs to the quote's
        // current paragraph.
        inner.add(lines[i]);
        i++;
      } else {
        break;
      }
    }

    out.add(MdQuote(_parseBlocks(inner)));
    return i;
  }

  int _readList(List<String> lines, int start, List<MdBlock> out) {
    final first = _listItem.firstMatch(lines[start])!;
    final isOrdered = first.group(3) != null;
    final startNumber = isOrdered ? int.parse(first.group(3)!) : 1;

    final items = <MdListItem>[];
    var i = start;

    while (i < lines.length) {
      final match = _listItem.firstMatch(lines[i]);
      // A thematic break wins over a bullet of the same characters.
      if (match == null || _thematicBreak.hasMatch(lines[i])) break;
      // A different marker kind starts a new list, not another item.
      if ((match.group(3) != null) != isOrdered) break;

      final contentIndent = match.group(1)!.length +
          match.group(2)!.length +
          match.group(4)!.length;

      final itemLines = <String>[match.group(5)!];
      i++;

      // Absorb continuation lines: anything indented into the item's content
      // column, plus blank lines that are followed by more indented content.
      while (i < lines.length) {
        final line = lines[i];
        if (line.trim().isEmpty) {
          final next = _nextNonBlank(lines, i);
          if (next != null &&
              !_thematicBreak.hasMatch(lines[next]) &&
              _indentOf(lines[next]) >= contentIndent) {
            itemLines.add('');
            i++;
            continue;
          }
          break;
        }
        if (_indentOf(line) >= contentIndent) {
          itemLines.add(_stripIndent(line, contentIndent));
          i++;
          continue;
        }
        // A sibling item or any other block at the outer level ends this item.
        break;
      }

      items.add(_buildListItem(itemLines));
    }

    out.add(MdList(
      marker: isOrdered ? MdListMarker.number : MdListMarker.bullet,
      items: items,
      start: startNumber,
    ));
    return i;
  }

  MdListItem _buildListItem(List<String> itemLines) {
    // Pull a leading `[ ]` / `[x]` off the first line for task lists.
    bool? checked;
    final task = _taskMarker.firstMatch(itemLines.first);
    if (task != null) {
      checked = task.group(1)!.toLowerCase() == 'x';
      itemLines = [task.group(2)!, ...itemLines.skip(1)];
    }
    return MdListItem(_parseBlocks(itemLines), checked: checked);
  }

  int _readTable(List<String> lines, int start, List<MdBlock> out) {
    final header = _splitRow(lines[start]);
    final alignments = _splitRow(lines[start + 1]).map(_alignOf).toList();

    final rows = <List<List<MdInline>>>[];
    var i = start + 2;
    while (i < lines.length &&
        lines[i].contains('|') &&
        lines[i].trim().isNotEmpty) {
      final cells = _splitRow(lines[i]);
      rows.add([
        for (var c = 0; c < header.length; c++)
          _parseInlines(c < cells.length ? cells[c] : ''),
      ]);
      i++;
    }

    out.add(MdTable(
      header: header.map(_parseInlines).toList(),
      rows: rows,
      alignments: alignments,
    ));
    return i;
  }

  int _readParagraph(List<String> lines, int start, List<MdBlock> out) {
    final buffer = <String>[];
    var i = start;

    while (i < lines.length) {
      final line = lines[i];
      if (line.trim().isEmpty) break;

      // A setext underline turns the paragraph so far into a heading.
      if (buffer.isNotEmpty && _setext.hasMatch(line)) {
        final level = line.trim().startsWith('=') ? 1 : 2;
        out.add(MdHeading(
          level: level,
          inlines: _parseInlines(buffer.join('\n')),
        ));
        return i + 1;
      }

      // Any other block start interrupts the paragraph.
      if (buffer.isNotEmpty && _interruptsParagraph(line)) break;

      buffer.add(line);
      i++;
    }

    if (buffer.isNotEmpty) out.add(MdParagraph(_parseInlines(buffer.join('\n'))));
    return i == start ? start + 1 : i;
  }

  bool _interruptsParagraph(String line) =>
      _atxHeading.hasMatch(line) ||
      _thematicBreak.hasMatch(line) ||
      _fence.hasMatch(line) ||
      _blockquote.hasMatch(line) ||
      _listItem.hasMatch(line);

  // ---------------------------------------------------------------------------
  // Inline level
  // ---------------------------------------------------------------------------

  /// Parses [text] into styled spans, inheriting the surrounding style flags so
  /// nested constructs such as `**bold _and italic_**` compose correctly.
  List<MdInline> _parseInlines(
    String text, {
    bool bold = false,
    bool italic = false,
    bool strike = false,
    String? href,
  }) {
    final out = <MdInline>[];
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isEmpty) return;
      out.add(MdTextSpan(
        buffer.toString(),
        bold: bold,
        italic: italic,
        strikethrough: strike,
        href: href,
      ));
      buffer.clear();
    }

    void addNested(String inner,
        {bool? b, bool? i, bool? s, String? link}) {
      flush();
      out.addAll(_parseInlines(
        inner,
        bold: b ?? bold,
        italic: i ?? italic,
        strike: s ?? strike,
        href: link ?? href,
      ));
    }

    var pos = 0;
    while (pos < text.length) {
      final char = text[pos];

      // Backslash escape: the next character is always literal.
      if (char == r'\' && pos + 1 < text.length) {
        final next = text[pos + 1];
        if (next == '\n') {
          flush();
          out.add(MdLineBreak());
        } else if (_escapable.contains(next)) {
          buffer.write(next);
        } else {
          buffer..write(char)..write(next);
        }
        pos += 2;
        continue;
      }

      // Hard line break: two or more trailing spaces before a newline.
      // A soft break collapses to a single space, as Markdown specifies.
      if (char == '\n') {
        final hard = buffer.length >= 2 &&
            buffer.toString().endsWith('  ');
        final soft = buffer.toString().trimRight();
        buffer.clear();
        buffer.write(soft);
        flush();
        out.add(hard ? MdLineBreak() : MdTextSpan(' ',
            bold: bold, italic: italic, strikethrough: strike, href: href));
        pos++;
        // Skip the next line's leading whitespace.
        while (pos < text.length && (text[pos] == ' ')) {
          pos++;
        }
        continue;
      }

      // Code span: a run of N backticks closed by another run of exactly N.
      if (char == '`') {
        final run = _runLength(text, pos, '`');
        final close = text.indexOf('`' * run, pos + run);
        if (close != -1 && _runLength(text, close, '`') == run) {
          flush();
          // Code spans take no further inline parsing.
          out.add(MdTextSpan(
            text.substring(pos + run, close).trim(),
            code: true,
            bold: bold,
            italic: italic,
            strikethrough: strike,
            href: href,
          ));
          pos = close + run;
          continue;
        }
      }

      // Image: ![alt](src)
      if (char == '!' && pos + 1 < text.length && text[pos + 1] == '[') {
        final link = _readLink(text, pos + 1);
        if (link != null) {
          flush();
          out.add(MdImageSpan(src: link.destination, alt: link.label));
          pos = link.end;
          continue;
        }
      }

      // Link: [text](href)
      if (char == '[') {
        final link = _readLink(text, pos);
        if (link != null) {
          addNested(link.label, link: link.destination);
          pos = link.end;
          continue;
        }
      }

      // Autolink: <https://example.com>
      if (char == '<') {
        final close = text.indexOf('>', pos + 1);
        if (close != -1) {
          final url = text.substring(pos + 1, close);
          if (_autolink.hasMatch(url)) {
            flush();
            out.add(MdTextSpan(url,
                bold: bold, italic: italic, strikethrough: strike, href: url));
            pos = close + 1;
            continue;
          }
        }
      }

      // Strikethrough: ~~text~~
      if (char == '~' &&
          _runLength(text, pos, '~') >= 2 &&
          _canOpen(text, pos, 2)) {
        final close = _findCloser(text, pos + 2, '~~');
        if (close != -1) {
          addNested(text.substring(pos + 2, close), s: true);
          pos = close + 2;
          continue;
        }
      }

      // Emphasis: ***both***, **bold**, *italic* (and the `_` equivalents).
      if (char == '*' || char == '_') {
        final run = _runLength(text, pos, char);
        // `_` does not open emphasis inside a word (snake_case stays intact).
        final intraword = char == '_' &&
            pos > 0 &&
            _isWordChar(text[pos - 1]);
        if (!intraword && _canOpen(text, pos, run)) {
          final take = run >= 3 ? 3 : run;
          final delim = char * take;
          final close = _findCloser(text, pos + take, delim);
          if (close != -1 && close > pos + take) {
            final inner = text.substring(pos + take, close);
            addNested(
              inner,
              b: take >= 2 ? true : null,
              i: take == 1 || take == 3 ? true : null,
            );
            pos = close + take;
            continue;
          }
        }
      }

      buffer.write(char);
      pos++;
    }

    flush();
    return out;
  }

  static const _escapable = r'\`*_{}[]()#+-.!|~>';
  static final _autolink = RegExp(r'^(https?|ftp|mailto):', caseSensitive: false);

  /// Finds the index of [delim] closing an emphasis run that began before
  /// [from], skipping escaped characters and code spans.
  int _findCloser(String text, int from, String delim) {
    var i = from;
    while (i < text.length) {
      if (text[i] == r'\') {
        i += 2;
        continue;
      }
      if (text[i] == '`') {
        final run = _runLength(text, i, '`');
        final close = text.indexOf('`' * run, i + run);
        i = close == -1 ? i + run : close + run;
        continue;
      }
      if (text.startsWith(delim, i)) {
        final run = _runLength(text, i, delim[0]);
        // For `*`/`_`, make sure we are not looking at a longer or shorter run
        // that belongs to a different delimiter length.
        if (delim[0] != '~' && run != delim.length) {
          i += run;
          continue;
        }
        // A run preceded by whitespace closes nothing — it is literal text.
        if (!_canClose(text, i)) {
          i += run;
          continue;
        }
        return i;
      }
      i++;
    }
    return -1;
  }

  /// Whether the delimiter run of length [run] at [pos] can open emphasis.
  ///
  /// CommonMark calls this "left-flanking": the run must be followed by real
  /// content, so the asterisks in `2 * 3 * 4` stay literal.
  static bool _canOpen(String text, int pos, int run) {
    final after = pos + run;
    return after < text.length && !_isWhitespace(text[after]);
  }

  /// Whether a delimiter run at [pos] can close emphasis ("right-flanking"):
  /// it must be preceded by real content.
  static bool _canClose(String text, int pos) =>
      pos > 0 && !_isWhitespace(text[pos - 1]);

  static bool _isWhitespace(String c) =>
      c == ' ' || c == '\n' || c == '\t' || c == '\r';

  /// Reads `[label](destination)` starting at the `[` in [start].
  _Link? _readLink(String text, int start) {
    // Find the matching `]`, allowing balanced nested brackets.
    var depth = 0;
    var i = start;
    var labelEnd = -1;
    while (i < text.length) {
      final c = text[i];
      if (c == r'\') {
        i += 2;
        continue;
      }
      if (c == '[') depth++;
      if (c == ']') {
        depth--;
        if (depth == 0) {
          labelEnd = i;
          break;
        }
      }
      i++;
    }
    if (labelEnd == -1) return null;
    if (labelEnd + 1 >= text.length || text[labelEnd + 1] != '(') return null;

    // Find the matching `)`, allowing balanced parens inside the URL.
    depth = 0;
    i = labelEnd + 1;
    var destEnd = -1;
    while (i < text.length) {
      final c = text[i];
      if (c == r'\') {
        i += 2;
        continue;
      }
      if (c == '(') depth++;
      if (c == ')') {
        depth--;
        if (depth == 0) {
          destEnd = i;
          break;
        }
      }
      i++;
    }
    if (destEnd == -1) return null;

    var destination = text.substring(labelEnd + 2, destEnd).trim();
    // Drop an optional title: [x](url "title")
    final space = destination.indexOf(RegExp(r'\s'));
    if (space != -1) destination = destination.substring(0, space);
    if (destination.startsWith('<') && destination.endsWith('>')) {
      destination = destination.substring(1, destination.length - 1);
    }

    return _Link(
      label: text.substring(start + 1, labelEnd),
      destination: destination,
      end: destEnd + 1,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _expandTabs(String line) {
    if (!line.contains('\t')) return line;
    final buffer = StringBuffer();
    for (final char in line.split('')) {
      if (char == '\t') {
        buffer.write(' ' * (4 - buffer.length % 4));
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  static int _runLength(String text, int start, String char) {
    var n = 0;
    while (start + n < text.length && text[start + n] == char) {
      n++;
    }
    return n;
  }

  static int _indentOf(String line) {
    var n = 0;
    while (n < line.length && line[n] == ' ') {
      n++;
    }
    return n;
  }

  static String _stripIndent(String line, int amount) {
    var n = 0;
    while (n < amount && n < line.length && line[n] == ' ') {
      n++;
    }
    return line.substring(n);
  }

  static int? _nextNonBlank(List<String> lines, int from) {
    for (var i = from; i < lines.length; i++) {
      if (lines[i].trim().isNotEmpty) return i;
    }
    return null;
  }

  static bool _isWordChar(String c) =>
      RegExp(r'[A-Za-z0-9]').hasMatch(c);

  /// Splits a table row on unescaped pipes, dropping the optional outer ones.
  static List<String> _splitRow(String line) {
    var row = line.trim();
    if (row.startsWith('|')) row = row.substring(1);
    if (row.endsWith('|') && !row.endsWith(r'\|')) {
      row = row.substring(0, row.length - 1);
    }

    final cells = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < row.length; i++) {
      if (row[i] == r'\' && i + 1 < row.length && row[i + 1] == '|') {
        buffer.write('|');
        i++;
        continue;
      }
      if (row[i] == '|') {
        cells.add(buffer.toString().trim());
        buffer.clear();
        continue;
      }
      buffer.write(row[i]);
    }
    cells.add(buffer.toString().trim());
    return cells;
  }

  static MdAlign _alignOf(String spec) {
    final s = spec.trim();
    final left = s.startsWith(':');
    final right = s.endsWith(':');
    if (left && right) return MdAlign.center;
    if (right) return MdAlign.right;
    return MdAlign.left;
  }
}

/// The pieces of a parsed `[label](destination)` construct.
class _Link {
  final String label;
  final String destination;

  /// Index just past the closing `)`.
  final int end;

  const _Link({
    required this.label,
    required this.destination,
    required this.end,
  });
}
