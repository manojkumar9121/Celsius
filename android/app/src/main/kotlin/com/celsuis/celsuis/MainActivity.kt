package com.celsuis.celsuis

import android.content.ContentUris
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "com.celsuis.celsuis/audio_scanner"
    private val WIDGET_CHANNEL = "com.celsuis.celsuis/widget"

    companion object {
        @Volatile
        var widgetEngine: FlutterEngine? = null

        fun forwardWidgetAction(action: String) {
            val engine = widgetEngine
            if (engine != null) {
                MethodChannel(engine.dartExecutor.binaryMessenger, "com.celsuis.celsuis/widget")
                    .invokeMethod(action, null)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        widgetEngine = flutterEngine

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getApiLevel" -> {
                    try {
                        result.success(android.os.Build.VERSION.SDK_INT)
                    } catch (e: Exception) {
                        result.error("API_LEVEL_ERROR", e.message, null)
                    }
                }
                "scanMediaStore" -> {
                    try {
                        val files = scanMediaStoreAudio()
                        result.success(files)
                    } catch (e: Exception) {
                        result.error("SCAN_ERROR", e.message, e.stackTraceToString())
                    }
                }
                "extractArtwork" -> {
                    try {
                        val path = call.argument<String>("path")
                        if (path != null) {
                            val artwork = extractArtwork(path)
                            result.success(artwork)
                        } else {
                            result.error("NO_PATH", "No path provided", null)
                        }
                    } catch (e: Exception) {
                        result.error("ARTWORK_ERROR", e.message, e.stackTraceToString())
                    }
                }
                "extractTags" -> {
                    try {
                        val path = call.argument<String>("path")
                        if (path != null) {
                            val tags = extractTags(path)
                            result.success(tags)
                        } else {
                            result.error("NO_PATH", "No path provided", null)
                        }
                    } catch (e: Exception) {
                        result.error("TAGS_ERROR", e.message, e.stackTraceToString())
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidget" -> {
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    val artPath = call.argument<String>("artPath")
                    PlayerWidget.saveWidgetData(this, title, artist, isPlaying, artPath)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        handleWidgetIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleWidgetIntent(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (widgetEngine === flutterEngine) {
            widgetEngine = null
        }
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handleWidgetIntent(intent: Intent?) {
        when (intent?.action) {
            PlayerWidget.ACTION_PREV, PlayerWidget.ACTION_PLAY_PAUSE, PlayerWidget.ACTION_NEXT -> {
                val flutterEngine = flutterEngine ?: return
                MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
                    .invokeMethod(intent.action!!, null)
            }
        }
    }

    private fun scanMediaStoreAudio(): List<Map<String, Any?>> {
        val files = mutableListOf<Map<String, Any?>>()
        val contentResolver = applicationContext.contentResolver
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }

        val projection = mutableListOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.SIZE,
        )

        val isAtLeastR = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
        if (!isAtLeastR) {
            projection.add(MediaStore.Audio.Media.DATA)
        } else {
            projection.add(MediaStore.Audio.Media.RELATIVE_PATH)
            projection.add(MediaStore.Audio.Media.DISPLAY_NAME)
        }

        val selection = "${MediaStore.Audio.Media.IS_MUSIC} = 1"
        val sortOrder = "${MediaStore.Audio.Media.TITLE} ASC"

        try {
            contentResolver.query(collection, projection.toTypedArray(), selection, null, sortOrder)
                ?.use { c ->
                    val idColumn = c.getColumnIndex(MediaStore.Audio.Media._ID)
                    val titleColumn = c.getColumnIndex(MediaStore.Audio.Media.TITLE)
                    val artistColumn = c.getColumnIndex(MediaStore.Audio.Media.ARTIST)
                    val albumColumn = c.getColumnIndex(MediaStore.Audio.Media.ALBUM)
                    val durationColumn = c.getColumnIndex(MediaStore.Audio.Media.DURATION)
                    val sizeColumn = c.getColumnIndex(MediaStore.Audio.Media.SIZE)

                    val dataColumn = if (!isAtLeastR)
                        c.getColumnIndex(MediaStore.Audio.Media.DATA)
                    else -1

                    val relativePathColumn = if (isAtLeastR)
                        c.getColumnIndex(MediaStore.Audio.Media.RELATIVE_PATH)
                    else -1

                    val displayNameColumn = if (isAtLeastR)
                        c.getColumnIndex(MediaStore.Audio.Media.DISPLAY_NAME)
                    else -1

                    while (c.moveToNext()) {
                        val id = if (idColumn >= 0) c.getLong(idColumn) else 0L
                        val title = if (titleColumn >= 0) c.getString(titleColumn) ?: "" else ""
                        val artist = if (artistColumn >= 0) c.getString(artistColumn) ?: "" else ""
                        val album = if (albumColumn >= 0) c.getString(albumColumn) ?: "" else ""
                        val duration = if (durationColumn >= 0) c.getInt(durationColumn) else 0
                        val size = if (sizeColumn >= 0) c.getLong(sizeColumn) else 0L

                        var filePath: String? = null

                        if (!isAtLeastR && dataColumn >= 0) {
                            filePath = c.getString(dataColumn)
                        } else if (isAtLeastR) {
                            val relativePath = if (relativePathColumn >= 0) c.getString(relativePathColumn) ?: "" else ""
                            val displayName = if (displayNameColumn >= 0) c.getString(displayNameColumn) ?: "" else ""
                            if (relativePath.isNotEmpty() && displayName.isNotEmpty()) {
                                filePath = "${Environment.getExternalStorageDirectory()?.absolutePath}/$relativePath/$displayName"
                            }
                        }

                        val contentUri = ContentUris.withAppendedId(
                            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id
                        ).toString()

                        val realPath = if (!isAtLeastR && dataColumn >= 0) {
                            c.getString(dataColumn)
                        } else {
                            val relativePath = if (relativePathColumn >= 0) c.getString(relativePathColumn) ?: "" else ""
                            val displayName = if (displayNameColumn >= 0) c.getString(displayNameColumn) ?: "" else ""
                            if (relativePath.isNotEmpty() && displayName.isNotEmpty()) {
                                "${Environment.getExternalStorageDirectory()?.absolutePath}/$relativePath/$displayName"
                            } else {
                                ""
                            }
                        }

                        if (filePath.isNullOrEmpty()) {
                            filePath = contentUri
                        } else if (isAtLeastR) {
                            filePath = contentUri
                        }

                        val file = mapOf(
                            "id" to id,
                            "path" to filePath,
                            "realPath" to realPath,
                            "title" to title,
                            "artist" to artist,
                            "album" to album,
                            "duration" to (duration / 1000),
                            "size" to size,
                            "uri" to contentUri
                        )
                        files.add(file)
                    }
                }
        } catch (e: Exception) {
            e.printStackTrace()
            throw e
        }
        return files
    }

    private fun extractArtwork(path: String): ByteArray? {
        val uri = Uri.parse(path)
        return try {
            val retriever = android.media.MediaMetadataRetriever()
            retriever.setDataSource(applicationContext, uri)
            val data = retriever.embeddedPicture
            retriever.release()
            data
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun extractTags(path: String): Map<String, Any?>? {
        val uri = Uri.parse(path)
        return try {
            val retriever = android.media.MediaMetadataRetriever()
            retriever.setDataSource(applicationContext, uri)
            val tags = mutableMapOf<String, Any?>()
            tags["title"] = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_TITLE)
            tags["artist"] = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_ARTIST)
            tags["album"] = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_ALBUM)
            tags["duration"] = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
            val artwork = retriever.embeddedPicture
            if (artwork != null) {
                tags["artwork"] = artwork
            }
            retriever.release()
            tags
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }
}
