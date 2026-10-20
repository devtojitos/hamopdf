import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfDocument;
import 'package:provider/provider.dart';
import '../../domain/entities/pdf_document.dart';
import '../home/home_controller.dart';
import 'download_button.dart';
import 'share_button.dart';

class ReaderPage extends StatefulWidget {
  final PdfDocument document;

  const ReaderPage({super.key, required this.document});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late final PdfViewerController _controller;
  late HomeController _homeController;

  bool _showControls = true;
  int _currentPage = 1;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    _controller = PdfViewerController();
    _currentPage =
        widget.document.lastPage > 0 ? widget.document.lastPage + 1 : 1;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache before dispose where context is unavailable
    _homeController = context.read<HomeController>();
  }

  @override
  void dispose() {
    _saveProgress();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _saveProgress() {
    if (_totalPages > 0) {
      _homeController.onDocumentClosed(
        widget.document.path,
        _currentPage - 1,
        _totalPages,
      );
    }
  }

  void _toggleControls() => setState(() => _showControls = !_showControls);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (_, __) => _saveProgress(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            // Opaque top bar. The page starts below it rather than behind it;
            // when the controls are hidden it collapses and the page grows to
            // fill the screen.
            ClipRect(
              child: AnimatedAlign(
                alignment: Alignment.bottomCenter,
                heightFactor: _showControls ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: _TopBar(
                  document: widget.document,
                  onBack: () => Navigator.pop(context),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: _toggleControls,
                child: Stack(
                  children: [
                    // PDF Viewer — fills the space below the top bar
                    PdfViewer.file(
                      widget.document.path,
                      controller: _controller,
                      params: PdfViewerParams(
                        backgroundColor: Colors.black,
                        onViewerReady: (document, controller) async {
                          setState(() => _totalPages = document.pages.length);
                          if (widget.document.lastPage > 0) {
                            await controller.goToPage(
                                pageNumber: widget.document.lastPage + 1);
                          }
                        },
                        onPageChanged: (page) {
                          if (page != null) setState(() => _currentPage = page);
                        },
                      ),
                    ),

                    // Bottom overlay bar
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: AnimatedSlide(
                        offset:
                            _showControls ? Offset.zero : const Offset(0, 1),
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: _BottomBar(
                          currentPage: _currentPage,
                          totalPages: _totalPages,
                          controller: _controller,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final PdfDocument document;
  final VoidCallback onBack;

  const _TopBar({required this.document, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // One solid colour behind both the status-bar inset and the bar itself.
    return ColoredBox(
      color: cs.surface,
      child: SafeArea(
        bottom: false,
        child: AppBar(
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
            tooltip: 'Back',
          ),
          title: Text(
            document.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            ShareButton(document: document, color: cs.onSurface),
            DownloadButton(document: document, color: cs.onSurface),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom bar
// ---------------------------------------------------------------------------

class _BottomBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final PdfViewerController controller;

  const _BottomBar({
    required this.currentPage,
    required this.totalPages,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final hasPrev = currentPage > 1;
    final hasNext = totalPages == 0 || currentPage < totalPages;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left,
                    color: Colors.white, size: 28),
                onPressed: hasPrev
                    ? () => controller.goToPage(pageNumber: currentPage - 1)
                    : null,
                tooltip: 'Previous page',
              ),
              Expanded(
                child: Text(
                  totalPages > 0
                      ? '$currentPage / $totalPages'
                      : '$currentPage',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right,
                    color: Colors.white, size: 28),
                onPressed: hasNext
                    ? () => controller.goToPage(pageNumber: currentPage + 1)
                    : null,
                tooltip: 'Next page',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
