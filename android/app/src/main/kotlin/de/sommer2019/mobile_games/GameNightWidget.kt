package de.sommer2019.mobile_games

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/**
 * "Spieleabend": unread messages, friend requests, friends online and quick
 * start buttons for the last played games. The app pushes the data
 * (lib/core/home_widgets.dart).
 */
class GameNightWidget : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    for (id in appWidgetIds) {
      appWidgetManager.updateAppWidget(id, build(context, widgetData))
    }
  }

  private fun number(data: SharedPreferences, key: String): Long =
      (data.all[key] as? Number)?.toLong() ?: 0L

  private fun link(context: Context, uri: String) =
      HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(uri))

  private fun build(context: Context, data: SharedPreferences): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.widget_game_night)
    views.setTextViewText(R.id.gn_unread, "💬 ${number(data, "unread")}")
    views.setTextViewText(R.id.gn_requests, "👋 ${number(data, "requests")}")
    val onlineCount = number(data, "onlineCount")
    val names = data.getString("online", "") ?: ""
    views.setTextViewText(
        R.id.gn_online,
        if (onlineCount == 0L) "Gerade ist kein Freund online"
        else "🟢 $onlineCount online: $names")
    views.setOnClickPendingIntent(R.id.gn_root, link(context, "mobilegames://home?homeWidget"))

    val buttons = intArrayOf(R.id.gn_game1, R.id.gn_game2, R.id.gn_game3)
    val recent =
        try {
          JSONArray(data.getString("recent", "[]") ?: "[]")
        } catch (_: Exception) {
          JSONArray()
        }
    for (i in buttons.indices) {
      if (i < recent.length()) {
        val game = recent.getJSONObject(i)
        views.setViewVisibility(buttons[i], View.VISIBLE)
        views.setTextViewText(buttons[i], "▶ " + game.optString("title"))
        views.setOnClickPendingIntent(
            buttons[i], link(context, "mobilegames://game/${game.optString("id")}?homeWidget"))
      } else if (i == 0) {
        views.setViewVisibility(buttons[i], View.VISIBLE)
        views.setTextViewText(buttons[i], "Spiel starten")
      } else {
        views.setViewVisibility(buttons[i], View.GONE)
      }
    }
    return views
  }
}
