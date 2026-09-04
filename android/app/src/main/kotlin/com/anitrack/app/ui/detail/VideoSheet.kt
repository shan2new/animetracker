package com.anitrack.app.ui.detail

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.view.MotionEvent
import android.view.ViewGroup
import android.webkit.WebChromeClient
import android.webkit.WebView
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicText
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.PreviouslyMaterialBridge
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.artEdge
import com.anitrack.app.design.rememberSymbol
import com.anitrack.app.ui.control.PressStyle
import com.anitrack.app.ui.control.TertiaryButton
import com.anitrack.app.ui.control.materialGlyphBox
import com.anitrack.app.ui.control.minimumTapTarget
import com.anitrack.app.ui.image.ArtMaxPixel
import com.anitrack.app.ui.image.RemoteImage
import com.anitrack.model.FranchiseVideo
import com.anitrack.model.copy.Copy

/*
 * THE TRAILER PLAYER — the port of `VideoSheet` / `VideoEmbed`
 * (ios/Sources/Features/FranchiseDetail/DetailEnrichment.swift).
 *
 * The whole of this file exists because of two documented provider failures, and both of them
 * reproduce **identically** on Android's WebView:
 *
 *   > The player is an `<iframe>` in a page of our own with a base URL, not the embed URL loaded
 *   > bare: YouTube refuses an embed that arrives with no referring origin ("Video player
 *   > configuration error", captured 3 Sep), and it refuses one that claims to BE youtube.com
 *   > ("This video is unavailable · 152-4", the next capture). A neutral origin of our own is what
 *   > a page embedding a video looks like from the provider's side.
 *
 * So: **do not** load the embed URL directly, and **do not** set the base URL to
 * `https://www.youtube.com`. The base URL must be a neutral origin the app owns
 * ([TRAILER_BASE_URL]), and the `referrerpolicy` must be `strict-origin-when-cross-origin` so
 * YouTube receives that origin.
 *
 * Where the provider cannot be embedded at all, the still stands in and the bar's `open_in_new`
 * glyph is the way out to it.
 */

/** The neutral origin the embed is served from. Ours, and resolvable by nobody — that is the point. */
const val TRAILER_BASE_URL = "https://previously.local/trailer"

/**
 * The wrapper page. Byte-for-byte the shipped one, including the `referrerpolicy`.
 *
 * `allow="autoplay; …"` plus `mediaPlaybackRequiresUserGesture = false` on the WebView are the two
 * halves of autoplay; either alone does nothing.
 */
internal fun trailerEmbedPage(embedUrl: String): String =
    """
    <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
    <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style></head>
    <body><iframe src="$embedUrl" referrerpolicy="strict-origin-when-cross-origin" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen playsinline></iframe></body></html>
    """.trimIndent()

