// Teste no motor do Safari (WebKit) com tela, toque e navegador de iPhone.
// Uso: node testar_webkit.js <pasta-de-saida>
// Parte 1: apps publicados (iservice.app.br), só telas públicas e cadastro até antes de criar a conta.
// Parte 2: versão de demonstração local (porta 8101 cliente, 8102 profissional), telas de quem está logado.
const pw = require('playwright');
const { devices } = pw;
const webkit = process.env.MOTOR === 'chromium' ? pw.chromium : pw.webkit;
const fs = require('fs');
const path = require('path');
const OUT = process.argv[2] || 'capturas';
fs.mkdirSync(OUT, { recursive: true });
const IPHONE = devices['iPhone 15'];
const rel = [];
const log = (...a) => { const s = a.join(' '); console.log(s); rel.push(s); };
const espera = (p, ms) => p.waitForTimeout(ms);

async function contexto(b) {
  const ctx = await b.newContext({
    ...IPHONE, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo',
    permissions: ['geolocation'], geolocation: { latitude: -15.8145, longitude: -47.9005 },
  });
  await ctx.addInitScript(() => {
    document.addEventListener('securitypolicyviolation', (e) => console.error('BLOQUEADO-CSP', e.violatedDirective, e.blockedURI));
  });
  return ctx;
}
function vigiar(p, nome) {
  p.on('pageerror', (e) => log(`[${nome}] ERRO-JS`, String(e).slice(0, 300)));
  p.on('console', (m) => { if (m.type() === 'error') log(`[${nome}] console:`, m.text().slice(0, 300)); });
  p.on('requestfailed', (r) => log(`[${nome}] falhou`, r.url().slice(0, 160), r.failure()?.errorText || ''));
  p.on('response', (r) => { if (r.status() >= 400) log(`[${nome}] HTTP ${r.status()}`, r.url().slice(0, 160)); });
}
async function foto(p, nome) { await p.screenshot({ path: path.join(OUT, nome + '.png') }); log('captura', nome); }
async function semantica(p) {
  await p.evaluate(() => { const e = document.querySelector('flt-semantics-placeholder'); if (e) e.click(); });
  await espera(p, 800);
}
async function rotulos(p) {
  return p.evaluate(() => [...document.querySelectorAll('flt-semantics, input, textarea')]
    .map((e) => (e.getAttribute('aria-label') || e.textContent || '').trim()).filter((t) => t && t.length < 80)
    .filter((t, i, a) => a.indexOf(t) === i).slice(0, 60));
}
// Toca no elemento (da árvore de acessibilidade do Flutter) cujo texto casa com o padrão.
async function tocar(p, padrao, opc = {}) {
  await semantica(p);
  const r = await p.evaluate(({ src, ultimo }) => {
    const re = new RegExp(src, 'i');
    const els = [...document.querySelectorAll('flt-semantics, input, textarea')].filter((e) => {
      const t = (e.getAttribute('aria-label') || '') + ' ' + (e.getAttribute('placeholder') || '') + ' ' + (e.children.length ? '' : e.textContent || '');
      const b = e.getBoundingClientRect();
      return re.test(t) && b.width > 0 && b.height > 0;
    });
    const e = ultimo ? els[els.length - 1] : els[0];
    if (!e) return null;
    const b = e.getBoundingClientRect();
    return { x: b.x + b.width / 2, y: b.y + b.height / 2 };
  }, { src: padrao.source, ultimo: !!opc.ultimo });
  if (!r) { log('  não achei', padrao.toString(), '| na tela:', JSON.stringify(await rotulos(p))); return false; }
  await p.touchscreen.tap(r.x, r.y);
  await espera(p, opc.ms ?? 900);
  return true;
}
async function digitar(p, campo, texto) {
  if (!(await tocar(p, campo, { ms: 500 }))) return false;
  await p.keyboard.type(texto, { delay: 25 });
  await espera(p, 300);
  return true;
}

