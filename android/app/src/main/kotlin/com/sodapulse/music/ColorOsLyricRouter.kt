package com.sodapulse.music

import android.app.Notification
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.hchen.superlyricapi.Publisher
import com.hchen.superlyricapi.SuperLyric
import com.hchen.superlyricapi.model.Line
import com.hchen.superlyricapi.model.Lyric
import com.hchen.superlyricapi.model.Word
import org.json.JSONObject
import java.util.concurrent.Callable
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

enum class LyricMode(val wireName: String) {
    AUTO("auto"),
    LYRIC_INFO("lyric_info"),
    SUPER_LYRIC("super_lyric"),
    TICKER("ticker"),
    OVERLAY("overlay");

    companion object {
        @JvmStatic
        fun fromWire(value: String?): LyricMode {
            val normalized = value?.trim()?.lowercase()?.replace('-', '_') ?: return AUTO
            return entries.firstOrNull {
                it.wireName == normalized || it.name.lowercase() == normalized
            } ?: AUTO
        }
    }
}

data class NativeLyricWord(
    val text: String,
    val startMs: Long,
    val endMs: Long,
) {
    companion object {
        @JvmStatic
        fun fromMap(map: Map<*, *>?): NativeLyricWord? {
            if (map == null) return null
            val text = (map["text"] as? String).orEmpty()
            val startMs = asLong(map["startMs"], 0L)
            val endMs = asLong(map["endMs"], startMs)
            return NativeLyricWord(
                text = text,
                startMs = startMs,
                endMs = endMs,
            )
        }
    }
}

data class NativeLyricLine(
    val text: String,
    val startMs: Long,
    val endMs: Long,
    val translation: String? = null,
    val phonetic: String? = null,
    val words: List<NativeLyricWord> = emptyList(),
) {
    companion object {
        @JvmStatic
        fun fromMap(map: Map<*, *>?): NativeLyricLine? {
            if (map == null) return null
            val text = (map["text"] as? String).orEmpty()
            val startMs = asLong(map["startMs"], 0L)
            val endMs = asLong(map["endMs"], startMs)
            val translation = (map["translation"] as? String)?.takeIf { it.isNotBlank() }
            val phonetic = (map["phonetic"] as? String)?.takeIf { it.isNotBlank() }
            val rawWords = map["words"] as? List<*>
            val words = rawWords
                ?.mapNotNull { NativeLyricWord.fromMap(it as? Map<*, *>) }
                ?: emptyList()
            return NativeLyricLine(
                text = text,
                startMs = startMs,
                endMs = endMs,
                translation = translation,
                phonetic = phonetic,
                words = words,
            )
        }
    }
}

data class NativeLyricPayload(
    val songId: String,
    val songName: String,
    val artist: String,
    val album: String,
    val durationMs: Long,
    val lrcText: String,
    val rawLyric: String,
    val translation: String,
    val roma: String,
    val lines: List<NativeLyricLine>,
) {
    companion object {
        @JvmStatic
        fun fromMap(map: Map<*, *>?): NativeLyricPayload? {
            if (map == null) return null
            val rawLines = map["lines"] as? List<*>
            val lines = rawLines
                ?.mapNotNull { NativeLyricLine.fromMap(it as? Map<*, *>) }
                ?: emptyList()
            return NativeLyricPayload(
                songId = (map["songId"] as? String).orEmpty(),
                songName = (map["songName"] as? String).orEmpty(),
                artist = (map["artist"] as? String).orEmpty(),
                album = (map["album"] as? String).orEmpty(),
                durationMs = asLong(map["durationMs"], 0L),
                lrcText = (map["lrcText"] as? String).orEmpty(),
                rawLyric = (map["rawLyric"] as? String).orEmpty(),
                translation = (map["translation"] as? String).orEmpty(),
                roma = (map["roma"] as? String).orEmpty(),
                lines = lines,
            )
        }
    }
}

private fun asLong(value: Any?, defaultValue: Long): Long {
    return when (value) {
        is Number -> value.toLong()
        is String -> value.toLongOrNull() ?: defaultValue
        else -> defaultValue
    }
}

data class SuperLyricStatusSnapshot(
    val status: String,
    val serverApiVersion: Int,
    val selectedMode: LyricMode,
    val resolvedMode: LyricMode,
    val lastPublishResult: String,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "status" to status,
        "serverApiVersion" to serverApiVersion,
        "selectedMode" to selectedMode.wireName,
        "resolvedMode" to resolvedMode.wireName,
        "lastPublishResult" to lastPublishResult,
    )
}

