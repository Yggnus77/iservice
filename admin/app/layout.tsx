import type { Metadata, Viewport } from 'next';
import { Montserrat } from 'next/font/google';
import Painel from '@/components/Painel';
import 'leaflet/dist/leaflet.css';
import './globals.css';

const fonte = Montserrat({ subsets: ['latin'], weight: ['400', '500', '600', '700', '800'], variable: '--fonte', display: 'swap' });

export const metadata: Metadata = {
  title: 'iService · Painel da equipe',
  description: 'Painel administrativo do iService.',
  robots: { index: false, follow: false },
  icons: { icon: '/admin/favicon.svg' },
};

export const viewport: Viewport = { themeColor: '#0a1f44', width: 'device-width', initialScale: 1 };

export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR" className={fonte.variable}>
      <body>
        <Painel>{children}</Painel>
      </body>
    </html>
  );
}
