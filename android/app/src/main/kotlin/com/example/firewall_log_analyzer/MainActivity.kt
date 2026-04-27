package com.example.firewall_log_analyzer

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.io.OutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.firewall_log_analyzer/export"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "saveToDownloads") {
                val fileName = call.argument<String>("fileName")
                val bytes = call.argument<ByteArray>("bytes")
                val mimeType = call.argument<String>("mimeType")

                if (fileName != null && bytes != null && mimeType != null) {
                    val path = saveToDownloads(fileName, bytes, mimeType)
                    if (path != null) {
                        result.success(path)
                    } else {
                        result.error("EXPORT_FAILED", "Failed to save to downloads folder", null)
                    }
                } else {
                    result.error("INVALID_ARGUMENTS", "Missing fileName, bytes, or mimeType", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun saveToDownloads(fileName: String, bytes: ByteArray, mimeType: String): String? {
        val resolver = contentResolver
        
        // Use MediaStore for Android 10 (API 29) and above
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val contentValues = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }

            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
            if (uri != null) {
                try {
                    resolver.openOutputStream(uri)?.use { outputStream ->
                        outputStream.write(bytes)
                        outputStream.flush()
                        // Return the user-friendly path
                        return "Downloads/$fileName"
                    }
                } catch (e: IOException) {
                    e.printStackTrace()
                }
            }
        } else {
            // Fallback for older Android versions
            try {
                val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                if (!downloadsDir.exists()) {
                    downloadsDir.mkdirs()
                }
                val file = File(downloadsDir, fileName)
                file.writeBytes(bytes)
                return file.absolutePath
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        return null
    }
}
