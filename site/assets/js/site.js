// Paliativo contra clickjacking: aberto dentro de um iframe de outro site, a
// página some e tenta abrir no lugar dela. O bloqueio definitivo é o cabeçalho HTTP.
if (window.top !== window.self) {
  document.documentElement.style.setProperty('display', 'none', 'important');
  try { window.top.location.replace(window.location.href); } catch (e) { /* bloqueado */ }
}

/* Contatos e links das lojas: preencha aqui e o site inteiro se atualiza.
   Campo vazio mostra "Em breve". */
const CONTATO = {
  whatsapp: '5598985516037',   // só números com DDI e DDD, ex.: '5561999999999'
  email: 'suporte@iservice.app.br',      // ex.: 'contato@seudominio.com.br'
  instagram: 'iserviceapp.br',  // usuário sem @, ex.: 'iservice.oficial'
  cnpj: ''        // ex.: '00.000.000/0001-00'
};
// Versão de teste: Android baixa o APK; iPhone usa a versão web até sair na App Store.
const APPS = {
  cliente: { apk: 'https://github.com/Yggnus77/iservice/releases/download/teste-android/iservice-cliente.apk', web: '/cliente/' },
  profissional: { apk: 'https://github.com/Yggnus77/iservice/releases/download/teste-android/iservice-profissional.apk', web: '/profissional/' }
};
const LOJAS = {
  ios: '',        // link da App Store quando o app for aprovado
  android: ''     // link do Google Play quando o app for aprovado
};

// Contagem de visitas e cliques em "Baixar" (painel > Site e downloads). Sem cookies:
// um código aleatório que muda todo dia, só para contar cada pessoa uma vez por dia.
const METRICAS = {
  url: 'https://aurjqwqqrxaexmwozezr.supabase.co/rest/v1/rpc/registrar_evento_site',
  chave: 'sb_publishable_Gc3o5rwSwK-ID6cYTGPmZA_8NO1hqkW'
};

