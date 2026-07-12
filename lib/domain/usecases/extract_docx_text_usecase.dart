import '../repositories/pdf_repository.dart';

class ExtractDocxTextUsecase {
  final PdfRepository _repository;

  const ExtractDocxTextUsecase(this._repository);

  Future<String> call(String path) => _repository.extractDocxText(path);
}
