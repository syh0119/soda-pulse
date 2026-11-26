package com.sodapulse.music

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class MediaActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_PREV = "com.sodapulse.music.ACTION_PREV"
        const val ACTION_PLAY_PAUSE = "com.sodapulse.music.ACTION_PLAY_PAUSE"
        const val ACTION_NEXT = "com.sodapulse.music.ACTION_NEXT"
        const val ACTION_STOP = "com.sodapulse.music.ACTION_STOP"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        val action = intent?.action ?: return
        val service = PlayerServiceBridge.service ?: return

        when (action) {
            ACTION_PREV -> service.previous()
            ACTION_PLAY_PAUSE -> service.togglePlay()
            ACTION_NEXT -> service.next()
            ACTION_STOP -> service.stopPlayback()
        }
    }
}
