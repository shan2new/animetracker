package com.anitrack.app.ui.auth

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.anitrack.app.BuildConfig
import com.anitrack.app.data.AppConfig
import com.anitrack.app.data.auth.AuthManager
import com.anitrack.app.design.AppFont
import com.anitrack.app.design.ContinuousCornerShape
import com.anitrack.app.design.MotionToken
import com.anitrack.app.design.SurfaceLevel
import com.anitrack.app.design.brand.BrandWord
import com.anitrack.app.design.brand.PreviouslyMark
import com.anitrack.app.design.ThemeColor
import com.anitrack.app.design.ThemeMetrics
import com.anitrack.app.design.ThemeRadius
import com.anitrack.app.design.ThemeSpace
import com.anitrack.app.design.ThemeType
import com.anitrack.app.design.motion
import com.anitrack.app.design.surface
import com.anitrack.app.ui.control.PrimaryButton
import com.anitrack.app.ui.control.minimumTapTarget
import com.anitrack.app.ui.isAccessibilityTextSize
import com.anitrack.app.ui.section.SectionLabel
import com.anitrack.app.ui.state.InlineNotice
import com.anitrack.model.copy.Copy
import com.clerk.api.ui.ClerkColors
import com.clerk.api.ui.ClerkDesign
import com.clerk.api.ui.ClerkTheme
import com.clerk.api.ui.ClerkTypography
import com.clerk.api.ui.ClerkTypographyDefaults
import com.clerk.ui.auth.AuthView

// =====================================================================================
// FIRST RUN — the port of `ios/Sources/Auth/SignInView.swift`.
//
// The brand, one action. Nothing to read, nothing to configure.
//
// There is no user artwork on first run, so THE MARK IS THE ART — and it has to be lit like art
// rather than decorated like a logo:
//
//  • The accent wash used to run from the status bar downward while the mark sat in the middle of
//    the screen, so the screen's only light source had nothing to do with its only object. The
//    bloom is centred ON the mark.
//  • The mark carried a raw amber `.shadow` — a coloured glow behind a logo, and not a shadow
//    token. Removed; the bloom does that job honestly.
//  • Two equal spacers pinned the identity to the exact vertical centre and stapled the button to
//    the floor. The identity sits on the upper third, where a title card sits.
//  • The developer card was a raised box with a grey outline round it — the exact wireframe
//    grammar this pass exists to remove. It is a `.raised` surface, visible because it is LIGHTER
//    and lit along its top edge.
//
// WHAT IS ANDROID'S AND NOT iOS'S
//
//  • The Clerk flow is a FULL-SCREEN overlay rather than a `.sheet`. `AuthView` is a complete auth
//    interface with its own dismiss control; on Android a sign-in flow is a screen, and system
//    back closes it (`BackHandler`). The meaning — a modal you can back out of, back to the gate —
//    is identical.
//  • `#if DEBUG` becomes `BuildConfig.DEBUG`, which is a compile-time `false` in release, so R8
//    deletes the branch and everything only it reaches. A runtime `FLAG_DEBUGGABLE` test would
//    leave the developer card and its DEV_AUTH_BYPASS sentence sitting in the shipped APK.
//  • The iOS `-devSignInId` / `-devSignInAuto` launch arguments become intent extras, so one
//    capture script drives both platforms (PLAN §2.5).
// =====================================================================================

/**
 * The gate. Drawn by the root whenever `auth.isSignedIn` is false and the splash has handed off.
 *
 * @param auth the app's one [AuthManager]. Passed rather than resolved so the screen has no
 *   opinion about how identity is scoped.
 */
