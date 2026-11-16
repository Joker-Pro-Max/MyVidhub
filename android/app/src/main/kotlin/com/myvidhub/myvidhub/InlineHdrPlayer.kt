package com.myvidhub.myvidhub

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MessageCodec
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.util.Locale

@UnstableApi
class InlineHdrPlayer(private val context: Context) : EventChannel.StreamHandler {
    private var player: ExoPlayer? = null
    private var view: PlayerView? = null
    private var sink: EventChannel.EventSink? = null
    private var resumeOnForeground = false
    private val handler = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            emit()
            if (player != null) handler.postDelayed(this, 500)
        }
    }

    val viewFactory = object : PlatformViewFactory(StandardMessageCodec.INSTANCE as MessageCodec<Any>) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
            val output = PlayerView(context).apply {
                useController = false
                keepScreenOn = true
                player = this@InlineHdrPlayer.player
            }
            view = output
            return object : PlatformView {
                override fun getView(): View = output
                override fun dispose() {
                    output.player = null
                    if (this@InlineHdrPlayer.view === output) this@InlineHdrPlayer.view = null
                }
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        emit()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "inlineOpen" -> open(call, result)
                "inlineClose" -> { close(); result.success(null) }
                "inlinePlay" -> { player?.play(); result.success(null) }
                "inlinePause" -> { player?.pause(); result.success(null) }
                "inlineSeek" -> { player?.seekTo((call.argument<Number>("position") ?: 0).toLong()); result.success(null) }
                "inlineRate" -> { player?.setPlaybackSpeed((call.argument<Number>("rate") ?: 1).toFloat()); result.success(null) }
                "inlineVolume" -> { player?.volume = ((call.argument<Number>("volume") ?: 100).toFloat() / 100).coerceIn(0f, 1f); result.success(null) }
                "inlineTrack" -> { selectTrack(call.argument<String>("type"), call.argument<String>("id")); result.success(null) }
                "inlineAspect" -> {
                    view?.resizeMode = when (call.argument<String>("mode")) {
                        "fill" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                        "stretch" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
                        else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
                    }
                    result.success(null)
                }
                "inlineSubtitleScale" -> {
                    val scale = (call.argument<Number>("scale") ?: 1).toFloat().coerceIn(0.5f, 2.5f)
                    view?.subtitleView?.setFractionalTextSize(0.0533f * scale)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("HDR", e.message, null)
        }
    }

    private fun open(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        if (url.isNullOrBlank()) {
            result.error("ARG", "缺少视频地址", null)
            return
        }
        close()
        val http = DefaultHttpDataSource.Factory().setAllowCrossProtocolRedirects(true)
        call.argument<String>("header")?.let { header ->
            val separator = header.indexOf(':')
            if (separator > 0) {
                http.setDefaultRequestProperties(
                    mapOf(header.substring(0, separator).trim() to header.substring(separator + 1).trim())
                )
            }
        }
        val source = DefaultMediaSourceFactory(DefaultDataSource.Factory(context, http))
        val playback = ExoPlayer.Builder(context).setMediaSourceFactory(source).build()
        player = playback
        view?.player = playback
        playback.addListener(object : Player.Listener {
            override fun onEvents(player: Player, events: Player.Events) = emit()
            override fun onPlayerError(error: PlaybackException) {
                sink?.success(mapOf("error" to "HDR 播放失败：${error.message ?: "设备可能不支持此格式"}"))
            }
        })
        val subtitles = call.argument<List<String>>("subtitles").orEmpty().mapNotNull { path ->
            val uri = mediaUri(path)
            val mime = when (uri.lastPathSegment?.substringAfterLast('.', "")?.lowercase(Locale.ROOT)) {
                "srt" -> MimeTypes.APPLICATION_SUBRIP
                "vtt" -> MimeTypes.TEXT_VTT
                "ttml", "xml" -> MimeTypes.APPLICATION_TTML
                else -> null
            } ?: return@mapNotNull null
            MediaItem.SubtitleConfiguration.Builder(uri).setMimeType(mime).build()
        }
        playback.setMediaItem(MediaItem.Builder().setUri(mediaUri(url)).setSubtitleConfigurations(subtitles).build())
        playback.seekTo((call.argument<Number>("position") ?: 0).toLong().coerceAtLeast(0))
        playback.volume = ((call.argument<Number>("volume") ?: 100).toFloat() / 100).coerceIn(0f, 1f)
        playback.setPlaybackSpeed((call.argument<Number>("rate") ?: 1).toFloat())
        playback.prepare()
        if (call.argument<Boolean>("playing") != false) playback.play()
        handler.post(tick)
        result.success(null)
    }

    private fun selectTrack(type: String?, id: String?) {
        val playback = player ?: return
        val trackType = if (type == "audio") C.TRACK_TYPE_AUDIO else C.TRACK_TYPE_TEXT
        val builder = playback.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(trackType)
            .setTrackTypeDisabled(trackType, id == "no")
        if (id != null && id != "no" && id != "auto") {
            val parts = id.split(':')
            val group = parts.getOrNull(0)?.toIntOrNull()?.let { playback.currentTracks.groups.getOrNull(it) }
            val index = parts.getOrNull(1)?.toIntOrNull()
            if (group != null && group.type == trackType && index != null && index in 0 until group.length) {
                builder.addOverride(TrackSelectionOverride(group.mediaTrackGroup, listOf(index)))
            }
        }
        playback.trackSelectionParameters = builder.build()
    }

    private fun emit() {
        val playback = player ?: return
        val tracks = mutableListOf<Map<String, Any?>>()
        playback.currentTracks.groups.forEachIndexed { groupIndex, group ->
            if (group.type != C.TRACK_TYPE_AUDIO && group.type != C.TRACK_TYPE_TEXT) return@forEachIndexed
            for (index in 0 until group.length) {
                if (!group.isTrackSupported(index)) continue
                val format = group.getTrackFormat(index)
                tracks.add(mapOf(
                    "id" to "$groupIndex:$index",
                    "type" to if (group.type == C.TRACK_TYPE_AUDIO) "audio" else "subtitle",
                    "title" to format.label,
                    "language" to format.language,
                    "codec" to format.sampleMimeType,
                    "channels" to format.channelCount.takeIf { it > 0 },
                    "selected" to group.isTrackSelected(index)
                ))
            }
        }
        val duration = playback.duration.takeIf { it != C.TIME_UNSET && it > 0 } ?: 0
        sink?.success(mapOf(
            "playing" to (playback.playWhenReady && playback.playbackState != Player.STATE_ENDED),
            "position" to playback.currentPosition.coerceAtLeast(0),
            "duration" to duration,
            "buffer" to playback.bufferedPosition.coerceAtLeast(0),
            "buffering" to (playback.playbackState == Player.STATE_BUFFERING),
            "completed" to (playback.playbackState == Player.STATE_ENDED),
            "volume" to (playback.volume * 100),
            "rate" to playback.playbackParameters.speed,
            "tracks" to tracks
        ))
    }

    fun close() {
        handler.removeCallbacks(tick)
        resumeOnForeground = false
        view?.player = null
        player?.release()
        player = null
    }

    fun onBackground() {
        resumeOnForeground = player?.playWhenReady == true
        player?.pause()
    }

    fun onForeground() {
        if (resumeOnForeground) player?.play()
        resumeOnForeground = false
    }

    private fun mediaUri(value: String): Uri =
        if (value.startsWith("/")) Uri.fromFile(File(value)) else Uri.parse(value)
}
