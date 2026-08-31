import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "StackCast — 読みたいニュースを、耳で聴ける時間に。",
  description: "あなた向けのニュースを見つけ、気になる記事を保存。AIが要約した音声Castで、移動中も家事の途中もニュースを耳で楽しめます。",
  icons: {
    icon: "/marketing/app-icon.png",
    shortcut: "/marketing/app-icon.png",
    apple: "/marketing/app-icon.png",
  },
  openGraph: {
    title: "StackCast — 読みたいニュースを、耳で聴ける時間に。",
    description: "ニュースを見つけ、保存し、AI音声Castで聴けるアプリ。",
    type: "website",
  },
  twitter: {
    card: "summary",
    title: "StackCast",
    description: "読みたいニュースを、耳で聴ける時間に。",
  },
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
