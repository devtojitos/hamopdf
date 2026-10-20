import 'dart:ui';

import 'package:flutter/foundation.dart';
import '../../domain/entities/docx_content.dart';
import '../../domain/entities/markdown_content.dart';
import '../../domain/entities/pdf_document.dart';
import '../../domain/entities/pptx_content.dart';
import '../../domain/usecases/download_document_usecase.dart';
import '../../domain/usecases/extract_docx_text_usecase.dart';
import '../../domain/usecases/parse_docx_usecase.dart';
import '../../domain/usecases/parse_markdown_usecase.dart';
import '../../domain/usecases/parse_pptx_usecase.dart';
import '../../domain/usecases/get_recent_pdfs_usecase.dart';
import '../../domain/usecases/pick_pdf_usecase.dart';
import '../../domain/usecases/remove_pdf_usecase.dart';
import '../../domain/usecases/share_document_usecase.dart';
import '../../domain/usecases/update_progress_usecase.dart';

class HomeController extends ChangeNotifier {
  final GetRecentPdfsUsecase _getRecentPdfs;
  final PickPdfUsecase _pickPdf;
  final RemovePdfUsecase _removePdf;
  final UpdateProgressUsecase _updateProgress;
  final ExtractDocxTextUsecase _extractDocxText;
  final ParseDocxUsecase _parseDocx;
  final ParsePptxUsecase _parsePptx;
  final ParseMarkdownUsecase _parseMarkdown;
  final DownloadDocumentUsecase _downloadDocument;
  final ShareDocumentUsecase _shareDocument;

  HomeController({
    required GetRecentPdfsUsecase getRecentPdfs,
    required PickPdfUsecase pickPdf,
    required RemovePdfUsecase removePdf,
    required UpdateProgressUsecase updateProgress,
    required ExtractDocxTextUsecase extractDocxText,
    required ParseDocxUsecase parseDocx,
    required ParsePptxUsecase parsePptx,
    required ParseMarkdownUsecase parseMarkdown,
    required DownloadDocumentUsecase downloadDocument,
    required ShareDocumentUsecase shareDocument,
  })  : _getRecentPdfs = getRecentPdfs,
        _pickPdf = pickPdf,
        _removePdf = removePdf,
        _updateProgress = updateProgress,
        _extractDocxText = extractDocxText,
        _parseDocx = parseDocx,
        _parsePptx = parsePptx,
        _parseMarkdown = parseMarkdown,
        _downloadDocument = downloadDocument,
        _shareDocument = shareDocument;

  List<PdfDocument> _recents = [];
  bool _loading = false;
  String? _error;

  List<PdfDocument> get recents => _recents;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadRecents() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _recents = await _getRecentPdfs();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<PdfDocument?> openFilePicker() async {
    try {
      final doc = await _pickPdf();
      if (doc != null) await loadRecents();
      return doc;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> remove(String path) async {
    await _removePdf(path);
    await loadRecents();
  }

  Future<void> onDocumentClosed(
      String path, int lastPage, int totalPages) async {
    await _updateProgress(path, lastPage, totalPages);
    await loadRecents();
  }

  /// Extracts the plain-text content of a `.docx` document.
  Future<String> extractDocxText(String path) => _extractDocxText(path);

  /// Parses a `.docx` document into a formatted [DocxContent] tree.
  Future<DocxContent> parseDocx(String path) => _parseDocx(path);

  /// Parses a `.pptx` presentation into positioned slides.
  Future<PptxContent> parsePptx(String path) => _parsePptx(path);

  /// Parses a Markdown document into a [MarkdownContent] tree.
  Future<MarkdownContent> parseMarkdown(String path) => _parseMarkdown(path);

  /// Saves a durable copy of the document at [path] to the device.
  ///
  /// Returns the saved location, or null if the user cancelled. Errors surface
  /// as exceptions so the reader can show them next to the download button.
  Future<String?> downloadDocument(String path) => _downloadDocument(path);

  /// Whether documents can be shared on this platform.
  bool get canShareDocuments => _shareDocument.isSupported;

  /// Opens the system share sheet for the document at [path], anchored to
  /// [origin] where the platform needs it.
  Future<void> shareDocument(String path, {Rect? origin}) =>
      _shareDocument(path, origin: origin);
}
