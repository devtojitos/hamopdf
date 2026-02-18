import '../repositories/pdf_repository.dart';

class RemovePdfUsecase {
  final PdfRepository _repository;

  const RemovePdfUsecase(this._repository);

  Future<void> call(String path) => _repository.removeDocument(path);
}
