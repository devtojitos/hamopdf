import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'data/datasources/local_pdf_datasource.dart';
import 'data/repositories/pdf_repository_impl.dart';
import 'domain/repositories/pdf_repository.dart';
import 'presentation/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final PdfRepository repository =
      PdfRepositoryImpl(LocalPdfDatasource());

  runApp(
    Provider<PdfRepository>.value(
      value: repository,
      child: const HamoPdfApp(),
    ),
  );
}