(function () {
  const visitante = (() => {
    const hoje = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Sao_Paulo' });
    try {
      const salvo = JSON.parse(localStorage.getItem('iservice-visita') || 'null');
      if (salvo && salvo.dia === hoje && /^[a-z0-9]{8,40}$/.test(salvo.id)) return salvo.id;
    } catch (e) { /* sem armazenamento: código novo a cada página */ }
    const id = Array.from(crypto.getRandomValues(new Uint8Array(12)), (b) => (b % 36).toString(36)).join('');
    try { localStorage.setItem('iservice-visita', JSON.stringify({ dia: hoje, id })); } catch (e) { /* ignora */ }
    return id;
  })();
  const registrar = (dados) => {
    if (/^(localhost|127\.)/.test(location.hostname)) return;
    try {
      fetch(METRICAS.url, {
        method: 'POST', keepalive: true,
        headers: { 'Content-Type': 'application/json', apikey: METRICAS.chave },
        body: JSON.stringify({ p_visitante: visitante, ...dados })
      }).catch(() => {});
    } catch (e) { /* contagem nunca atrapalha o site */ }
  };
  // De onde a pessoa veio: o código de campanha do link (?utm_source=instagram) ou o site anterior.
  const origem = (() => {
    const q = new URLSearchParams(location.search);
    const campanha = (q.get('utm_source') || q.get('origem') || '').toLowerCase();
    if (campanha) return { p_origem: campanha.slice(0, 30), p_meio: (q.get('utm_medium') || '').toLowerCase().slice(0, 30) || null };
    let host = '';
    try { host = document.referrer ? new URL(document.referrer).hostname.replace(/^www\./, '') : ''; } catch (e) { /* ignora */ }
    if (!host || host === location.hostname || host.endsWith('iservice.app.br')) return {};
    const conhecidos = [['google', /(^|\.)google\./], ['instagram', /instagram\.com$/], ['facebook', /(facebook\.com|fb\.me)$/],
      ['whatsapp', /(whatsapp\.com|wa\.me)$/], ['youtube', /youtube\.com$/], ['tiktok', /tiktok\.com$/], ['bing', /bing\.com$/],
      ['twitter', /(t\.co|x\.com|twitter\.com)$/], ['linkedin', /(linkedin\.com|lnkd\.in)$/]];
    const achado = conhecidos.find(([, re]) => re.test(host));
    return { p_origem: achado ? achado[0] : host.slice(0, 30) };
  })();
  registrar({ p_tipo: 'visita', p_pagina: location.pathname.slice(0, 60), ...origem });

  const formatarFone = (n) => {
    const d = n.replace(/\D/g, '').replace(/^55/, '');
    return d.length === 11 ? `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}` : n;
  };
  const contatos = {
    whatsapp: CONTATO.whatsapp && { href: `https://wa.me/${CONTATO.whatsapp.replace(/\D/g, '')}`, texto: formatarFone(CONTATO.whatsapp) },
    email: CONTATO.email && { href: `mailto:${CONTATO.email}`, texto: CONTATO.email },
    instagram: CONTATO.instagram && { href: `https://instagram.com/${CONTATO.instagram.replace(/^@/, '')}`, texto: `@${CONTATO.instagram.replace(/^@/, '')}` }
  };

  document.querySelectorAll('[data-contato]').forEach((el) => {
    const c = contatos[el.dataset.contato];
    const alvo = el.querySelector('[data-texto]') || el;
    if (c) {
      el.href = c.href;
      if (!el.hasAttribute('data-manter-texto')) alvo.textContent = c.texto;
      if (c.href.startsWith('http')) { el.target = '_blank'; el.rel = 'noopener'; }
    } else {
      el.removeAttribute('href');
      el.classList.add('breve');
      if (!el.hasAttribute('data-manter-texto')) alvo.textContent += ' (em breve)';
    }
  });
  document.querySelectorAll('[data-se-contato]').forEach((el) => {
    if (!contatos[el.dataset.seContato]) el.hidden = true;
  });
  document.querySelectorAll('[data-cnpj]').forEach((el) => {
    el.textContent = CONTATO.cnpj ? `CNPJ ${CONTATO.cnpj}` : 'CNPJ em registro';
  });

  document.querySelectorAll('[data-loja]').forEach((el) => {
    const url = LOJAS[el.dataset.loja];
    if (url) {
      el.href = url; el.target = '_blank'; el.rel = 'noopener';
      el.removeAttribute('aria-disabled');
      el.querySelector('.breve')?.remove();
      el.querySelector('small').textContent = el.dataset.loja === 'ios' ? 'Baixar na' : 'Disponível no';
    }
  });

  // "Baixar o app" e "Quero me cadastrar": pergunta se é cliente ou profissional
  const botoesBaixar = document.querySelectorAll('[data-baixar]');
  if (botoesBaixar.length) {
    const iphone = /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    const opcao = (tipo, cor, icone, titulo, texto) => `
      <div class="escolha ${cor}" data-tipo="${tipo}">
        <span class="ms">${icone}</span>
        <div>
          <b>${titulo}</b>
          <span>${texto}</span>
          <a class="btn ${cor === 'azul' ? 'btn-azul' : 'btn-laranja'}" href="${iphone ? APPS[tipo].web : APPS[tipo].apk}"${iphone ? '' : ' download'}>
            <span class="ms">${iphone ? 'open_in_browser' : 'download'}</span> ${iphone ? 'Abrir no navegador' : 'Baixar para Android'}
          </a>
          <a class="outro" href="${iphone ? APPS[tipo].apk : APPS[tipo].web}">${iphone ? 'Tem Android? Baixe o app' : 'Tem iPhone? Use pelo navegador'}</a>
        </div>
      </div>`;
    const janela = document.createElement('dialog');
    janela.className = 'janela-baixar';
    janela.setAttribute('aria-labelledby', 'titulo-baixar');
    janela.innerHTML = `
      <button class="fechar" type="button" aria-label="Fechar"><span class="ms">close</span></button>
      <h3 id="titulo-baixar">Baixar o iService</h3>
      <p>Você quer contratar ou oferecer serviços?</p>
      ${opcao('cliente', 'azul', 'person_search', 'Sou cliente', 'Quero contratar um profissional perto de mim.')}
      ${opcao('profissional', 'laranja', 'construction', 'Sou profissional', 'Quero me cadastrar e receber pedidos.')}
      <small>${iphone
        ? 'No iPhone o iService funciona pelo navegador até chegar à App Store.'
        : 'Versão de teste. Se o celular pedir, permita instalar apps desta fonte.'}</small>`;
    document.body.appendChild(janela);
    janela.querySelectorAll('.escolha a').forEach((a) => a.addEventListener('click', () => {
      registrar({ p_tipo: 'baixar', p_app: a.closest('.escolha').dataset.tipo, p_plataforma: a.href.endsWith('.apk') ? 'android' : 'navegador' });
    }));
    janela.querySelector('.fechar').addEventListener('click', () => janela.close());
    janela.addEventListener('click', (e) => { if (e.target === janela) janela.close(); });
    botoesBaixar.forEach((b) => b.addEventListener('click', (e) => {
      e.preventDefault();
      janela.querySelectorAll('.escolha').forEach((el) => el.classList.toggle('destaque', el.dataset.tipo === b.dataset.baixar));
      janela.showModal();
    }));
  }

  const ano = document.getElementById('ano');
  if (ano) ano.textContent = new Date().getFullYear();

  // cabeçalho: transparente sobre o herói, sólido ao rolar
  const topo = document.querySelector('.topo.sobre-heroi');
  if (topo) {
    const atualizar = () => topo.classList.toggle('solido', window.scrollY > 24);
    atualizar();
    window.addEventListener('scroll', atualizar, { passive: true });
  }

  // menu do celular
  const botao = document.querySelector('.abrir-menu');
  const gaveta = document.getElementById('gaveta');
  if (botao && gaveta) {
    const fechar = () => { gaveta.classList.remove('aberta'); botao.setAttribute('aria-expanded', 'false'); botao.querySelector('.ms').textContent = 'menu'; };
    botao.addEventListener('click', () => {
      const aberta = gaveta.classList.toggle('aberta');
      botao.setAttribute('aria-expanded', String(aberta));
      botao.querySelector('.ms').textContent = aberta ? 'close' : 'menu';
      if (aberta && topo) topo.classList.add('solido');
    });
    gaveta.querySelectorAll('a').forEach((a) => a.addEventListener('click', fechar));
  }
})();

