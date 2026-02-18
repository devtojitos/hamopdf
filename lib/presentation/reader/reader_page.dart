import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfDocument;
import 'package:provider/provider.dart';
import '../../domain/entities/pdf_document.dart';
import '../home/home_controller.dart';

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
        body: GestureDetector(
          onTap: _toggleControls,
          child: Stack(
            children: [
              // PDF Viewer — fills the screen
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

              // Top overlay bar
              AnimatedSlide(
                offset:
                    _showControls ? Offset.zero : const Offset(0, -1),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: _TopBar(
                  title: widget.document.name,
                  onBack: () => Navigator.pop(context),
                ),
              ),

              // Bottom overlay bar
              AnimatedSlide(
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
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _TopBar({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
              tooltip: 'Back',
            ),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
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

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
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
      ),
    );
  }
}
