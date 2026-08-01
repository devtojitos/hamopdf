import '../entities/docx_content.dart';
import '../entities/markdown_content.dart';
import '../entities/pdf_document.dart';

abstract class PdfRepository {
  Future<List<PdfDocument>> getRecentDocuments();
  Future<void> saveDocument(PdfDocument document);
  Future<void> removeDocument(String path);
  Future<void> updateProgress(String path, int lastPage, int totalPages);

  /// Opens the system file picker for a supported document (PDF, DOCX or
  /// Markdown). Returns the selected file path, or null if the user cancelled.
  Future<String?> pickDocumentFile();

  /// Saves a durable copy of the document at [path] where the user can find it
  /// — the public Downloads folder on Android, a chosen location on desktop.
  ///
  /// Returns the saved location, or null if the user cancelled. Throws a
  /// [DownloadException] when the copy fails.
  Future<String?> downloadDocument(String path);

  /// Extracts the plain text content of a `.docx` file at [path].
  Future<String> extractDocxText(String path);

  /// Parses a `.docx` file at [path] into a formatted [DocxContent] tree
  /// (paragraphs, runs, lists, tables and inline images).
  Future<DocxContent> parseDocx(String path);

  /// Parses a Markdown file at [path] into a [MarkdownContent] tree
  /// (headings, paragraphs, lists, code blocks, quotes and tables).
  Future<MarkdownContent> parseMarkdown(String path);
}
