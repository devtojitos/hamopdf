import '../entities/pdf_document.dart';

abstract class PdfRepository {
  Future<List<PdfDocument>> getRecentDocuments();
  Future<void> saveDocument(PdfDocument document);
  Future<void> removeDocument(String path);
  Future<void> updateProgress(String path, int lastPage, int totalPages);
  Future<String?> pickPdfFile();
}
