export default function robots() {
  return {
    rules: [
      { userAgent: '*', allow: '/' },
      { userAgent: 'OAI-SearchBot', allow: '/' },
    ],
    sitemap: 'https://previously-tv.shan2new.chatgpt.site/sitemap.xml',
  };
}
