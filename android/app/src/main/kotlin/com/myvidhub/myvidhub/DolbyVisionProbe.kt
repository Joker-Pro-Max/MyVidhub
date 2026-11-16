package com.myvidhub.myvidhub

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import java.io.File

@UnstableApi
class DolbyVisionProbe(
    private val context: Context,
    private val url: String,
    private val header: String?,
    private val complete: (Boolean) -> Unit
) {
    private val handler = Handler(Looper.getMainLooper())
    private var player: ExoPlayer? = null
    private var finished = false
    private val timeout = Runnable { finish(false) }

    fun start() {
        try {
            val http = DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(8000)
                .setReadTimeoutMs(8000)
            if (!header.isNullOrBlank()) {
                val separator = header.indexOf(':')
                if (separator > 0) {
                    http.setDefaultRequestProperties(
                        mapOf(header.substring(0, separator).trim() to header.substring(separator + 1).trim())
                    )
                }
            }
            val source = DefaultMediaSourceFactory(DefaultDataSource.Factory(context, http))
            val probe = ExoPlayer.Builder(context).setMediaSourceFactory(source).build()
            player = probe
            probe.addListener(object : Player.Listener {
                override fun onTracksChanged(tracks: Tracks) {
                    val videoGroups = tracks.groups.filter { it.type == C.TRACK_TYPE_VIDEO }
                    if (videoGroups.isEmpty()) return
                    val selected = videoGroups.flatMap { group ->
                        (0 until group.length)
                            .filter { group.isTrackSelected(it) }
                            .map { group.getTrackFormat(it) }
                    }
                    if (selected.isEmpty()) return
                    finish(selected.any { isDolbyVisionFormat(it.sampleMimeType, it.codecs) })
                }

                override fun onPlayerError(error: PlaybackException) {
                    finish(false)
                }
            })
            val uri = if (url.startsWith("/")) Uri.fromFile(File(url)) else Uri.parse(url)
            probe.setMediaItem(MediaItem.fromUri(uri))
            handler.postDelayed(timeout, 10000)
            probe.prepare()
        } catch (_: Exception) {
            finish(false)
        }
    }

    fun finish(dolbyVision: Boolean = false) {
        if (finished) return
        finished = true
        handler.removeCallbacks(timeout)
        player?.release()
        player = null
        complete(dolbyVision)
    }
}
