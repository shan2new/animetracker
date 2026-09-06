import type { Metadata } from 'next';
import './globals.css';

const origin = 'https://landing-ten-theta-55.vercel.app';
export const metadata: Metadata = {
  metadataBase: new URL(origin),
  title: 'Previously. — TV & anime tracking, right where you left off',
  description:
    'Previously. keeps your TV shows and anime in one place. Track episodes across seasons, see what is coming next, and catch up on what changed while you were away.',
  alternates: { canonical: '/' },
  openGraph: {
    type: 'website',
    siteName: 'Previously.',
    title: 'Previously. — Your shows. Right where you left them.',
    description:
      'A little less keeping track. A lot more getting lost in a good story.',
    url: origin,
  },
  twitter: {
    card: 'summary',
    title: 'Previously. — Your shows. Right where you left them.',
    description:
      'A personal TV and anime tracker for the stories you keep coming back to.',
  },
  icons: { icon: '/brand/icon.svg', apple: '/brand/icon.svg' },
  robots: { index: true, follow: true },
};
export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className="dark">
      <head>
        <meta name="theme-color" content="#09090b" />
        <link
          rel="preload"
          href="/fonts/Outfit-Regular.ttf"
          as="font"
          type="font/ttf"
          crossOrigin="anonymous"
        />
        <link
          rel="preload"
          href="/fonts/Outfit-Bold.ttf"
          as="font"
          type="font/ttf"
          crossOrigin="anonymous"
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
