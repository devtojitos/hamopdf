import 'dart:ui';

import '../repositories/pdf_repository.dart';

class ShareDocumentUsecase {
  final PdfRepository _repository;

  const ShareDocumentUsecase(this._repository);

  bool get isSupported => _repository.canShareDocuments;

  Future<void> call(String path, {Rect? origin}) =>
      _repository.shareDocument(path, origin: origin);
}
