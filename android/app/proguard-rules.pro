# R8 / ProGuard rules for the release build.
#
# Most of what this app needs arrives as CONSUMER rules from the libraries themselves and must not
# be restated here — a duplicated keep rule is a rule that silently stops matching when the library
# changes shape:
#
#   * kotlinx.serialization bundles its own rules (since the 1.4.x rules PR, revised with R8 tests
#     in 1.10.0). Nothing is needed for the wire types in `:model` — none of them carries a NAMED
#     companion object, which is the one documented case those rules do not cover.
#   * Retrofit bundles rules that keep any interface declaring `@retrofit2.http.*` methods, its
#     generic signatures and its `Continuation` parameters. `AniTrackApi` is covered by them.
#   * OkHttp bundles rules for its optional Conscrypt/BouncyCastle/Animal-Sniffer references.
#
# Verify against a real release build, never by reading this file.

# The transport layer's exceptions are matched by TYPE, never by name, so obfuscation is safe — but
# the class names appear in `diagnostic` log lines and in crash reports, and an obfuscated
# `ApiError$Infrastructure` makes a production log unreadable for no gain in size.
-keepnames class com.anitrack.app.data.api.ApiError { *; }
-keepnames class com.anitrack.app.data.api.ApiError$* { *; }

# `AuthToken` is read back out of an OkHttp request by its runtime Class object
# (`request.tag(AuthToken::class.java)`), which R8 tracks — but only while the class is not merged
# into another. Keep it whole.
-keep class com.anitrack.app.data.api.AuthToken { *; }
