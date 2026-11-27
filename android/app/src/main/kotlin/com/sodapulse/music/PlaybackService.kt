package com.sodapulse.music

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaDescription
import android.media.MediaMetadata
import android.media.browse.MediaBrowser
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Binder
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import androidx.annotation.OptIn
import androidx.core.content.ContextCompat
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import java.io.File
import java.util.concurrent.Executors

class PlaybackService : Service() {

    companion object {
        private const val CHANNEL_ID = "sodapulse_playback_channel"
        private const val CHANNEL_NAME = "Music Playback"
        private const val NOTIFICATION_ID = 1001

        private const val ACTION_PREV = "com.sodapulse.music.ACTION_PREV"
        private const val ACTION_PLAY_PAUSE = "com.sodapulse.music.ACTION_PLAY_PAUSE"
        private const val ACTION_NEXT = "com.sodapulse.music.ACTION_NEXT"
        private const val ACTION_FAVORITE = "com.sodapulse.music.ACTION_FAVORITE"
        private const val ACTION_STOP = "com.sodapulse.music.ACTION_STOP"

        private const val TICK_INTERVAL_MS = 50L
        private const val PLAYBACK_PUSH_INTERVAL_MS = 250L
    }

    inner class LocalBinder : Binder() {
        fun getService(): PlaybackService = this@PlaybackService
    }

    private data class QueueTrack(
        val id: String,
        val uri: String,
        val title: String,
        val artist: String,
        val album: String,
        val durationMs: Long
    )

    private val localBinder = LocalBinder()
    private val tickHandler = Handler(Looper.getMainLooper())
    private val coverExecutor = Executors.newSingleThreadExecutor()

    private lateinit var player: ExoPlayer
    private lateinit var mediaSession: MediaSession
    private lateinit var notificationManager: NotificationManager
    private lateinit var audioManager: AudioManager
    private lateinit var lyricRouter: ColorOsLyricRouter

    private var audioFocusRequest: AudioFocusRequest? = null
    private var hasAudioFocus = false
    private var resumeOnFocusGain = false

    private var currentTrackId: String = ""
    private var currentTitle: String = "SodaPulse"
    private var currentArtist: String = ""
    private var currentAlbum: String = ""
    private var currentDurationMs: Long = 0L
    private var currentCoverUri: String? = null
    private var currentFavorite: Boolean = false
    private var coverBitmap: Bitmap? = null
    private var lastLyricInfoJson: String? = null
    @Volatile
    private var currentTrackHeaders: Map<String, String> = emptyMap()

    private var queueTracks: List<QueueTrack> = emptyList()
    private var currentQueueIndex: Int = -1
    private var lyricOffsetMs: Long = 0L

    private var isTicking = false
    private var lastPlaybackPushMs = 0L
    private var fadeStep = 0
    private var isDucked = false
    private var pendingFadeIn = false
    private var isFadingIn = false

    private val fadeInRunnable = object : Runnable {
        override fun run() {
            if (!::player.isInitialized) {
                isFadingIn = false
                pendingFadeIn = false
                return
            }
            if (isDucked) {
                isFadingIn = false
                pendingFadeIn = false
                player.volume = 0.25f
                return
            }
            if (!player.isPlaying) {
                isFadingIn = false
                pendingFadeIn = false
                player.volume = 1.0f
                return
            }
            fadeStep++
            val targetVol = (fadeStep / 4f).coerceIn(0.25f, 1.0f)
            player.volume = targetVol
            if (fadeStep < 4) {
                tickHandler.postDelayed(this, 30L)
            } else {
                isFadingIn = false
                player.volume = 1.0f
            }
        }
    }

    private fun cancelFadeIn(restoreVolume: Boolean = true) {
        tickHandler.removeCallbacks(fadeInRunnable)
        isFadingIn = false
        pendingFadeIn = false
        if (restoreVolume && ::player.isInitialized) {
            player.volume = if (isDucked) 0.25f else 1.0f
        }
    }