@Composable
fun SignInScreen(
    auth: AuthManager,
    modifier: Modifier = Modifier,
) {
    val lastError by auth.lastError.collectAsState()
    var showClerkAuth by rememberSaveable { mutableStateOf(false) }

    Box(
        modifier = modifier
            .fillMaxSize()
            // The canvas ignores the safe area (iOS: `.ignoresSafeArea()`); only the content inside
            // is inset.
            .background(ThemeColor.canvas),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .padding(horizontal = ThemeSpace.x6)
                .padding(bottom = ThemeSpace.x10),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // iOS: `Spacer(minLength: 32) · identity · Spacer(minLength: 32) · Spacer(minLength: 0)
            // · action`. A SwiftUI spacer is a minimum PLUS an equal share of the slack, so the
            // three of them put the identity one third of the way down the free space. Compose has
            // no minimum-plus-weight spacer, so each is spelled out as its minimum followed by its
            // share — one share above the identity, two below it.
            //
            // "Two equal spacers pinned the identity to the exact vertical centre and stapled the
            // button to the floor. The identity now sits on the upper third, where a title card
            // sits."
            Spacer(Modifier.height(ThemeSpace.x8))
            Spacer(Modifier.weight(1f))

            Identity()

            Spacer(Modifier.height(ThemeSpace.x8))
            Spacer(Modifier.weight(2f))

            Action(
                auth = auth,
                lastError = lastError,
                onSignIn = { showClerkAuth = true },
            )
        }

        if (showClerkAuth) {
            ClerkAuthOverlay(
                auth = auth,
                onDismiss = { showClerkAuth = false },
            )
        }
    }
}

// -------------------------------------------------------------------------------------
// Identity
// -------------------------------------------------------------------------------------

@Composable
private fun Identity(modifier: Modifier = Modifier) {
    val isAX = isAccessibilityTextSize()
    Column(
        modifier = modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // The icon's ribbon, lit, then the name with its coral full stop.
        PreviouslyMark(width = MarkWidth, lit = true, bloom = true)

        BrandWord(
            style = ThemeType.displayXL,
            modifier = Modifier.padding(top = ThemeSpace.x5),
        )

        BasicText(
            text = Copy.Brand.promise,
            style = ThemeType.heroMeta.copy(
                color = ThemeColor.textSecondary,
                textAlign = TextAlign.Center,
            ),
            modifier = Modifier
                .padding(top = ThemeMetrics.labelGap)
                // At an accessibility size the sentence gets the full gutter-to-gutter width
                // rather than wrapping to four lines inside its own inset.
                .padding(horizontal = if (isAX) 0.dp else ThemeSpace.x6),
        )
    }
}

// -------------------------------------------------------------------------------------
// Action — three mutually exclusive branches
// -------------------------------------------------------------------------------------

/**
 * Whether the developer bypass may be offered at all.
 *
 * **Two gates, both required.** [BuildConfig.DEBUG] keeps the panel out of any build that can
 * reach the Play Store — a raw text field and the string "the backend must allow DEV_AUTH_BYPASS
 * outside production" as the first screen of a submitted app is an automatic rejection and a
 * one-star screenshot. [AppConfig.isLocalBackend] keeps it out of a debug build that has been
 * pointed at a real host, because a `dev:` bearer must never be SENT toward production even if the
 * server there would refuse it.
 *
 * Both operands are constants in a release build, so R8 removes this branch and `DevSignInCard`
 * with it — the Kotlin equivalent of iOS's `#if DEBUG`, and the reason this is not a runtime
 * `FLAG_DEBUGGABLE` test.
 */
private val devSignInAvailable: Boolean
    get() = BuildConfig.DEBUG && !AppConfig.isClerkConfigured && AppConfig.isLocalBackend

