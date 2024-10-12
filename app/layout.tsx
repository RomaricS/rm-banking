export const dynamic = 'force-dynamic';

import type { Metadata } from 'next';
import { Inter, IBM_Plex_Serif } from 'next/font/google';
import './globals.css';
import { AppTitle } from '@/constants';

const inter = Inter({
    subsets: ['latin'],
    variable: '--font-inter',
});

const ibmPlexSerif = IBM_Plex_Serif({
    subsets: ['latin'],
    weight: ['400', '700'],
    variable: '--font-inter',
});

export const metadata: Metadata = {
    title: AppTitle,
    description: `${AppTitle} is a modern banking platform`,
    icons: '/icons/logo.svg',
};

export default function RootLayout({
    children,
}: Readonly<{
    children: React.ReactNode;
}>) {
    return (
        <html lang='en'>
            <body className={`${inter.variable} ${ibmPlexSerif.variable}`}>
                {children}
            </body>
        </html>
    );
}
