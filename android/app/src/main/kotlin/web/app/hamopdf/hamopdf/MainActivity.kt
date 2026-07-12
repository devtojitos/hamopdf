package web.app.hamopdf.hamopdf

import android.content.Intent
import android.net.Uri
import android.os.Bundle
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
}