async function publicado(b, app) {
  const base = (process.env.BASE || 'https://iservice.app.br/') + app + '/';
  const ctx = await contexto(b);
  const p = await ctx.newPage();
  vigiar(p, app);
  const t0 = Date.now();
  await p.goto(base, { waitUntil: 'load' });
  await p.waitForSelector('flt-glass-pane, flutter-view', { timeout: 60000 }).catch(() => log(`[${app}] Flutter não apareceu em 60 s`));
  log(`[${app}] abriu em ${((Date.now() - t0) / 1000).toFixed(1)} s`);
  await espera(p, 6000);
  await foto(p, `${app}-01-boas-vindas`);
  await semantica(p);
  log(`[${app}] na tela:`, JSON.stringify(await rotulos(p)));

  // Atalho na Tela de Início: manifesto e ícone que o iPhone usa.
  const meta = await p.evaluate(async () => {
    const q = (s) => document.querySelector(s)?.getAttribute('href') || document.querySelector(s)?.getAttribute('content');
    const icone = document.querySelector('link[rel="apple-touch-icon"]')?.href;
    const man = document.querySelector('link[rel="manifest"]')?.href;
    const r = { icone, manifesto: man, titulo: q('meta[name="apple-mobile-web-app-title"]'), capaz: q('meta[name="apple-mobile-web-app-capable"]'), viewport: q('meta[name="viewport"]') };
    if (icone) { const res = await fetch(icone); const bl = await res.blob(); const bm = await createImageBitmap(bl); r.iconeStatus = res.status; r.iconeTamanho = `${bm.width}x${bm.height}`; }
    if (man) { const res = await fetch(man); const j = await res.json(); r.manifestoStatus = res.status; r.display = j.display; r.nome = j.name; r.start = j.start_url; }
    return r;
  });
  log(`[${app}] tela de início:`, JSON.stringify(meta));

  // Busca de endereço (Stadia) a partir da página: mostra se a política de segurança deixa passar.
  const busca = await p.evaluate(async () => {
    try { const r = await fetch('https://api.stadiamaps.com/geocoding/v1/search?text=SQS%20308%2C%20Bras%C3%ADlia&size=1'); return 'status ' + r.status; } catch (e) { return 'bloqueada: ' + e; }
  });
  log(`[${app}] busca de endereço pelo navegador:`, busca);

  // Cadastro: passo 1 (dados) e passo 2 (endereço + "Confira no mapa"). Nada é gravado no banco
  // antes do passo 3 (e-mail e senha), onde o teste para.
  await p.evaluate(() => { location.hash = '#/cadastro/1'; });
  await espera(p, 3500);
  await foto(p, `${app}-02-cadastro-dados`);
  await digitar(p, /Nome completo/, 'Maria Teste da Silva');
  await digitar(p, /nascimento/, '15031990');
  await digitar(p, /CPF/, '52998224725');
  await digitar(p, /Celular/, '61987654321');
  await p.keyboard.press('Enter').catch(() => {});
  await espera(p, 600);
  await foto(p, `${app}-03-cadastro-dados-preenchidos`);
  await tocar(p, /^\s*Continuar\s*$/, { ms: 2500, ultimo: true });
  await foto(p, `${app}-04-cadastro-endereco`);
  log(`[${app}] passo 2 na tela:`, JSON.stringify(await rotulos(p)));
  if (await tocar(p, /Cidade ou região/, { ms: 1500 })) {
    await foto(p, `${app}-05-lista-cidades`);
    // Entorno (GO): o bairro passa a ser obrigatório, é o caso mais completo.
    await tocar(p, /Valparaíso de Goiás/, { ms: 1500 });
  }
  await digitar(p, /^Endereço|Rua 10/, 'Rua 10 Qd 5');
  await digitar(p, /Lote|Bloco \/ casa/, '12');
  await digitar(p, /Bairro/, 'Céu Azul');
  await p.keyboard.press('Enter').catch(() => {});
  await foto(p, `${app}-06-endereco-preenchido`);
  await tocar(p, /^\s*Continuar\s*$/, { ms: 7000, ultimo: true });
  await foto(p, `${app}-07-confira-no-mapa`);
  log(`[${app}] depois do endereço:`, JSON.stringify(await rotulos(p)));
  await tocar(p, /Confirmar|Está certo|Usar este/, { ms: 3000, ultimo: true });
  await foto(p, `${app}-08-passo-email-senha`);

  // Tela de entrar
  await p.evaluate(() => { location.hash = '#/entrar'; });
  await espera(p, 3000);
  await digitar(p, /E-mail/, 'teste@exemplo.com');
  await espera(p, 800);
  await foto(p, `${app}-09-entrar-com-teclado`);
  await ctx.close();
}

