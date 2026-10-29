/* Contatos e links das lojas: preencha aqui e o site inteiro se atualiza.
   Campo vazio mostra "Em breve". */
const CONTATO = {
  whatsapp: '',   // só números com DDI e DDD, ex.: '5561999999999'
  email: '',      // ex.: 'contato@seudominio.com.br'
  instagram: '',  // usuário sem @, ex.: 'iservice.oficial'
  cnpj: ''        // ex.: '00.000.000/0001-00'
};
const LOJAS = {
  ios: '',        // link da App Store quando o app for aprovado
  android: ''     // link do Google Play quando o app for aprovado
};

(function () {
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