// "Por dentro da plataforma": abas Clientes/Profissionais e carrossel de telas reais.
(function () {
  const secao = document.getElementById('por-dentro');
  if (!secao) return;
  const DURACAO = 6000;
  const reduzido = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  let visivel = false;

  const carrosseis = [...secao.querySelectorAll('[data-carrossel]')].map((painel) => {
    const telas = [...painel.querySelectorAll('.tela')];
    const passos = [...painel.querySelectorAll('.telas-passos li')];
    const pontos = [...painel.querySelectorAll('.pontos button')];
    const pausa = painel.querySelector('[data-pausa]');
    const total = telas.length;
    let atual = 0, timer = null, pausado = reduzido, sobre = false;

    const parar = () => { clearTimeout(timer); timer = null; };
    const podeRodar = () => !pausado && !sobre && visivel && !painel.hidden;
    const barra = () => {
      painel.querySelectorAll('.barra').forEach((b) => b.classList.remove('correndo'));
      if (!podeRodar()) return;
      const b = passos[atual].querySelector('.barra');
      void b.offsetWidth; // reinicia a animação
      b.style.setProperty('--duracao', `${DURACAO}ms`);
      b.classList.add('correndo');
    };
    const agendar = () => {
      parar();
      barra();
      if (podeRodar()) timer = setTimeout(() => ir(atual + 1), DURACAO);
    };
    function ir(i) {
      atual = (i + total) % total;
      telas.forEach((t, k) => { t.classList.toggle('ativa', k === atual); t.setAttribute('aria-hidden', String(k !== atual)); });
      passos.forEach((p, k) => {
        p.classList.toggle('ativo', k === atual);
        const b = p.querySelector('button');
        if (k === atual) b.setAttribute('aria-current', 'step'); else b.removeAttribute('aria-current');
      });
      pontos.forEach((p, k) => { if (k === atual) p.setAttribute('aria-current', 'step'); else p.removeAttribute('aria-current'); });
      agendar();
    }
    const mostrarPausa = () => {
      painel.classList.toggle('pausado', pausado);
      pausa.querySelector('.ms').textContent = pausado ? 'play_arrow' : 'pause';
      pausa.setAttribute('aria-label', pausado ? 'Retomar a troca automática' : 'Pausar a troca automática');
    };

    painel.querySelectorAll('[data-ir]').forEach((b) => b.addEventListener('click', () => ir(Number(b.dataset.ir))));
    painel.querySelector('[data-anterior]').addEventListener('click', () => ir(atual - 1));
    painel.querySelector('[data-proximo]').addEventListener('click', () => ir(atual + 1));
    pausa.addEventListener('click', () => { pausado = !pausado; mostrarPausa(); agendar(); });
    const celular = painel.querySelector('.telas-celular');
    celular.addEventListener('mouseenter', () => { sobre = true; agendar(); });
    celular.addEventListener('mouseleave', () => { sobre = false; agendar(); });

    // Arrastar a tela para o lado troca de passo (celular).
    const moldura = painel.querySelector('.moldura');
    let x0 = null;
    moldura.addEventListener('pointerdown', (e) => { x0 = e.clientX; });
    moldura.addEventListener('pointerup', (e) => {
      if (x0 === null) return;
      const dx = e.clientX - x0; x0 = null;
      if (Math.abs(dx) > 40) ir(atual + (dx < 0 ? 1 : -1));
    });
    moldura.addEventListener('pointercancel', () => { x0 = null; });

    mostrarPausa();
    return { painel, ir: () => ir(0), agendar, parar };
  });

  // Abas acessíveis: clique e setas do teclado.
  const abas = [...secao.querySelectorAll('[role="tab"]')];
  const escolher = (aba, foco) => {
    abas.forEach((a) => {
      const sel = a === aba;
      a.setAttribute('aria-selected', String(sel));
      a.tabIndex = sel ? 0 : -1;
      document.getElementById(a.getAttribute('aria-controls')).hidden = !sel;
    });
    carrosseis.forEach((c) => (c.painel.hidden ? c.parar() : c.ir()));
    if (foco) aba.focus();
  };
  abas.forEach((a, i) => {
    a.addEventListener('click', () => escolher(a));
    a.addEventListener('keydown', (e) => {
      const d = { ArrowRight: 1, ArrowLeft: -1 }[e.key];
      if (d) { e.preventDefault(); escolher(abas[(i + d + abas.length) % abas.length], true); }
    });
  });

  // Só troca sozinho quando a seção está na tela.
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(([e]) => {
      visivel = e.isIntersecting;
      carrosseis.forEach((c) => c.agendar());
    }, { threshold: 0.35 }).observe(secao);
  }
})();

