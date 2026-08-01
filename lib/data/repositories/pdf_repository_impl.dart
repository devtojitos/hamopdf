import 'dart:convert';
import 'dart:io';
import 'package:docx_to_text/docx_to_text.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/docx_content.dart';
import '../../domain/entities/markdown_content.dart';
import '../../domain/entities/pdf_document.dart';
import '../../domain/repositories/pdf_repository.dart';
import '../datasources/docx_parser.dart';
import '../datasources/download_datasource.dart';
import '../datasources/local_pdf_datasource.dart';
import '../datasources/markdown_parser.dart';

/// Runs off the UI isolate via [compute]; must be a top-level function.
DocxContent _parseDocxBytes(Uint8List bytes) => DocxParser().parse(bytes);

/// Runs off the UI isolate via [compute]; must be a top-level function.
MarkdownContent _parseMarkdownSource(String source) =>
    const MarkdownParser().parse(source);

class PdfRepositoryImpl implements PdfRepository {
  final LocalPdfDatasource _datasource;
  final DownloadDatasource _downloads;

  const PdfRepositoryImpl(
    this._datasource, {
    DownloadDatasource downloads = const DownloadDatasource(),
  }) : _downloads = downloads;

  @override
  Future<List<PdfDocument>> getRecentDocuments() =>
      _datasource.getRecentDocuments();

  @override
  Future<void> saveDocument(PdfDocument document) =>
      _datasource.saveDocument(document);

  @override
  Future<void> removeDocument(String path) =>
      _datasource.removeDocument(path);

  @override
  Future<void> updateProgress(String path, int lastPage, int totalPages) =>
      _datasource.updateProgress(path, lastPage, totalPages);

  @override
  Future<String?> pickDocumentFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'md', 'markdown'],
      allowMultiple: false,
    );
    return result?.files.single.path;
  }

  @override
  Future<String?> downloadDocument(String path) =>
      _downloads.saveToDownloads(path);

  @override
  Future<String> extractDocxText(String path) async {
    final bytes = await File(path).readAsBytes();
    return docxToText(bytes, handleNumbering: true);
  }

  @override
  Future<DocxContent> parseDocx(String path) async {
    final bytes = await File(path).readAsBytes();
    return compute(_parseDocxBytes, bytes);
  }

  @override
  Future<MarkdownContent> parseMarkdown(String path) async {
    // Decode leniently: notes exported from other tools are not always valid
    // UTF-8, and a stray byte should not fail the whole document.
    final bytes = await File(path).readAsBytes();
    final source = const Utf8Decoder(allowMalformed: true).convert(bytes);
    return compute(_parseMarkdownSource, source);
  }
}
