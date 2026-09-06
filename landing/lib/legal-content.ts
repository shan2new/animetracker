export type LegalKind = 'privacy' | 'terms' | 'support' | 'delete-account';
export type LegalSection = {
  title: string;
  paragraphs: string[];
  items?: string[];
};
export type LegalContent = {
  title: string;
  summary: string;
  sections: LegalSection[];
};

// Publication is intentionally gated on facts, not a calendar date. Do not replace
// these with a guessed personal email, retention period, or deletion guarantee.
export const legalPublication = {
  operator: 'Shantanu Sinha',
  contactEmail: 'shantanusinha95@gmail.com',
  effectiveDate: null as string | null,
  draft: true,
};
export const legalContent: Record<LegalKind, LegalContent> = {
  privacy: {
    title: 'Privacy Policy',
    summary:
      'How Previously. handles your account, watching activity and information you choose to share.',
    sections: [
      {
        title: 'Who this policy covers',
        paragraphs: [
          'This policy covers the Previously. iPhone app, its supporting service, and this website. Previously. is operated by Shantanu Sinha. For privacy questions, contact shantanusinha95@gmail.com.',
        ],
      },
      {
        title: 'Information used to run Previously.',
        paragraphs: [
          'Previously. uses information you provide and information generated when you use the service. The exact information available depends on the features and sign-in methods you use.',
        ],
        items: [
          'Account information: your authentication identifier, an internal account identifier, email address when supplied, and account creation and last-opened timestamps. Clerk handles sign-in and authentication.',
          'Watching activity: saved shows, library statuses, watched episode counts, and the dates those records are changed.',
          'Preferences: selected country, language and streaming-provider preferences when those settings are used. A selected country is a preference; it is not a GPS reading.',
          'Updates: notification content and its creation and read status.',
          'On-device information: recent searches, cached show details and images, rewatch records, settings, and any exports you create.',
          'Service requests: searches, requested pages and technical connection information processed by the app service, authentication provider and hosting infrastructure.',
        ],
      },
      {
        title: 'Why this information is used',
        paragraphs: [
          'Information is used to sign you in, maintain your library and progress, show relevant schedules and updates, honor your settings, respond to support requests, and operate and protect the service.',
        ],
        items: [
          'Notifications require your permission and are scheduled on the device by the current iPhone app.',
          'The website’s interactive example keeps sample progress in the page session. It does not create an app account or update your library.',
          'The reviewed app and website do not contain an advertising SDK or an app-owned analytics integration. Provider and infrastructure data practices must still be verified before making broader claims about tracking or collection.',
        ],
      },
      {
        title: 'Services that receive information',
        paragraphs: [
          'Previously. uses external services for specific functions. Their actual configuration and applicable data-processing terms must be verified before publication.',
        ],
        items: [
          'Clerk receives information needed for authentication and session management.',
          'AniList and TMDB may receive search terms when the backend searches their catalogs. These catalog requests do not deliberately include your Previously. account identifier or watched-episode history.',
          'If AI search correction is enabled, Cerebras receives the search text to suggest a corrected title. Avoid entering private information into a show search.',
          'Catalog enrichment can use Cerebras, OpenRouter and its selected model providers, and Anthropic-powered research. The reviewed enrichment inputs contain show metadata and public announcements, rather than account identifiers or personal episode progress.',
          'Your device loads artwork from the image hosts referenced by the catalog. Those hosts receive ordinary image requests, which can expose network information such as an IP address.',
          'Opening a trailer or another external link involves the destination service and its own privacy practices.',
          'Network and hosting providers process requests to deliver and protect the app service and this website. Confirm the deployed providers, logging settings and processing locations before publication.',
        ],
      },
      {
        title: 'Retention and deletion',
        paragraphs: [
          'The app database currently stores account information and watching records until they are changed or deleted. Removing an individual show from the library does not necessarily erase its episode progress.',
          'The current in-app deletion flow removes the primary Previously. database records and signs you out. It does not yet remove the Clerk identity, and some on-device history and cache files remain. Complete account deletion must be implemented and verified before this policy is published as a store-ready policy.',
          'The operator must define the retention and deletion treatment of support correspondence, service logs, backups and processor-held data. This draft intentionally makes no unverified retention deadline or immediate-backup-erasure promise.',
        ],
      },
      {
        title: 'Your controls and requests',
        paragraphs: [
          'You can change your library and supported preferences, control notifications in iPhone settings, and export library information from Profile. A library export is not an export of every category of personal information.',
          'The Account Deletion page describes the intended request channels and the current publication blockers. For privacy requests, contact Shantanu Sinha at shantanusinha95@gmail.com.',
          'Depending on where you live, applicable law may give you rights to access, correct, erase or restrict use of personal information, object to processing, withdraw consent, or complain to a relevant authority. Identity verification may be needed to protect your account when handling a request.',
        ],
      },
      {
        title: 'Security, location and audience',
        paragraphs: [
          'The configured public app API uses HTTPS. Access to account endpoints requires authentication. No method of transmission or storage can be guaranteed to eliminate every risk.',
          'The operator must confirm processing locations, applicable legal bases, the intended audience and any child-privacy requirements for the regions where the app will be offered. No age threshold or international-transfer guarantee has been assumed in this draft.',
        ],
      },
      {
        title: 'Changes and contact',
        paragraphs: [
          'When the published policy changes, its effective date will be updated and any notice required by applicable law will be provided. This draft has no effective date. The operator is Shantanu Sinha. Privacy questions can be sent to shantanusinha95@gmail.com.',
        ],
      },
    ],
  },
  terms: {
    title: 'Terms of Use',
    summary:
      'The rules for using Previously. and its website, with room for the rights that applicable law protects.',
    sections: [
      {
        title: 'About Previously.',
        paragraphs: [
          'Previously. is a personal companion for tracking TV and anime. It organizes show information, seasons, episode progress and updates. It does not provide a license or subscription to watch third-party content, and it does not stream or download TV episodes.',
          'These draft terms cover the supporting service and website. The operator is Shantanu Sinha. The effective date, intended audience and remaining service terms require confirmation before these terms take effect.',
        ],
      },
      {
        title: 'Apple’s app license',
        paragraphs: [
          'For an app distributed through Apple’s App Store, Apple’s standard end-user license agreement applies unless a valid custom agreement is supplied through App Store Connect. These service terms are not intended to replace the applicable app license or mandatory consumer rights.',
        ],
      },
      {
        title: 'Your account and use',
        paragraphs: [
          'Use the service lawfully, keep your sign-in credentials secure, and provide accurate information when you ask us to help with your account. Do not impersonate another person or access an account without permission.',
        ],
        items: [
          'Do not interfere with the service, bypass access controls, introduce malicious code or use the service to harm others.',
          'Do not use catalog material in a way that infringes its owner’s rights.',
          'Contact shantanusinha95@gmail.com if you believe someone has accessed your account without permission.',
        ],
      },
      {
        title: 'Catalog information and third-party content',
        paragraphs: [
          'Release dates, episode counts, artwork and other catalog information come from external sources and can change or contain errors. Check the relevant broadcaster or provider when a date or availability matters to you.',
          'Show names, images, trademarks and other third-party materials belong to their respective owners. Previously. does not claim ownership of them or imply an endorsement by a broadcaster, studio or streaming service.',
          'External services and linked destinations have their own terms and privacy policies. Access to a title may require a separate subscription or payment to its provider.',
        ],
      },
      {
        title: 'Availability and changes',
        paragraphs: [
          'Features may change as the service develops, and maintenance or external-provider issues can interrupt availability. Previously. does not promise uninterrupted service or that every catalog item will always be available.',
          'No subscription price, renewal arrangement or refund policy is established by these draft terms. Any future paid offering needs clear terms at purchase and any required store billing integration.',
        ],
      },
      {
        title: 'Your information and ending use',
        paragraphs: [
          'The Privacy Policy explains how account information and watching activity are handled. You can stop using the service, export supported library information and request account deletion through the published deletion process once it is operational.',
          'Deleting the app from a device is not itself a request to delete a server account.',
        ],
      },
      {
        title: 'Rights and responsibility',
        paragraphs: [
          'To the extent permitted by applicable law, the service and catalog information are provided as available. Nothing in these terms excludes a right or responsibility that cannot lawfully be excluded, including mandatory consumer protections.',
          'Any further liability limits, governing-law provisions or dispute procedures must be chosen and reviewed for the operator and launch markets. They have not been invented in this draft.',
        ],
      },
      {
        title: 'Questions about these terms',
        paragraphs: [
          'For questions, contact Shantanu Sinha at shantanusinha95@gmail.com. This draft is not yet an effective agreement.',
        ],
      },
    ],
  },
  support: {
    title: 'Support',
    summary:
      'Help with your library, progress, sign-in and data in Previously.',
    sections: [
      {
        title: 'Contact Previously.',
        paragraphs: [
          'Previously. is made by Shantanu Sinha. Email shantanusinha95@gmail.com for help with the app, your account or your information.',
          'When contacting support, include the app version, iPhone model, iOS version and a short description of what happened. Include the show title when the issue concerns catalog information.',
        ],
        items: [
          'Never send your password, sign-in code, session token or payment information.',
          'Only attach a screenshot if you are comfortable sharing everything visible in it.',
        ],
      },
      {
        title: 'A show or date looks wrong',
        paragraphs: [
          'Catalog dates and episode details can change. Tell support which title, season or episode is affected and what looks incorrect. Previously. is a tracker; the broadcaster or streaming provider controls viewing access.',
        ],
      },
      {
        title: 'Your library and notifications',
        paragraphs: [
          'You can manage your followed shows and progress in the app. Notification permission can be changed in iPhone Settings. Profile includes a library export option for JSON or CSV files.',
        ],
      },
      {
        title: 'Account access and deletion',
        paragraphs: [
          'You can email shantanusinha95@gmail.com for sign-in help or a privacy request without reinstalling the app. The Account Deletion page explains the current deletion flow and its limitations. Support may need to verify account ownership before making account changes.',
        ],
      },
      {
        title: 'Release availability',
        paragraphs: [
          'Previously. is being built for iPhone. A public download link will be added to this website when it is available.',
        ],
      },
    ],
  },
  'delete-account': {
    title: 'Account Deletion',
    summary:
      'A direct place to request deletion of your Previously. account and associated data.',
    sections: [
      {
        title: 'Request deletion without the app',
        paragraphs: [
          'This page is intended to provide a deletion request channel even if you have uninstalled Previously. Email shantanusinha95@gmail.com with the subject “Previously. account deletion request” to contact Shantanu Sinha about deleting your account.',
          'The request should identify the Previously. account you want deleted. Support may verify ownership to prevent someone else from deleting your account. Do not send your password or one-time sign-in code.',
        ],
      },
      {
        title: 'The in-app option',
        paragraphs: [
          'The current iPhone app offers Profile → Delete account → a confirmation step. It removes the primary app database records and signs you out.',
          'Release blocker: this flow must also delete the Clerk identity and correctly clear account-related local records. It currently leaves the authentication identity and some local history behind. This draft is not a claim that store account-deletion requirements have been met.',
        ],
      },
      {
        title: 'What a complete deletion should cover',
        paragraphs: [
          'Before this page is published, the deletion workflow must be verified for the following categories:',
        ],
        items: [
          'The Previously. account record and Clerk authentication identity and sessions.',
          'Saved shows, statuses, episode progress, preferences and notification records.',
          'App-managed local account history, caches and temporary export files on the device performing deletion.',
          'Any support records, service logs or backups linked to the account, subject to a disclosed and justified retention policy.',
        ],
      },
      {
        title: 'What to expect after a request',
        paragraphs: [
          'The operator must confirm request handling, verification, completion notice and any justified retention before publication. This draft makes no unverified deletion deadline.',
          'Copies you saved or shared outside the app are under your control and cannot be removed remotely by Previously. Removing Previously. does not delete a separate account you hold with a broadcaster or streaming service.',
        ],
      },
    ],
  },
};
