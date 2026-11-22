// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

package dev.meshgrame.meshgrame

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

class MainActivity : FlutterActivity() {
    private var hideNavigation = false

    companion object {
        private var retainedEngine: FlutterEngine? = null
        private var navigationHidden = false
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        retainedEngine ?: FlutterEngine(context.applicationContext).also { engine ->
            retainedEngine = engine
            RadioNotifications.register(context.applicationContext, engine.dartExecutor.binaryMessenger)
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RadioNotifications.attach(this)
        hideNavigation = navigationHidden
        val app = applicationContext
        val screen = WeakReference(this)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "meshgrame/app_info").setMethodCallHandler { call, result ->
            if (call.method == "buildInfo") {
                result.success(app.buildInfo())
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(messenger, "meshgrame/wifi_signal").setMethodCallHandler { call, result ->
            if (call.method == "readRssi") {
                result.success(app.wifiRssi())
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(messenger, "meshgrame/android").setMethodCallHandler { call, result ->
            when (call.method) {
                "bluetoothProblem" -> result.success(app.bluetoothProblem(call.arguments == true))
                "hideNavigation" -> {
                    navigationHidden = call.arguments == true
                    screen.get()?.apply {
                        hideNavigation = navigationHidden
                        updateNavigationBar()
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        RadioNotifications.detach(this)
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        RadioNotifications.onPermissionResult(this, requestCode)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && hideNavigation) updateNavigationBar()
    }

    private fun updateNavigationBar() {
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        val navigation = WindowInsetsCompat.Type.navigationBars()
        if (hideNavigation) {
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(navigation)
        } else {
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_DEFAULT
            controller.show(navigation)
        }
    }
}

@Suppress("DEPRECATION")
private fun Context.buildInfo(): Map<String, String?> {
    val info = packageManager.getPackageInfo(packageName, 0)
    val number = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        info.longVersionCode
    } else {
        info.versionCode.toLong()
    }
    return mapOf(
        "version" to info.versionName,
        "number" to number.toString(),
        "date" to getString(R.string.meshgrame_build_date),
    )
}

private fun Context.bluetoothProblem(scanning: Boolean): String? {
        val bluetooth = getSystemService(BluetoothManager::class.java)
        val adapter = bluetooth?.adapter ?: return "unsupported"
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) return "unsupported"

        // FlutterBluePlus handles the runtime permission prompt for the operation itself.
        val canReadState = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        if (canReadState && (adapter.state == BluetoothAdapter.STATE_OFF ||
            adapter.state == BluetoothAdapter.STATE_TURNING_OFF)) return "off"
        if (scanning && Build.VERSION.SDK_INT < Build.VERSION_CODES.S && !locationEnabled()) return "location"
        return null
    }

    @Suppress("DEPRECATION")
    private fun Context.locationEnabled(): Boolean = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        getSystemService(LocationManager::class.java)?.isLocationEnabled == true
    } else {
        Settings.Secure.getInt(contentResolver, Settings.Secure.LOCATION_MODE, 0) != 0
    }

    @Suppress("DEPRECATION")
    private fun Context.wifiRssi(): Int? {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        if (!wifi.isWifiEnabled) return null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val connectivity = getSystemService(ConnectivityManager::class.java) ?: return null
            val networks = listOfNotNull(connectivity.activeNetwork) + connectivity.allNetworks
            for (network in networks.distinct()) {
                val caps = connectivity.getNetworkCapabilities(network) ?: continue
                if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) continue
                validRssi((caps.transportInfo as? WifiInfo)?.rssi)?.let { return it }
                if (caps.signalStrength != NetworkCapabilities.SIGNAL_STRENGTH_UNSPECIFIED) {
                    validRssi(caps.signalStrength)?.let { return it }
                }
            }
        }
        // Legacy Wi-Fi reports use a signed 8-bit value and -127 for an unavailable sample.
        val info = wifi.connectionInfo ?: return null
        return if (info.networkId >= 0 || info.supplicantState == android.net.wifi.SupplicantState.COMPLETED) {
            validRssi(info.rssi)
        } else {
            null
        }
    }

    private fun validRssi(sample: Int?): Int? = sample?.takeIf { it in -126..-1 }
