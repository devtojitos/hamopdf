import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../domain/repositories/pdf_repository.dart';
import '../domain/usecases/extract_docx_text_usecase.dart';
import '../domain/usecases/get_recent_pdfs_usecase.dart';
import '../domain/usecases/pick_pdf_usecase.dart';
import '../domain/usecases/remove_pdf_usecase.dart';
import '../domain/usecases/update_progress_usecase.dart';
import 'home/home_controller.dart';
import 'home/home_page.dart';

class HamoPdfApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const HamoPdfApp({super.key, required this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<PdfRepository>();

    return ChangeNotifierProvider(
      create: (_) => HomeController(
        getRecentPdfs: GetRecentPdfsUsecase(repo),
        pickPdf: PickPdfUsecase(repo),
        removePdf: RemovePdfUsecase(repo),
        updateProgress: UpdateProgressUsecase(repo),
        extractDocxText: ExtractDocxTextUsecase(repo),
      )..loadRecents(),
      child: MaterialApp(
        title: 'HamoPDF',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: const HomePage(),
      ),
    );
  }
}
