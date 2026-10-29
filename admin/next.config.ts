import type { NextConfig } from 'next';

// Exportação estática: o painel é publicado em iservice.app.br/admin/ (ramo gh-pages).
// Toda a segurança está no banco (funções admin_* conferem e_admin()).
const config: NextConfig = {
  output: 'export',
  basePath: '/admin',
  trailingSlash: true,
  images: { unoptimized: true },
  reactStrictMode: true,
};

export default config;
