package com.anitrack.app.ui.detail

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.view.MotionEvent
import android.view.ViewGroup
import kotlinx.coroutines.delay
import com.anitrack.app.ui.section.HeroBadge
import com.anitrack.app.ui.image.rememberArtTint
import com.anitrack.app.ui.chrome.LocalCanUseMaterial
import com.anitrack.app.ui.AutoSizeText
import com.anitrack.app.design.artEdge
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.LocalReduceMotion
import com.anitrack.app.design.ContinuousCornerShape
import androidx.compose.ui.unit.dp
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.blur
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.RepeatMode
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.graphics.Color
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxSize
import android.view.View
import android.webkit.WebChromeClient
import android.webkit.WebView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.viewinterop.AndroidView
import com.anitrack.app.design.PreviouslyIcons
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.ui.image.ArtMaxPixel
import com.anitrack.app.ui.image.RemoteImage
import com.anitrack.model.FranchiseVideo
import com.anitrack.model.copy.Copy
import android.webkit.JavascriptInterface
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.border
import androidx.compose.foundation.Image
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.foundation.layout.size
import com.anitrack.app.design.rememberSymbol
import com.anitrack.app.ui.control.materialGlyphBox
import com.anitrack.app.ui.state.IndeterminateArc

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
    <style>html,body{margin:0;padding:0;background:transparent;height:100%;overflow:hidden}iframe{position:absolute;inset:0;width:100%;height:100%;border:0;background:transparent}</style></head>
    <body><iframe src="${withJsApi(embedUrl)}" referrerpolicy="strict-origin-when-cross-origin" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen allowtransparency="true" playsinline></iframe>
    <script>
    (function(){
      var f=document.querySelector('iframe');
      function listen(){try{f.contentWindow.postMessage(JSON.stringify({event:'listening',id:'1',channel:'widget'}),'https://www.youtube.com');}catch(e){}}
      f.addEventListener('load',function(){listen();setTimeout(listen,400);setTimeout(listen,1200);setTimeout(listen,3000);});
      window.addEventListener('message',function(e){
        if(e.origin!=='https://www.youtube.com'||!window.Stage)return;
        var d;try{d=JSON.parse(e.data);}catch(x){return;}
        if(!d)return;
        var s=(d.event==='onStateChange')?d.info:(d.event==='infoDelivery'&&d.info)?d.info.playerState:undefined;
        if(s===1)Stage.playing();
        if(d.event==='onReady')Stage.ready();
        if(d.event==='onError')Stage.failed();
      });
    })();
    </script></body></html>
    """.trimIndent()

/**
 * The embed with the player's messages switched on: `enablejsapi` makes the iframe answer the
 * `listening` handshake above, and `origin` must be the wrapper page's own origin (the base URL's).
 */
internal fun withJsApi(embedUrl: String): String {
    if (embedUrl.contains("enablejsapi=")) return embedUrl
    val sep = if (embedUrl.contains('?')) '&' else '?'
    return "$embedUrl${sep}enablejsapi=1&origin=$TRAILER_ORIGIN"
}

private const val TRAILER_ORIGIN = "https://previously.local"

/**
 * The trailer STAGE.
 *
 * A trailer is a stage, not a sheet: the show's art blurred and slowly breathing across the whole
 * screen, a glow in the show's colour around the picture, the show's name in the billboard's lockup.
 * The picture is the trailer's still at the width of the screen with the provider's page over it,
 * autoplaying inline; the player's own fullscreen button works — the chrome client hands its view
 * to the stage ([fullscreenView]), which draws it over everything until the player gives it back.
 * Back dismisses. (iOS hands playback to the system's full-screen player the moment it starts;
 * Android has no such hand-off, so the picture plays where it is and fullscreen is the player's
 * own button.) The bottom sheet with a small embed at its top was "utter trash"; the brief was
 * "surreal according to 2026 standards. Immersive… absolute bliss to watch" (user, 4 Sep).
 *
 * A **new video is a new stage**, so the player is built once and nothing reloads — key the caller's
 * `if (video != null)` on the video itself and this holds.
 */
@Composable
fun VideoSheet(
    video: FranchiseVideo,
    showTitle: String,
    onDismiss: () -> Unit,
    /** The show's landscape art (else its poster): the ambient stage behind the picture. */
    ambientArt: String? = null,
) {
    val uriHandler = LocalUriHandler.current
    val watchUrl = video.watchUrl
    val kind = Copy.Video.kind(video.kind.wire)
    val subline = remember(video) {
        listOfNotNull(
            video.title?.takeIf { !it.equals(kind, ignoreCase = true) },
            video.partLabel,
        ).joinToString(" · ").ifEmpty { null }
    }
    val stageArt = ambientArt ?: video.thumbnailUrl
    val tint = rememberArtTint(stageArt)
    val glow = tint ?: ThemeColor.textPrimary
    // Exposure by palette (i3): a dark key art under the 0.22 veil photographed as black, and the
    // veil that lit it blew a bright one out.
    val artIsDark = tint?.let { oklabLightness(it) < STAGE_DARK_LIGHTNESS } ?: false
    val canBlur = LocalCanUseMaterial.current
    val reduceMotion = LocalReduceMotion.current
    var fullscreenView by remember { mutableStateOf<View?>(null) }

    // The still stays OVER the player until the player is actually playing: the embed paints
    // black while it buffers (ten seconds on the emulator, a beat on a phone), and the provider's
    // loading chrome is not the stage's. A refused autoplay uncovers the player after a patience
    // so its own play control can be pressed; an embed that never answers uncovers at a limit.
    var playerPlaying by remember { mutableStateOf(false) }
    var playerReady by remember { mutableStateOf(false) }
    var coverTimedOut by remember { mutableStateOf(false) }
    var waited by remember { mutableStateOf(false) }
    val covered = !playerPlaying && !coverTimedOut
    LaunchedEffect(playerReady) {
        if (playerReady) {
            delay(STAGE_COVER_PATIENCE_MS)
            coverTimedOut = true
        }
    }
    LaunchedEffect(Unit) {
        delay(STAGE_SPINNER_AFTER_MS)
        waited = true
        delay(STAGE_COVER_LIMIT_MS - STAGE_SPINNER_AFTER_MS)
        coverTimedOut = true
    }

    // The stage lights up a beat after it arrives, and the art breathes: one transform on one
    // blurred layer, 20 s out and back.
    var lit by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        delay(120)
        lit = true
    }
    val litAlpha by animateFloatAsState(
        targetValue = if (lit) 1f else 0f,
        animationSpec = tween(durationMillis = 900),
        label = "trailerStageLit",
    )
    val breath = rememberInfiniteTransition(label = "trailerStageBreath")
    val drift by breath.animateFloat(
        initialValue = 1.10f,
        targetValue = if (reduceMotion) 1.10f else 1.22f,
        animationSpec = infiniteRepeatable(tween(durationMillis = 20_000), RepeatMode.Reverse),
        label = "trailerStageDrift",
    )

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .background(Color.Black),
        ) {
            // The ambient stage: the show's art across the whole screen, blurred to light, dimmed
            // to a stage, breathing. Where there is no blur the art is dimmed harder instead.
            Box(
                Modifier
                    .fillMaxSize()
                    .graphicsLayer {
                        alpha = litAlpha
                        scaleX = drift
                        scaleY = drift
                    }
                    .then(if (canBlur) Modifier.blur(STAGE_BLUR) else Modifier),
            ) {
                RemoteImage(
                    url = stageArt,
                    modifier = Modifier.fillMaxSize(),
                    maxPixel = ArtMaxPixel.VIDEO_POSTER,
                    placeholder = false,
                )
                Box(
                    Modifier
                        .fillMaxSize()
                        // Lit, not buried (i1-F6): at 0.42 the ambient photographed as black.
                        .background(Color.Black.copy(alpha = if (!canBlur) 0.5f else if (artIsDark) 0.08f else 0.22f)),
                )
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(
                            Brush.verticalGradient(
                                0f to Color.Black.copy(alpha = 0.66f),
                                0.42f to Color.Black.copy(alpha = 0f),
                                0.62f to Color.Black.copy(alpha = 0.08f),
                                1f to Color.Black.copy(alpha = 0.84f),
                            ),
                        ),
                )
            }

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .statusBarsPadding(),
                horizontalAlignment = Alignment.Start,
            ) {
                // The billboard's lockup: what it is as the badge, the show as the title, the
                // video's own name and its season as one line.
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = LOCKUP_TOP)
                        .padding(horizontal = ThemeMetrics.gutter)
                        .graphicsLayer { alpha = litAlpha },
                    verticalArrangement = Arrangement.spacedBy(ThemeSpace.x2),
                ) {
                    HeroBadge(text = kind)
                    if (showTitle.isNotEmpty()) {
                        AutoSizeText(
                            text = showTitle,
                            style = ThemeType.displayXL.copy(color = ThemeColor.textPrimary),
                            minScale = 0.82f,
                            maxLines = 2,
                        )
                    }
                    if (subline != null) {
                        BasicText(
                            text = subline,
                            style = ThemeType.heroMeta.copy(color = ThemeColor.textSecondary),
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                Spacer(Modifier.weight(1f))
                // The picture, with a glow in the show's colour behind it: a tight halo and a
                // wide bloom, the way iOS draws two shadows.
                Box(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = ThemeSpace.x2),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier
                            .matchParentSize()
                            .graphicsLayer { scaleX = 1.35f; scaleY = 1.9f }
                            .background(
                                Brush.radialGradient(
                                    0f to glow.copy(alpha = 0.42f),
                                    0.55f to glow.copy(alpha = 0.16f),
                                    1f to Color.Transparent,
                                ),
                            ),
                    )
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .aspectRatio(ThemeMetrics.wideAspect)
                            .clip(ContinuousCornerShape(ThemeRadius.card))
                            .background(Color.Black)
                            .artEdge(ThemeRadius.card),
                    ) {
                        // The trailer's own still is the first frame; the provider's page
                        // (transparent until it paints) arrives over it.
                        RemoteImage(
                            url = video.thumbnailUrl,
                            modifier = Modifier.matchParentSize(),
                            maxPixel = ArtMaxPixel.VIDEO_POSTER,
                            placeholder = false,
                        )
                        val embed = video.embedUrl
                        if (embed != null) {
                            VideoEmbed(
                                embedUrl = embed,
                                modifier = Modifier.matchParentSize(),
                                onFullscreenView = { fullscreenView = it },
                                onPlaying = { playerPlaying = true },
                                onReady = { playerReady = true },
                                onFailed = { coverTimedOut = true },
                            )
                        }
                        // The cover: the still again, over the player, with the play disc that
                        // becomes a spinner once the wait is the only thing left to say.
                        androidx.compose.animation.AnimatedVisibility(
                            visible = covered && embed != null,
                            enter = androidx.compose.animation.EnterTransition.None,
                            exit = androidx.compose.animation.fadeOut(tween(durationMillis = 260)),
                            modifier = Modifier.matchParentSize(),
                        ) {
                            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                RemoteImage(
                                    url = video.thumbnailUrl,
                                    modifier = Modifier.matchParentSize(),
                                    maxPixel = ArtMaxPixel.VIDEO_POSTER,
                                    placeholder = false,
                                )
                                Box(
                                    Modifier
                                        .size(STAGE_PLAY_DISC)
                                        .background(ThemeColor.scrimStrong, CircleShape)
                                        .border(ThemeMetrics.hairline, ThemeColor.hairline, CircleShape),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    if (waited) {
                                        IndeterminateArc(
                                            tint = ThemeColor.textPrimary,
                                            diameter = STAGE_SPINNER,
                                            stroke = STAGE_SPINNER_STROKE,
                                            sweep = STAGE_SPINNER_SWEEP,
                                        )
                                    } else {
                                        Image(
                                            imageVector = rememberSymbol(PreviouslyIcons.PlayArrowFilled),
                                            contentDescription = null,
                                            modifier = Modifier
                                                .padding(start = STAGE_PLAY_NUDGE)
                                                .size(materialGlyphBox(STAGE_PLAY_GLYPH)),
                                            colorFilter = ColorFilter.tint(ThemeColor.textPrimary),
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                Spacer(Modifier.weight(1f))
                Spacer(Modifier.height(ThemeSpace.x6))
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .statusBarsPadding()
                    .padding(horizontal = ThemeSpace.x2, vertical = ThemeSpace.x1),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                BarGlyphButton(
                    symbol = PreviouslyIcons.Close,
                    label = Copy.Action.done,
                    glyph = DetailMetrics.barGlyph,
                    onClick = onDismiss,
                )
                Spacer(Modifier.weight(1f))
                if (watchUrl != null) {
                    // "Leaves the app" is `open_in_new` on Android, not SF's diagonal arrow —
                    // the Android reflex, settled by D29.
                    BarGlyphButton(
                        symbol = PreviouslyIcons.OpenInNew,
                        label = if (video.youtubeId != null) Copy.Action.openOnYouTube else Copy.Action.openInBrowser,
                        glyph = DetailMetrics.barGlyph,
                        onClick = { uriHandler.openUri(watchUrl) },
                    )
                }
            }
            val fullscreen = fullscreenView
            if (fullscreen != null) {
                AndroidView(
                    factory = { fullscreen },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
    }
}

private val STAGE_BLUR = 56.dp
private val LOCKUP_TOP = 64.dp

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
fun VideoEmbed(
    embedUrl: String,
    modifier: Modifier = Modifier,
    /** The player's own fullscreen view, when it asks for one; `null` when it gives it back. */
    onFullscreenView: (View?) -> Unit = {},
    /** The player has started playing (state 1): the cover comes off. */
    onPlaying: () -> Unit = {},
    /** The player is ready (autoplay may still be refused): the cover's patience starts here. */
    onReady: () -> Unit = {},
    /** The player reported an error: the cover comes off so its own message can be read. */
    onFailed: () -> Unit = {},
) {
    val html = remember(embedUrl) { trailerEmbedPage(embedUrl) }
    val playing by rememberUpdatedState(onPlaying)
    val ready by rememberUpdatedState(onReady)
    val failed by rememberUpdatedState(onFailed)
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
                // The player's state, through the wrapper page's listener (the IFrame API's own
                // handshake, no API script): the still over the picture waits on it.
                addJavascriptInterface(
                    StageBridge(this, onPlaying = { playing() }, onReady = { ready() }, onFailed = { failed() }),
                    "Stage",
                )
                // The chrome client is what makes the provider's fullscreen button work: it
                // hands the player's fullscreen view to the cover, which draws it over everything.
                webChromeClient = object : WebChromeClient() {
                    override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                        onFullscreenView(view)
                    }

                    override fun onHideCustomView() {
                        onFullscreenView(null)
                    }
                }
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

/** OKLab L under which the stage art is lit rather than veiled. */
private const val STAGE_DARK_LIGHTNESS = 0.34

/** The wrapper page's window.Stage: every call hops to the main thread before it touches state. */
private class StageBridge(
    private val host: View,
    private val onPlaying: () -> Unit,
    private val onReady: () -> Unit,
    private val onFailed: () -> Unit,
) {
    @JavascriptInterface
    fun playing() { host.post(onPlaying) }

    @JavascriptInterface
    fun ready() { host.post(onReady) }

    @JavascriptInterface
    fun failed() { host.post(onFailed) }
}

/** The stage's play disc: the trailer card's, at the picture's scale. */
private val STAGE_PLAY_DISC = 56.dp
private val STAGE_PLAY_GLYPH = 20.dp
private val STAGE_PLAY_NUDGE = 2.dp
private val STAGE_SPINNER = 22.dp
private val STAGE_SPINNER_STROKE = 2.dp
/** The refresh indicator's own arc. */
private const val STAGE_SPINNER_SWEEP = 280f

/** The still stays over the player this long after it is ready and has not started: a refused autoplay. */
private const val STAGE_COVER_PATIENCE_MS = 5_000L
/** …and this long from the stage's arrival whatever happens (an embed that never answers). */
private const val STAGE_COVER_LIMIT_MS = 14_000L
/** The play glyph becomes a spinner after this: the tap has been made; what is left is waiting. */
private const val STAGE_SPINNER_AFTER_MS = 900L
