package app.oxplayer.utility

import NativeMuxedAudioRow
import NativeMuxedSubtitleRow
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector

data class InternalTrack(
    val rendererIndex: Int,
    val groupIndex: Int,
    val trackIndex: Int,
    val label: String,
    val language: String? = null,
    val codec: String? = null,
)

@OptIn(UnstableApi::class)
fun ExoPlayer.getAudioTracks(): List<InternalTrack> {
    val selector = trackSelector as? DefaultTrackSelector ?: return emptyList()
    val mapped = selector.currentMappedTrackInfo ?: return emptyList()
    val result = mutableListOf<InternalTrack>()

    for (rendererIndex in 0 until mapped.rendererCount) {
        if (mapped.getRendererType(rendererIndex) != C.TRACK_TYPE_AUDIO) continue

        val groups = mapped.getTrackGroups(rendererIndex)
        for (groupIndex in 0 until groups.length) {
            val group = groups[groupIndex]
            for (trackIndex in 0 until group.length) {
                val format = group.getFormat(trackIndex)
                result.add(
                    InternalTrack(
                        rendererIndex = rendererIndex,
                        groupIndex = groupIndex,
                        trackIndex = trackIndex,
                        label = format.label ?: format.language ?: "Audiotrack: $trackIndex",
                        language = format.language,
                        codec = format.sampleMimeType ?: format.codecs,
                    )
                )
            }
        }
    }
    return result
}

@OptIn(UnstableApi::class)
fun ExoPlayer.setInternalAudioTrack(audioTrack: InternalTrack) {
    try {
        val selector = trackSelector as? DefaultTrackSelector ?: return
        val mapped = selector.currentMappedTrackInfo ?: return
        val groups = mapped.getTrackGroups(audioTrack.rendererIndex)
        if (audioTrack.groupIndex >= groups.length) return

        val group = groups[audioTrack.groupIndex]
        val override = TrackSelectionOverride(group, audioTrack.trackIndex)

        selector.setParameters(
            selector.buildUponParameters()
                .setRendererDisabled(audioTrack.rendererIndex, false)
                .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                .build()
        )

        this.trackSelectionParameters = this.trackSelectionParameters
            .buildUpon()
            .setOverrideForType(override)
            .build()
    } catch (e: Exception) {
        e.printStackTrace()
    }
}

@OptIn(UnstableApi::class)
fun ExoPlayer.clearAudioTrack(disable: Boolean = true) {
    val selector = trackSelector as? DefaultTrackSelector ?: return
    selector.setParameters(
        selector.buildUponParameters()
            .setRendererDisabled(C.TRACK_TYPE_AUDIO, disable)
            .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, disable)
            .build()
    )

    this.trackSelectionParameters = selector.parameters.buildUpon()
        .build()
}

@OptIn(UnstableApi::class)
fun ExoPlayer.getSubtitleTracks(): List<InternalTrack> {
    val selector = trackSelector as? DefaultTrackSelector ?: return emptyList()
    val mapped = selector.currentMappedTrackInfo ?: return emptyList()
    val result = mutableListOf<InternalTrack>()

    for (rendererIndex in 0 until mapped.rendererCount) {
        if (mapped.getRendererType(rendererIndex) != C.TRACK_TYPE_TEXT) continue

        val groups = mapped.getTrackGroups(rendererIndex)
        for (groupIndex in 0 until groups.length) {
            val group = groups[groupIndex]
            for (trackIndex in 0 until group.length) {
                val format = group.getFormat(trackIndex)
                result.add(
                    InternalTrack(
                        rendererIndex = rendererIndex,
                        groupIndex = groupIndex,
                        trackIndex = trackIndex,
                        label = format.label ?: format.language ?: "Subtitletrack: $trackIndex",
                        language = format.language,
                        codec = format.sampleMimeType ?: format.codecs,
                    )
                )
            }
        }
    }
    return result
}

@OptIn(UnstableApi::class)
fun ExoPlayer.clearSubtitleTrack() {
    val selector = trackSelector as? DefaultTrackSelector ?: return
    val newParams = selector.buildUponParameters()
        .setRendererDisabled(C.TRACK_TYPE_TEXT, false)
        .setPreferredTextLanguage(null)
        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
        .build()
    selector.setParameters(newParams)

    this.trackSelectionParameters = selector.parameters.buildUpon()
        .build()
}

@OptIn(UnstableApi::class)
fun ExoPlayer.enableSubtitles(language: String? = null) {
    val selector = trackSelector as? DefaultTrackSelector ?: return
    val newParams = selector.buildUponParameters()
        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
        .setPreferredTextLanguage(language)
        .build()
    selector.setParameters(newParams)

    this.trackSelectionParameters = selector.parameters.buildUpon()
        .build()
}


@OptIn(UnstableApi::class)
fun ExoPlayer.setInternalSubtitleTrack(subtitleTrack: InternalTrack) {
    try {
        enableSubtitles()
        val selector = trackSelector as? DefaultTrackSelector ?: return
        val mapped = selector.currentMappedTrackInfo ?: return
        val groups = mapped.getTrackGroups(subtitleTrack.rendererIndex)
        if (subtitleTrack.groupIndex >= groups.length) return

        val group = groups[subtitleTrack.groupIndex]
        val override = TrackSelectionOverride(group, subtitleTrack.trackIndex)

        selector.setParameters(
            selector.buildUponParameters()
                .setRendererDisabled(subtitleTrack.rendererIndex, false)
                .build()
        )

        // Clear text overrides first so the first selection after prepare always
        // triggers a fresh TextRenderer → SubtitleView bind (avoids "selected in UI
        // but invisible until user toggles track" on some Media3 builds).
        this.trackSelectionParameters = this.trackSelectionParameters
            .buildUpon()
            .clearOverridesOfType(C.TRACK_TYPE_TEXT)
            .setOverrideForType(override)
            .build()
    } catch (e: Exception) {
        e.printStackTrace()
    }
}

fun InternalTrack.toNativeMuxedAudioRow(): NativeMuxedAudioRow =
    NativeMuxedAudioRow(
        trackId = "${rendererIndex}:${groupIndex}:${trackIndex}",
        title = label,
        languageCode = language.orEmpty(),
        codec = codec.orEmpty(),
    )

fun InternalTrack.toNativeMuxedSubtitleRow(): NativeMuxedSubtitleRow =
    NativeMuxedSubtitleRow(
        trackId = "${rendererIndex}:${groupIndex}:${trackIndex}",
        title = label,
        languageCode = language.orEmpty(),
        codec = codec.orEmpty(),
    )