// Formulários do site: "Não achou sua profissão? Sugira" (janela na página inicial) e
// "Fazer uma reclamação" (reclamacao.html). Os dois falam com funções do banco que só
// aceitam texto curto, têm limite por dia e caem no painel (Sugestões de profissões e E-mails).
(function () {
  const RPC = 'https://aurjqwqqrxaexmwozezr.supabase.co/rest/v1/rpc/';
  const CHAVE = 'sb_publishable_Gc3o5rwSwK-ID6cYTGPmZA_8NO1hqkW';
  const REGIOES = {
    'Distrito Federal': [['asa-norte', 'Asa Norte'], ['asa-sul', 'Asa Sul'], ['agua-quente', 'Água Quente'], ['aguas-claras', 'Águas Claras'],
      ['arapoanga', 'Arapoanga'], ['arniqueira', 'Arniqueira'], ['brazlandia', 'Brazlândia'], ['candangolandia', 'Candangolândia'],
      ['ceilandia', 'Ceilândia'], ['cruzeiro', 'Cruzeiro'], ['fercal', 'Fercal'], ['gama', 'Gama'], ['guara', 'Guará'], ['itapoa', 'Itapoã'],
      ['jardim-botanico', 'Jardim Botânico'], ['lago-norte', 'Lago Norte'], ['lago-sul', 'Lago Sul'], ['noroeste', 'Noroeste'],
      ['nucleo-bandeirante', 'Núcleo Bandeirante'], ['paranoa', 'Paranoá'], ['park-way', 'Park Way'], ['planaltina', 'Planaltina'],
      ['recanto-das-emas', 'Recanto das Emas'], ['riacho-fundo', 'Riacho Fundo'], ['riacho-fundo-2', 'Riacho Fundo II'], ['samambaia', 'Samambaia'],
      ['santa-maria', 'Santa Maria'], ['sao-sebastiao', 'São Sebastião'], ['estrutural', 'SCIA/Estrutural'], ['sia', 'SIA'],
      ['sobradinho', 'Sobradinho'], ['sobradinho-2', 'Sobradinho II'], ['sol-nascente', 'Sol Nascente/Pôr do Sol'], ['sudoeste', 'Sudoeste/Octogonal'],
      ['taguatinga', 'Taguatinga'], ['varjao', 'Varjão'], ['vicente-pires', 'Vicente Pires']],
    'Entorno (Goiás)': [['aguas-lindas', 'Águas Lindas de Goiás'], ['alexania', 'Alexânia'], ['cidade-ocidental', 'Cidade Ocidental'],
      ['cocalzinho', 'Cocalzinho de Goiás'], ['cristalina', 'Cristalina'], ['formosa', 'Formosa'], ['luziania', 'Luziânia'], ['novo-gama', 'Novo Gama'],
      ['padre-bernardo', 'Padre Bernardo'], ['planaltina-go', 'Planaltina de Goiás'], ['santo-antonio', 'Santo Antônio do Descoberto'],
      ['valparaiso', 'Valparaíso de Goiás']]
  };
  const visitante = () => {
    try {
      const v = JSON.parse(localStorage.getItem('iservice-visita') || 'null');
      if (v && /^[a-z0-9]{8,40}$/.test(v.id)) return v.id;
    } catch (e) { /* sem armazenamento */ }
    return null;
  };
  async function chamar(funcao, dados) {
    let r;
    try {
      r = await fetch(RPC + funcao, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', apikey: CHAVE },
        body: JSON.stringify({ ...dados, p_visitante: visitante() })
      });
    } catch (e) {
      throw new Error('Sem conexão. Confira a internet e tente de novo.');
    }
    const corpo = await r.json().catch(() => null);
    if (!r.ok) {
      throw new Error(corpo && corpo.code === 'P0001' && corpo.message ? corpo.message : 'Não foi possível enviar agora. Tente de novo em alguns minutos.');
    }
    return corpo || {};
  }
  const esc = (t) => String(t).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const mostrarErro = (form, msg, campo) => {
    const caixa = form.querySelector('.form-erro');
    caixa.textContent = msg;
    caixa.hidden = !msg;
    form.querySelectorAll('[aria-invalid]').forEach((el) => el.removeAttribute('aria-invalid'));
    if (campo) { campo.setAttribute('aria-invalid', 'true'); campo.focus(); }
  };
  const enviando = (form, sim, texto) => {
    const b = form.querySelector('[type=submit]');
    if (!b.dataset.original) b.dataset.original = b.innerHTML;
    b.disabled = sim;
    b.innerHTML = sim ? texto : b.dataset.original;
  };

  // ------------------------------------------------ sugestão de profissão
  const abrir = document.querySelectorAll('[data-sugerir]');
  if (abrir.length) {
    const opcoes = Object.entries(REGIOES).map(([grupo, lista]) =>
      `<optgroup label="${grupo}">${lista.map(([id, nome]) => `<option value="${id}">${nome}</option>`).join('')}</optgroup>`).join('');
    const janela = document.createElement('dialog');
    janela.className = 'janela-baixar janela-form';
    janela.setAttribute('aria-labelledby', 'titulo-sugerir');
    janela.innerHTML = `
      <button class="fechar" type="button" aria-label="Fechar"><span class="ms">close</span></button>
      <div data-etapa="form">
        <h3 id="titulo-sugerir">Sugerir uma profissão</h3>
        <p>Diga qual serviço você quer encontrar ou oferecer no iService. As profissões mais pedidas entram primeiro.</p>
        <form class="form-site" novalidate>
          <label class="campo"><span>Qual profissão?</span>
            <input name="profissao" maxlength="60" required autocomplete="off" placeholder="Ex.: Costureira, técnico de celular"></label>
          <fieldset class="campo"><legend>Você é</legend>
            <div class="opcoes">
              <label class="opcao"><input type="radio" name="perfil" value="cliente" checked><span>Cliente<small>Quero contratar</small></span></label>
              <label class="opcao"><input type="radio" name="perfil" value="profissional"><span>Profissional<small>Quero trabalhar</small></span></label>
            </div>
          </fieldset>
          <label class="campo"><span>Onde você está? <em>opcional</em></span>
            <select name="regiao"><option value="">Escolha a cidade ou região</option>${opcoes}<option value="outra">Outra cidade</option></select></label>
          <label class="campo"><span>Contato <em>opcional</em></span>
            <input name="contato" maxlength="120" autocomplete="off" placeholder="Telefone ou e-mail">
            <small>Se quiser, avisamos quando essa profissão chegar à plataforma.</small></label>
          <label class="armadilha" aria-hidden="true">Não preencha<input name="site" tabindex="-1" autocomplete="off"></label>
          <p class="form-erro" role="alert" hidden></p>
          <button class="btn btn-azul" type="submit">Enviar sugestão <span class="ms">arrow_forward</span></button>
        </form>
      </div>
      <div class="form-pronto" data-etapa="pronto" hidden tabindex="-1">
        <span class="ms selo-ok">check_circle</span>
        <h3>Obrigado pela sugestão!</h3>
        <p data-mensagem></p>
        <div class="acoes-pronto">
          <button class="btn btn-contorno-escuro" type="button" data-outra>Sugerir outra</button>
          <button class="btn btn-azul" type="button" data-fechar>Fechar</button>
        </div>
      </div>`;
    document.body.appendChild(janela);
    const form = janela.querySelector('form');
    const etapaForm = janela.querySelector('[data-etapa=form]');
    const etapaPronto = janela.querySelector('[data-etapa=pronto]');
    const voltar = () => { form.reset(); mostrarErro(form, ''); etapaPronto.hidden = true; etapaForm.hidden = false; };
    janela.querySelector('.fechar').addEventListener('click', () => janela.close());
    janela.querySelector('[data-fechar]').addEventListener('click', () => janela.close());
    janela.querySelector('[data-outra]').addEventListener('click', () => { voltar(); form.profissao.focus(); });
    janela.addEventListener('click', (e) => { if (e.target === janela) janela.close(); });
    janela.addEventListener('close', voltar);
    abrir.forEach((b) => b.addEventListener('click', (e) => { e.preventDefault(); janela.showModal(); form.profissao.focus(); }));

    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const nome = form.profissao.value.trim();
      if (nome.length < 2) return mostrarErro(form, 'Escreva o nome da profissão.', form.profissao);
      mostrarErro(form, '');
      enviando(form, true, 'Enviando...');
      try {
        const r = await chamar('site_sugerir_profissao', {
          p_profissao: nome, p_perfil: form.perfil.value, p_regiao: form.regiao.value || null,
          p_contato: form.contato.value.trim() || null, p_armadilha: form.site.value || null
        });
        janela.querySelector('[data-mensagem]').innerHTML = r.ja_existe
          ? `Boa notícia: <b>${esc(nome)}</b> já está no iService. <a href="index.html#baixar" data-baixar-link>Baixe o app</a> para ${form.perfil.value === 'profissional' ? 'se cadastrar' : 'pedir agora'}.`
          : `Recebemos <b>${esc(nome)}</b>. Vamos usar a sua sugestão para escolher as próximas profissões da plataforma.`;
        janela.querySelector('[data-baixar-link]')?.addEventListener('click', () => janela.close());
        etapaForm.hidden = true;
        etapaPronto.hidden = false;
        etapaPronto.focus();
      } catch (err) {
        mostrarErro(form, err.message);
      } finally {
        enviando(form, false);
      }
    });
  }

  // ------------------------------------------------ reclamação
  const rec = document.getElementById('form-reclamacao');
  if (rec) {
    const contador = rec.querySelector('[data-contador]');
    const contar = () => { contador.textContent = `${rec.texto.value.length.toLocaleString('pt-BR')} de 4.000`; };
    rec.texto.addEventListener('input', contar);
    contar();
    const emailOk = (v) => /^[^@\s<>()",;]+@[^@\s<>()",;]+\.[a-z]{2,}$/i.test(v);
    rec.addEventListener('submit', async (e) => {
      e.preventDefault();
      const v = (n) => rec[n].value.trim();
      if (v('nome').length < 2) return mostrarErro(rec, 'Escreva o seu nome.', rec.nome);
      if (!emailOk(v('email'))) return mostrarErro(rec, 'Confira o seu e-mail. É por ele que vamos responder.', rec.email);
      if (!v('motivo')) return mostrarErro(rec, 'Escolha o motivo da reclamação.', rec.motivo);
      if (v('texto').length < 20) return mostrarErro(rec, 'Conte um pouco mais o que aconteceu (pelo menos 20 letras).', rec.texto);
      mostrarErro(rec, '');
      enviando(rec, true, 'Enviando...');
      try {
        const r = await chamar('site_enviar_reclamacao', {
          p_nome: v('nome'), p_email: v('email'), p_motivo: v('motivo'), p_texto: v('texto'),
          p_perfil: rec.perfil.value, p_telefone: v('telefone') || null, p_pedido: v('pedido') || null,
          p_armadilha: rec.site.value || null
        });
        const pronto = document.getElementById('reclamacao-pronta');
        pronto.querySelector('[data-protocolo]').textContent = r.protocolo || 'registrado';
        pronto.querySelector('[data-email]').textContent = v('email').toLowerCase();
        rec.hidden = true;
        pronto.hidden = false;
        pronto.focus();
        window.scrollTo({ top: 0, behavior: 'smooth' });
      } catch (err) {
        mostrarErro(rec, err.message);
      } finally {
        enviando(rec, false);
      }
    });
  }
})();
