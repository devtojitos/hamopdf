import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/pdf_document.dart';
import '../home/home_controller.dart';

/// Renders a `.docx` document as scrollable plain text.
///
/// Flutter has no native DOCX renderer, so the document's text is extracted
/// and displayed in a clean reading view. Images and complex formatting are
/// not preserved.
class DocxReaderPage extends StatefulWidget {
  final PdfDocument document;

  const DocxReaderPage({super.key, required this.document});

  @override
  State<DocxReaderPage> createState() => _DocxReaderPageState();
}

class _DocxReaderPageState extends State<DocxReaderPage> {
  late Future<String> _textFuture;
  double _fontSize = 17;

  @override
  void initState() {
    super.initState();
    _textFuture =
        context.read<HomeController>().extractDocxText(widget.document.path);
  }

  void _changeFontSize(double delta) {
    setState(() => _fontSize = (_fontSize + delta).clamp(12.0, 30.0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.document.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.text_decrease),
            tooltip: 'Smaller text',
            onPressed: () => _changeFontSize(-1),
          ),
          IconButton(
            icon: const Icon(Icons.text_increase),
            tooltip: 'Larger text',
            onPressed: () => _changeFontSize(1),
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _textFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(message: snapshot.error.toString());
          }
          final text = (snapshot.data ?? '').trim();
          if (text.isEmpty) {
            return const _ErrorState(
              message: 'This document appears to be empty or contains no '
                  'readable text.',
            );
          }
          return SelectionArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              child: Text(
                text,
                style: TextStyle(fontSize: _fontSize, height: 1.5),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined,
                size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