class ColorOsLyricRouter(context: Context? = null) {

    interface OverlayLyricSink {
        fun onOverlayLyric(
            line: NativeLyricLine?,
            lineIndex: Int,
            positionMs: Long,
            isPlaying: Boolean,
        )

        fun onOverlayClear()
    }

    private val appContext: Context? = context?.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val workerThreadId = AtomicReference<Long?>(null)
    private val workerExecutor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(
            {
                workerThreadId.set(Thread.currentThread().id)
                runnable.run()
            },
            "ColorOsLyricRouter-Worker",
        ).apply {
            isDaemon = true
        }
    }
    private val released = AtomicBoolean(false)

    @Volatile
    var selectedMode: LyricMode = LyricMode.AUTO
        private set

    @Volatile
    private var cachedStatusName: String = "UNAVAILABLE"

    @Volatile
    private var cachedServerApiVersion: Int = -1

    @Volatile
    private var lastPublishResult: String = "IDLE"

    @Volatile
    private var activeResolvedMode: LyricMode = LyricMode.LYRIC_INFO

    @Volatile
    private var currentPayload: NativeLyricPayload? = null

    @Volatile
    private var sortedLines: List<NativeLyricLine> = emptyList()

    @Volatile
    private var lastTickerLineIndex: Int = -1

    @Volatile
    private var lastTickerText: String? = null

    var onTickerLineChanged: ((lineText: String, lineIndex: Int) -> Unit)? = null
    var onOverlayTick: ((line: NativeLyricLine?, lineIndex: Int, positionMs: Long, isPlaying: Boolean) -> Unit)? = null
    var overlaySink: OverlayLyricSink? = null

    fun setMode(mode: LyricMode) {
        selectedMode = mode
        activeResolvedMode = resolveActiveMode()
    }

    fun setModeFromWire(wire: String?) {
        setMode(LyricMode.fromWire(wire))
    }

    fun queryStatusSnapshot(): SuperLyricStatusSnapshot {
        refreshSuperLyricStatusSync()
        val resolved = resolveModeFromStatus(selectedMode, cachedStatusName)
        activeResolvedMode = resolved
        return SuperLyricStatusSnapshot(
            status = cachedStatusName,
            serverApiVersion = cachedServerApiVersion,
            selectedMode = selectedMode,
            resolvedMode = resolved,
            lastPublishResult = lastPublishResult,
        )
    }

    fun resolveActiveMode(): LyricMode {
        if (selectedMode != LyricMode.AUTO) {
            activeResolvedMode = selectedMode
            return selectedMode
        }
        refreshSuperLyricStatusSync()
        val resolved = resolveModeFromStatus(selectedMode, cachedStatusName)
        activeResolvedMode = resolved
        return resolved
    }

    fun onTrackChanged(
        payload: NativeLyricPayload,
        onLyricInfoReady: ((String) -> Unit)? = null,
    ) {
        currentPayload = payload
        sortedLines = payload.lines
            .map { line ->
                val start = line.startMs.coerceAtLeast(0L)
                val end = line.endMs.coerceAtLeast(start)
                val normalizedWords = line.words
                    .sortedBy { it.startMs }
                    .map { word ->
                        val wStart = word.startMs.coerceAtLeast(0L)
                        val wEnd = word.endMs.coerceAtLeast(wStart)
                        word.copy(startMs = wStart, endMs = wEnd)
                    }
                line.copy(
                    startMs = start,
                    endMs = end,
                    words = normalizedWords,
                )
            }
            .sortedBy { it.startMs }
        lastTickerLineIndex = -1
        lastTickerText = null

        if (released.get()) return

        workerExecutor.execute {
            refreshSuperLyricStatusOnWorker()
            val mode = resolveModeFromStatus(selectedMode, cachedStatusName)
            activeResolvedMode = mode

            when (mode) {
                LyricMode.SUPER_LYRIC -> {
                    val result = publishSuperLyricOnWorker(payload)
                    lastPublishResult = result
                    if (result == "EMPTY_LINES" && selectedMode == LyricMode.AUTO) {
                        val json = buildLyricInfoJson(payload)
                        dispatchLyricInfo(json, onLyricInfoReady)
                    }
                }

                LyricMode.LYRIC_INFO -> {
                    clearSuperLyricOnWorker()
                    val json = buildLyricInfoJson(payload)
                    lastPublishResult = "LYRIC_INFO_READY"
                    dispatchLyricInfo(json, onLyricInfoReady)
                }

                LyricMode.TICKER -> {
                    clearSuperLyricOnWorker()
                    lastPublishResult = "TICKER_READY"
                }

                LyricMode.OVERLAY -> {
                    clearSuperLyricOnWorker()
                    lastPublishResult = "OVERLAY_READY"
                }

                LyricMode.AUTO -> {
                    // Unreachable because resolveModeFromStatus resolves AUTO.
                    lastPublishResult = "AUTO_UNRESOLVED"
                }
            }
        }
    }

    fun onPositionTick(
        positionMs: Long,
        isPlaying: Boolean,
        offsetMs: Long = 0L,
    ) {
        val effectivePosMs = (positionMs + offsetMs).coerceAtLeast(0L)
        val lines = sortedLines
        val mode = activeResolvedMode

        when (mode) {
            LyricMode.TICKER -> {
                if (!isPlaying || lines.isEmpty()) {
                    if (lastTickerLineIndex != -1 || !lastTickerText.isNullOrEmpty()) {
                        lastTickerLineIndex = -1
                        lastTickerText = ""
                        onTickerLineChanged?.invoke("", -1)
                    }
                    return
                }
                val idx = findActiveLineIndex(lines, effectivePosMs)
                val text = if (idx >= 0) lines[idx].text else ""
                if (idx != lastTickerLineIndex || text != lastTickerText) {
                    lastTickerLineIndex = idx
                    lastTickerText = text
                    onTickerLineChanged?.invoke(text, idx)
                }
            }

            LyricMode.OVERLAY -> {
                val idx = if (lines.isNotEmpty()) findActiveLineIndex(lines, effectivePosMs) else -1
                val line = if (idx >= 0) lines[idx] else null
                overlaySink?.onOverlayLyric(line, idx, effectivePosMs, isPlaying)
                onOverlayTick?.invoke(line, idx, effectivePosMs, isPlaying)
            }

            else -> Unit
        }
    }

    fun clear() {
        currentPayload = null
        sortedLines = emptyList()
        if (lastTickerLineIndex != -1 || !lastTickerText.isNullOrEmpty()) {
            lastTickerLineIndex = -1
            lastTickerText = null
            onTickerLineChanged?.invoke("", -1)
        } else {
            lastTickerLineIndex = -1
            lastTickerText = null
        }
        overlaySink?.onOverlayClear()
        onOverlayTick?.invoke(null, -1, 0L, false)

        if (released.get()) return
        workerExecutor.execute {
            clearSuperLyricOnWorker()
            lastPublishResult = "CLEARED"
        }
    }

    fun buildLyricInfoJson(payload: NativeLyricPayload): String {
        val lyricText = payload.lrcText.ifBlank { payload.rawLyric }
        return JSONObject().apply {
            put("songName", payload.songName)
            put("artist", payload.artist)
            put("lyric", lyricText)
            put("songId", payload.songId)
            put("album", payload.album)
            put("rawLyric", payload.rawLyric)
            put("translation", payload.translation)
            put("roma", payload.roma)
        }.toString()
    }

    fun release() {
        if (released.compareAndSet(false, true)) {
            currentPayload = null
            sortedLines = emptyList()
            try {
                workerExecutor.execute { clearSuperLyricOnWorker() }
            } catch (_: Throwable) {
            }
            workerExecutor.shutdown()
        }
    }

    private fun refreshSuperLyricStatusSync() {
        if (released.get()) return
        if (Thread.currentThread().id == workerThreadId.get()) {
            refreshSuperLyricStatusOnWorker()
            return
        }
        try {
            workerExecutor.submit(
                Callable {
                    refreshSuperLyricStatusOnWorker()
                },
            ).get(STATUS_QUERY_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        } catch (t: Throwable) {
            Log.w(TAG, "refreshSuperLyricStatusSync failed: ${t.message}")
        }
    }

    private fun refreshSuperLyricStatusOnWorker() {
        try {
            val status = SuperLyric.status()
            cachedStatusName = status.name
        } catch (t: Throwable) {
            cachedStatusName = "UNAVAILABLE"
            Log.w(TAG, "SuperLyric.status() error: ${t.message}")
        }
        try {
            cachedServerApiVersion = SuperLyric.serverApiVersion()
        } catch (t: Throwable) {
            cachedServerApiVersion = -1
            Log.w(TAG, "SuperLyric.serverApiVersion() error: ${t.message}")
        }
    }

    private fun publishSuperLyricOnWorker(payload: NativeLyricPayload): String {
        val id = payload.songId.ifBlank { "track_${payload.songName.hashCode()}" }
        val title = payload.songName.ifBlank { "Unknown" }
        val duration = payload.durationMs.coerceAtLeast(0L)

        val builtLines = payload.lines
            .sortedBy { it.startMs }
            .map { line ->
                val start = line.startMs.coerceAtLeast(0L)
                val end = line.endMs.coerceAtLeast(start)
                val builtWords = line.words
                    .sortedBy { it.startMs }
                    .map { word ->
                        val wStart = word.startMs.coerceAtLeast(0L)
                        val wEnd = word.endMs.coerceAtLeast(wStart)
                        Word(
                            text = word.text,
                            start = wStart,
                            end = wEnd,
                        )
                    }
                Line(
                    text = line.text,
                    start = start,
                    end = end,
                    words = builtWords,
                    translation = line.translation?.takeIf { it.isNotBlank() },
                    phonetic = line.phonetic?.takeIf { it.isNotBlank() },
                )
            }

        if (builtLines.isEmpty()) {
            clearSuperLyricOnWorker()
            return "EMPTY_LINES"
        }

        return try {
            val doc = Lyric(
                id = id,
                title = title,
                artist = payload.artist,
                album = payload.album,
                duration = duration,
                lines = builtLines,
            )
            val publisher: Publisher = SuperLyric.publisher()
            val res = publisher.publish(doc)
            res.name
        } catch (t: Throwable) {
            Log.e(TAG, "SuperLyric publish failed: ${t.message}", t)
            "PUBLISH_ERROR:${t.javaClass.simpleName}"
        }
    }

    private fun clearSuperLyricOnWorker() {
        try {
            val publisher: Publisher = SuperLyric.publisher()
            publisher.clear()
        } catch (t: Throwable) {
            Log.w(TAG, "SuperLyric.publisher().clear() failed: ${t.message}")
        }
    }

    private fun resolveModeFromStatus(mode: LyricMode, statusName: String): LyricMode {
        if (mode != LyricMode.AUTO) return mode
        return if (isSuperLyricAvailable(statusName)) {
            LyricMode.SUPER_LYRIC
        } else {
            LyricMode.LYRIC_INFO
        }
    }

    private fun isSuperLyricAvailable(statusName: String): Boolean {
        return when (statusName.uppercase()) {
            "V5", "V4", "LEGACY" -> true
            "UNAVAILABLE", "DENIED" -> false
            else -> false
        }
    }

    private fun dispatchLyricInfo(
        json: String,
        onLyricInfoReady: ((String) -> Unit)?,
    ) {
        if (onLyricInfoReady == null) return
        if (Looper.myLooper() == Looper.getMainLooper()) {
            onLyricInfoReady.invoke(json)
        } else {
            mainHandler.post { onLyricInfoReady.invoke(json) }
        }
    }

    private fun findActiveLineIndex(
        lines: List<NativeLyricLine>,
        positionMs: Long,
    ): Int {
        if (lines.isEmpty()) return -1
        var low = 0
        var high = lines.lastIndex
        var candidate = -1
        while (low <= high) {
            val mid = (low + high) ushr 1
            if (lines[mid].startMs <= positionMs) {
                candidate = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        if (candidate < 0) return -1
        val line = lines[candidate]
        if (line.endMs > line.startMs && positionMs > line.endMs) {
            return -1
        }
        return candidate
    }

    companion object {
        private const val TAG = "ColorOsLyricRouter"
        private const val STATUS_QUERY_TIMEOUT_MS = 1000L

        const val FLAG_ALWAYS_SHOW_TICKER = 0x01000000
        const val FLAG_ONLY_UPDATE_TICKER = 0x02000000

        @JvmStatic
        fun applyTickerFlags(notification: Notification, onlyUpdate: Boolean) {
            notification.flags = notification.flags or FLAG_ALWAYS_SHOW_TICKER
            notification.flags = if (onlyUpdate) {
                notification.flags or FLAG_ONLY_UPDATE_TICKER
            } else {
                notification.flags and FLAG_ONLY_UPDATE_TICKER.inv()
            }
        }
    }
}
