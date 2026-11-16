package com.myvidhub.myvidhub

import java.util.Locale

internal fun isDolbyVisionFormat(mime: String?, codecs: String?): Boolean {
    if (mime.equals("video/dolby-vision", ignoreCase = true)) return true
    return codecs?.lowercase(Locale.ROOT)?.split(',')?.any {
        val codec = it.trim()
        codec.startsWith("dvhe.") || codec.startsWith("dvh1.") ||
            codec.startsWith("dvav.") || codec.startsWith("dva1.")
    } == true
}
