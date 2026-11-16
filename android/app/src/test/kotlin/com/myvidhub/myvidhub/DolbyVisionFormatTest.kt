package com.myvidhub.myvidhub

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DolbyVisionFormatTest {
    @Test
    fun detectsDolbyVisionMimeAndCodecIdentifiers() {
        assertTrue(isDolbyVisionFormat("video/dolby-vision", null))
        assertTrue(isDolbyVisionFormat("video/hevc", "dvhe.08.06"))
        assertTrue(isDolbyVisionFormat(null, "mp4a.40.2, DVH1.05.06"))
        assertTrue(isDolbyVisionFormat(null, "dvav.09.01"))
        assertTrue(isDolbyVisionFormat(null, "dva1.09.01"))
    }

    @Test
    fun doesNotTreatOrdinaryVideoOrHdr10AsDolbyVision() {
        assertFalse(isDolbyVisionFormat("video/hevc", "hvc1.2.4.L153.B0"))
        assertFalse(isDolbyVisionFormat("video/avc", "avc1.640028"))
        assertFalse(isDolbyVisionFormat(null, null))
        assertFalse(isDolbyVisionFormat("video/hevc", "not-dvhe.08.06"))
    }
}
