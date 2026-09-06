import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify'

// Privacy Policy and Terms of Use, served as static pages from the backend's own HTTPS origin.
//
// App Store guideline 5.1.1 requires both to be reachable at a stable URL, and TestFlight external
// testing requires the privacy policy specifically. Serving them here rather than from separate
// hosting keeps them on the one domain the app already talks to — the URLs are wired into
// `ios/project.yml` (PRIVACY_POLICY_URL / TERMS_URL) and surfaced by Profile's legal rows.
//
// Registered on the ROOT instance (see server.ts) alongside `/health`, so they are public: the
// `authenticate` preHandler lives inside the franchise/me plugins' own encapsulation and does not
// reach here. A privacy policy behind a login is not a privacy policy.
//
// NOTE ON MAINTENANCE: `LAST_UPDATED` is the date shown to the reader. Bump it in the same commit
// as any change to what the app actually collects — a policy whose text moved but whose date did
// not is worse than no date at all.

const LAST_UPDATED = '3 September 2026'
const SUPPORT_EMAIL = 'shantanusinha95@gmail.com'
const APP_NAME = 'Previously.'

/** Shared chrome. Dark, system-font, one column — legible on a phone opened from the Profile row. */
function page(title: string, body: string): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} — ${APP_NAME}</title>
<style>
  :root { color-scheme: dark light; }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 2.5rem 1.25rem 5rem;
    background: #09090b; color: #e8e8ea;
    font: 16px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
    -webkit-text-size-adjust: 100%;
  }
  main { max-width: 42rem; margin: 0 auto; }
  h1 { font-size: 1.75rem; line-height: 1.2; margin: 0 0 .35rem; letter-spacing: -.02em; }
  h2 { font-size: 1.075rem; margin: 2.25rem 0 .6rem; letter-spacing: -.01em; }
  .updated { color: #8a8a92; font-size: .875rem; margin: 0 0 2rem; }
  p, li { color: #c9c9d1; }
  ul { padding-left: 1.25rem; }
  li { margin: .35rem 0; }
  a { color: #f0b429; text-decoration: none; }
  a:hover { text-decoration: underline; }
  strong { color: #e8e8ea; font-weight: 600; }
  footer { margin-top: 3.5rem; padding-top: 1.25rem; border-top: 1px solid #232327;
           color: #6f6f78; font-size: .8125rem; }
  @media (prefers-color-scheme: light) {
    body { background: #fbfbfc; color: #18181b; }
    p, li { color: #3f3f46; }
    strong { color: #18181b; }
    .updated { color: #71717a; }
    a { color: #a16207; }
    footer { border-top-color: #e4e4e7; color: #71717a; }
  }
</style>
</head>
<body>
<main>
<h1>${title}</h1>
<p class="updated">${APP_NAME} · Last updated ${LAST_UPDATED}</p>
${body}
<footer>
  Questions about this document? Email <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a>.
</footer>
</main>
</body>
</html>`
}

const PRIVACY_BODY = `
<p>
  ${APP_NAME} is a personal, independently built TV and anime tracker. It is run by one person, not
  a company, and it makes no money from your data. This page describes exactly what the app stores,
  why, and how to get rid of it.
</p>

<h2>What the app stores about you</h2>
<p>Only what is needed to keep your library on your account rather than on one phone:</p>
<ul>
  <li><strong>Your email address and a user identifier</strong>, supplied by the sign-in provider
      when you create an account.</li>
  <li><strong>Your library</strong> — which shows you follow, the status you gave each one
      (watching, completed, planned, paused, dropped), and how far through each season you are.</li>
  <li><strong>Reminder preferences</strong> — which shows you asked to be alerted about.</li>
  <li><strong>The time you last opened the app</strong>, used to decide what counts as new since
      your last visit.</li>
</ul>
<p>
  That is the complete list. The app has <strong>no analytics, no advertising, no tracking
  identifiers and no third-party SDKs that collect data about you</strong>. Nothing is sold, rented
  or shared with data brokers, and nothing is used to build an advertising profile. There is no
  behavioural logging: the app does not record which screens you visit or what you search for.
</p>

<h2>What stays on your device</h2>
<p>
  Some things never leave your phone: a cached copy of your library so the app opens without a
  network, your scheduled episode reminders, your rewatch sessions, and your display and haptics
  preferences. Deleting the app removes all of it.
</p>

<h2>Services the app relies on</h2>
<ul>
  <li><strong>Clerk</strong> handles sign-in and holds your email address and account credentials.
      The app never sees or stores your password.</li>
  <li><strong>AniList</strong> and <strong>The Movie Database (TMDB)</strong> provide the show
      catalogue — titles, artwork, air dates, cast. These are queried by the server, not by your
      phone, so your device and IP address are never exposed to them, and no information about you
      is sent to them.</li>
  <li><strong>JustWatch</strong>, via TMDB, provides streaming availability for your country. The
      app sends only a two-letter region code, never your precise location.</li>
  <li><strong>Language-model providers</strong> (OpenRouter, Cerebras) help group show franchises
      and fix misspelled searches. They receive only public show titles. No account data, and no
      information about who searched, is ever sent.</li>
</ul>

<h2>Where your data lives</h2>
<p>
  The backend is <strong>self-hosted on private hardware</strong>, not on a commercial cloud
  platform. Data is transmitted over HTTPS. Please note this is a small personal project: it is
  maintained on a best-effort basis and carries no uptime guarantee.
</p>

<h2>Deleting your data</h2>
<p>
  Open <strong>Profile → Delete Account</strong>. That erases your account row, your subscriptions,
  your progress and your notifications from the server in a single operation. It is immediate and
  cannot be undone. If you would rather it be done for you, email
  <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a>. Deleting your account here does not by
  itself delete your credentials held by the sign-in provider; ask and they will be removed too.
</p>

<h2>Retention</h2>
<p>
  Your library is kept for as long as your account exists, because that <em>is</em> the product.
  There is no separate archive, backup export or log of your activity that survives deletion.
</p>

<h2>Children</h2>
<p>
  The app is not directed at children under 13 and does not knowingly collect their information.
</p>

<h2>Your rights</h2>
<p>
  You can ask what is stored about you, ask for a copy of it, or ask for it to be corrected or
  erased, by emailing <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a>. Because this is a
  one-person project, expect a reply in days rather than hours.
</p>

<h2>Changes</h2>
<p>
  If what the app collects changes, this page changes with it and the date at the top moves. During
  the beta, material changes will also be mentioned in the TestFlight release notes.
</p>
`

const TERMS_BODY = `
<p>
  These terms cover your use of ${APP_NAME}, a personal, independently built TV and anime tracker.
  By using the app you agree to them. If you do not, please delete the app.
</p>

<h2>This is beta software</h2>
<p>
  ${APP_NAME} is offered for testing. It is provided <strong>as is</strong>, without warranty of
  any kind. Expect bugs, expect the design to change, and expect that a release may lose data or
  reset state. Do not rely on it as the only record of anything you care about.
</p>

<h2>Availability</h2>
<p>
  The backend runs on private hardware maintained by one person. It may be slow, unavailable, or
  discontinued at any time and without notice. No uptime is promised.
</p>

<h2>Your account</h2>
<p>
  You are responsible for your sign-in credentials and for activity on your account. Use the app
  for personal, non-commercial purposes. Please do not attempt to break, overload or gain
  unauthorised access to the service, scrape it in bulk, or use it to redistribute the catalogue
  data it displays. Accounts that do may be removed.
</p>

<h2>Show information and artwork</h2>
<p>
  Titles, synopses, artwork, air dates, cast information and trailers come from
  <strong>AniList</strong> and <strong>The Movie Database (TMDB)</strong>, and streaming
  availability comes from <strong>JustWatch</strong>. That material belongs to its respective
  rights holders and is shown for reference only. ${APP_NAME} is not endorsed by or affiliated with
  any of them, nor with any studio, streaming service or broadcaster.
</p>
<p>
  <strong>${APP_NAME} does not host, stream, download or link to pirated video.</strong> It tracks
  what you watch and tells you where a show is legitimately available.
</p>

<h2>Trailers</h2>
<p>
  Trailers play through the provider's own embedded player. Your use of them is subject to that
  provider's terms.
</p>

<h2>Ending it</h2>
<p>
  You can delete your account at any time from <strong>Profile → Delete Account</strong>, which
  erases your data as described in the <a href="/privacy">Privacy Policy</a>. Access may be
  withdrawn if these terms are breached, or if the project is simply shut down.
</p>

<h2>Liability</h2>
<p>
  To the fullest extent permitted by law, the developer is not liable for any indirect or
  consequential loss arising from your use of the app, including lost data or a missed episode.
  Nothing here limits rights that cannot be limited under the law that applies to you.
</p>

<h2>Changes</h2>
<p>
  These terms may change as the app develops. The date at the top shows when they last did.
</p>

<h2>Contact</h2>
<p>
  <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a>
</p>
`

export const legalRoutes: FastifyPluginAsync = async (app) => {
  // `text/html; charset=utf-8` explicitly: Fastify would otherwise serialize the string as JSON
  // and the reader would get a quoted blob of markup.
  const send =
    (title: string, body: string) => async (_req: FastifyRequest, reply: FastifyReply) =>
      reply.header('content-type', 'text/html; charset=utf-8').send(page(title, body))

  app.get('/privacy', send('Privacy Policy', PRIVACY_BODY))
  app.get('/terms', send('Terms of Use', TERMS_BODY))
}
