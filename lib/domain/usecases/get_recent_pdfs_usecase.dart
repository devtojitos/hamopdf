import '../entities/pdf_document.dart';
import '../repositories/pdf_repository.dart';

class GetRecentPdfsUsecase {
  final PdfRepository _repository;

  const GetRecentPdfsUsecase(this._repository);

  Future<List<PdfDocument>> call() => _repository.getRecentDocuments();
}
