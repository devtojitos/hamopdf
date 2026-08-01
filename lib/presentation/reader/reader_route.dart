import 'package:flutter/material.dart';
import '../../domain/entities/pdf_document.dart';
import 'docx_reader_page.dart';
import 'markdown_reader_page.dart';
import 'reader_page.dart';

/// Picks the reader that can display [document].
///
/// Single source of truth for the type-to-page mapping, shared by the recents
/// list and by files opened from other apps.
Widget readerPageFor(PdfDocument document) => switch (document.type) {
      DocType.docx => DocxReaderPage(document: document),
      DocType.markdown => MarkdownReaderPage(document: document),
      DocType.pdf => ReaderPage(document: document),
    };