    private fun startFadeIn() {
        tickHandler.removeCallbacks(fadeInRunnable)
        if (!::player.isInitialized) return
        if (isDucked) {
            isFadingIn = false
            pendingFadeIn = false
            player.volume = 0.25f
            return
        }
        if (!player.isPlaying) {
            pendingFadeIn = true
            isFadingIn = false
            player.volume = 1.0f
            return
        }
        pendingFadeIn = false
        isFadingIn = true
        fadeStep = 0
        player.volume = 0.25f
        tickHandler.postDelayed(fadeInRunnable, 30L)
    }

    private val tickRunnable = object : Runnable {
        override fun run() {
            if (!::player.isInitialized || !player.isPlaying) {
                isTicking = false
                return
            }
            if (!isDucked && !isFadingIn && player.volume < 0.99f) {
                player.volume = 1.0f
            }
            val posMs = player.currentPosition.coerceAtLeast(0L)
            lyricRouter.onPositionTick(posMs, true, lyricOffsetMs)

            val now = SystemClock.elapsedRealtime()
            if (now - lastPlaybackPushMs >= PLAYBACK_PUSH_INTERVAL_MS) {
                lastPlaybackPushMs = now
                pushPlaybackState()
            }
            tickHandler.postDelayed(this, TICK_INTERVAL_MS)
        }
    }

