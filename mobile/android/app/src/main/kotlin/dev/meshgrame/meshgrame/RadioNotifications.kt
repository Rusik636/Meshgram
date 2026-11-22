// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

package dev.meshgrame.meshgrame

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

internal object RadioNotifications {
    private const val messageChannel = "mesh_messages"
    private const val quietChannel = "mesh_messages_quiet"
    private const val radioChannel = "mesh_radio_connection"
    private const val permissionRequest = 571
    private var platformChannel: MethodChannel? = null
    var backgroundStopped = false
        private set
    private var activity = WeakReference<MainActivity>(null)
    private var inAppRingtone: Ringtone? = null
    private var permissionResult: MethodChannel.Result? = null

    fun attach(host: MainActivity) {
        activity = WeakReference(host)
    }

    fun detach(host: MainActivity) {
        if (activity.get() !== host) return
        activity.clear()
        permissionResult?.success(permission(host))
        permissionResult = null
    }

    fun register(context: Context, messenger: BinaryMessenger) {
        createChannels(context)
        val channel = MethodChannel(messenger, "meshgrame/notifications")
        platformChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "permission" -> result.success(permission(context))
                "requestPermission" -> requestPermission(context, result)
                "openSettings" -> {
                    activity.get()?.startActivity(if (Build.VERSION.SDK_INT >= 26) {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                    } else {
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                    })
                    result.success(null)
                }
                "connectionService" -> result.success(connectionService(context, call.arguments == true))
                "resumeConnectionService" -> {
                    backgroundStopped = false
                    result.success(null)
                }
                "playInAppSound" -> {
                    if (activity.get()?.hasWindowFocus() == true) {
                        val ringtone = inAppRingtone ?: RingtoneManager.getRingtone(
                            context, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                        ).also { inAppRingtone = it }
                        if (ringtone?.isPlaying == false) ringtone.play()
                    }
                    result.success(null)
                }
                "publish" -> {
                    if (!backgroundStopped && permission(context) == "enabled" && activity.get()?.hasWindowFocus() != true) {
                        val chat = call.argument<String>("chat")
                        val title = call.argument<String>("title")
                        val body = call.argument<String>("body")
                        if (chat != null && title != null && body != null) {
                            publish(context, chat, title, body, call.argument<Boolean>("sound") != false)
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun permission(context: Context): String {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            val asked = context.getSharedPreferences("meshgram_notifications", Context.MODE_PRIVATE)
                .getBoolean("permissionAsked", false)
            return if (asked) "disabled" else "prompt"
        }
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return "disabled"
        if (Build.VERSION.SDK_INT >= 26 &&
            context.getSystemService(NotificationManager::class.java)
                .getNotificationChannel(messageChannel)?.importance == NotificationManager.IMPORTANCE_NONE) {
            return "disabled"
        }
        return "enabled"
    }

    private fun requestPermission(context: Context, result: MethodChannel.Result) {
        val host = activity.get()
        if (Build.VERSION.SDK_INT < 33 || permission(context) != "prompt" ||
            host == null || !host.hasWindowFocus() || permissionResult != null) {
            result.success(permission(context))
            return
        }
        permissionResult = result
        context.getSharedPreferences("meshgram_notifications", Context.MODE_PRIVATE)
            .edit().putBoolean("permissionAsked", true).apply()
        host.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), permissionRequest)
    }

    fun onPermissionResult(context: Context, request: Int) {
        if (request != permissionRequest) return
        permissionResult?.success(permission(context))
        permissionResult = null
    }

    fun stopFromNotification() {
        if (backgroundStopped) return
        backgroundStopped = true
        platformChannel?.invokeMethod("backgroundStopped", null)
    }

    private fun connectionService(context: Context, enabled: Boolean): Boolean {
        if (enabled && backgroundStopped) return false
        val intent = Intent(context, RadioConnectionService::class.java)
        return try {
            if (enabled) {
                ContextCompat.startForegroundService(context, intent)
            } else {
                context.stopService(intent)
            }
            true
        } catch (error: IllegalStateException) {
            false
        } catch (error: SecurityException) {
            false
        }
    }

    private fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        context.getSystemService(NotificationManager::class.java).createNotificationChannels(listOf(
            NotificationChannel(messageChannel, context.getString(R.string.mesh_message_notifications), NotificationManager.IMPORTANCE_HIGH),
            NotificationChannel(quietChannel, context.getString(R.string.mesh_message_notifications_quiet), NotificationManager.IMPORTANCE_LOW),
            NotificationChannel(radioChannel, context.getString(R.string.mesh_radio_notifications), NotificationManager.IMPORTANCE_LOW).apply {
                setShowBadge(false)
            },
        ))
    }

    private fun builder(context: Context, channel: String) = NotificationCompat.Builder(context, channel)
        .setSmallIcon(R.drawable.ic_mesh_notification)
        .setContentIntent(PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        ))

    private fun publish(context: Context, chat: String, title: String, body: String, sound: Boolean) {
        val content = builder(context, if (sound) messageChannel else quietChannel)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(if (sound) NotificationCompat.DEFAULT_ALL else 0)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(chat, 1, content)
        } catch (_: SecurityException) {
            // The notification permission can change while a packet is being received.
        }
    }

    fun serviceNotification(context: Context): Notification {
        createChannels(context)
        val stop = PendingIntent.getService(
            context, 0,
            Intent(context, RadioConnectionService::class.java).setAction(RadioConnectionService.ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return builder(context, radioChannel)
            .setContentTitle(context.getString(R.string.mesh_radio_background))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .addAction(0, context.getString(R.string.mesh_radio_stop), stop)
            .build()
    }
}

class RadioConnectionService : Service() {
    companion object {
        const val ACTION_STOP = "dev.meshgrame.client.STOP_BACKGROUND_RADIO"
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) RadioNotifications.stopFromNotification()
        if (RadioNotifications.backgroundStopped) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        val notification = RadioNotifications.serviceNotification(this)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(2, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(2, notification)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
