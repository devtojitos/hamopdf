import '../entities/pptx_content.dart';
import '../repositories/pdf_repository.dart';

class ParsePptxUsecase {
  final PdfRepository _repository;

  const ParsePptxUsecase(this._repository);

  Future<PptxContent> call(String path) => _repository.parsePptx(path);
}