    private val becomingNoisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                pause()
            }
        }
    }

    private val audioFocusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                resumeOnFocusGain = false
                hasAudioFocus = false
                isDucked = false
                cancelFadeIn(restoreVolume = true)
                pause()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                resumeOnFocusGain = ::player.isInitialized && player.isPlaying
                isDucked = false
                cancelFadeIn(restoreVolume = true)
                pause()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                isDucked = true
                cancelFadeIn(restoreVolume = false)
                if (::player.isInitialized) {
                    player.volume = 0.25f
                }
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                hasAudioFocus = true
                isDucked = false
                cancelFadeIn(restoreVolume = true)
                if (::player.isInitialized) {
                    if (resumeOnFocusGain) {
                        resumeOnFocusGain = false
                        play()
                    }
                }
            }
        }
    }

    private val mediaSessionCallback = object : MediaSession.Callback() {
        override fun onPlay() {
            play()
        }

        override fun onPause() {
            pause()
        }

        override fun onSkipToNext() {
            next()
        }

        override fun onSkipToPrevious() {
            previous()
        }

        override fun onSeekTo(pos: Long) {
            seekTo(pos)
        }

        override fun onStop() {
            stopPlayback()
        }
    }

    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            updateMediaSessionPlaybackState()
            if (playbackState == Player.STATE_READY) {
                if (player.duration > 0L && player.duration != currentDurationMs) {
                    currentDurationMs = player.duration
                    updateMediaMetadata(lyricInfoJson = null)
                }
            } else if (playbackState == Player.STATE_ENDED) {
                stopTickLoop()
                lyricRouter.onPositionTick(
                    player.duration.coerceAtLeast(0L),
                    false,
                    lyricOffsetMs
                )
                pushPlaybackState()
                PlayerServiceBridge.sendAction("ended", emptyMap())
            }
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            updateMediaSessionPlaybackState()
            if (isPlaying) {
                if (pendingFadeIn && !isDucked) {
                    startFadeIn()
                } else if (!isDucked && !isFadingIn && ::player.isInitialized) {
                    player.volume = 1.0f
                }
                startTickLoop()
            } else {
                if (isFadingIn) {
                    cancelFadeIn(restoreVolume = true)
                }
                stopTickLoop()
                if (::player.isInitialized) {
                    lyricRouter.onPositionTick(
                        player.currentPosition.coerceAtLeast(0L),
                        false,
                        lyricOffsetMs
                    )
                }
            }
            pushPlaybackState()
            updateNotification(tickerText = null, onlyUpdate = true)
        }

        override fun onPlayerError(error: PlaybackException) {
            stopTickLoop()
            updateMediaSessionPlaybackState()
            pushPlaybackState()
            PlayerServiceBridge.sendAction(
                "error",
                mapOf("message" to (error.message ?: "Playback error"))
            )
        }
    }

    @OptIn(UnstableApi::class)
    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        createNotificationChannel()

        val media3AudioAttributes = androidx.media3.common.AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
            .build()

        val renderersFactory = object : DefaultRenderersFactory(this) {
            override fun buildAudioSink(
                context: Context,
                enableFloatOutput: Boolean,
                enableAudioTrackPlaybackParams: Boolean
            ): AudioSink {
                return DefaultAudioSink.Builder(context)
                    .setAudioProcessors(arrayOf(SodaEqAudioProcessor()))
                    .build()
            }
        }

        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(10_000)
            .setReadTimeoutMs(15_000)
            .setUserAgent("Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36")

        val dynamicHttpFactory = DataSource.Factory {
            val ds = httpFactory.createDataSource()
            val hdrs = currentTrackHeaders
            if (hdrs.isNotEmpty()) {
                for ((k, v) in hdrs) {
                    if (k.isNotBlank() && v.isNotBlank()) {
                        ds.setRequestProperty(k, v)
                    }
                }
            }
            ds
        }

        val mediaSourceFactory = DefaultMediaSourceFactory(
            DefaultDataSource.Factory(this, dynamicHttpFactory)
        )

        player = ExoPlayer.Builder(this, renderersFactory)
            .setMediaSourceFactory(mediaSourceFactory)
            .setAudioAttributes(media3AudioAttributes, false)
            .build()
        player.addListener(playerListener)

        mediaSession = MediaSession(this, "SodaPulseMediaSession").apply {
            setCallback(mediaSessionCallback)
            isActive = true
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val focusAttrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(focusAttrs)
                .setAcceptsDelayedFocusGain(true)
                .setOnAudioFocusChangeListener(audioFocusChangeListener)
                .build()
        }

        ContextCompat.registerReceiver(
            this,
            becomingNoisyReceiver,
            IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )

        lyricRouter = ColorOsLyricRouter(this)
        PlayerServiceBridge.service = this
        PlayerServiceBridge.lyricRouter = lyricRouter

        lyricRouter.overlaySink = object : ColorOsLyricRouter.OverlayLyricSink {
            override fun onOverlayLyric(
                line: NativeLyricLine?,
                lineIndex: Int,
                positionMs: Long,
                isPlaying: Boolean
            ) {
                if (line == null || line.text.isBlank()) {
                    KaraokeOverlayController.hide()
                    return
                }
                val words = line.words.map { w ->
                    WordSeg(text = w.text, startMs = w.startMs, endMs = w.endMs)
                }
                KaraokeOverlayController.updateLyric(
                    lineText = line.text,
                    translation = line.translation,
                    words = words,
                    positionMs = positionMs
                )
            }

            override fun onOverlayClear() {
                KaraokeOverlayController.hide()
            }
        }

        lyricRouter.onTickerLineChanged = { lineText, _ ->
            updateNotification(tickerText = lineText, onlyUpdate = true)
        }

        updateMediaSessionPlaybackState()
    }

    override fun onBind(intent: Intent?): IBinder = localBinder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PREV -> previous()
            ACTION_PLAY_PAUSE -> togglePlay()
            ACTION_NEXT -> next()
            ACTION_FAVORITE -> toggleFavoriteAction()
            ACTION_STOP -> stopPlayback()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        cancelFadeIn(restoreVolume = false)
        stopTickLoop()
        try {
            unregisterReceiver(becomingNoisyReceiver)
        } catch (_: Exception) {
        }
        abandonAudioFocus()
        lyricRouter.release()
        coverExecutor.shutdownNow()
        KaraokeOverlayController.hide()
        mediaSession.isActive = false
        mediaSession.release()
        player.removeListener(playerListener)
        player.release()
        if (PlayerServiceBridge.service === this) {
            PlayerServiceBridge.service = null
        }
        if (PlayerServiceBridge.lyricRouter === lyricRouter) {
            PlayerServiceBridge.lyricRouter = null
        }
        super.onDestroy()
    }

    fun loadAndPlay(args: Map<String, Any?>) {
        val trackMap = (args["track"] as? Map<*, *>) ?: args

        val id = (trackMap["id"] as? String) ?: trackMap["id"]?.toString() ?: ""
        val uriRaw = (trackMap["uri"] as? String)?.takeIf { it.isNotBlank() }
            ?: (trackMap["filePath"] as? String)?.takeIf { it.isNotBlank() }
            ?: ""
        val title = (trackMap["title"] as? String)?.takeIf { it.isNotBlank() } ?: "SodaPulse"
        val artist = (trackMap["artist"] as? String) ?: ""
        val album = (trackMap["album"] as? String) ?: ""
        val durationMs = (trackMap["durationMs"] as? Number)?.toLong() ?: 0L
        val coverUri = (trackMap["albumArtUri"] as? String)?.takeIf { it.isNotBlank() }
        val isFav = (trackMap["isFavorite"] as? Boolean) ?: false
        val rawHeaders = (args["headers"] as? Map<*, *>) ?: (trackMap["headers"] as? Map<*, *>)
        val parsedHeaders = mutableMapOf<String, String>()
        if (rawHeaders != null) {
            for ((k, v) in rawHeaders) {
                val ks = k?.toString()?.trim()
                val vs = v?.toString()?.trim()
                if (!ks.isNullOrEmpty() && !vs.isNullOrEmpty()) {
                    parsedHeaders[ks] = vs
                }
            }
        }
        currentTrackHeaders = parsedHeaders

        currentTrackId = id
        currentTitle = title
        currentArtist = artist
        currentAlbum = album
        currentDurationMs = durationMs
        currentCoverUri = coverUri
        currentFavorite = isFav
        coverBitmap = null
        lastLyricInfoJson = null

        if (coverUri != null) {
            val targetTrackId = id
            coverExecutor.execute {
                val bmp = LocalLibraryScanner.loadCoverBitmap(this, coverUri, 512)
                if (bmp != null) {
                    tickHandler.post {
                        if (currentTrackId == targetTrackId) {
                            coverBitmap = bmp
                            updateMediaMetadata(lyricInfoJson = null)
                            updateNotification(tickerText = null, onlyUpdate = true)
                        }
                    }
                }
            }
        }

        val mediaUri = resolveMediaUri(uriRaw)
        if (mediaUri != null) {
            isDucked = false
            cancelFadeIn(restoreVolume = true)
            pendingFadeIn = true
            player.volume = 1.0f
            player.setMediaItem(MediaItem.fromUri(mediaUri))
            player.prepare()
            requestAudioFocus()
            player.play()
        }

        updateMediaMetadata(lyricInfoJson = null)

        val lyricMap = args["lyricPayload"] as? Map<*, *>
        val payload = NativeLyricPayload.fromMap(lyricMap)
        if (payload != null) {
            lyricRouter.onTrackChanged(payload) { json ->
                tickHandler.post {
                    updateMediaMetadata(lyricInfoJson = json)
                }
            }
        } else {
            lyricRouter.clear()
        }

        val notification = buildNotification(tickerText = null, onlyUpdate = false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        updateMediaSessionPlaybackState()
        pushPlaybackState()
        publishLyricStatus()
    }

    fun setQueue(items: List<Map<String, Any?>>, index: Int) {
        val parsed = items.mapIndexed { idx, map ->
            val id = (map["id"] as? String) ?: map["id"]?.toString() ?: "item_$idx"
            val uri = (map["uri"] as? String)?.takeIf { it.isNotBlank() }
                ?: (map["filePath"] as? String)?.takeIf { it.isNotBlank() }
                ?: ""
            val title = (map["title"] as? String)?.takeIf { it.isNotBlank() } ?: "Unknown"
            val artist = (map["artist"] as? String) ?: ""
            val album = (map["album"] as? String) ?: ""
            val durationMs = (map["durationMs"] as? Number)?.toLong() ?: 0L
            QueueTrack(
                id = id,
                uri = uri,
                title = title,
                artist = artist,
                album = album,
                durationMs = durationMs
            )
        }
        queueTracks = parsed
        currentQueueIndex = if (parsed.isEmpty()) -1 else index.coerceIn(0, parsed.lastIndex)

        val sessionQueue = parsed.mapIndexed { idx, track ->
            val description = MediaDescription.Builder()
                .setMediaId(track.id)
                .setTitle(track.title)
                .setSubtitle(track.artist)
                .setDescription(track.album)
                .build()
            MediaSession.QueueItem(description, idx.toLong())
        }
        mediaSession.setQueue(sessionQueue)
    }

    fun play() {
        if (!::player.isInitialized) return
        isDucked = false
        cancelFadeIn(restoreVolume = true)
        requestAudioFocus()
        player.play()
        updateMediaSessionPlaybackState()
        updateNotification(tickerText = null, onlyUpdate = true)
    }

    fun pause() {
        if (!::player.isInitialized) return
        player.pause()
        updateMediaSessionPlaybackState()
        updateNotification(tickerText = null, onlyUpdate = true)
    }

    fun togglePlay() {
        if (!::player.isInitialized) return
        if (player.isPlaying) {
            pause()
        } else {
            play()
        }
    }

    fun seekTo(posMs: Long) {
        if (!::player.isInitialized) return
        val target = posMs.coerceAtLeast(0L)
        player.seekTo(target)
        updateMediaSessionPlaybackState()
        lyricRouter.onPositionTick(target, player.isPlaying, lyricOffsetMs)
        pushPlaybackState()
    }

    fun next() {
        PlayerServiceBridge.sendAction("next", emptyMap())
    }

    fun previous() {
        PlayerServiceBridge.sendAction("previous", emptyMap())
    }

    fun stopPlayback() {
        cancelFadeIn(restoreVolume = false)
        stopTickLoop()
        if (::player.isInitialized) {
            player.stop()
            player.clearMediaItems()
        }
        lyricRouter.clear()
        KaraokeOverlayController.hide()
        abandonAudioFocus()
        updateMediaSessionPlaybackState()
        pushPlaybackState()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    fun setLyricMode(mode: String) {
        lyricRouter.setModeFromWire(mode)
        publishLyricStatus()
    }

    fun setFavorite(favorite: Boolean) {
        if (currentFavorite != favorite) {
            currentFavorite = favorite
            updateNotification(tickerText = null, onlyUpdate = true)
        }
    }

    private fun toggleFavoriteAction() {
        currentFavorite = !currentFavorite
        updateNotification(tickerText = null, onlyUpdate = true)
        PlayerServiceBridge.sendAction("favorite", mapOf("trackId" to currentTrackId))
    }

    fun setPlaybackSpeed(speed: Float) {
        if (!::player.isInitialized) return
        val clamped = speed.coerceIn(0.5f, 2.0f)
        player.setPlaybackSpeed(clamped)
        updateMediaSessionPlaybackState()
        pushPlaybackState()
    }

    fun setLyricOffset(offsetMs: Long) {
        lyricOffsetMs = offsetMs
        if (::player.isInitialized) {
            lyricRouter.onPositionTick(
                player.currentPosition.coerceAtLeast(0L),
                player.isPlaying,
                lyricOffsetMs
            )
        }
    }

    fun setOverlayConfig(config: Map<String, Any?>) {
        val enabled = (config["enabled"] as? Boolean) ?: false
        val locked = (config["locked"] as? Boolean) ?: false
        val fontSizeSp = (config["fontSizeSp"] as? Number)?.toFloat() ?: 20f
        val yOffsetPx = (config["yOffsetPx"] as? Number)?.toInt() ?: 120
        KaraokeOverlayController.configure(this, enabled, locked, fontSizeSp, yOffsetPx)
    }

    fun getMediaSessionToken(): MediaSession.Token = mediaSession.sessionToken

    fun getQueueMediaItems(): List<MediaBrowser.MediaItem> {
        return queueTracks.map { track ->
            val extras = Bundle().apply {
                putString("uri", track.uri)
                putString("album", track.album)
                putLong("durationMs", track.durationMs)
            }
            val description = MediaDescription.Builder()
                .setMediaId(track.id)
                .setTitle(track.title)
                .setSubtitle(track.artist)
                .setDescription(track.album)
                .setExtras(extras)
                .build()
            MediaBrowser.MediaItem(description, MediaBrowser.MediaItem.FLAG_PLAYABLE)
        }
    }

    private fun resolveMediaUri(uriRaw: String): Uri? {
        if (uriRaw.isBlank()) return null
        return if (uriRaw.startsWith("/")) {
            Uri.fromFile(File(uriRaw))
        } else {
            Uri.parse(uriRaw)
        }
    }

    private fun requestAudioFocus(): Boolean {
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = audioFocusRequest ?: return false
            audioManager.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                audioFocusChangeListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN
            )
        }
        hasAudioFocus = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return hasAudioFocus
    }

    private fun abandonAudioFocus() {
        hasAudioFocus = false
        resumeOnFocusGain = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(audioFocusChangeListener)
        }
    }

    private fun updateMediaMetadata(lyricInfoJson: String?) {
        val duration = if (::player.isInitialized && player.duration > 0L) {
            player.duration
        } else {
            currentDurationMs
        }
        val builder = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_MEDIA_ID, currentTrackId)
            .putString(MediaMetadata.METADATA_KEY_TITLE, currentTitle)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, currentArtist)
            .putString(MediaMetadata.METADATA_KEY_ALBUM, currentAlbum)

        if (duration > 0L) {
            builder.putLong(MediaMetadata.METADATA_KEY_DURATION, duration)
        }
        coverBitmap?.let { bmp ->
            builder.putBitmap(MediaMetadata.METADATA_KEY_ART, bmp)
            builder.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, bmp)
            builder.putBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON, bmp)
        }
        if (!lyricInfoJson.isNullOrBlank()) {
            lastLyricInfoJson = lyricInfoJson
        }
        val effectiveLyricJson = lastLyricInfoJson
        if (!effectiveLyricJson.isNullOrBlank()) {
            try {
                builder.putString("lyricInfo", effectiveLyricJson)
            } catch (_: Exception) {
            }
        }
        mediaSession.setMetadata(builder.build())
    }

    private fun updateMediaSessionPlaybackState() {
        val pos = if (::player.isInitialized) player.currentPosition.coerceAtLeast(0L) else 0L
        val isPlaying = ::player.isInitialized && player.isPlaying
        val state = when {
            !::player.isInitialized -> PlaybackState.STATE_NONE
            player.playerError != null -> PlaybackState.STATE_ERROR
            player.playbackState == Player.STATE_BUFFERING -> PlaybackState.STATE_BUFFERING
            isPlaying -> PlaybackState.STATE_PLAYING
            player.playbackState == Player.STATE_READY -> PlaybackState.STATE_PAUSED
            player.playbackState == Player.STATE_ENDED ||
                player.playbackState == Player.STATE_IDLE -> PlaybackState.STATE_STOPPED
            else -> PlaybackState.STATE_NONE
        }

        val actions = PlaybackState.ACTION_PLAY or
            PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or
            PlaybackState.ACTION_SKIP_TO_NEXT or
            PlaybackState.ACTION_SKIP_TO_PREVIOUS or
            PlaybackState.ACTION_SEEK_TO or
            PlaybackState.ACTION_STOP

        val playbackState = PlaybackState.Builder()
            .setActions(actions)
            .setState(state, pos, if (isPlaying) 1.0f else 0.0f, SystemClock.elapsedRealtime())
            .build()

        mediaSession.setPlaybackState(playbackState)
    }

    private fun startTickLoop() {
        if (isTicking) return
        isTicking = true
        lastPlaybackPushMs = 0L
        tickHandler.removeCallbacks(tickRunnable)
        tickHandler.post(tickRunnable)
    }

    private fun stopTickLoop() {
        isTicking = false
        tickHandler.removeCallbacks(tickRunnable)
    }

    private fun pushPlaybackState() {
        if (!::player.isInitialized) return
        val duration = if (player.duration > 0L) player.duration else currentDurationMs
        PlayerServiceBridge.sendPlayback(
            mapOf(
                "trackId" to currentTrackId,
                "positionMs" to player.currentPosition.coerceAtLeast(0L),
                "durationMs" to duration.coerceAtLeast(0L),
                "isPlaying" to player.isPlaying,
                "playbackState" to player.playbackState,
                "queueIndex" to currentQueueIndex
            )
        )
    }

    private fun publishLyricStatus() {
        val snapshot = lyricRouter.queryStatusSnapshot()
        PlayerServiceBridge.sendLyricStatus(
            mapOf(
                "superLyricStatus" to snapshot.status,
                "superLyricVersion" to snapshot.serverApiVersion,
                "selectedMode" to snapshot.selectedMode.wireName,
                "activeMode" to snapshot.resolvedMode.wireName,
                "lastPublishResult" to snapshot.lastPublishResult
            )
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun buildServicePendingIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, PlaybackService::class.java).apply {
            this.action = action
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getService(this, requestCode, intent, flags)
    }

    private fun buildContentPendingIntent(): PendingIntent? {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        launchIntent.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(this, 0, launchIntent, flags)
    }

    private fun buildNotification(tickerText: String?, onlyUpdate: Boolean): Notification {
        val isPlaying = ::player.isInitialized && player.isPlaying

        val prevAction = Notification.Action.Builder(
            Icon.createWithResource(this, R.drawable.ic_noti_prev),
            "Previous",
            buildServicePendingIntent(ACTION_PREV, 1)
        ).build()

        val playPauseAction = Notification.Action.Builder(
            Icon.createWithResource(
                this,
                if (isPlaying) R.drawable.ic_noti_pause else R.drawable.ic_noti_play
            ),
            if (isPlaying) "Pause" else "Play",
            buildServicePendingIntent(ACTION_PLAY_PAUSE, 2)
        ).build()

        val nextAction = Notification.Action.Builder(
            Icon.createWithResource(this, R.drawable.ic_noti_next),
            "Next",
            buildServicePendingIntent(ACTION_NEXT, 3)
        ).build()

        val favAction = Notification.Action.Builder(
            Icon.createWithResource(
                this,
                if (currentFavorite) R.drawable.ic_noti_heart_filled else R.drawable.ic_noti_heart_outline
            ),
            "Favorite",
            buildServicePendingIntent(ACTION_FAVORITE, 4)
        ).build()

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setSmallIcon(R.drawable.ic_noti_music)
            .setContentTitle(currentTitle)
            .setContentText(currentArtist)
            .setOngoing(isPlaying)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(prevAction)
            .addAction(playPauseAction)
            .addAction(nextAction)
            .addAction(favAction)
            .setStyle(
                Notification.MediaStyle()
                    .setMediaSession(mediaSession.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )

        coverBitmap?.let { builder.setLargeIcon(it) }

        if (currentAlbum.isNotBlank()) {
            builder.setSubText(currentAlbum)
        }
        buildContentPendingIntent()?.let { builder.setContentIntent(it) }
        if (!tickerText.isNullOrBlank()) {
            builder.setTicker(tickerText)
        }

        val notification = builder.build()
        ColorOsLyricRouter.applyTickerFlags(notification, onlyUpdate)
        return notification
    }

    private fun updateNotification(tickerText: String?, onlyUpdate: Boolean) {
        val notification = buildNotification(tickerText = tickerText, onlyUpdate = onlyUpdate)
        notificationManager.notify(NOTIFICATION_ID, notification)
    }
}
