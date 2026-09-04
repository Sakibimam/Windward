import type { Metadata } from "next";
import { Instrument_Serif, IBM_Plex_Sans, IBM_Plex_Mono } from "next/font/google";
import "./globals.css";
import Nav from "@/components/Nav";
import Footer from "@/components/Footer";

const display = Instrument_Serif({
  subsets: ["latin"],
  weight: ["400"],
  style: ["normal", "italic"],
  variable: "--font-display",
  display: "swap",
});

const sans = IBM_Plex_Sans({
  subsets: ["latin"],
  weight: ["400", "500", "600"],
  variable: "--font-sans",
  display: "swap",
});
const mono = IBM_Plex_Mono({
  subsets: ["latin"],
  weight: ["400", "500"],
  variable: "--font-mono",
  display: "swap",
});

const SITE = "https://windward-hook.vercel.app";
const BLURB =
  "A Uniswap v4 hook that prices volatility from the pool's own tick history, and the shuffled-null control built to falsify it.";

export const metadata: Metadata = {
  metadataBase: new URL(SITE),
  title: { default: "Windward", template: "%s · Windward" },
  description: BLURB,
  icons: { icon: "/windward-mark.png" },
  openGraph: {
    type: "website",
    url: SITE,
    siteName: "Windward",
    title: "Windward — calm pool, cheap swap. Wild pool, higher fee.",
    description: BLURB,
    images: [{ url: "/og.png", width: 1200, height: 630, alt: "Windward: a Uniswap v4 hook that prices every swap off the pool's own volatility." }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Windward — calm pool, cheap swap. Wild pool, higher fee.",
    description: BLURB,
    creator: "@hisakibimam",
    images: ["/og.png"],
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className={`${display.variable} ${sans.variable} ${mono.variable}`}>
        <Nav />
        <div className="grid-bg">{children}</div>
        <Footer />
      </body>
    </html>
  );
}
