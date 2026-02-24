package web.app.hamopdf.hamopdf

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "web.app.hamopdf/intent"
    }

    private var channel: MethodChannel? = null

    /** Holds a file path received before Flutter is ready (cold start). */
    private var pendingFilePath: String? = null

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
                        val sourcePath = call.argument<String>("sourcePath")
                        val fileName = call.argument<String>("fileName")
                        if (sourcePath != null && fileName != null) {
                            result.success(saveToDownloads(sourcePath, fileName))
                        } else {
                            result.error("INVALID_ARGS", "sourcePath and fileName are required", null)
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

    private fun resolveFilePath(intent: Intent): String? {
        if (intent.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        return when (uri.scheme) {
            "file" -> uri.path
            "content" -> copyContentToCache(uri)
            else -> null
        }
    }

    /**
     * Copies a content:// URI (used by WhatsApp and most modern apps) into
     * the app's cache directory so Flutter can open it as a plain file path.
     */
    private fun copyContentToCache(uri: Uri): String? {
        return try {
            val fileName = queryDisplayName(uri) ?: "document.pdf"
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

    private fun saveToDownloads(sourcePath: String, fileName: String): Boolean {
        return try {
            val source = File(sourcePath)
            if (!source.exists()) return false

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+ — no storage permission needed
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                    put(MediaStore.Downloads.MIME_TYPE, "application/pdf")
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
                ) ?: return false
                contentResolver.openOutputStream(uri)?.use { output ->
                    source.inputStream().use { input -> input.copyTo(output) }
                }
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
                true
            } else {
                // Android 9 and below — write directly to Downloads directory
                val downloadsDir = Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS
                )
                downloadsDir.mkdirs()
                source.copyTo(File(downloadsDir, fileName), overwrite = true)
                true
            }
        } catch (e: Exception) {
            false
        }
    }
}
