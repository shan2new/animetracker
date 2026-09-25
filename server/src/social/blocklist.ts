// The server-side word list behind the content filter (social/contentFilter.ts).
//
// Source: hand-curated for this app on 25 Sep 2026, organised by the categories of LDNOOBW's `en`
// list ("List of Dirty, Naughty, Obscene, and Otherwise Bad Words",
// https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words, CC BY 4.0),
// filtered to the categories below. It is not a verbatim copy of that list: entries that collide
// with ordinary English or anime discussion ("chink in the armour", "Maine Coon", "cp" = couple
// pairing, the Berserk arc everyone discusses) were left out on purpose. Review it with a human
// before widening it, and never put a real term in a test — tests inject fake terms (`zzbadword`).
//
// Matching (contentFilter.ts `containsBlockedTerm`): every term and every comment is folded
// (NFKC, lowercase, diacritics stripped, leet digits/symbols mapped, runs of 3+ letters collapsed).
//   word       — a whole token (or its plural in "s"); a multi-word term matches as a token run.
//                Whole words only, so there is no Scunthorpe problem.
//   substring  — anywhere in the text with every separator removed, which catches "s.l.u.r"
//                spacing. Reserved for strings that occur inside no ordinary word.

export interface BlockedTerm {
  term: string
  match: 'word' | 'substring'
}

const word = (term: string): BlockedTerm => ({ term, match: 'word' })
const substring = (term: string): BlockedTerm => ({ term, match: 'substring' })

/**
 * Applies EVERYWHERE: comments, handles, display names. Slurs (ethnic, racial, homophobic,
 * transphobic, ableist), sexual terms involving minors, and explicit self-harm incitement.
 */
export const BLOCKED_TERMS: readonly BlockedTerm[] = [
  // Ethnic and racial slurs.
  word('nigger'),
  word('nigga'),
  substring('sandnigger'),
  word('niglet'),
  word('jigaboo'),
  word('porch monkey'),
  word('golliwog'),
  word('wetback'),
  word('beaner'),
  word('spic'),
  word('kike'),
  word('gook'),
  word('zipperhead'),
  word('ching chong'),
  word('jap'),
  word('raghead'),
  word('towelhead'),
  word('paki'),
  word('gypsy scum'),
  // Homophobic and transphobic slurs.
  substring('faggot'),
  word('fag'),
  word('dyke'),
  word('tranny'),
  word('trannies'),
  word('shemale'),
  // Ableist slurs.
  word('retard'),
  word('retarded'),
  word('tard'),
  word('spaz'),
  word('mongoloid'),
  // Sexual terms involving minors.
  substring('childporn'),
  word('child porn'),
  word('kiddie porn'),
  word('kiddy porn'),
  word('jailbait'),
  word('lolicon'),
  word('shotacon'),
  word('pedo'),
  word('paedo'),
  word('pedophile'),
  word('paedophile'),
  word('underage sex'),
  word('preteen sex'),
  // Explicit self-harm incitement.
  word('kys'),
  word('kill yourself'),
  word('kill urself'),
  word('kill ur self'),
  word('hang yourself'),
  word('neck yourself'),
  word('slit your wrists'),
  word('drink bleach'),
  word('go kill yourself'),
]

/**
 * Handles and display names ONLY: general profanity and sexual words. Mild profanity is allowed
 * in comments in v1, but a public name is shown next to every comment its owner writes.
 */
export const NAME_ONLY_TERMS: readonly BlockedTerm[] = [
  substring('fuck'),
  substring('motherfucker'),
  word('shit'),
  word('shitty'),
  word('bullshit'),
  substring('bitch'),
  word('bastard'),
  word('cunt'),
  word('twat'),
  word('dick'),
  word('dickhead'),
  word('cock'),
  word('prick'),
  word('pussy'),
  word('ass'),
  word('asshole'),
  word('arsehole'),
  word('wank'),
  word('wanker'),
  word('bollocks'),
  word('piss'),
  substring('whore'),
  word('slut'),
  substring('porn'),
  word('sex'),
  word('sexy'),
  word('penis'),
  word('vagina'),
  word('boobs'),
  word('tits'),
  word('cum'),
  substring('dildo'),
  word('rape'),
  word('rapist'),
  word('hentai'),
  word('nsfw'),
  word('horny'),
  word('milf'),
  word('anal'),
  substring('blowjob'),
  substring('handjob'),
  word('nude'),
  word('nudes'),
  word('xxx'),
  substring('onlyfans'),
]
