package app.oxplayer.composables.dialogs

import SubtitleTrack
import androidx.annotation.OptIn
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.unit.dp
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import android.os.Handler
import android.os.Looper
import app.oxplayer.messengers.properlySetSubAndAudioTracks
import app.oxplayer.objects.Localized
import app.oxplayer.objects.Translate
import app.oxplayer.objects.VideoPlayerObject
import app.oxplayer.utility.InternalTrack
import app.oxplayer.utility.clearSubtitleTrack
import app.oxplayer.utility.setInternalSubtitleTrack

/** Server sent a real subtitle list (more than a lone Off row). */
private fun hasUsableServerSubtitleList(server: List<SubtitleTrack>): Boolean =
    server.isNotEmpty() && (server.size > 1 || server.any { it.index != -1L })

/** Off + one row per muxed Exo text track; indices -1, 1..n match [properlySetSubAndAudioTracks] list layout. */
private fun muxedFallbackSubtitleRows(internal: List<InternalTrack>): List<SubtitleTrack> {
    if (internal.isEmpty()) return emptyList()
    val off = SubtitleTrack(
        name = "Off",
        languageCode = "",
        codec = "",
        index = -1L,
        external = false,
        url = null,
    )
    return listOf(off) + internal.mapIndexed { i, t ->
        SubtitleTrack(
            name = t.label.ifBlank { "Subtitle ${i + 1}" },
            languageCode = t.language.orEmpty(),
            codec = t.codec.orEmpty(),
            index = (i + 1).toLong(),
            external = false,
            url = null,
        )
    }
}

@OptIn(UnstableApi::class)
@Composable
fun SubtitlePicker(
    player: ExoPlayer,
    onDismissRequest: () -> Unit,
) {
    val selectedIndex by VideoPlayerObject.currentSubtitleTrackIndex.collectAsState()
    val subTitles by VideoPlayerObject.subtitleTracks.collectAsState(emptyList())
    val internalSubTracks by VideoPlayerObject.exoSubTracks.collectAsState(emptyList())

    val effectiveSubTitles = remember(subTitles, internalSubTracks) {
        if (hasUsableServerSubtitleList(subTitles)) {
            subTitles
        } else {
            muxedFallbackSubtitleRows(internalSubTracks).ifEmpty { subTitles }
        }
    }

    LaunchedEffect(subTitles, internalSubTracks) {
        if (internalSubTracks.isEmpty()) return@LaunchedEffect
        if (hasUsableServerSubtitleList(subTitles)) return@LaunchedEffect
        val impl = VideoPlayerObject.implementation
        val cur = impl.playbackData.value ?: return@LaunchedEffect
        val built = muxedFallbackSubtitleRows(internalSubTracks)
        if (built.isEmpty() || cur.subtitleTracks == built) return@LaunchedEffect
        val prevDef = cur.defaultSubtrack
        // If Jellyfin default stream index does not exist on rebuilt mux rows (-1,1,2,…), keep
        // "subtitles on" by defaulting to the first real track (index 1), not Off.
        val newDef = when {
            built.any { it.index == prevDef } -> prevDef
            prevDef > 0 && built.size > 1 -> 1L
            else -> -1L
        }
        impl.playbackData.value = cur.copy(subtitleTracks = built, defaultSubtrack = newDef)
        VideoPlayerObject.setSubtitleTrackIndex(newDef.toInt(), init = true)
        val patched = impl.playbackData.value
        if (patched != null) {
            Handler(Looper.getMainLooper()).post {
                player.properlySetSubAndAudioTracks(patched)
            }
        }
    }

    if (effectiveSubTitles.isEmpty()) return

    val focusRequesters = remember(effectiveSubTitles) {
        effectiveSubTitles.associateWith { FocusRequester() }
    }

    val listState = rememberLazyListState()

    LaunchedEffect(selectedIndex, effectiveSubTitles) {
        val selectedSubIndex = effectiveSubTitles.indexOfFirst { it.index == selectedIndex.toLong() }

        if (selectedSubIndex in effectiveSubTitles.indices) {
            listState.scrollToItem(selectedSubIndex)
            focusRequesters[effectiveSubTitles[selectedSubIndex]]?.requestFocus()
        }
    }

    CustomModalBottomSheet(
        onDismissRequest,
        maxWidth = 600.dp,
    ) {
        LazyColumn(
            state = listState,
            modifier = Modifier
                .wrapContentWidth()
                .padding(horizontal = 8.dp, vertical = 16.dp),
        ) {
            effectiveSubTitles.forEachIndexed { index, serverSub ->
                val isOffTrack = index == 0
                val selected = serverSub.index == selectedIndex.toLong()

                item {
                    TrackButton(
                        modifier = Modifier
                            .fillMaxWidth()
                            .focusRequester(focusRequesters[serverSub]!!),
                        onClick = {
                            val serverList =
                                VideoPlayerObject.implementation.playbackData.value?.subtitleTracks.orEmpty()
                            val shouldSyncFlutter = serverList.isNotEmpty() &&
                                !(serverList.size == 1 && serverList[0].index == -1L)
                            if (isOffTrack) {
                                VideoPlayerObject.setSubtitleTrackIndex(-1, init = !shouldSyncFlutter)
                                player.clearSubtitleTrack()
                            } else {
                                val internalTrackIndex = index - 1

                                val internalSubTrack =
                                    internalSubTracks.elementAtOrNull(internalTrackIndex)

                                if (internalSubTrack != null) {
                                    VideoPlayerObject.setSubtitleTrackIndex(
                                        serverSub.index.toInt(),
                                        init = !shouldSyncFlutter,
                                    )
                                    player.clearSubtitleTrack()
                                    Handler(Looper.getMainLooper()).post {
                                        player.setInternalSubtitleTrack(internalSubTrack)
                                        Handler(Looper.getMainLooper()).post {
                                            player.setInternalSubtitleTrack(internalSubTrack)
                                        }
                                    }
                                }
                            }
                        },
                        selected = selected,
                    ) {
                        if (isOffTrack) {
                            Translate(Localized::off) {
                                Text(it)
                            }
                        } else {
                            Text(
                                text = serverSub.name,
                            )
                        }
                    }
                }
            }
        }
    }
}