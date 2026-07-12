import 'dart:io';
import '../entities/pdf_document.dart';
import '../repositories/pdf_repository.dart';

class PickPdfUsecase {
  final PdfRepository _repository;

  const PickPdfUsecase(this._repository);

  Future<PdfDocument?> call() async {
    final path = await _repository.pickDocumentFile();
    if (path == null) return null;

    final type = DocType.fromExtension(path);

    // Derive a clean display name from the file path (drop the extension).
    final fileName = path.split(Platform.pathSeparator).last;
    final dot = fileName.lastIndexOf('.');
    final name = dot > 0 ? fileName.substring(0, dot) : fileName;

    final doc = PdfDocument(
      path: path,
      name: name,
      lastOpened: DateTime.now(),
      type: type,
    );

    await _repository.saveDocument(doc);
    return doc;
  }
}
