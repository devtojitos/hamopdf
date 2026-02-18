import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/pdf_document.dart';

class LocalPdfDatasource {
  static const _key = 'recent_pdfs';

  Future<List<PdfDocument>> getRecentDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final docs = <PdfDocument>[];
    for (final item in raw) {
      try {
        docs.add(PdfDocument.fromJsonString(item));
      } catch (_) {
        // Skip corrupted entries
      }
    }
    docs.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    return docs;
  }

  Future<void> saveDocument(PdfDocument doc) async {
    final prefs = await SharedPreferences.getInstance();
    final docs = await getRecentDocuments();

    final index = docs.indexWhere((d) => d.path == doc.path);
    if (index >= 0) {
      docs[index] = doc;
    } else {
      docs.insert(0, doc);
    }

    await prefs.setStringList(
      _key,
      docs.map((d) => d.toJsonString()).toList(),
    );
  }

  Future<void> removeDocument(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final docs = await getRecentDocuments();
    docs.removeWhere((d) => d.path == path);
    await prefs.setStringList(
      _key,
      docs.map((d) => d.toJsonString()).toList(),
    );
  }

  Future<void> updateProgress(
      String path, int lastPage, int totalPages) async {
    final prefs = await SharedPreferences.getInstance();
    final docs = await getRecentDocuments();
    final index = docs.indexWhere((d) => d.path == path);
    if (index < 0) return;

    docs[index] = docs[index].copyWith(
      lastPage: lastPage,
      totalPages: totalPages,
      lastOpened: DateTime.now(),
    );

    await prefs.setStringList(
      _key,
      docs.map((d) => d.toJsonString()).toList(),
    );
  }
}
