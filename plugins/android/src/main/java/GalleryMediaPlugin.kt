package com.pshand.gallery.media

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.os.Build
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.Permission
import app.tauri.annotation.PermissionCallback
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

private const val FULL = "full"
private const val SELECTED = "selected"
private const val NONE = "none"

@InvokeArg
class PageArgs {
    var offset: Int = 0
    var limit: Int = 100
}

@InvokeArg
class MediaArgs {
    var mediaId: Long = 0
    lateinit var destination: String
}

@InvokeArg
class BackgroundArgs {
    var autoBackup: Boolean = false
    var wifiOnly: Boolean = true
    var backgroundBackup: Boolean = false
    lateinit var databasePath: String
    lateinit var cachePath: String
}

@TauriPlugin(permissions = [
    Permission(strings = [Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED], alias = "modernImages"),
    Permission(strings = [Manifest.permission.READ_MEDIA_IMAGES], alias = "images"),
    Permission(strings = [Manifest.permission.READ_EXTERNAL_STORAGE], alias = "legacyImages")
])
class GalleryMediaPlugin(private val activity: Activity) : Plugin(activity) {
    private val io = Executors.newSingleThreadExecutor()

    @Command
    fun configureBackground(invoke: Invoke) {
        val args = invoke.parseArgs(BackgroundArgs::class.java)
        if (args.autoBackup && access() != FULL) {
            invoke.reject("Allow access to all phone photos before enabling automatic backup")
            return
        }
        try {
            val manager = WorkManager.getInstance(activity.applicationContext)
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(if (args.wifiOnly) NetworkType.UNMETERED else NetworkType.CONNECTED)
                .setRequiresStorageNotLow(true).build()
            activity.getSharedPreferences("gallery-backup", 0).edit()
                .putBoolean("autoBackup", args.autoBackup)
                .putBoolean("wifiOnly", args.wifiOnly)
                .putBoolean("backgroundBackup", args.backgroundBackup)
                .putString("databasePath", args.databasePath)
                .putString("cachePath", args.cachePath).commit()
            if (args.autoBackup && args.backgroundBackup) {
                val periodic = PeriodicWorkRequestBuilder<GalleryBackupWorker>(15, TimeUnit.MINUTES)
                    .setConstraints(constraints).build()
                manager.enqueueUniquePeriodicWork("gallery-phone-backup", ExistingPeriodicWorkPolicy.UPDATE, periodic)
            } else {
                manager.cancelUniqueWork("gallery-phone-backup")
            }
            if (args.autoBackup) {
                val immediate = OneTimeWorkRequestBuilder<GalleryBackupWorker>()
                    .setConstraints(constraints).build()
                manager.enqueueUniqueWork("gallery-phone-backup-now", ExistingWorkPolicy.REPLACE, immediate)
            } else {
                manager.cancelUniqueWork("gallery-phone-backup-now")
            }
            invoke.resolve(JSObject().apply { put("configured", true) })
        } catch (error: Exception) { invoke.reject(error.message ?: "Could not schedule background backup") }
    }