@Composable
private fun Action(
    auth: AuthManager,
    lastError: String?,
    onSignIn: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(ThemeSpace.x3),
    ) {
        when {
            AppConfig.isClerkConfigured ->
                PrimaryButton(
                    label = Copy.Auth.SIGN_IN,
                    onClick = onSignIn,
                    modifier = Modifier.fillMaxWidth(),
                )

            devSignInAvailable -> DevSignInCard(auth = auth)

            // Fails CLOSED: no key, no field, no bypass, and nothing a reviewer could mistake for a
            // way in. The condition is a build misconfiguration, so it is stated as one rather than
            // dressed up as a temporary outage the user could wait out.
            else -> BasicText(
                text = Copy.Auth.UNAVAILABLE_IN_THIS_BUILD,
                style = ThemeType.metadata.copy(
                    color = ThemeColor.textTertiary,
                    textAlign = TextAlign.Center,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
        }

        // A failure here is a FOOTNOTE, never an alert box. The sentence is held after it clears so
        // the fade-out has something to fade; the write happens before its only reader (the child
        // below), so it costs no extra composition pass.
        val retained = remember { mutableStateOf("") }
        lastError?.let { retained.value = it }
        AnimatedVisibility(
            visible = lastError != null,
            enter = fadeIn(animationSpec = motion(MotionToken.UI_GENTLE)),
            exit = fadeOut(animationSpec = motion(MotionToken.UI_GENTLE)),
        ) {
            InlineNotice(retained.value)
        }
    }
}

// -------------------------------------------------------------------------------------
// The Clerk flow
// -------------------------------------------------------------------------------------

/**
 * Clerk's prebuilt `AuthView`, themed as closely to the design law as `ClerkTheme` allows.
 *
 * This is the accepted divergence recorded in `research/product-decisions.md` §7: `AuthView` is a
 * third-party component and will not honour the design law exactly. What [previouslyClerkTheme]
 * **can** restyle is the colour roles, the corner radius and the typeface; what it **cannot** is
 * the component's own layout, button anatomy, press language, field chrome, error presentation and
 * (crucially) which roles it spends on which elements. Treat the remaining gap as a known
 * divergence rather than a bug; the escape hatch, if it ever looks foreign enough to matter, is a
 * custom flow against `clerk-android-api`'s headless methods.
 *
 * Drawn on an opaque canvas so the gate underneath does not show through Clerk's own background.
 */
@Composable
private fun ClerkAuthOverlay(
    auth: AuthManager,
    onDismiss: () -> Unit,
) {
    BackHandler(onBack = onDismiss)
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(ThemeColor.canvas),
    ) {
        AuthView(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.safeDrawing),
            clerkTheme = remember { previouslyClerkTheme() },
            isDismissible = true,
            onDismiss = onDismiss,
            onAuthComplete = {
                // Belt and braces: `AuthManager` already follows `auth.events`, but the gate should
                // not depend on an event ordering it does not own — iOS re-derives here too.
                auth.refreshClerkSignInState()
                onDismiss()
            },
        )
    }
}

/**
 * The app's palette and voice, expressed in the vocabulary `ClerkTheme` offers.
 *
 * Also the theme to hand `initializeClerk(context, previouslyClerkTheme())` from
 * `Application.onCreate()`, so a Clerk surface reached from anywhere else is themed too.
 *
 * **`primary` is [ThemeColor.accent] here, and that is not a violation of the amber rule — but it
 * is the one thing the side-by-side sign-off must actually look at.** Amber is legal as a GROUND
 * (the primary capsule, with [ThemeColor.onAccent] ink on top), which is what Clerk's primary CTA
 * is, and the user has just pressed an amber capsule to get here — a grey Continue on the next
 * screen would read as a different app. The risk is that Clerk may also tint its inline *links*
 * ("Sign up instead", "Use another method") with the same role, and an amber tappable WORD is
 * exactly what the rule forbids. If the capture shows that, change this one line to
 * [ThemeColor.interactive] and accept a neutral CTA — the rule outranks the continuity.
 *
 * Every role is assigned. `ClerkColors` defaults each to `null`, and a null role falls back to
 * Clerk's own default — which on a #09090B ground is the same failure mode as an unmapped
 * material3 role: not a subtle tint error, a light-on-white slab.
 *
 * `lightColors` and `darkColors` are the same map as `colors`: **the app is dark-only and never
 * follows the system setting**, so a light variant would be a way for this sheet to disagree with
 * the app that opened it.
 */
internal fun previouslyClerkTheme(): ClerkTheme = ClerkTheme(
    colors = previouslyClerkColors,
    lightColors = previouslyClerkColors,
    darkColors = previouslyClerkColors,
    typography = previouslyClerkTypography,
    // Clerk's default is 8 dp. `compactControl` (12) is what this app rounds a control to.
    design = ClerkDesign(borderRadius = ThemeRadius.compactControl),
)

