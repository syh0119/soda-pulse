package com.sodapulse.music

import android.media.browse.MediaBrowser
import android.os.Bundle
import android.service.media.MediaBrowserService

class SodaBrowserService : MediaBrowserService() {

    companion object {
        private const val ROOT_ID = "root"
    }

    override fun onCreate() {
        super.onCreate()
        PlayerServiceBridge.service?.getMediaSessionToken()?.let { token ->
            sessionToken = token
        }
    }

    override fun onGetRoot(
        clientPackageName: String,
        clientUid: Int,
        rootHints: Bundle?
    ): BrowserRoot {
        if (sessionToken == null) {
            PlayerServiceBridge.service?.getMediaSessionToken()?.let { token ->
                sessionToken = token
            }
        }
        return BrowserRoot(ROOT_ID, null)
    }

    override fun onLoadChildren(
        parentId: String,
        result: Result<MutableList<MediaBrowser.MediaItem>>
    ) {
        if (parentId == ROOT_ID) {
            val items = PlayerServiceBridge.service?.getQueueMediaItems() ?: mutableListOf()
            result.sendResult(items)
        } else {
            result.sendResult(mutableListOf())
        }
    }
}