    @Command
    fun runAutoBackup(invoke: Invoke) {
        val preferences = activity.getSharedPreferences("gallery-backup", 0)
        if (preferences.getBoolean("autoBackup", false) && access() == FULL) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(if (preferences.getBoolean("wifiOnly", true)) NetworkType.UNMETERED else NetworkType.CONNECTED)
                .setRequiresStorageNotLow(true).build()
            val request = OneTimeWorkRequestBuilder<GalleryBackupWorker>().setConstraints(constraints).build()
            WorkManager.getInstance(activity.applicationContext)
                .enqueueUniqueWork("gallery-phone-backup-now", ExistingWorkPolicy.KEEP, request)
        }
        invoke.resolve(JSObject().apply { put("configured", true) })
    }

    private fun granted(permission: String): Boolean =
        ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED

    private fun access(): String = when {
        Build.VERSION.SDK_INT < 23 -> FULL
        Build.VERSION.SDK_INT >= 33 && granted(Manifest.permission.READ_MEDIA_IMAGES) -> FULL
        Build.VERSION.SDK_INT >= 34 && granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) -> SELECTED
        Build.VERSION.SDK_INT < 33 && granted(Manifest.permission.READ_EXTERNAL_STORAGE) -> FULL
        else -> NONE
    }

    private fun accessResult(): JSObject = JSObject().apply { put("access", access()) }

    @Command
    fun checkAccess(invoke: Invoke) = invoke.resolve(accessResult())

    @Command
    fun requestAccess(invoke: Invoke) {
        if (access() == FULL) { invoke.resolve(accessResult()); return }
        val alias = when {
            Build.VERSION.SDK_INT >= 34 -> "modernImages"
            Build.VERSION.SDK_INT >= 33 -> "images"
            else -> "legacyImages"
        }
        requestPermissionForAlias(alias, invoke, "accessCallback")
    }

    @PermissionCallback
    private fun accessCallback(invoke: Invoke) = invoke.resolve(accessResult())

    @Command
    fun listMedia(invoke: Invoke) {
        val args = invoke.parseArgs(PageArgs::class.java)
        if (access() == NONE) { invoke.reject("Photo access is not granted"); return }
        if (args.offset < 0 || args.limit !in 1..200) { invoke.reject("Invalid media page"); return }
        io.execute {
            try {
                val records = org.json.JSONArray()
                var total = 0
                val columns = arrayOf(
                    MediaStore.Images.Media._ID, MediaStore.Images.Media.DISPLAY_NAME,
                    MediaStore.Images.Media.DATE_TAKEN, MediaStore.Images.Media.DATE_ADDED,
                    MediaStore.Images.Media.MIME_TYPE, MediaStore.Images.Media.SIZE,
                    MediaStore.Images.Media.BUCKET_DISPLAY_NAME) +
                    if (Build.VERSION.SDK_INT >= 29) arrayOf(MediaStore.Images.Media.RELATIVE_PATH) else emptyArray()
                val order = "${MediaStore.Images.Media.DATE_TAKEN} DESC, ${MediaStore.Images.Media._ID} DESC"
                var nextOffset = args.offset
                activity.contentResolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, columns,
                    null, null, order)?.use { cursor ->
                    total = cursor.count
                    if (cursor.moveToPosition(args.offset)) {
                        do {
                            nextOffset = cursor.position + 1
                            val mime = cursor.getString(4) ?: ""
                            if (mime !in setOf("image/jpeg", "image/png", "image/webp", "image/gif")) continue
                            val row = JSObject()
                            row.put("mediaId", cursor.getLong(0))
                            row.put("filename", cursor.getString(1) ?: "Photo")
                            val taken = cursor.getLong(2).takeIf { it > 0 } ?: cursor.getLong(3) * 1000
                            row.put("takenAtMillis", taken)
                            row.put("mimeType", mime)
                            row.put("bytes", cursor.getLong(5))
                            row.put("folder", if (Build.VERSION.SDK_INT >= 29) cursor.getString(7) ?: cursor.getString(6) ?: "Other"
                                else cursor.getString(6) ?: "Other")
                            records.put(row)
                        } while (records.length() < args.limit && cursor.moveToNext())
                    }
                }
                invoke.resolve(JSObject().apply {
                    put("items", records)
                    put("offset", args.offset)
                    put("count", records.length())
                    put("nextOffset", nextOffset)
                    put("total", total)
                })
            } catch (error: Exception) { invoke.reject(error.message ?: "Could not read phone photos") }
        }
    }

    private fun uri(mediaId: Long) = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, mediaId)

    private fun digest(mediaId: Long): String {
        val digest = MessageDigest.getInstance("SHA-256")
        activity.contentResolver.openInputStream(uri(mediaId)).use { input ->
            requireNotNull(input) { "Photo is no longer available" }
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

    @Command
    fun hashOriginal(invoke: Invoke) {
        val args = invoke.parseArgs(MediaArgs::class.java)
        if (access() == NONE) { invoke.reject("Photo access is not granted"); return }
        io.execute {
            try { invoke.resolve(JSObject().apply { put("sha256", digest(args.mediaId)) }) }
            catch (error: Exception) { invoke.reject(error.message ?: "Could not read phone photo") }
        }
    }

    @Command
    fun copyOriginal(invoke: Invoke) {
        val args = invoke.parseArgs(MediaArgs::class.java)
        if (access() == NONE) { invoke.reject("Photo access is not granted"); return }
        io.execute {
            val target = File(args.destination)
            val partial = File(target.parentFile, target.name + ".partial")
            try {
                target.parentFile?.mkdirs()
                val digest = MessageDigest.getInstance("SHA-256")
                activity.contentResolver.openInputStream(uri(args.mediaId)).use { input ->
                    requireNotNull(input) { "Photo is no longer available" }
                    partial.outputStream().use { output ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            digest.update(buffer, 0, count)
                            output.write(buffer, 0, count)
                        }
                    }
                }
                if (!partial.renameTo(target)) throw IllegalStateException("Could not save phone photo")
                invoke.resolve(JSObject().apply {
                    put("path", target.absolutePath)
                    put("sha256", digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) })
                })
            } catch (error: Exception) {
                partial.delete()
                invoke.reject(error.message ?: "Could not read phone photo")
            }
        }
    }

    private fun encodePreview(mediaId: Long, destination: String, maxLength: Int): String {
        val target = File(destination)
        val partial = File(target.parentFile, target.name + ".partial")
        target.parentFile?.mkdirs()
        try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            activity.contentResolver.openInputStream(uri(mediaId)).use { input ->
                requireNotNull(input) { "Photo is no longer available" }
                BitmapFactory.decodeStream(input, null, bounds)
            }
            require(bounds.outWidth > 0 && bounds.outHeight > 0) { "Could not decode photo" }
            var sample = 1
            while (maxOf(bounds.outWidth, bounds.outHeight) / sample > maxLength * 2) sample *= 2
            val options = BitmapFactory.Options().apply { inSampleSize = sample }
            val decoded = activity.contentResolver.openInputStream(uri(mediaId)).use { input ->
                requireNotNull(input) { "Photo is no longer available" }
                BitmapFactory.decodeStream(input, null, options) ?: error("Could not decode photo")
            }
            val scale = minOf(1.0, maxLength.toDouble() / maxOf(decoded.width, decoded.height))
            val scaled = if (scale < 1.0) android.graphics.Bitmap.createScaledBitmap(decoded,
                maxOf(1, (decoded.width * scale).toInt()), maxOf(1, (decoded.height * scale).toInt()), true)
                else decoded
            val orientation = try {
                activity.contentResolver.openInputStream(uri(mediaId)).use { input ->
                    requireNotNull(input)
                    ExifInterface(input).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
                }
            } catch (_: Exception) { ExifInterface.ORIENTATION_NORMAL }
            val matrix = Matrix()
            when (orientation) {
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.setRotate(90f); matrix.postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
                ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.setRotate(270f); matrix.postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(270f)
            }
            val bitmap = if (matrix.isIdentity) scaled else android.graphics.Bitmap.createBitmap(
                scaled, 0, 0, scaled.width, scaled.height, matrix, true)
            partial.outputStream().use { output ->
                if (!bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 80, output)) error("Could not encode photo preview")
            }
            if (bitmap !== scaled) scaled.recycle()
            if (scaled !== decoded) decoded.recycle()
            bitmap.recycle()
            if (!partial.renameTo(target)) error("Could not save photo preview")
            return target.absolutePath
        } catch (error: Exception) {
            partial.delete()
            throw error
        }
    }

    @Command
    fun makeThumbnail(invoke: Invoke) {
        val args = invoke.parseArgs(MediaArgs::class.java)
        if (access() == NONE) { invoke.reject("Photo access is not granted"); return }
        io.execute {
            try {
                invoke.resolve(JSObject().apply { put("path", encodePreview(args.mediaId, args.destination, 640)) })
            } catch (error: Exception) { invoke.reject(error.message ?: "Could not make thumbnail") }
        }
    }

    @Command
    fun makePreview(invoke: Invoke) {
        val args = invoke.parseArgs(MediaArgs::class.java)
        if (access() == NONE) { invoke.reject("Photo access is not granted"); return }
        io.execute {
            try {
                invoke.resolve(JSObject().apply { put("path", encodePreview(args.mediaId, args.destination, 1920)) })
            } catch (error: Exception) { invoke.reject(error.message ?: "Could not make preview") }
        }
    }
}
