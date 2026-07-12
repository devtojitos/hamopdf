import '../entities/pdf_document.dart';

abstract class PdfRepository {
  Future<List<PdfDocument>> getRecentDocuments();
  Future<void> saveDocument(PdfDocument document);
  Future<void> removeDocument(String path);
  Future<void> updateProgress(String path, int lastPage, int totalPages);

  /// Opens the system file picker for a supported document (PDF or DOCX).
  /// Returns the selected file path, or null if the user cancelled.
  Future<String?> pickDocumentFile();

  /// Extracts the plain text content of a `.docx` file at [path].
  Future<String> extractDocxText(String path);
}
