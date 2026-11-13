// Depois do `next build`: põe em cada página de out/ uma Content-Security-Policy
// (meta tag) com o hash SHA-256 de cada script embutido que o Next gerou.
// Assim o navegador só roda os scripts do próprio painel, sem 'unsafe-inline'.
// frame-ancestors não vale em meta tag; o bloqueio de iframe fica no
// public/anti-enquadramento.js e, de verdade, no cabeçalho HTTP da camada na frente.
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const SUPABASE = 'https://aurjqwqqrxaexmwozezr.supabase.co';

function paginas(dir) {
  return readdirSync(dir).flatMap((nome) => {
    const p = join(dir, nome);
    if (statSync(p).isDirectory()) return paginas(p);
    return nome.endsWith('.html') ? [p] : [];
  });
}

function politica(hashes) {
  return [
    "default-src 'self'",
    `script-src 'self' ${hashes.join(' ')}`.trim(),
    "style-src 'self' 'unsafe-inline'",
    "font-src 'self'",
    "img-src 'self' data: blob: https://tile.openstreetmap.org " + SUPABASE,
    `connect-src 'self' ${SUPABASE} wss://aurjqwqqrxaexmwozezr.supabase.co`,
    "worker-src 'self' blob:",
    "manifest-src 'self'",
    "base-uri 'self'",
    "object-src 'none'",
    "form-action 'self'",
    'upgrade-insecure-requests',
  ].join('; ');
}

let total = 0;
for (const arq of paginas('out')) {
  let html = readFileSync(arq, 'utf8');
  if (html.includes('http-equiv="Content-Security-Policy"')) continue;
  const hashes = new Set();
  for (const [, attrs, corpo] of html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)) {
    if (/\bsrc=/.test(attrs) || /type="application\/(ld\+)?json"/.test(attrs)) continue;
    hashes.add(`'sha256-${createHash('sha256').update(corpo, 'utf8').digest('base64')}'`);
  }
  const meta =
    `<meta http-equiv="Content-Security-Policy" content="${politica([...hashes])}"/>` +
    '<meta name="referrer" content="strict-origin-when-cross-origin"/>';
  const depois = html.replace(/<meta charSet="utf-8"\/>/i, (m) => m + meta);
  if (depois === html) throw new Error(`Sem <meta charset> em ${arq}`);
  writeFileSync(arq, depois);
  total++;
}
console.log(`CSP aplicada em ${total} páginas.`);