private val previouslyClerkColors: ClerkColors by lazy {
    ClerkColors(
        // The primary CTA's GROUND, and the ink on it. See the note above.
        primary = ThemeColor.accent,
        primaryForeground = ThemeColor.onAccent,

        background = ThemeColor.canvas,
        foreground = ThemeColor.textPrimary,
        mutedForeground = ThemeColor.textSecondary,
        muted = ThemeColor.surfaceFlat,
        neutral = ThemeColor.textSecondary,

        // A field is a `.floating` control with a full-perimeter edge — the same anatomy the
        // developer card's own field wears below.
        input = ThemeColor.surfaceFloating,
        inputForeground = ThemeColor.textPrimary,
        border = ThemeColor.stroke,

        // Focus is STATE, and state is the second legal reading of amber.
        ring = ThemeColor.focusRing,

        secondaryButtonBackground = ThemeColor.surfaceFloating,
        secondaryButtonForeground = ThemeColor.textPrimary,

        danger = ThemeColor.destructive,
        success = ThemeColor.success,
        warning = ThemeColor.warning,
        shadow = Color.Black,
    )
}

/**
 * Outfit, in every slot Clerk draws a word in.
 *
 * Only the FACE is replaced; Clerk keeps its own sizes, weights and tracking. That is the honest
 * limit of "as close as `ClerkTheme` allows" — the app's type ramp is an assignment of tokens to
 * roles (`heroTitle` for a hero, `rowTitle` for a repeating row), and Clerk's roles are its own,
 * so imposing this app's sizes on them would produce a ramp neither system designed.
 */
private val previouslyClerkTypography: ClerkTypography by lazy {
    ClerkTypography(
        displaySmall = ClerkTypographyDefaults.displaySmall.inOutfit(),
        headlineLarge = ClerkTypographyDefaults.headlineLarge.inOutfit(),
        headlineMedium = ClerkTypographyDefaults.headlineMedium.inOutfit(),
        headlineSmall = ClerkTypographyDefaults.headlineSmall.inOutfit(),
        titleMedium = ClerkTypographyDefaults.titleMedium.inOutfit(),
        titleSmall = ClerkTypographyDefaults.titleSmall.inOutfit(),
        bodyLarge = ClerkTypographyDefaults.bodyLarge.inOutfit(),
        bodyMedium = ClerkTypographyDefaults.bodyMedium.inOutfit(),
        bodySmall = ClerkTypographyDefaults.bodySmall.inOutfit(),
        labelMedium = ClerkTypographyDefaults.labelMedium.inOutfit(),
        labelSmall = ClerkTypographyDefaults.labelSmall.inOutfit(),
    )
}

/** Swap the face, keep everything else. Nullable-receiver so a null default passes through. */
private fun TextStyle?.inOutfit(): TextStyle? = this?.copy(fontFamily = AppFont.outfit)

// -------------------------------------------------------------------------------------
// The developer card (debug builds pointed at a local backend, only)
// -------------------------------------------------------------------------------------

@Composable
private fun DevSignInCard(
    auth: AuthManager,
    modifier: Modifier = Modifier,
) {
    val launchIntent = LocalContext.current.findActivity()?.intent
    // `-devSignInId <clerkId>` on iOS; `--es devSignInId <clerkId>` here. Pre-fills the field so a
    // scripted emulator run can sign in without typing into the device.
    var devId by rememberSaveable {
        mutableStateOf(
            launchIntent?.getStringExtra(EXTRA_DEV_SIGN_IN_ID)?.takeIf { it.isNotEmpty() }
                ?: DEFAULT_DEV_ID,
        )
    }
    val onContinue = { auth.signInDev(devId) }

    // `--ez devSignInAuto true`: a scripted run signs in on appear with the seeded id.
    val autoSignIn = launchIntent != null &&
        (
            launchIntent.getBooleanExtra(EXTRA_DEV_SIGN_IN_AUTO, false) ||
                TRUTHY_EXTRA_VALUES.contains(launchIntent.getStringExtra(EXTRA_DEV_SIGN_IN_AUTO).orEmpty())
            )
    LaunchedEffect(autoSignIn) {
        if (autoSignIn && devId.isNotEmpty()) onContinue()
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            // A card is visible because it is LIGHTER and lit along its top edge, not because it
            // has a grey line drawn round it.
            .surface(SurfaceLevel.Raised, radius = ThemeRadius.card)
            .padding(ThemeSpace.x4),
        horizontalAlignment = Alignment.Start,
        verticalArrangement = Arrangement.spacedBy(ThemeMetrics.labelGap),
    ) {
        SectionLabel(text = Copy.Auth.DEVELOPER_SIGN_IN)

        BasicText(
            text = Copy.Auth.DEVELOPER_EXPLAINER,
            style = ThemeType.metadata.copy(color = ThemeColor.textSecondary),
        )

        DevIdField(
            value = devId,
            onValueChange = { devId = it },
            onSubmit = onContinue,
            modifier = Modifier.padding(top = ThemeSpace.x1),
        )

        PrimaryButton(
            // The shared table's word — the same "Continue" every other confirm-and-proceed
            // control in the app uses.
            label = Copy.Action.continueLabel,
            onClick = onContinue,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = ThemeSpace.x1),
        )
    }
}

