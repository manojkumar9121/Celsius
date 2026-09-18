package com.celsius.celsius

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.RemoteViews
import java.io.File

class PlayerWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_UPDATE_WIDGET -> {
                val appWidgetManager = AppWidgetManager.getInstance(context)
                val ids = appWidgetManager.getAppWidgetIds(
                    android.content.ComponentName(context, PlayerWidget::class.java)
                )
                for (appWidgetId in ids) {
                    updateAppWidget(context, appWidgetManager, appWidgetId)
                }
            }
            ACTION_PREV, ACTION_PLAY_PAUSE, ACTION_NEXT -> {
                val action = intent.action ?: return
                MainActivity.forwardWidgetAction(action)
            }
        }
    }

    companion object {
        const val ACTION_UPDATE_WIDGET = "com.celsius.celsius.ACTION_UPDATE_WIDGET"
        const val ACTION_PREV = "com.celsius.celsius.ACTION_PREV"
        const val ACTION_PLAY_PAUSE = "com.celsius.celsius.ACTION_PLAY_PAUSE"
        const val ACTION_NEXT = "com.celsius.celsius.ACTION_NEXT"
        const val PREFS_NAME = "celsius_widget"
        const val KEY_TITLE = "widget_title"
        const val KEY_ARTIST = "widget_artist"
        const val KEY_IS_PLAYING = "widget_is_playing"
        const val KEY_ART_PATH = "widget_art_path"

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val title = prefs.getString(KEY_TITLE, "No song playing") ?: "No song playing"
            val artist = prefs.getString(KEY_ARTIST, "") ?: ""
            val isPlaying = prefs.getBoolean(KEY_IS_PLAYING, false)
            val artPath = prefs.getString(KEY_ART_PATH, null)

            val views = RemoteViews(context.packageName, R.layout.widget_player)

            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_artist, artist)

            if (isPlaying) {
                views.setImageViewResource(R.id.widget_play_pause, android.R.drawable.ic_media_pause)
            } else {
                views.setImageViewResource(R.id.widget_play_pause, android.R.drawable.ic_media_play)
            }

            if (artPath != null && File(artPath).exists()) {
                try {
                    val bitmap = BitmapFactory.decodeFile(artPath)
                    if (bitmap != null) {
                        views.setImageViewBitmap(R.id.widget_album_art, bitmap)
                    }
                } catch (_: Exception) {
                    views.setImageViewResource(R.id.widget_album_art, R.mipmap.ic_launcher)
                }
            } else {
                views.setImageViewResource(R.id.widget_album_art, R.mipmap.ic_launcher)
            }

            // Launch app on widget tap
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val launchPendingIntent = PendingIntent.getActivity(
                context, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_title, launchPendingIntent)
            views.setOnClickPendingIntent(R.id.widget_artist, launchPendingIntent)
            views.setOnClickPendingIntent(R.id.widget_album_art, launchPendingIntent)

            // Button actions
            val prevIntent = Intent(context, PlayerWidget::class.java).apply {
                action = ACTION_PREV
            }
            views.setOnClickPendingIntent(R.id.widget_prev, PendingIntent.getBroadcast(
                context, 1, prevIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            ))

            val playPauseIntent = Intent(context, PlayerWidget::class.java).apply {
                action = ACTION_PLAY_PAUSE
            }
            views.setOnClickPendingIntent(R.id.widget_play_pause, PendingIntent.getBroadcast(
                context, 2, playPauseIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            ))

            val nextIntent = Intent(context, PlayerWidget::class.java).apply {
                action = ACTION_NEXT
            }
            views.setOnClickPendingIntent(R.id.widget_next, PendingIntent.getBroadcast(
                context, 3, nextIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            ))

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        fun saveWidgetData(context: Context, title: String, artist: String, isPlaying: Boolean, artPath: String?) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().apply {
                putString(KEY_TITLE, title)
                putString(KEY_ARTIST, artist)
                putBoolean(KEY_IS_PLAYING, isPlaying)
                putString(KEY_ART_PATH, artPath)
                apply()
            }
            // Trigger widget update
            val intent = Intent(context, PlayerWidget::class.java).apply {
                action = ACTION_UPDATE_WIDGET
            }
            context.sendBroadcast(intent)
        }
    }
}
