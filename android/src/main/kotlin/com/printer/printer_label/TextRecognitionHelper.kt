package com.printer.printer_label

import android.content.Context
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.io.File

/**
 * Nhận chữ trong ảnh bằng ML Kit (chạy trên máy, không gửi ảnh đi) — VD đọc IP /
 * gateway trên tờ self-test của máy in. Kết quả gọi trên luồng chính.
 */
object TextRecognitionHelper {
    fun recognize(ctx: Context, path: String, done: (String?) -> Unit) {
        val image = try {
            InputImage.fromFilePath(ctx, Uri.fromFile(File(path)))
        } catch (_: Throwable) {
            done(null)
            return
        }
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        recognizer.process(image)
            .addOnSuccessListener { done(it.text) }
            .addOnFailureListener { done(null) }
            .addOnCompleteListener { recognizer.close() }
    }
}
