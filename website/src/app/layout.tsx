import type { Metadata } from "next";
import { Nosifer, Space_Grotesk } from "next/font/google";

import { assetPath, SITE_ORIGIN } from "@/config/site";
import "./globals.css";

const spaceGrotesk = Space_Grotesk({
  variable: "--font-space-grotesk",
  subsets: ["latin"],
  weight: ["300", "400", "500", "600", "700"],
});

const nosifer = Nosifer({
  subsets: ["latin"],
  weight: "400",
  variable: "--font-nosifer",
});

export const metadata: Metadata = {
  metadataBase: new URL(`${SITE_ORIGIN}/`),
  title: "OXPlayer",
  description:
    "Transform your Telegram videos into a beautiful Netflix-style media library with smart organization, seamless playback, and powerful streaming features.",
  icons: {
    icon: [{ url: assetPath("/images/logo.png"), type: "image/png" }],
    apple: [{ url: assetPath("/images/logo.png"), type: "image/png" }],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" data-theme="light" className="scroll-smooth">
      <body className={` ${nosifer.variable} ${spaceGrotesk.variable} antialiased`} suppressHydrationWarning={true}>
        {children}
      </body>
    </html>
  );
}
