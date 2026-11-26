package com.sodapulse.music

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object PlayerServiceBridge {
    @Volatile
    var service: PlaybackService? = null

    @Volatile
    var lyricRouter: ColorOsLyricRouter? = null

    @Volatile
    var eventSink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    fun sendPlayback(data: Map<String, Any?>) {
        emit("playback", data)
    }

    fun sendAction(action: String, extras: Map<String, Any?> = emptyMap()) {
        val payload = HashMap<String, Any?>(extras.size + 1)
        payload.putAll(extras)
        payload["action"] = action
        emit("action", payload)
    }

    fun sendLyricStatus(data: Map<String, Any?>) {
        emit("lyric_status", data)
    }

    private fun emit(type: String, data: Map<String, Any?>) {
        val sink = eventSink ?: return
        val event = mapOf(
            "type" to type,
            "data" to data
        )
        if (Looper.myLooper() == Looper.getMainLooper()) {
            try {
                sink.success(event)
            } catch (_: Exception) {
            }
        } else {
            mainHandler.post {
                try {
                    eventSink?.success(event)
                } catch (_: Exception) {
                }
            }
        }
    }
}
