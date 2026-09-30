package com.personalstorage.personalstorage

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

/**
 * Resizable capture widget with two one-tap buttons: *New note* and *Voice*. Declared for the
 * `home_screen` and `keyguard` categories, so it can live on the lock screen wherever the device
 * supports lock-screen widgets (e.g. Android 14+ tablets).
 */
class CaptureWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_capture).apply {
                setOnClickPendingIntent(R.id.widget_new_note, deepLink(context, "capture", 1))
                setOnClickPendingIntent(R.id.widget_voice, deepLink(context, "voice", 2))
            }
            manager.updateAppWidget(id, views)
        }
    }

    private fun deepLink(context: Context, route: String, requestCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("personalstorage:///$route")).apply {
            setPackage(context.packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        return PendingIntent.getActivity(
            context, requestCode, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