const CENAS = [
  ['c-inicio', 'cliente', 'caminho', '/inicio'],
  ['c-mapa', 'cliente', 'caminho', '/profissao/eletricista'],
  ['c-perfil-pro', 'cliente', 'caminho', '/profissional/u-carlos?profissao=eletricista'],
  ['c-solicitar', 'cliente', 'caminho', '/solicitar/u-carlos?profissao=eletricista&esp=3'],
  ['c-acompanhar', 'cliente', 'caminho', '/pedido/p1'],
  ['c-chat', 'cliente', 'caminho', '/pedido/p1/chat?nome=Carlos%20Henrique%20Souza&sub=Eletricista'],
  ['c-avaliar', 'cliente', 'concluido', '/pedido/p1/avaliar'],
  ['c-perfil', 'cliente', 'caminho', '/perfil'],
  ['p-inicio', 'profissional', 'solicitado', '/inicio'],
  ['p-solicitacoes', 'profissional', 'solicitado', '/solicitacoes'],
  ['p-pedido-novo', 'profissional', 'solicitado', '/pedido/p1'],
  ['p-atendimento', 'profissional', 'atendimento', '/pedido/p1'],
  ['p-agenda', 'profissional', 'atendimento', '/agenda'],
  ['p-ganhos', 'profissional', 'concluido', '/ganhos'],
  ['p-perfil', 'profissional', 'concluido', '/perfil'],
];
const PORTA = { cliente: 8101, profissional: 8102 };

async function demo(b) {
  const amostra = path.join(OUT, 'amostra.jpg');
  for (const [n, app, etapa, rota] of CENAS) {
    const ctx = await contexto(b);
    const p = await ctx.newPage();
    vigiar(p, 'demo ' + n);
    try {
      await p.goto(`http://localhost:${PORTA[app]}/?etapa=${etapa}#/inicio`);
      await espera(p, 6000);
      if (rota !== '/inicio') { await p.evaluate((r) => { location.hash = '#' + r; }, rota); await espera(p, 4500); }
      if (n === 'c-chat') {
        if (await digitar(p, /mensagem|Escreva/i, 'Oi, Carlos! Pode vir às 10h?')) await foto(p, 'demo-c-chat-digitando');
      }
      if (n === 'c-avaliar') {
        // Foto da galeria: o iPhone abre o seletor de fotos; aqui entregamos uma imagem pronta.
        fs.existsSync(amostra) || fs.copyFileSync(path.join(__dirname, 'amostra.jpg'), amostra);
        p.on('filechooser', async (fc) => { log('  seletor de foto abriu, multiplo=' + fc.isMultiple()); await fc.setFiles(amostra); });
        await tocar(p, /Adicionar foto/, { ms: 3000 });
      }
      await foto(p, 'demo-' + n);
    } catch (e) { log('demo', n, 'FALHOU', String(e).slice(0, 200)); }
    await ctx.close();
  }
}

(async () => {
  const parte = process.env.PARTE || 'tudo';
  const b = await webkit.launch();
  log('WebKit', b.version(), '| aparelho iPhone 15', JSON.stringify(IPHONE.viewport));
  if (parte !== 'demo') for (const app of ['cliente', 'profissional']) {
    try { await publicado(b, app); } catch (e) { log(`[${app}] FALHOU`, String(e).slice(0, 300)); }
  }
  if (parte !== 'publicado') await demo(b);
  await b.close();
  fs.writeFileSync(path.join(OUT, 'relatorio.txt'), rel.join('\n') + '\n');
})();
