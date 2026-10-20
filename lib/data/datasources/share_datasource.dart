import 'dart:io';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

/// Raised when a document could not be handed to the system share sheet.
///
/// [message] is safe to show to the user as-is.
class ShareException implements Exception {
  final String message;

  const ShareException(this.message);

  @override
  String toString() => message;
}

/// Hands documents to the platform share sheet (WhatsApp, mail, Drive, …).
class ShareDatasource {
  const ShareDatasource();

  /// Prefix the Android side puts on files it copies out of a shared
  /// `content://` stream (see `MainActivity.copyContentToCache`).
  static const _sharedCachePrefix = 'shared_';

  /// share_plus cannot share files on Linux.
  bool get isSupported => !Platform.isLinux;

  /// Opens the share sheet for the file at [path].
  ///
  /// [origin] is the global rect of the button that triggered the share; iPad
  /// and macOS anchor their share popover to it.
  ///
  /// Throws a [ShareException] if the sheet could not be shown.
  Future<void> share(String path, {Rect? origin}) async {
    if (!await File(path).exists()) {
      throw const ShareException('The file no longer exists on this device.');
    }

    var fileName = path.split(Platform.pathSeparator).last;
    if (fileName.startsWith(_sharedCachePrefix)) {
      fileName = fileName.substring(_sharedCachePrefix.length);
    }

    // The result (shared / dismissed) is not reported back: closing the sheet
    // is the user's choice, not an error.
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(path, mimeType: _mimeTypeFor(fileName))],
        fileNameOverrides: [fileName],
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      throw ShareException('Could not share the file: $e');
    }
  }

  String _mimeTypeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
      return 'text/markdown';
    }
    return 'application/octet-stream';
  }
}
