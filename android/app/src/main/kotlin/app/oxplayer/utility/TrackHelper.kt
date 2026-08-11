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
    val builder = selector.buildUponParameters()
        .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, disable)
    if (disable) {
        builder.clearOverridesOfType(C.TRACK_TYPE_AUDIO)
    }
    selector.setParameters(builder.build())

    this.trackSelectionParameters = selector.parameters
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
fun ExoPlayer.isSubtitleTrackDisabled(): Boolean {
    val selector = trackSelector as? DefaultTrackSelector ?: return true
    return C.TRACK_TYPE_TEXT in selector.parameters.disabledTrackTypes
}

@OptIn(UnstableApi::class)
fun ExoPlayer.isInternalSubtitleTrackSelected(subtitleTrack: InternalTrack): Boolean {
    if (isSubtitleTrackDisabled()) return false
    val selector = trackSelector as? DefaultTrackSelector ?: return false
    val mapped = selector.currentMappedTrackInfo ?: return false
    if (subtitleTrack.rendererIndex >= mapped.rendererCount) return false
    val groups = mapped.getTrackGroups(subtitleTrack.rendererIndex)
    if (subtitleTrack.groupIndex >= groups.length) return false
    val group = groups[subtitleTrack.groupIndex]
    val override = selector.parameters.overrides[group] ?: return false
    return subtitleTrack.trackIndex in override.trackIndices
}

@OptIn(UnstableApi::class)
fun ExoPlayer.clearSubtitleTrack() {
    val selector = trackSelector as? DefaultTrackSelector ?: return
    val mapped = selector.currentMappedTrackInfo
    val params = this.trackSelectionParameters.buildUpon()
        .setPreferredTextLanguage(null)
        .setSelectUndeterminedTextLanguage(false)
        .clearOverridesOfType(C.TRACK_TYPE_TEXT)
        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)

    // Explicitly disable every mapped text group so ASS bitmap + text siblings both go off.
    if (mapped != null) {
        for (rendererIndex in 0 until mapped.rendererCount) {
            if (mapped.getRendererType(rendererIndex) != C.TRACK_TYPE_TEXT) continue
            val groups = mapped.getTrackGroups(rendererIndex)
            for (groupIndex in 0 until groups.length) {
                params.addOverride(TrackSelectionOverride(groups[groupIndex], emptyList()))
            }
        }
    }

    selector.setParameters(
        selector.buildUponParameters()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
            .setPreferredTextLanguage(null)
            .build()
    )
    this.trackSelectionParameters = params.build()
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
        val selector = trackSelector as? DefaultTrackSelector ?: return
        val mapped = selector.currentMappedTrackInfo ?: return
        if (subtitleTrack.rendererIndex >= mapped.rendererCount) return
        val wantedGroups = mapped.getTrackGroups(subtitleTrack.rendererIndex)
        if (subtitleTrack.groupIndex >= wantedGroups.length) return

        // Do not call enableSubtitles(preferredLanguage): preferred-language auto-select
        // re-enables sibling text groups alongside the explicit override.
        val params = this.trackSelectionParameters.buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
            .setPreferredTextLanguage(null)
            .setSelectUndeterminedTextLanguage(false)
            .clearOverridesOfType(C.TRACK_TYPE_TEXT)

        // One softsub only. ass-media LEGACY emits ASS as bitmap cues on one group while
        // Media3 may still default-select a parallel text/SSA group → small ASS + large
        // CaptionStyleCompat text both on SubtitleView until other groups are disabled.
        for (rendererIndex in 0 until mapped.rendererCount) {
            if (mapped.getRendererType(rendererIndex) != C.TRACK_TYPE_TEXT) continue
            val groups = mapped.getTrackGroups(rendererIndex)
            for (groupIndex in 0 until groups.length) {
                val group = groups[groupIndex]
                if (rendererIndex == subtitleTrack.rendererIndex &&
                    groupIndex == subtitleTrack.groupIndex
                ) {
                    params.addOverride(
                        TrackSelectionOverride(group, listOf(subtitleTrack.trackIndex)),
                    )
                } else {
                    params.addOverride(TrackSelectionOverride(group, emptyList()))
                }
            }
        }

        selector.setParameters(
            selector.buildUponParameters()
                .setRendererDisabled(subtitleTrack.rendererIndex, false)
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                .setPreferredTextLanguage(null)
                .build(),
        )
        this.trackSelectionParameters = params.build()
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
