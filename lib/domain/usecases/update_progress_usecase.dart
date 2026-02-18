import '../repositories/pdf_repository.dart';

class UpdateProgressUsecase {
  final PdfRepository _repository;

  const UpdateProgressUsecase(this._repository);

  Future<void> call(String path, int lastPage, int totalPages) =>
      _repository.updateProgress(path, lastPage, totalPages);
}
