import 'dart:io';
import '../entities/pdf_document.dart';
import '../repositories/pdf_repository.dart';

class PickPdfUsecase {
  final PdfRepository _repository;

  const PickPdfUsecase(this._repository);

  Future<PdfDocument?> call() async {
    final path = await _repository.pickPdfFile();
    if (path == null) return null;

    // Derive a clean display name from the file path
    final fileName = path.split(Platform.pathSeparator).last;
    final name = fileName.endsWith('.pdf')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;

    final doc = PdfDocument(
      path: path,
      name: name,
      lastOpened: DateTime.now(),
    );

    await _repository.saveDocument(doc);
    return doc;
  }
}
