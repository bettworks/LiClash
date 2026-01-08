package com.appshub.liclash.services

import android.annotation.SuppressLint
import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.appshub.liclash.GlobalState
import com.appshub.liclash.models.VpnOptions


class LiClashService : Service(), BaseServiceInterface {

    override fun start(options: VpnOptions) = 0

    override fun stop() {
        stopSelf()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
    }
    
    private var cachedBuilder: NotificationCompat.Builder? = null

    private suspend fun notificationBuilder(): NotificationCompat.Builder {
        if (cachedBuilder == null) {
            cachedBuilder = createLiClashNotificationBuilder().await()
        }
        return cachedBuilder!!
    }

    @SuppressLint("ForegroundServiceType")
    override suspend fun startForeground(title: String, content: String) {
        val separator = " ︙ "
        val combinedText = "$title$separator$content"
        val spannable = android.text.SpannableString(combinedText)
        val startIndex = title.length + separator.length
        
        if (startIndex < combinedText.length) {
            spannable.setSpan(
                android.text.style.RelativeSizeSpan(0.83f),
                startIndex,
                combinedText.length,
                android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }

        startForeground(
            notificationBuilder()
                .setContentTitle(spannable)
                .setContentText(null)
                .build()
        )
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        GlobalState.getCurrentVPNPlugin()?.requestGc()
    }


    private val binder = LocalBinder()

    inner class LocalBinder : Binder() {
        fun getService(): LiClashService = this@LiClashService
    }

    override fun onBind(intent: Intent): IBinder {
        return binder
    }

    override fun onUnbind(intent: Intent?): Boolean {
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        stop()
        super.onDestroy()
    }
}