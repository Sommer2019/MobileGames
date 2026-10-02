package de.sommer2019.mobile_games

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import kotlin.random.Random

/**
 * Dice on the home screen: 1–6 dice, tap to roll. Works without starting the
 * app; the 📳 button opens the dice cup in the app (shaking works there).
 */
class DiceWidget : AppWidgetProvider() {

  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    for (id in ids) render(context, manager, id)
  }

  override fun onDeleted(context: Context, ids: IntArray) {
    val edit = prefs(context).edit()
    for (id in ids) {
      edit.remove("count_$id")
      edit.remove("rolled_$id")
      for (i in 0 until MAX) edit.remove("v${i}_$id")
    }
    edit.apply()
  }

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
    if (id == -1) return
    val manager = AppWidgetManager.getInstance(context)
    val p = prefs(context)
    when (intent.action) {
      ACTION_PLUS, ACTION_MINUS -> {
        val delta = if (intent.action == ACTION_PLUS) 1 else -1
        val count = (count(context, id) + delta).coerceIn(1, MAX)
        p.edit().putInt("count_$id", count).apply()
        render(context, manager, id)
      }
      ACTION_ROLL -> roll(context, manager, id)
    }
  }

  /** A short tumble of random faces, then the result. */
  private fun roll(context: Context, manager: AppWidgetManager, id: Int) {
    val pending = goAsync()
    val handler = Handler(Looper.getMainLooper())
    val count = count(context, id)
    vibrate(context)
    val frames = 5
    for (f in 0..frames) {
      handler.postDelayed({
        val values = IntArray(count) { Random.nextInt(1, 7) }
        if (f == frames) {
          val edit = prefs(context).edit()
          for (i in 0 until count) edit.putInt("v${i}_$id", values[i])
          edit.putBoolean("rolled_$id", true).apply()
          render(context, manager, id)
          pending.finish()
        } else {
          render(context, manager, id, values)
        }
      }, f * 70L)
    }
  }

  private fun vibrate(context: Context) {
    try {
      val v = context.getSystemService(Vibrator::class.java)
      v?.vibrate(VibrationEffect.createOneShot(25, VibrationEffect.DEFAULT_AMPLITUDE))
    } catch (_: Exception) {
    }
  }

  companion object {
    const val MAX = 6
    const val ACTION_ROLL = "de.sommer2019.mobile_games.dice.ROLL"
    const val ACTION_PLUS = "de.sommer2019.mobile_games.dice.PLUS"
    const val ACTION_MINUS = "de.sommer2019.mobile_games.dice.MINUS"
    private val DIE_VIEWS = intArrayOf(R.id.die1, R.id.die2, R.id.die3, R.id.die4, R.id.die5, R.id.die6)
    private val FACES = intArrayOf(R.drawable.die_1, R.drawable.die_2, R.drawable.die_3, R.drawable.die_4, R.drawable.die_5, R.drawable.die_6)

    private fun prefs(context: Context) =
        context.getSharedPreferences("dice_widget", Context.MODE_PRIVATE)

    private fun count(context: Context, id: Int) = prefs(context).getInt("count_$id", 2)

    private fun action(context: Context, id: Int, action: String, code: Int): PendingIntent {
      val intent = Intent(context, DiceWidget::class.java)
          .setAction(action)
          .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
      return PendingIntent.getBroadcast(
          context, id * 10 + code, intent,
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun render(context: Context, manager: AppWidgetManager, id: Int, tumbling: IntArray? = null) {
      val p = prefs(context)
      val count = count(context, id)
      val rolled = p.getBoolean("rolled_$id", false)
      val views = RemoteViews(context.packageName, R.layout.widget_dice)
      var sum = 0
      for (i in 0 until MAX) {
        if (i < count) {
          val v = tumbling?.get(i) ?: p.getInt("v${i}_$id", i % 6 + 1)
          sum += v
          views.setViewVisibility(DIE_VIEWS[i], View.VISIBLE)
          views.setImageViewResource(DIE_VIEWS[i], FACES[v - 1])
        } else {
          views.setViewVisibility(DIE_VIEWS[i], View.GONE)
        }
      }
      views.setTextViewText(R.id.dice_count, if (count == 1) "1 Würfel" else "$count Würfel")
      views.setTextViewText(
          R.id.dice_sum,
          when {
            tumbling != null -> "…"
            !rolled -> "Tippen zum Würfeln"
            count == 1 -> "Gewürfelt: $sum"
            else -> "Summe: $sum"
          })
      views.setOnClickPendingIntent(R.id.dice_row, action(context, id, ACTION_ROLL, 1))
      views.setOnClickPendingIntent(R.id.dice_sum, action(context, id, ACTION_ROLL, 1))
      views.setOnClickPendingIntent(R.id.dice_plus, action(context, id, ACTION_PLUS, 2))
      views.setOnClickPendingIntent(R.id.dice_minus, action(context, id, ACTION_MINUS, 3))
      views.setOnClickPendingIntent(
          R.id.dice_open,
          HomeWidgetLaunchIntent.getActivity(
              context, MainActivity::class.java, Uri.parse("mobilegames://dice?homeWidget")))
      manager.updateAppWidget(id, views)
    }
  }
}
