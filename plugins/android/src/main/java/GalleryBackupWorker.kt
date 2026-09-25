package com.pshand.gallery.media

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import android.os.StatFs
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.io.File
import java.security.MessageDigest

class GalleryBackupWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    init { System.loadLibrary("gallery_lib") }

    private external fun isMediaSynced(databasePath: String, mediaId: Long): Boolean
    private external fun isHashSynced(databasePath: String, hash: String): Boolean
    private external fun recordExistingPhoto(databasePath: String, mediaId: Long, hash: String,
        filename: String, takenAtMillis: Long, mimeType: String, bytes: Long, folder: String): Boolean
    private external fun uploadStagedPhoto(context: Context, databasePath: String, cachePath: String,
        sourcePath: String, filename: String, takenAtMillis: Long, mediaId: Long, mimeType: String, folder: String): Boolean

    private fun hasFullAccess(): Boolean = when {
        Build.VERSION.SDK_INT >= 33 -> ContextCompat.checkSelfPermission(applicationContext,
            Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED
        else -> ContextCompat.checkSelfPermission(applicationContext,
            Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
    }

    private fun photoUri(id: Long) = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)

    private fun hash(id: Long): String {
        val digest = MessageDigest.getInstance("SHA-256")
        applicationContext.contentResolver.openInputStream(photoUri(id)).use { input ->
            requireNotNull(input) { "Photo is no longer available" }
            val buffer = ByteArray(64 * 1024)
            while (true) {
                if (isStopped) error("Backup stopped")
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

    private fun copy(id: Long, destination: File) {
        destination.parentFile?.mkdirs()
        applicationContext.contentResolver.openInputStream(photoUri(id)).use { input ->
            requireNotNull(input) { "Photo is no longer available" }
            destination.outputStream().use { output ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    if (isStopped) error("Backup stopped")
                    val count = input.read(buffer)
                    if (count < 0) break
                    output.write(buffer, 0, count)
                }
            }
        }
    }

    override fun doWork(): Result {
        val preferences = applicationContext.getSharedPreferences("gallery-backup", 0)
        if (!preferences.getBoolean("autoBackup", false)) return Result.success()
        if (!hasFullAccess()) return Result.retry()
        val database = preferences.getString("databasePath", null) ?: return Result.retry()
        val cache = preferences.getString("cachePath", null) ?: return Result.retry()
        val started = SystemClock.elapsedRealtime()
        var completed = 0
        val columns = arrayOf(MediaStore.Images.Media._ID, MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.DATE_TAKEN, MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.MIME_TYPE, MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.BUCKET_DISPLAY_NAME) +
            if (Build.VERSION.SDK_INT >= 29) arrayOf(MediaStore.Images.Media.RELATIVE_PATH) else emptyArray()
        val order = "${MediaStore.Images.Media.DATE_TAKEN} DESC, ${MediaStore.Images.Media._ID} DESC"
        try {
            applicationContext.contentResolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                columns, null, null, order)?.use { cursor ->
                while (cursor.moveToNext()) {
                    if (isStopped || SystemClock.elapsedRealtime() - started > 8 * 60 * 1000) return Result.retry()
                    val id = cursor.getLong(0)
                    val filename = cursor.getString(1) ?: "Photo.jpg"
                    val taken = cursor.getLong(2).takeIf { it > 0 } ?: cursor.getLong(3) * 1000
                    val mime = cursor.getString(4) ?: continue
                    val bytes = cursor.getLong(5)
                    val folder = if (Build.VERSION.SDK_INT >= 29) cursor.getString(7) ?: cursor.getString(6) ?: "Other"
                        else cursor.getString(6) ?: "Other"
                    if (mime !in setOf("image/jpeg", "image/png", "image/webp", "image/gif") || bytes <= 0) continue
                    if (isMediaSynced(database, id)) continue
                    val hash = hash(id)
                    if (isHashSynced(database, hash)) {
                        if (!recordExistingPhoto(database, id, hash, filename, taken, mime, bytes, folder)) return Result.retry()
                        continue
                    }
                    val available = StatFs(applicationContext.cacheDir.path).availableBytes
                    if (available < bytes + 64L * 1024 * 1024) return Result.retry()
                    val staged = File(applicationContext.cacheDir, "phone-media/work/$id-${System.currentTimeMillis()}.original")
                    try {
                        copy(id, staged)
                        if (!uploadStagedPhoto(applicationContext, database, cache, staged.absolutePath,
                            filename, taken, id, mime, folder)) return Result.retry()
                    } finally { staged.delete() }
                    completed++
                    if (completed >= 10) break
                }
            }
            return Result.success()
        } catch (_: SecurityException) { return Result.retry() }
          catch (_: Exception) { return Result.retry() }
    }
}
