package web.app.hamopdf.hamopdf

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "web.app.hamopdf/intent"
        private const val STORAGE_PERMISSION_CODE = 4711
    }

    private var channel: MethodChannel? = null

    /** Holds a file path received before Flutter is ready (cold start). */
    private var pendingFilePath: String? = null

    /** Download request parked while the storage permission dialog is up (API < 29). */
    private var pendingDownload: Pair<String, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialFile" -> {
                        result.success(pendingFilePath)
                        pendingFilePath = null
                    }
                    "saveToDownloads" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("bad_args", "Missing source path", null)
                        } else {
                            requestDownload(path, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Store the path; Flutter may not be ready yet so we buffer it.
        pendingFilePath = resolveFilePath(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val path = resolveFilePath(intent) ?: return
        // App is already running — invoke Flutter directly.
        channel?.invokeMethod("onNewFile", path)
    }

    // -------------------------------------------------------------------------
    // Opening shared files
    // -------------------------------------------------------------------------

    private fun resolveFilePath(intent: Intent): String? {
        if (intent.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        return when (uri.scheme) {
            "file" -> uri.path
            "content" -> copyContentToCache(uri, intent.type)
            else -> null
        }
    }

    /**
     * Copies a content:// URI (used by WhatsApp and most modern apps) into
     * the app's cache directory so Flutter can open it as a plain file path.
     *
     * The cached file name keeps the original extension (or one derived from
     * [mimeType]) so Flutter can route to the correct reader by type.
     */
    private fun copyContentToCache(uri: Uri, mimeType: String?): String? {
        return try {
            val fileName = queryDisplayName(uri) ?: "document${extensionFor(mimeType)}"
            val dest = File(cacheDir, "shared_$fileName")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(dest).use { output ->
                    input.copyTo(output)
                }
            }
            dest.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    /** Picks a file extension for the fallback name based on the shared MIME type. */
    private fun extensionFor(mimeType: String?): String = when (mimeType) {
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document" -> ".docx"
        "text/markdown", "text/x-markdown" -> ".md"
        else -> ".pdf"
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (e: Exception) {
            uri.lastPathSegment
        }
    }

    // -------------------------------------------------------------------------
    // Saving to the public Downloads folder
    // -------------------------------------------------------------------------

    /**
     * Copies [sourcePath] into the device's public Downloads folder.
     *
     * On API 29+ this goes through MediaStore and needs no permission. Below
     * that we write the file directly, which requires WRITE_EXTERNAL_STORAGE,
     * so the permission is requested first and the call resumed in
     * [onRequestPermissionsResult].
     */
    private fun requestDownload(sourcePath: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(sourcePath, result)
            return
        }

        val granted = ContextCompat.checkSelfPermission(
            this, Manifest.permission.WRITE_EXTERNAL_STORAGE
        ) == PackageManager.PERMISSION_GRANTED

        if (granted) {
            saveToLegacyDownloads(sourcePath, result)
        } else if (pendingDownload != null) {
            result.error("busy", "Another download is already in progress", null)
        } else {
            pendingDownload = sourcePath to result
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                STORAGE_PERMISSION_CODE
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != STORAGE_PERMISSION_CODE) return

        val (path, result) = pendingDownload ?: return
        pendingDownload = null

        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            saveToLegacyDownloads(path, result)
        } else {
            result.error(
                "permission_denied",
                "Storage permission is required to save the file",
                null
            )
        }
    }

    private fun saveViaMediaStore(sourcePath: String, result: MethodChannel.Result) {
        val source = File(sourcePath)
        if (!source.exists()) {
            result.error("not_found", "The file no longer exists", null)
            return
        }

        var uri: Uri? = null
        try {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, source.name)
                put(MediaStore.Downloads.MIME_TYPE, mimeTypeFor(source.name))
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                // Hide the entry from other apps until the copy has finished.
                put(MediaStore.Downloads.IS_PENDING, 1)
            }

            val resolver = contentResolver
            uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: run {
                    result.error("insert_failed", "Could not create the download entry", null)
                    return
                }

            resolver.openOutputStream(uri)?.use { output ->
                source.inputStream().use { input -> input.copyTo(output) }
            } ?: throw IllegalStateException("Could not open the destination file")

            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)

            result.success("${Environment.DIRECTORY_DOWNLOADS}/${source.name}")
        } catch (e: Exception) {
            // Roll back the half-written entry so no broken file is left behind.
            uri?.let { runCatching { contentResolver.delete(it, null, null) } }
            result.error("save_failed", e.message ?: "Could not save the file", null)
        }
    }

    private fun saveToLegacyDownloads(sourcePath: String, result: MethodChannel.Result) {
        try {
            val source = File(sourcePath)
            if (!source.exists()) {
                result.error("not_found", "The file no longer exists", null)
                return
            }

            val dir = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS
            )
            if (!dir.exists()) dir.mkdirs()

            val dest = uniqueFile(dir, source.name)
            source.inputStream().use { input ->
                FileOutputStream(dest).use { output -> input.copyTo(output) }
            }

            result.success("${Environment.DIRECTORY_DOWNLOADS}/${dest.name}")
        } catch (e: Exception) {
            result.error("save_failed", e.message ?: "Could not save the file", null)
        }
    }

    /** Returns [name] in [dir], suffixed with `(1)`, `(2)`… if already taken. */
    private fun uniqueFile(dir: File, name: String): File {
        var candidate = File(dir, name)
        if (!candidate.exists()) return candidate

        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""

        var n = 1
        while (candidate.exists() && n < 1000) {
            candidate = File(dir, "$stem ($n)$ext")
            n++
        }
        return candidate
    }

    private fun mimeTypeFor(name: String): String = when {
        name.endsWith(".pdf", true) -> "application/pdf"
        name.endsWith(".docx", true) ->
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        name.endsWith(".md", true) || name.endsWith(".markdown", true) -> "text/markdown"
        else -> "application/octet-stream"
    }
}
