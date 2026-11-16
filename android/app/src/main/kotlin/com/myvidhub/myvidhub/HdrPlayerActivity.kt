package com.myvidhub.myvidhub

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.Display
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.Toast
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import java.io.File
import java.util.Locale

@UnstableApi
class HdrPlayerActivity : Activity() {
    private var player: ExoPlayer? = null
    private var resumePlayback = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            )

        val url = intent.getStringExtra("url")
        if (url.isNullOrBlank()) {
            finish()
            return
        }

        val header = intent.getStringExtra("header")
        val http = DefaultHttpDataSource.Factory().setAllowCrossProtocolRedirects(true)
        if (!header.isNullOrBlank()) {
            val separator = header.indexOf(':')
            if (separator > 0) {
                http.setDefaultRequestProperties(
                    mapOf(header.substring(0, separator).trim() to header.substring(separator + 1).trim())
                )
            }
        }
        val sourceFactory = DefaultMediaSourceFactory(DefaultDataSource.Factory(this, http))
        val playback = ExoPlayer.Builder(this).setMediaSourceFactory(sourceFactory).build()
        player = playback

        val videoView = PlayerView(this).apply {
            player = playback
            setShowSubtitleButton(true)
            setShowNextButton(false)
            setShowPreviousButton(false)
            keepScreenOn = true
        }
        val close = ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            contentDescription = "返回"
            setBackgroundColor(0x66000000)
            setOnClickListener { finish() }
        }
        val root = FrameLayout(this).apply {
            setBackgroundColor(android.graphics.Color.BLACK)
            addView(videoView, FrameLayout.LayoutParams(-1, -1))
            val size = (48 * resources.displayMetrics.density).toInt()
            addView(close, FrameLayout.LayoutParams(size, size, Gravity.TOP or Gravity.START))
        }
        setContentView(root)

        playback.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                Toast.makeText(
                    this@HdrPlayerActivity,
                    "无法播放此视频：设备可能不支持该格式或杜比视界配置",
                    Toast.LENGTH_LONG
                ).show()
            }
        })
        val subtitles = intent.getStringArrayListExtra("subtitles").orEmpty().mapNotNull { path ->
            val uri = mediaUri(path)
            val mime = when (uri.lastPathSegment?.substringAfterLast('.', "")?.lowercase(Locale.ROOT)) {
                "srt" -> MimeTypes.APPLICATION_SUBRIP
                "vtt" -> MimeTypes.TEXT_VTT
                "ttml", "xml" -> MimeTypes.APPLICATION_TTML
                else -> null
            } ?: return@mapNotNull null
            MediaItem.SubtitleConfiguration.Builder(uri).setMimeType(mime).build()
        }
        playback.setMediaItem(
            MediaItem.Builder()
                .setUri(mediaUri(url))
                .setSubtitleConfigurations(subtitles)
                .build()
        )
        playback.seekTo(intent.getLongExtra("position", 0).coerceAtLeast(0))
        playback.prepare()
        playback.play()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            @Suppress("DEPRECATION")
            val hdrTypes = windowManager.defaultDisplay.hdrCapabilities?.supportedHdrTypes ?: intArrayOf()
            if (!hdrTypes.contains(Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION)) {
                Toast.makeText(this, "屏幕未报告杜比视界支持，画质取决于设备和片源", Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun mediaUri(value: String): Uri =
        if (value.startsWith("/")) Uri.fromFile(File(value)) else Uri.parse(value)

    override fun onStop() {
        super.onStop()
        resumePlayback = player?.isPlaying == true
        player?.pause()
    }

    override fun onStart() {
        super.onStart()
        if (resumePlayback) player?.play()
        resumePlayback = false
    }

    override fun finish() {
        player?.let {
            val duration = it.duration.takeIf { value -> value != C.TIME_UNSET && value > 0 } ?: 0
            setResult(
                RESULT_OK,
                Intent()
                    .putExtra("position", it.currentPosition)
                    .putExtra("duration", duration)
                    .putExtra("finished", it.playbackState == Player.STATE_ENDED)
            )
        }
        super.finish()
    }

    override fun onDestroy() {
        player?.release()
        player = null
        super.onDestroy()
    }
}
