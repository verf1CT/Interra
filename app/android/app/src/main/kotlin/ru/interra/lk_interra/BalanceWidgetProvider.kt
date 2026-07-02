package ru.interra.lk_interra

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// Виджет баланса на домашнем экране Android. Данные (`balance_text`,
/// `balance_updated`) пишет приложение через home_widget; тап открывает приложение.
class BalanceWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val balanceRaw = widgetData.getString("balance_text", null)
        val balance = if (balanceRaw.isNullOrEmpty() || balanceRaw == "—") "нет данных" else balanceRaw
        val updated = widgetData.getString("balance_updated", null)

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.balance_widget).apply {
                setTextViewText(R.id.widget_value, balance)
                setTextViewText(
                    R.id.widget_updated,
                    if (!updated.isNullOrEmpty()) "обновлено $updated" else "откройте приложение",
                )
                // Тап по виджету — открыть приложение.
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
