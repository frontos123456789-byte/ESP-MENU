import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = {
  title: "What do websites know about me?",
  description:
    "A browser privacy self-check. See your IP, fingerprint, network exposure, and everything an ordinary website can learn without asking for permissions.",
  robots: { index: false, follow: false },
};
export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="ru">
      <body>{children}</body>
    </html>
  );
}
