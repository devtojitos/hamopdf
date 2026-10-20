import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/pdf_document.dart';
import '../home/home_controller.dart';

/// App-bar action that sends the open document to another app through the
/// system share sheet (WhatsApp, mail, Drive, Nearby Share, …).
///
/// Renders nothing on platforms that cannot share files.
class ShareButton extends StatefulWidget {
  final PdfDocument document;

  /// Icon colour, for readers that draw their own bar.
  final Color? color;

  const ShareButton({super.key, required this.document, this.color});

  @override
  State<ShareButton> createState() => _ShareButtonState();
}

class _ShareButtonState extends State<ShareButton> {
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    final messenger = ScaffoldMessenger.of(context);
    final controller = context.read<HomeController>();

    // iPad and macOS anchor the share popover to the button.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

    String? error;
    try {
      await controller.shareDocument(widget.document.path, origin: origin);
    } catch (e) {
      error = e.toString();
    }

    if (!mounted) return;
    setState(() => _sharing = false);

    if (error != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(error),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!context.read<HomeController>().canShareDocuments) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: Icon(Icons.share_outlined, color: widget.color),
      tooltip: 'Share',
      // Disabled while the sheet is opening so a double tap cannot stack two.
      onPressed: _sharing ? null : _share,
    );
  }
}
