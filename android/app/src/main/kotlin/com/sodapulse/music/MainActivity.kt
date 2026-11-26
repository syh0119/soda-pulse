package com.sodapulse.music

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "com.sodapulse.music/player"
        private const val EVENT_CHANNEL = "com.sodapulse.music/events"
        private const val PREFS_NAME = "sodapulse_prefs"
        private const val REQUEST_PERMISSIONS_CODE = 1001
    }

    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingServiceActions = mutableListOf<(PlaybackService) -> Unit>()

    private var playbackService: PlaybackService? = null
    private var isBound = false
    private var isBinding = false
    private var pendingPermissionResult: MethodChannel.Result? = null

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            isBinding = false
            val binder = service as? PlaybackService.LocalBinder ?: return
            val boundService = binder.getService()
            playbackService = boundService
            isBound = true
            val actions = pendingServiceActions.toList()
            pendingServiceActions.clear()
            for (action in actions) {
                action(boundService)
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            isBinding = false
            isBound = false
            playbackService = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                PlayerServiceBridge.eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                PlayerServiceBridge.eventSink = null
            }
        })
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scanLocalAudio" -> {
                executor.execute {
                    try {
                        val tracks = LocalLibraryScanner.scanAudio(applicationContext)
                        mainHandler.post { result.success(tracks) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("SCAN_ERROR", e.message, null) }
                    }
                }
            }

            "readTrackLyrics" -> {
                val filePath = call.argument<String>("filePath")
                val uri = call.argument<String>("uri")
                executor.execute {
                    try {
                        val lyrics = LocalLibraryScanner.readSidecarLyrics(applicationContext, filePath, uri)
                        mainHandler.post { result.success(lyrics) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("LYRICS_READ_ERROR", e.message, null) }
                    }
                }
            }

            "prepareDemoAudio" -> {
                executor.execute {
                    try {
                        val demo = LocalLibraryScanner.prepareDemoAudio(applicationContext)
                        mainHandler.post { result.success(demo) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("DEMO_AUDIO_ERROR", e.message, null) }
                    }
                }
            }

            "loadAndPlay" -> {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                withPlaybackService(startForeground = true) { service ->
                    service.loadAndPlay(args)
                    result.success(true)
                }
            }

            "play" -> {
                withPlaybackService(startForeground = true) { service ->
                    service.play()
                    result.success(true)
                }
            }

            "pause" -> {
                withPlaybackService(startForeground = false) { service ->
                    service.pause()
                    result.success(true)
                }
            }

            "togglePlay" -> {
                withPlaybackService(startForeground = true) { service ->
                    service.togglePlay()
                    result.success(true)
                }
            }

            "seekTo" -> {
                val positionMs = (call.argument<Number>("positionMs")
                    ?: call.argument<Number>("position"))?.toLong() ?: 0L
                withPlaybackService(startForeground = false) { service ->
                    service.seekTo(positionMs)
                    result.success(true)
                }
            }

            "next" -> {
                withPlaybackService(startForeground = true) { service ->
                    service.next()
                    result.success(true)
                }
            }

            "previous" -> {
                withPlaybackService(startForeground = true) { service ->
                    service.previous()
                    result.success(true)
                }
            }

            "setQueue" -> {
                val items = call.argument<List<Map<String, Any?>>>("items")
                    ?: call.argument<List<Map<String, Any?>>>("queue")
                    ?: emptyList()
                val index = call.argument<Number>("index")?.toInt() ?: 0
                withPlaybackService(startForeground = false) { service ->
                    service.setQueue(items, index)
                    result.success(true)
                }
            }

            "setLyricMode" -> {
                val mode = call.argument<String>("mode") ?: "auto"
                withPlaybackService(startForeground = false) { service ->
                    service.setLyricMode(mode)
                    result.success(true)
                }
            }

            "setLyricOffset" -> {
                val offsetMs = (call.argument<Number>("offsetMs")
                    ?: call.argument<Number>("offset"))?.toLong() ?: 0L
                withPlaybackService(startForeground = false) { service ->
                    service.setLyricOffset(offsetMs)
                    result.success(true)
                }
            }

            "setOverlayConfig" -> {
                @Suppress("UNCHECKED_CAST")
                val config = call.arguments as? Map<String, Any?> ?: emptyMap()
                withPlaybackService(startForeground = false) { service ->
                    service.setOverlayConfig(config)
                    result.success(true)
                }
            }

            "canDrawOverlays" -> {
                result.success(KaraokeOverlayController.canDrawOverlays(applicationContext))
            }

            "requestOverlayPermission" -> {
                KaraokeOverlayController.requestOverlayPermission(this)
                result.success(true)
            }

            "requestPermissions" -> {
                requestAppPermissions(result)
            }

            "getEnvironmentStatus" -> {
                executor.execute {
                    try {
                        val router = PlayerServiceBridge.lyricRouter ?: ColorOsLyricRouter(applicationContext)
                        val snapshot = router.queryStatusSnapshot()
                        val statusMap = mapOf(
                            "superLyricStatus" to snapshot.status,
                            "superLyricVersion" to snapshot.serverApiVersion,
                            "activeMode" to snapshot.resolvedMode.wireName,
                            "selectedMode" to snapshot.selectedMode.wireName,
                            "canDrawOverlay" to KaraokeOverlayController.canDrawOverlays(applicationContext),
                            "hasAudioPerm" to hasAudioPermission(),
                            "hasNotifPerm" to hasNotificationPermission(),
                            "androidSdk" to Build.VERSION.SDK_INT,
                            "brand" to Build.BRAND,
                            "model" to Build.MODEL,
                            "lastPublishResult" to snapshot.lastPublishResult
                        )
                        mainHandler.post { result.success(statusMap) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("ENV_STATUS_ERROR", e.message, null) }
                    }
                }
            }

            "getPreferences" -> {
                val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val resultMap = mutableMapOf<String, Any?>()
                for ((key, value) in prefs.all) {
                    resultMap[key] = when (value) {
                        is Float -> value.toDouble()
                        is Set<*> -> value.filterIsInstance<String>()
                        else -> value
                    }
                }
                result.success(resultMap)
            }

            "savePreferences" -> {
                @Suppress("UNCHECKED_CAST")
                val data = call.arguments as? Map<String, Any?> ?: emptyMap()
                val editor = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                for ((key, value) in data) {
                    when (value) {
                        null -> editor.remove(key)
                        is Boolean -> editor.putBoolean(key, value)
                        is Int -> editor.putInt(key, value)
                        is Long -> editor.putLong(key, value)
                        is Double -> editor.putFloat(key, value.toFloat())
                        is Float -> editor.putFloat(key, value)
                        is String -> editor.putString(key, value)
                        is List<*> -> editor.putStringSet(key, value.filterIsInstance<String>().toSet())
                    }
                }
                editor.apply()
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    private fun withPlaybackService(
        startForeground: Boolean,
        action: (PlaybackService) -> Unit
    ) {
        val service = playbackService
        if (service != null && isBound) {
            if (startForeground) {
                ContextCompat.startForegroundService(this, Intent(this, PlaybackService::class.java))
            }
            action(service)
            return
        }

        pendingServiceActions.add(action)
        val intent = Intent(this, PlaybackService::class.java)
        if (startForeground) {
            ContextCompat.startForegroundService(this, intent)
        }
        if (!isBinding) {
            isBinding = bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
        }
    }

    private fun hasAudioPermission(): Boolean {
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        return ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun buildPermissionStatusMap(): Map<String, Boolean> {
        return mapOf(
            "audio" to hasAudioPermission(),
            "notifications" to hasNotificationPermission(),
            "overlay" to KaraokeOverlayController.canDrawOverlays(applicationContext)
        )
    }

    private fun requestAppPermissions(result: MethodChannel.Result) {
        val missing = mutableListOf<String>()
        if (!hasAudioPermission()) {
            val audioPerm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                Manifest.permission.READ_MEDIA_AUDIO
            } else {
                Manifest.permission.READ_EXTERNAL_STORAGE
            }
            missing.add(audioPerm)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !hasNotificationPermission()) {
            missing.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        if (missing.isEmpty()) {
            result.success(buildPermissionStatusMap())
            return
        }

        pendingPermissionResult = result
        ActivityCompat.requestPermissions(this, missing.toTypedArray(), REQUEST_PERMISSIONS_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_PERMISSIONS_CODE) {
            pendingPermissionResult?.success(buildPermissionStatusMap())
            pendingPermissionResult = null
        }
    }

    override fun onDestroy() {
        pendingServiceActions.clear()
        pendingPermissionResult = null
        if (isBound || isBinding) {
            try {
                unbindService(serviceConnection)
            } catch (_: IllegalArgumentException) {
            }
            isBound = false
            isBinding = false
        }
        playbackService = null
        executor.shutdownNow()
        super.onDestroy()
    }
}
