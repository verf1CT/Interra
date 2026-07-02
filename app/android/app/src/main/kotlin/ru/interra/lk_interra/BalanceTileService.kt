package ru.interra.lk_interra

import android.content.Intent
import android.graphics.drawable.Icon
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/// Плитка «Быстрых настроек»: показывает баланс, тап открывает приложение.
/// Данные берём из того же хранилища, что и виджет (home_widget).
class BalanceTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        val prefs = getSharedPreferences("HomeWidgetPreferences", MODE_PRIVATE)
        val balance = prefs.getString("balance_text", null)
        qsTile?.apply {
            label = "Баланс Интерры"
            // Подпись с суммой (API 29+); ниже — просто оставляем label.
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                subtitle = if (balance.isNullOrEmpty() || balance == "—") "нет данных" else balance
            }
            icon = Icon.createWithResource(this@BalanceTileService, R.drawable.ic_wifi_white)
            state = Tile.STATE_ACTIVE
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (intent != null) {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val pi = android.app.PendingIntent.getActivity(
                    this, 0, intent,
                    android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT,
                )
                startActivityAndCollapse(pi)
            } else {
                @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
                startActivityAndCollapse(intent)
            }
        }
    }
}
