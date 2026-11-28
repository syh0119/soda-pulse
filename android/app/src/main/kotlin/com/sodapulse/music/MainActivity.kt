package com.sodapulse.music

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.graphics.Color
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.OpenableColumns
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "com.sodapulse.music/player"
        private const val EVENT_CHANNEL = "com.sodapulse.music/events"
        private const val PREFS_NAME = "sodapulse_prefs"
        private const val REQUEST_PERMISSIONS_CODE = 1001
        private const val REQUEST_PICK_TEXT_FILE = 1002
        private const val REQUEST_SCAN_QR = 1003
        private const val REQUEST_PICK_QR_IMAGE = 1004
    }

    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingServiceActions = mutableListOf<(PlaybackService) -> Unit>()

    private var playbackService: PlaybackService? = null
    private var isBound = false
    private var isBinding = false
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPickFileResult: MethodChannel.Result? = null
    private var pendingScanQrResult: MethodChannel.Result? = null
    private var pendingPickQrImageResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                    android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                )
        }
        @Suppress("DEPRECATION")
        window.statusBarColor = Color.TRANSPARENT
        @Suppress("DEPRECATION")
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val lp = window.attributes
            lp.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            window.attributes = lp
        }
    }

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

            "setEqParams" -> {
                val gainsRaw = call.argument<List<*>>("gains") ?: emptyList<Any?>()
                val preGain = (call.argument<Number>("preGain"))?.toFloat() ?: 0f
                val gains = FloatArray(5) { idx ->
                    (gainsRaw.getOrNull(idx) as? Number)?.toFloat() ?: 0f
                }
                SodaEqAudioProcessor.setParams(gains, preGain)
                result.success(true)
            }

            "setLoudnessNorm" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                val targetLufs = (call.argument<Number>("targetLufs"))?.toFloat() ?: -14.0f
                SodaEqAudioProcessor.setLoudnessNorm(enabled, targetLufs)
                result.success(true)
            }

            "setPlaybackSpeed" -> {
                val speed = (call.argument<Number>("speed"))?.toFloat() ?: 1.0f
                withPlaybackService(startForeground = false) { service ->
                    service.setPlaybackSpeed(speed)
                    result.success(true)
                }
            }

            "setFavorite" -> {
                val favorite = call.argument<Boolean>("favorite") ?: false
                withPlaybackService(startForeground = false) { service ->
                    service.setFavorite(favorite)
                    result.success(true)
                }
            }

            "getAppStoragePaths" -> {
                val baseDir = (getExternalFilesDir(null) ?: filesDir).absolutePath
                val downloadDir = File(
                    getExternalFilesDir(Environment.DIRECTORY_MUSIC) ?: filesDir,
                    "SodaPulseDownloads"
                ).apply { mkdirs() }.absolutePath
                val cacheDirPath = (externalCacheDir ?: cacheDir).absolutePath
                result.success(
                    mapOf(
                        "baseDir" to baseDir,
                        "downloadDir" to downloadDir,
                        "cacheDir" to cacheDirPath
                    )
                )
            }

            "probeAudioHardware" -> {
                executor.execute {
                    val info = probeAudioHardwareInfo()
                    mainHandler.post { result.success(info) }
                }
            }

            "getCoverArtInfo" -> {
                val uri = call.argument<String>("uri")
                executor.execute {
                    try {
                        val info = LocalLibraryScanner.getCoverArtInfo(applicationContext, uri)
                        mainHandler.post { result.success(info) }
                    } catch (e: Exception) {
                        mainHandler.post { result.success(mapOf("path" to null, "color" to null)) }
                    }
                }
            }

            "shareText" -> {
                val text = call.argument<String>("text") ?: ""
                val subject = call.argument<String>("subject")
                try {
                    val sendIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                        if (!subject.isNullOrBlank()) {
                            putExtra(Intent.EXTRA_SUBJECT, subject)
                        }
                    }
                    startActivity(Intent.createChooser(sendIntent, "分享到"))
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SHARE_ERROR", e.message, null)
                }
            }

            "pickTextFile" -> {
                pendingPickFileResult?.success(null)
                pendingPickFileResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                }
                @Suppress("DEPRECATION")
                startActivityForResult(intent, REQUEST_PICK_TEXT_FILE)
            }

            "scanQrCode" -> {
                pendingScanQrResult?.success(null)
                pendingScanQrResult = result
                val intent = Intent(this, QrScannerActivity::class.java)
                @Suppress("DEPRECATION")
                startActivityForResult(intent, REQUEST_SCAN_QR)
            }

            "pickQrImage" -> {
                pendingPickQrImageResult?.success(null)
                pendingPickQrImageResult = result
                val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = "image/*"
                }
                @Suppress("DEPRECATION")
                startActivityForResult(
                    Intent.createChooser(intent, "选择二维码图片"),
                    REQUEST_PICK_QR_IMAGE
                )
            }

            "generateQrPng" -> {
                val text = call.argument<String>("text") ?: ""
                val size = (call.argument<Number>("size")?.toInt() ?: 640).coerceIn(128, 1280)
                if (text.isBlank()) {
                    result.error("INVALID_QR_TEXT", "二维码内容不能为空", null)
                    return
                }
                executor.execute {
                    try {
                        val png = QrCodecHelper.generateQrPng(text, size)
                        mainHandler.post { result.success(png) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("QR_ENCODE_ERROR", e.message, null) }
                    }
                }
            }

            "exportTextFile" -> {
                val fileName = call.argument<String>("fileName") ?: "sodapulse_backup.json"
                val content = call.argument<String>("content") ?: ""
                executor.execute {
                    try {
                        val dir = getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS) ?: filesDir
                        if (!dir.exists()) dir.mkdirs()
                        val outFile = File(dir, fileName)
                        outFile.writeText(content, Charsets.UTF_8)
                        mainHandler.post { result.success(mapOf("path" to outFile.absolutePath)) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("EXPORT_ERROR", e.message, null) }
                    }
                }
            }

            "pluginLoad" -> {
                val id = call.argument<String>("id") ?: ""
                val script = call.argument<String>("script") ?: ""
                val type = call.argument<String>("type") ?: "musicFree"
                executor.execute {
                    try {
                        val res = SodaJsPluginRuntime.loadPlugin(applicationContext, id, script, type)
                        mainHandler.post { result.success(res) }
                    } catch (e: Exception) {
                        mainHandler.post { result.success(mapOf("ok" to false, "error" to (e.message ?: "load failed"))) }
                    }
                }
            }

            "pluginUnload" -> {
                val id = call.argument<String>("id") ?: ""
                executor.execute {
                    val ok = try {
                        SodaJsPluginRuntime.unloadPlugin(id)
                    } catch (_: Exception) {
                        false
                    }
                    mainHandler.post { result.success(ok) }
                }
            }

            "pluginTest" -> {
                val id = call.argument<String>("id") ?: ""
                executor.execute {
                    try {
                        val res = SodaJsPluginRuntime.testPlugin(applicationContext, id)
                        mainHandler.post { result.success(res) }
                    } catch (e: Exception) {
                        mainHandler.post { result.success(mapOf("ok" to false, "error" to (e.message ?: "test failed"))) }
                    }
                }
            }

            "pluginSearch" -> {
                val pluginId = call.argument<String>("pluginId") ?: ""
                val query = call.argument<String>("query") ?: ""
                val page = call.argument<Number>("page")?.toInt() ?: 1
                executor.execute {
                    try {
                        val tracks = SodaJsPluginRuntime.searchTracks(applicationContext, pluginId, query, page)
                        mainHandler.post { result.success(tracks) }
                    } catch (e: Exception) {
                        mainHandler.post { result.success(emptyList<Map<String, Any?>>()) }
                    }
                }
            }

            "pluginResolveUrl" -> {
                val pluginId = call.argument<String>("pluginId") ?: ""
                val rawItemJson = call.argument<String>("rawItemJson") ?: "{}"
                val quality = call.argument<String>("quality") ?: "standard"
                val source = call.argument<String>("source") ?: ""
                executor.execute {
                    try {
                        val res = SodaJsPluginRuntime.resolveMediaUrl(applicationContext, pluginId, rawItemJson, quality, source)
                        mainHandler.post { result.success(res) }
                    } catch (e: Exception) {
                        mainHandler.post { result.success(mapOf("ok" to false, "error" to (e.message ?: "resolve failed"))) }
                    }
                }
            }

            "pluginResolveLyric" -> {
                val pluginId = call.argument<String>("pluginId") ?: ""
                val rawItemJson = call.argument<String>("rawItemJson") ?: "{}"
                executor.execute {
                    try {
                        val res = SodaJsPluginRuntime.resolveLyric(applicationContext, pluginId, rawItemJson)
                        mainHandler.post { result.success(res) }
                    } catch (e: Exception) {
                        mainHandler.post { result.success(mapOf("ok" to false, "error" to (e.message ?: "lyric failed"))) }
                    }
                }
            }

            "pluginImportSheet" -> {
                val pluginId = call.argument<String>("pluginId") ?: ""
                val urlOrId = call.argument<String>("urlOrId") ?: ""
                executor.execute {
                    try {
                        val tracks = SodaJsPluginRuntime.importMusicSheet(applicationContext, pluginId, urlOrId)
                        mainHandler.post { result.success(tracks) }
                    } catch (e: Exception) {
                        mainHandler.post { result.success(emptyList<Map<String, Any?>>()) }
                    }
                }
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

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_PICK_TEXT_FILE) {
            val res = pendingPickFileResult
            pendingPickFileResult = null
            if (res == null) return
            val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
            if (uri == null) {
                res.success(null)
                return
            }
            executor.execute {
                try {
                    var displayName = "file.txt"
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                        if (c.moveToFirst()) {
                            val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (idx >= 0) {
                                displayName = c.getString(idx) ?: displayName
                            }
                        }
                    }
                    val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: ByteArray(0)
                    if (bytes.size > 5 * 1024 * 1024) {
                        mainHandler.post { res.error("FILE_TOO_LARGE", "文件超过 5MB", null) }
                        return@execute
                    }
                    val text = bytes.toString(Charsets.UTF_8)
                    mainHandler.post { res.success(mapOf("name" to displayName, "content" to text)) }
                } catch (e: Exception) {
                    mainHandler.post { res.error("READ_FILE_ERROR", e.message, null) }
                }
            }
        } else if (requestCode == REQUEST_SCAN_QR) {
            val res = pendingScanQrResult
            pendingScanQrResult = null
            if (res == null) return
            val qrText = if (resultCode == Activity.RESULT_OK) {
                data?.getStringExtra(QrScannerActivity.EXTRA_QR_TEXT)
            } else {
                null
            }
            res.success(qrText)
        } else if (requestCode == REQUEST_PICK_QR_IMAGE) {
            val res = pendingPickQrImageResult
            pendingPickQrImageResult = null
            if (res == null) return
            val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
            if (uri == null) {
                res.success(null)
                return
            }
            executor.execute {
                try {
                    val decoded = QrCodecHelper.decodeQrFromUri(applicationContext, uri)
                    if (!decoded.isNullOrBlank()) {
                        mainHandler.post { res.success(decoded) }
                    } else {
                        mainHandler.post {
                            res.error("QR_NOT_FOUND", "未在图片中识别到有效二维码", null)
                        }
                    }
                } catch (e: Exception) {
                    mainHandler.post { res.error("QR_DECODE_ERROR", e.message, null) }
                }
            }
        }
    }

    override fun onDestroy() {
        pendingServiceActions.clear()
        pendingPermissionResult = null
        pendingPickFileResult = null
        pendingScanQrResult = null
        pendingPickQrImageResult = null
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

    private fun audioDeviceTypeLabel(type: Int): String {
        return when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "扬声器"
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "听筒"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "有线耳机 (带麦)"
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "有线耳机"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "蓝牙音频 (A2DP)"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "蓝牙通话 (SCO)"
            AudioDeviceInfo.TYPE_USB_DEVICE -> "USB 音频设备"
            AudioDeviceInfo.TYPE_USB_HEADSET -> "USB-C 耳机/DAC"
            AudioDeviceInfo.TYPE_HDMI -> "HDMI 输出"
            AudioDeviceInfo.TYPE_LINE_ANALOG -> "模拟线路输出"
            AudioDeviceInfo.TYPE_LINE_DIGITAL -> "数字线路输出"
            else -> if (Build.VERSION.SDK_INT >= 31 && type == AudioDeviceInfo.TYPE_BLE_HEADSET) {
                "LE Audio 蓝牙耳机"
            } else {
                "音频设备 ($type)"
            }
        }
    }

    private fun probeAudioHardwareInfo(): Map<String, Any?> {
        val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val outputDevices = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && am != null) {
            am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map { dev ->
                val typeName = audioDeviceTypeLabel(dev.type)
                val productName = dev.productName?.toString()?.trim().orEmpty()
                val displayName = if (productName.isNotEmpty() && !productName.equals(Build.MODEL, ignoreCase = true)) {
                    "$productName ($typeName)"
                } else {
                    typeName
                }
                mapOf(
                    "id" to dev.id,
                    "name" to displayName,
                    "type" to dev.type,
                    "typeName" to typeName,
                    "sampleRates" to dev.sampleRates.toList(),
                    "channelCounts" to dev.channelCounts.toList(),
                    "isSink" to dev.isSink
                )
            }
        } else {
            emptyList()
        }

        var eqSupported = false
        var eqBands = 0
        var eqRange = listOf<Int>()
        var eqCenterFreqsHz = listOf<Int>()
        var loudnessSupported = false
        var probeSessionId = 0
        var probeError: String? = null

        var track: AudioTrack? = null
        var eq: Equalizer? = null
        var le: LoudnessEnhancer? = null
        try {
            val sr = 44100
            val minBuf = AudioTrack.getMinBufferSize(
                sr,
                AudioFormat.CHANNEL_OUT_STEREO,
                AudioFormat.ENCODING_PCM_16BIT
            ).coerceAtLeast(1024)
            track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(sr)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .build()
                )
                .setBufferSizeInBytes(minBuf)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            probeSessionId = track.audioSessionId
            try {
                track.play()
                val silence = ByteArray(minBuf.coerceAtMost(2048))
                track.write(silence, 0, silence.size)
            } catch (_: Throwable) {
            }

            try {
                eq = Equalizer(0, probeSessionId)
                eqSupported = true
                eqBands = eq.numberOfBands.toInt()
                eqRange = eq.bandLevelRange.map { it.toInt() }
                eqCenterFreqsHz = (0 until eqBands).map { b ->
                    eq.getCenterFreq(b.toShort()) / 1000
                }
            } catch (e: Throwable) {
                eqSupported = false
                probeError = e.message
            }

            try {
                le = LoudnessEnhancer(probeSessionId)
                loudnessSupported = true
            } catch (e: Throwable) {
                loudnessSupported = false
                if (probeError == null) probeError = e.message
            }
        } catch (e: Throwable) {
            probeError = e.message
        } finally {
            try { le?.release() } catch (_: Throwable) {}
            try { eq?.release() } catch (_: Throwable) {}
            try { track?.stop() } catch (_: Throwable) {}
            try { track?.release() } catch (_: Throwable) {}
        }

        val preferredDevice = outputDevices.firstOrNull {
            val t = it["type"] as? Int ?: 0
            t == AudioDeviceInfo.TYPE_USB_HEADSET ||
                t == AudioDeviceInfo.TYPE_USB_DEVICE ||
                t == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                t == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                t == AudioDeviceInfo.TYPE_WIRED_HEADPHONES
        } ?: outputDevices.firstOrNull()

        return mapOf(
            "devices" to outputDevices,
            "activeDeviceName" to (preferredDevice?.get("name") ?: "系统默认输出"),
            "activeDeviceType" to (preferredDevice?.get("typeName") ?: "默认"),
            "equalizerSupported" to eqSupported,
            "equalizerBands" to eqBands,
            "equalizerRangeMb" to eqRange,
            "centerFreqsHz" to eqCenterFreqsHz,
            "loudnessEnhancerSupported" to loudnessSupported,
            "probeSessionId" to probeSessionId,
            "probeError" to probeError,
            "alacDecoderSupported" to true,
            "alacDecoderEngine" to "SodaPulse Pure-Kotlin ALAC (16/24-bit · 最高 192kHz)"
        )
    }
}
