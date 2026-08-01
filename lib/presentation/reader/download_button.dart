import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/pdf_document.dart';
import '../home/home_controller.dart';

/// App-bar action that saves a durable copy of the open document.
///
/// Documents opened from WhatsApp, mail or any other app live in the app's
/// cache and can be cleared by the system at any time — this puts a real copy
/// in the phone's Downloads folder.
class DownloadButton extends StatefulWidget {
  final PdfDocument document;

  /// Icon colour, for readers that draw their own bar over a dark background.
  final Color? color;

  const DownloadButton({super.key, required this.document, this.color});

  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> {
  bool _saving = false;
  bool _saved = false;

  Future<void> _download() async {
    if (_saving) return;
    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.of(context);
    final controller = context.read<HomeController>();

    String? location;
    String? error;
    try {
      location = await controller.downloadDocument(widget.document.path);
    } catch (e) {
      error = e.toString();
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = error == null && location != null;
    });

    messenger.hideCurrentSnackBar();
    if (error != null) {
      messenger.showSnackBar(SnackBar(
        content: Text(error),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ));
    } else if (location != null) {
      messenger.showSnackBar(SnackBar(
        content: Text('Saved to $location'),
        behavior: SnackBarBehavior.floating,
      ));
    }
    // A null location without an error means the user cancelled — say nothing.
  }

  @override
  Widget build(BuildContext context) {
    if (_saving) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.color,
            ),
          ),
        ),
      );
    }

    return IconButton(
      icon: Icon(
        _saved ? Icons.download_done : Icons.download_outlined,
        color: widget.color,
      ),
      tooltip: _saved ? 'Saved to device' : 'Save to device',
      onPressed: _download,
    );
  }
}