@Composable
private fun DevIdField(
    value: String,
    onValueChange: (String) -> Unit,
    onSubmit: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = ContinuousCornerShape(ThemeRadius.compactControl)
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = minimumTapTarget)
            .background(ThemeColor.surfaceFloating, shape)
            // Compose insets a border, matching SwiftUI's `strokeBorder`: "a control may carry a
            // full-perimeter edge, but a centred 1-pt line straddles the shape and smears outside
            // it."
            .border(ThemeMetrics.hairline, ThemeColor.stroke, shape)
            .padding(horizontal = DevFieldInset),
        textStyle = ThemeType.body.copy(color = ThemeColor.textPrimary),
        singleLine = true,
        // Amber, deliberately: the shipped iOS field tints its caret `accent`, and this debug-only
        // card is outside the pass that made every caret ink. `spec/networking-auth.md` §9.5 and
        // `spec/profile-shell.md` §5 both pin it. Not a precedent for any shipping field.
        cursorBrush = SolidColor(ThemeColor.accent),
        keyboardOptions = KeyboardOptions(
            capitalization = KeyboardCapitalization.None,
            autoCorrectEnabled = false,
            imeAction = ImeAction.Done,
        ),
        keyboardActions = KeyboardActions(onDone = { onSubmit() }),
        decorationBox = { innerTextField ->
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = minimumTapTarget),
                contentAlignment = Alignment.CenterStart,
            ) {
                if (value.isEmpty()) {
                    BasicText(
                        text = Copy.Auth.DEV_USER_ID_PLACEHOLDER,
                        style = ThemeType.body.copy(color = ThemeColor.textTertiary),
                    )
                }
                innerTextField()
            }
        },
    )
}

/** iOS `-devSignInId <clerkId>`. */
private const val EXTRA_DEV_SIGN_IN_ID = "devSignInId"

/** iOS `-devSignInAuto 1`. */
private const val EXTRA_DEV_SIGN_IN_AUTO = "devSignInAuto"

/** `--ez` gives a real boolean; `--es` is accepted too so one capture script can use either. */
private val TRUTHY_EXTRA_VALUES = setOf("1", "true")

private const val DEFAULT_DEV_ID = "demo-user"

/** The hosting activity, for the debug intent extras. `null` in a preview or a test harness. */
private fun Context.findActivity(): Activity? {
    var context: Context? = this
    while (context is ContextWrapper) {
        if (context is Activity) return context
        context = context.baseContext
    }
    return context as? Activity
}

// -------------------------------------------------------------------------------------
// The brand mark
//
// The gate draws the identity; it does not own it. `design/brand/PreviouslyMark.kt` is the one
// drawing of the mark in the app — this file used to carry a private copy of the path, the 1.58
// aspect, the bloom and three `Color(0x…)` literals, and so did Today's header and Profile's disc.
// -------------------------------------------------------------------------------------

/** iOS `PreviouslyMark(width: 56, lit: true)`. */
private val MarkWidth = 56.dp

/**
 * The dev field's side inset. One step over `ThemeSpace.x3` on purpose: at 12 the caret sits on the
 * curve of a 12-dp corner. It is named because a screen spends no literal.
 */
private val DevFieldInset = 14.dp

