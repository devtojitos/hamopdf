import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// Raised when a document could not be saved to the device.
///
/// [message] is safe to show to the user as-is.
class DownloadException implements Exception {
  final String message;

  const DownloadException(this.message);

  @override
  String toString() => message;
}

/// Copies documents out of the app's private storage into a location the user
/// can browse.
///
/// Files opened from WhatsApp, mail or any other app arrive as a `content://`
/// stream that the native side buffers into the cache directory — they are not
/// really "on the phone" and Android may clear them at any time. Downloading
/// makes a durable copy.
class DownloadDatasource {
  static const _channel = MethodChannel('web.app.hamopdf/intent');

  const DownloadDatasource();

  /// Saves the file at [path] where the user can find it again.
  ///
  /// On Android the copy goes straight into the public Downloads folder and the
  /// returned string is its location (`Download/report.pdf`). On desktop the
  /// user picks the destination; null means they cancelled.
  ///
  /// Throws a [DownloadException] if the copy fails.
  Future<String?> saveToDownloads(String path) async {
    if (!await File(path).exists()) {
      throw const DownloadException('The file no longer exists on this device.');
    }

    if (Platform.isAndroid) {
      return _saveViaPlatformChannel(path);
    }
    return _saveViaFilePicker(path);
  }

  Future<String?> _saveViaPlatformChannel(String path) async {
    try {
      return await _channel.invokeMethod<String>(
        'saveToDownloads',
        {'path': path},
      );
    } on PlatformException catch (e) {
      throw DownloadException(switch (e.code) {
        'permission_denied' =>
          'Storage permission is needed to save the file. You can grant it in '
              'Settings > Apps > HamoPDF > Permissions.',
        'not_found' => 'The file no longer exists on this device.',
        _ => e.message ?? 'Could not save the file.',
      });
    } on MissingPluginException {
      throw const DownloadException('Saving is not supported on this device.');
    }
  }

  /// Desktop fallback: ask for a destination, then write the bytes there.
  Future<String?> _saveViaFilePicker(String path) async {
    final fileName = path.split(Platform.pathSeparator).last;
    try {
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save document',
        fileName: fileName,
      );
      if (destination == null) return null;

      await File(path).copy(destination);
      return destination;
    } on DownloadException {
      rethrow;
    } catch (e) {
      throw DownloadException('Could not save the file: $e');
    }
  }
}
