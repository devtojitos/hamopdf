import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/pdf_document.dart';
import '../reader/reader_page.dart';
import 'home_controller.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HamoPDF'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_outlined),
            tooltip: 'Open PDF',
            onPressed: () => _pickAndOpen(context),
          ),
        ],
      ),
      body: Consumer<HomeController>(
        builder: (context, ctrl, _) {
          if (ctrl.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (ctrl.error != null) {
            return _ErrorState(
              message: ctrl.error!,
              onRetry: ctrl.loadRecents,
            );
          }
          if (ctrl.recents.isEmpty) {
            return _EmptyState(onOpen: () => _pickAndOpen(context));
          }
          return _RecentsList(
            recents: ctrl.recents,
            onOpen: (doc) => _openDocument(context, doc),
            onRemove: (doc) => _confirmRemove(context, ctrl, doc),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pickAndOpen(context),
        icon: const Icon(Icons.add),
        label: const Text('Open PDF'),
      ),
    );
  }

  Future<void> _pickAndOpen(BuildContext context) async {
    final ctrl = context.read<HomeController>();
    final doc = await ctrl.openFilePicker();
    if (doc != null && context.mounted) {
      _openDocument(context, doc);
    }
  }

  void _openDocument(BuildContext context, PdfDocument doc) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReaderPage(document: doc)),
    ).then((_) {
      if (context.mounted) context.read<HomeController>().loadRecents();
    });
  }

  Future<void> _confirmRemove(
      BuildContext context, HomeController ctrl, PdfDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from recents?'),
        content: Text(doc.name),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true) ctrl.remove(doc.path);
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final VoidCallback onOpen;
  const _EmptyState({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf_outlined,
                size: 80, color: cs.primary.withAlpha(100)),
            const SizedBox(height: 20),
            Text('No PDFs yet',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Tap the button below to browse and open a PDF file.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.outline),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open PDF'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recents list
// ---------------------------------------------------------------------------

class _RecentsList extends StatelessWidget {
  final List<PdfDocument> recents;
  final void Function(PdfDocument) onOpen;
  final void Function(PdfDocument) onRemove;

  const _RecentsList({
    required this.recents,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: recents.length,
      itemBuilder: (_, i) => _PdfCard(
        doc: recents[i],
        onOpen: onOpen,
        onRemove: onRemove,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PDF card
// ---------------------------------------------------------------------------

class _PdfCard extends StatelessWidget {
  final PdfDocument doc;
  final void Function(PdfDocument) onOpen;
  final void Function(PdfDocument) onRemove;

  const _PdfCard(
      {required this.doc, required this.onOpen, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onOpen(doc),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.picture_as_pdf,
                    color: cs.onPrimaryContainer, size: 26),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    if (doc.totalPages > 0) ...[
                      LinearProgressIndicator(
                        value: doc.progress,
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Page ${doc.lastPage + 1} of ${doc.totalPages}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.outline),
                      ),
                    ] else
                      Text(
                        _relativeDate(doc.lastOpened),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.outline),
                      ),
                  ],
                ),
              ),
              // Remove button
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => onRemove(doc),
                tooltip: 'Remove',
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
