package com.personalstorage.personalstorage

import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hosts the Flutter UI and bridges the Android *share sheet* to Dart.
 *
 * Deep links (`personalstorage:///capture`, `///voice`) need no code here: the Flutter embedding
 * forwards them to the Navigator as routes. Shared text / photos arrive as `ACTION_SEND` intents;
 * they are converted to plain data (text + app-private file paths) and handed to Dart through the
 * `app.personalstorage/launch` channel, either on demand (`getInitialShare`, cold start) or pushed
 * (`onShare`, app already running).
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingShare: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingShare = extractShare(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialShare" -> {
                        result.success(pendingShare)
                        pendingShare = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractShare(intent)?.let { channel?.invokeMethod("onShare", it) }
    }

    /** Text and/or images carried by a SEND / SEND_MULTIPLE intent, or null for other intents. */
    private fun extractShare(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) return null

        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
        val uris = mutableListOf<Uri>()
        if (intent.action == Intent.ACTION_SEND) {
            streamExtra(intent)?.let { uris.add(it) }
        } else {
            streamListExtra(intent)?.let { uris.addAll(it) }
        }
        val images = uris.mapIndexedNotNull { i, uri -> copyToCache(uri, i) }
        val combined = listOfNotNull(subject?.takeIf { it.isNotBlank() && text?.contains(it) != true }, text)
            .joinToString("\n")
            .ifBlank { null }
        if (combined == null && images.isEmpty()) return null
        return mapOf("text" to combined, "images" to images)
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableExtra(Intent.EXTRA_STREAM)

    @Suppress("DEPRECATION")
    private fun streamListExtra(intent: Intent): List<Uri>? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)

    /** Copies a shared content:// image into the app's private cache and returns its path. */
    private fun copyToCache(uri: Uri, index: Int): String? = try {
        val subtype = contentResolver.getType(uri)?.substringAfter('/', "jpeg") ?: "jpeg"
        val ext = subtype.substringBefore('+').filter { it.isLetterOrDigit() }.take(5).ifEmpty { "jpg" }
        val out = File(cacheDir, "shared_${System.currentTimeMillis()}_$index.$ext")
        contentResolver.openInputStream(uri)?.use { input -> out.outputStream().use { input.copyTo(it) } }
        if (out.length() > 0) out.absolutePath else null
    } catch (e: Exception) {
        null
    }

    companion object {
        private const val CHANNEL = "app.personalstorage/launch"
    }
}