/**
 * The player sheet.
 *
 * A **new video is a new sheet**, so the player is built once and nothing reloads — key the caller's
 * `if (video != null)` on the video itself and this holds.
 *
 * `skipPartiallyExpanded` is the port of "no detents are set": iOS gets a full-height system sheet,
 * and a half-height media player is not a state this design has.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VideoSheet(
    video: FranchiseVideo,
    showTitle: String,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val uriHandler = LocalUriHandler.current
    val watchUrl = video.watchUrl
    val meta = remember(video, showTitle) {
        listOfNotNull(
            showTitle.takeIf { it.isNotEmpty() },
            Copy.Video.kind(video.kind.wire),
            video.partLabel,
        ).joinToString(" · ")
    }

    PreviouslyMaterialBridge {
        ModalBottomSheet(
            onDismissRequest = onDismiss,
            sheetState = sheetState,
            containerColor = ThemeColor.canvas,
            scrimColor = ThemeColor.scrimStrong,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = ThemeMetrics.gutter)
                    .padding(top = ThemeSpace.x2, bottom = ThemeSpace.x6),
                verticalArrangement = Arrangement.spacedBy(ThemeMetrics.gutter),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (watchUrl != null) {
                        // "Leaves the app" is `open_in_new` on Android, not SF's diagonal arrow —
                        // the Android reflex, settled by D29.
                        val label = if (video.youtubeId != null) {
                            Copy.Action.openOnYouTube
                        } else {
                            Copy.Action.openInBrowser
                        }
                        Box(
                            Modifier
                                .size(minimumTapTarget)
                                .clickable(
                                    interactionSource = null,
                                    indication = PressStyle.tertiary,
                                    role = Role.Button,
                                    onClick = { uriHandler.openUri(watchUrl) },
                                )
                                .semantics(mergeDescendants = true) { contentDescription = label },
                            contentAlignment = Alignment.Center,
                        ) {
                            Image(
                                imageVector = rememberSymbol(PreviouslyIcons.OpenInNew),
                                contentDescription = null,
                                modifier = Modifier.size(materialGlyphBox(DetailMetrics.barGlyph)),
                                colorFilter = ColorFilter.tint(ThemeColor.interactive),
                            )
                        }
                    }
                    Spacer(Modifier.weight(1f))
                    TertiaryButton(label = Copy.Action.done, onClick = onDismiss)
                }

                Box(
                    Modifier
                        .fillMaxWidth()
                        .aspectRatio(ThemeMetrics.wideAspect)
                        .clip(ContinuousCornerShape(ThemeRadius.card))
                        .background(ThemeColor.surfaceFlat)
                        .artEdge(ThemeRadius.card),
                ) {
                    val embed = video.embedUrl
                    if (embed != null) {
                        VideoEmbed(embedUrl = embed, modifier = Modifier.matchParentSize())
                    } else {
                        // The provider cannot be embedded. The still stands in, and the bar's glyph
                        // is the way out to it.
                        RemoteImage(
                            url = video.thumbnailUrl,
                            modifier = Modifier.matchParentSize(),
                            maxPixel = ArtMaxPixel.VIDEO_POSTER,
                            placeholder = false,
                        )
                    }
                }

                Column(verticalArrangement = Arrangement.spacedBy(ThemeMetrics.titleGap)) {
                    BasicText(
                        text = video.displayTitle,
                        style = ThemeType.showTitleL.copy(color = ThemeColor.textPrimary),
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (meta.isNotEmpty()) {
                        BasicText(
                            text = meta,
                            style = ThemeType.metadata.copy(color = ThemeColor.textSecondary),
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
        }
    }
}

/**
 * The `WebView`, configured exactly as the shipped `WKWebView` is.
 *
 * The touch listener is the port of `scrollView.isScrollEnabled = false`: only `ACTION_MOVE` is
 * swallowed, so taps still reach the player's own controls. It consumes no down/up event, which is
 * why there is no `performClick` to call.
 *
 * The view is destroyed on release — a `WebView` that outlives its composition keeps a media session
 * and a decoder alive, and on this screen that means a trailer still playing behind a dismissed
 * sheet.
 */
@SuppressLint("SetJavaScriptEnabled", "ClickableViewAccessibility")
@Composable
fun VideoEmbed(embedUrl: String, modifier: Modifier = Modifier) {
    val html = remember(embedUrl) { trailerEmbedPage(embedUrl) }
    AndroidView(
        modifier = modifier,
        factory = { context ->
            WebView(context).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                )
                settings.javaScriptEnabled = true
                // The Android spelling of `mediaTypesRequiringUserActionForPlayback = []`.
                settings.mediaPlaybackRequiresUserGesture = false
                settings.domStorageEnabled = true
                isVerticalScrollBarEnabled = false
                isHorizontalScrollBarEnabled = false
                setOnTouchListener { _, event -> event.action == MotionEvent.ACTION_MOVE }
                setBackgroundColor(AndroidColor.TRANSPARENT)
                // Without a chrome client the provider's fullscreen button does nothing at all.
                webChromeClient = WebChromeClient()
                loadDataWithBaseURL(TRAILER_BASE_URL, html, "text/html", "utf-8", null)
            }
        },
        onRelease = { webView ->
            webView.stopLoading()
            webView.loadUrl("about:blank")
            webView.destroy()
        },
    )
}
