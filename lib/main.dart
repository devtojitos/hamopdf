import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'data/datasources/local_pdf_datasource.dart';
import 'data/repositories/pdf_repository_impl.dart';
import 'domain/entities/pdf_document.dart';
import 'domain/repositories/pdf_repository.dart';
import 'presentation/app.dart';
import 'presentation/home/home_controller.dart';
import 'presentation/reader/reader_page.dart';

const _intentChannel = MethodChannel('web.app.hamopdf/intent');
final _navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final PdfRepository repository = PdfRepositoryImpl(LocalPdfDatasource());

  // Handle files opened while the app is already running.
  _intentChannel.setMethodCallHandler((call) async {
    if (call.method == 'onNewFile') {
      final path = call.arguments as String?;
      if (path != null) await _openExternalFile(path, repository);
    }
  });

  runApp(
    Provider<PdfRepository>.value(
      value: repository,
      child: HamoPdfApp(navigatorKey: _navigatorKey),
    ),
  );

  // Check for a file that was tapped before Flutter was ready (cold start).
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final path =
          await _intentChannel.invokeMethod<String>('getInitialFile');
      if (path != null) await _openExternalFile(path, repository);
    } catch (_) {}
  });
}

/// Saves the file to recents and navigates straight to the reader.
Future<void> _openExternalFile(String path, PdfRepository repo) async {
  final name = path.split(Platform.pathSeparator).last;
  final doc = PdfDocument(
    path: path,
    name: name,
    lastOpened: DateTime.now(),
  );

  await repo.saveDocument(doc);

  _navigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => ReaderPage(document: doc)),
  ).then((_) {
    // Refresh the recents list when the reader is closed.
    _navigatorKey.currentContext
        ?.read<HomeController>()
        .loadRecents();
  });
}
