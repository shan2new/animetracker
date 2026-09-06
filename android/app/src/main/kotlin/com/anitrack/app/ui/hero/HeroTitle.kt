package com.anitrack.app.ui.hero

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.ui.AutoSizeText
import com.anitrack.app.ui.image.RemoteImage
import com.anitrack.model.BillboardName
import androidx.compose.ui.text.style.TextAlign

/**
 * The billboard's NAME: the show's logo treatment — the catalogue's title image, Netflix's and
 * Disney+'s billboard grammar — where the gallery has one AND it can be drawn at the headline's mass
 * ([HeroLogo.box]), else the name set in type. The art under it is the textless poster where the
 * gallery has one, so the name is never on the screen twice in the same hand. Accessibility sizes
 * always set the name in type: a logo cannot grow with the reader's text. iOS `HeroTitle`.
 */
@Composable
fun HeroTitle(
    text: String,
    name: BillboardName,
    style: TextStyle,
    minScale: Float,
    maxLines: Int,
    isAX: Boolean,
    modifier: Modifier = Modifier,
) {
    val logo = (name as? BillboardName.Logo)?.image
    val w = logo?.width
    val h = logo?.height
    if (logo != null && w != null && h != null && w > 0 && h > 0 && !isAX) {
        val aspect = w.toFloat() / h.toFloat()
        BoxWithConstraints(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            val box = HeroLogo.box(aspect, maxWidth)
            if (box != null) {
                RemoteImage(
                    url = logo.url,
                    modifier = Modifier
                        // The optical gap a logo adds beneath itself — see [HeroLogo.bottomGap].
                        .padding(bottom = HeroLogo.bottomGap)
                        .width(box.first)
                        .height(box.second)
                        .semantics {
                            heading()
                            contentDescription = text
                        },
                    maxPixel = LOGO_MAX_PIXEL,
                    contentScale = ContentScale.Fit,
                    alignment = Alignment.Center,
                    placeholder = false,
                )
            } else {
                AutoSizeText(
                    text = text,
                    style = style.copy(textAlign = TextAlign.Center),
                    minScale = minScale,
                    maxLines = maxLines,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    } else {
        // The billboard's lockup is CENTRED (5 Sep).
        AutoSizeText(
            text = text,
            style = style.copy(textAlign = TextAlign.Center),
            minScale = minScale,
            maxLines = maxLines,
            modifier = modifier.fillMaxWidth(),
        )
    }
}

/**
 * The logo's box is the HEADLINE'S MASS (5 Sep, iOS `HeroTitle.logoBox`): within 88 % of the copy's
 * run and 96 dp, and only if it lands at least 45 % of the run wide and 32 dp tall — else the name
 * is set in type. The first rule was `min(78 % width, 84 dp × aspect)`, a box rather than a mass,
 * and the library's logos came out anywhere between 84×84 and 282×31 while a text title always had
 * one mass: TMDB's logo pool mixes circular series emblems (Slime, Demon Slayer) and stacked marks
 * (Solo Leveling) in with real title treatments, and the flagship's headline was an 84-dp sticker
 * under a badge wider than it ("poorly built and rushed", user). An emblem is not a title treatment
 * and a strip is not a headline; both set the name in type.
 */
object HeroLogo {
    // Settled by the placement spike (5 Sep, iOS `HeroTitle.logoBox`): within 88 % of the run and
    // 120 dp, EVERY logo, emblems included — the user liked the show's own logotype as the
    // headline and disliked only its placement.
    const val maxWidthFraction: Float = 0.88f
    val maxHeight: Dp = 120.dp

    /**
     * A text title's line box carries its own descender space; a logo's bounds are its ink, so the
     * line under it sat 3–4 dp off the artwork (Chainsaw Man, Black Clover, 5 Sep).
     */
    val bottomGap: Dp = 8.dp

    /** The size a logo of [aspect] is drawn at within a copy run of [copyWidth], or null. */
    fun box(aspect: Float, copyWidth: Dp): Pair<Dp, Dp>? {
        if (aspect <= 0f || copyWidth <= 0.dp) return null
        val w = minOf(copyWidth * maxWidthFraction, maxHeight * aspect)
        return w to w / aspect
    }
}

private const val LOGO_MAX_PIXEL = 1000
