import '../entities/markdown_content.dart';
import '../repositories/pdf_repository.dart';

class ParseMarkdownUsecase {
  final PdfRepository _repository;

  const ParseMarkdownUsecase(this._repository);

  Future<MarkdownContent> call(String path) => _repository.parseMarkdown(path);
}
