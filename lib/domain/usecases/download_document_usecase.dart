import '../repositories/pdf_repository.dart';

class DownloadDocumentUsecase {
  final PdfRepository _repository;

  const DownloadDocumentUsecase(this._repository);

  /// Returns the saved location, or null if the user cancelled.
  Future<String?> call(String path) => _repository.downloadDocument(path);
}
