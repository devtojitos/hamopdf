import '../entities/docx_content.dart';
import '../repositories/pdf_repository.dart';

class ParseDocxUsecase {
  final PdfRepository _repository;

  const ParseDocxUsecase(this._repository);

  Future<DocxContent> call(String path) => _repository.parseDocx(path);
}
