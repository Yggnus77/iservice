// Modelos dos e-mails do iService, na identidade da marca (Montserrat, azul,
// laranja e verde). Sem dependências: a Edge Function enviar-email usa este
// arquivo, e tools/previa_emails.ts gera a prévia e os modelos do Auth com ele.
//
// Cada modelo recebe o contexto da notificação e devolve o conteúdo; montar()
// transforma o conteúdo no HTML (tabelas e estilos em linha, como os
// programas de e-mail exigem) e na versão só texto.

export const SITE = "https://iservice.app.br";
export const SUPORTE_EMAIL = "iservice86@gmail.com";
export const SUPORTE_WHATSAPP = "(98) 98551-6037";
export const SUPORTE_WHATSAPP_LINK = "https://wa.me/5598985516037";
export const INSTAGRAM = "https://instagram.com/iservice.app";

const COR = {
  azul: "#0052CC",
  azulSuave: "#E8F0FC",
  laranja: "#FF8A00",
  laranjaTexto: "#B25F00",
  laranjaSuave: "#FFF4E5",
  verde: "#00A846",
  verdeTexto: "#00873A",
  verdeSuave: "#E6F9EE",
  perigo: "#C62828",
  perigoSuave: "#FDECEC",
  texto: "#0A1F44",
  textoSuave: "#4A5B78",
  linha: "#E1E6EF",
  fundo: "#F4F6FB",
  noite: "#011031",
};

const FONTE = "Montserrat, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";

export type App = "cliente" | "profissional";
export type Tom = "azul" | "laranja" | "verde" | "perigo";

export type Contexto = {
  nome: string;                      // nome completo do destinatário
  app: App;                          // app em que a pessoa usa a conta citada
  titulo: string;                    // título da notificação
  corpo: string;                     // texto da notificação
  dados: Record<string, unknown>;    // dados da notificação + o que a função buscou
};

type Passo = { texto: string; estado?: "feito" | "atual" | "proximo" };

export type Conteudo = {
  assunto: string;
  previa: string;                    // linha cinza que aparece ao lado do assunto
  app?: App;
  selo?: { texto: string; tom: Tom };
  titulo: string;
  saudacao?: string;
  paragrafos: string[];
  destaque?: { rotulo: string; texto: string; tom: Tom };
  detalhes?: [string, string][];
  passosTitulo?: string;
  passos?: Passo[];
  botao?: { texto: string; link: string; tom?: Tom };
  depois?: string[];
  nota?: string;
  linkReserva?: boolean;             // mostra o endereço do botão por extenso
};

// ---------------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------------
export function esc(s: unknown): string {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function primeiroNome(nome: string): string {
  const n = (nome ?? "").trim().split(/\s+/)[0] ?? "";
  return n ? n.charAt(0).toUpperCase() + n.slice(1).toLowerCase() : "";
}

function texto(v: unknown): string {
  return typeof v === "string" ? v.trim() : v === null || v === undefined ? "" : String(v);
}

function urlApp(app: App, caminho = ""): string {
  return `${SITE}/${app}/${caminho}`;
}

function tons(tom: Tom) {
  return {
    azul: { forte: COR.azul, texto: COR.azul, suave: COR.azulSuave },
    laranja: { forte: COR.laranja, texto: COR.laranjaTexto, suave: COR.laranjaSuave },
    verde: { forte: COR.verde, texto: COR.verdeTexto, suave: COR.verdeSuave },
    perigo: { forte: COR.perigo, texto: COR.perigo, suave: COR.perigoSuave },
  }[tom];
}

function dataBr(v: unknown): string {
  const s = texto(v);
  if (!s) return "";
  const d = new Date(s);
  if (isNaN(d.getTime())) return s;
  return d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "America/Sao_Paulo" });
}

// ---------------------------------------------------------------------------
// Modelos de cada etapa (chave = tipo da notificação)
// ---------------------------------------------------------------------------
export const MODELOS: Record<string, (c: Contexto) => Conteudo> = {
  boas_vindas: (c) =>
    c.app === "profissional"
      ? {
        assunto: `${primeiroNome(c.nome) || "Boas-vindas"}, falta pouco para você receber pedidos`,
        previa: "Complete seu cadastro e envie para análise. A gente avisa aqui quando for aprovado.",
        app: "profissional",
        selo: { texto: "Conta criada", tom: "laranja" },
        titulo: "Boas-vindas ao iService",
        paragrafos: [
          "Seu e-mail está confirmado. Agora é só completar o cadastro para começar a receber pedidos de clientes perto de você.",
        ],
        passosTitulo: "Seus próximos passos",
        passos: [
          { texto: "Complete o perfil com foto, profissões e especialidades.", estado: "atual" },
          { texto: "Envie o documento com foto e a selfie para ganhar o selo de verificado.", estado: "proximo" },
          { texto: "Envie o cadastro para análise. Avisamos por e-mail assim que for aprovado.", estado: "proximo" },
        ],
        botao: { texto: "Completar meu cadastro", link: urlApp("profissional") },
        nota: "Neste início, o iService é grátis para profissionais.",
      }
      : {
        assunto: `Boas-vindas ao iService, ${primeiroNome(c.nome) || "que bom ter você aqui"}!`,
        previa: "Profissionais de confiança perto de você, para resolver ainda hoje.",
        app: "cliente",
        selo: { texto: "Conta ativa", tom: "verde" },
        titulo: "Que bom ter você no iService",
        paragrafos: [
          "Seu e-mail está confirmado. A partir de agora você encontra profissionais avaliados perto de você para resolver o que precisa, ainda hoje.",
        ],
        passosTitulo: "Como funciona",
        passos: [
          { texto: "Escolha o serviço: eletricista, encanador, chaveiro, faxina e muito mais." },
          { texto: "Veja primeiro os mais bem avaliados da sua região, com preço e distância." },
          { texto: "Peça direto ao profissional escolhido e acompanhe tudo pelo app." },
        ],
        botao: { texto: "Encontrar um profissional", link: urlApp("cliente") },
        nota: "Todo serviço contratado pelo app tem a Garantia iService: se algo der errado, nossa equipe ajuda a resolver.",
      },

  cadastro_recebido: (c) => {
    const reenvio = c.dados.reenvio === true;
    const profissoes = texto(c.dados.profissoes);
    return {
      assunto: reenvio ? "Recebemos seu cadastro corrigido" : `Recebemos seu cadastro, ${primeiroNome(c.nome) || "profissional"}`,
      previa: "Seu cadastro está em análise. Você não precisa fazer nada agora.",
      app: "profissional",
      selo: { texto: "Em análise", tom: "laranja" },
      titulo: reenvio ? "Seu cadastro voltou para análise" : "Seu cadastro está em análise",
      paragrafos: [
        reenvio
          ? "Obrigado por fazer os ajustes. Nossa equipe vai conferir tudo de novo."
          : "Obrigado por se cadastrar. Nossa equipe está conferindo seus documentos, profissões e certificações. É assim que mantemos o iService seguro para clientes e profissionais.",
      ],
      detalhes: profissoes ? [["Profissões", profissoes], ["Enviado em", dataBr(c.dados.enviado_em) || dataBr(new Date().toISOString())]] : undefined,
      passosTitulo: "Andamento",
      passos: [
        { texto: "Cadastro enviado", estado: "feito" },
        { texto: "Análise da equipe iService", estado: "atual" },
        { texto: "Aprovação e primeiros pedidos", estado: "proximo" },
      ],
      depois: ["Você recebe um e-mail e um aviso no app assim que a análise terminar. Não precisa fazer nada agora."],
      botao: { texto: "Acompanhar no app", link: urlApp("profissional") },
    };
  },

  cadastro_aprovado: (c) => ({
    assunto: `Parabéns, ${primeiroNome(c.nome) || "profissional"}! Seu cadastro foi aprovado`,
    previa: "Você já aparece para clientes da sua região. Ative o modo disponível.",
    app: "profissional",
    selo: { texto: "Aprovado", tom: "verde" },
    titulo: "Você já pode receber pedidos",
    paragrafos: [
      "Conferimos seus dados e seu perfil foi aprovado, com o selo de verificado. A partir de agora você aparece para clientes da sua região.",
    ],
    passosTitulo: "Dicas para começar bem",
    passos: [
      { texto: "Ative o modo disponível sempre que puder atender." },
      { texto: "Responda rápido: cada pedido vai só para você e expira se ficar sem resposta." },
      { texto: "Capriche no atendimento. Os mais bem avaliados aparecem primeiro." },
    ],
    botao: { texto: "Ficar disponível agora", link: urlApp("profissional"), tom: "verde" },
  }),

  cadastro_recusado: (c) => ({
    assunto: "Seu cadastro precisa de um ajuste",
    previa: "Falta corrigir um detalhe antes da aprovação.",
    app: "profissional",
    selo: { texto: "Ajuste necessário", tom: "laranja" },
    titulo: "Falta corrigir um detalhe",
    paragrafos: ["Analisamos seu cadastro e encontramos algo que precisa ser ajustado antes da aprovação."],
    destaque: { rotulo: "O que ajustar", texto: c.corpo || "Confira os documentos enviados.", tom: "laranja" },
    depois: ["Depois de corrigir, envie o cadastro de novo pelo app. Ele volta para a análise na hora."],
    botao: { texto: "Corrigir meu cadastro", link: urlApp("profissional") },
  }),

  documento_recusado: (c) => ({
    assunto: "Precisamos de uma nova foto do seu documento",
    previa: "Envie a foto de novo pelo app para continuar a análise.",
    app: "profissional",
    selo: { texto: "Documento", tom: "laranja" },
    titulo: "Envie uma nova foto",
    paragrafos: ["Não conseguimos aprovar uma das fotos que você enviou."],
    destaque: { rotulo: "O que aconteceu", texto: c.corpo, tom: "laranja" },
    passosTitulo: "Para a foto ser aprovada",
    passos: [
      { texto: "Fotografe em um lugar bem iluminado, sem reflexo." },
      { texto: "Mostre o documento inteiro, sem cortar as bordas." },
      { texto: "Confira se os dados estão legíveis antes de enviar." },
    ],
    botao: { texto: "Enviar nova foto", link: urlApp("profissional") },
  }),

  reclamacao_recebida: (c) => {
    const pro = c.app === "profissional";
    const codigo = texto(c.dados.codigo);
    return {
      assunto: `Reclamação aberta sobre o pedido #${codigo}`,
      previa: "Nossa equipe vai ouvir os dois lados e mediar uma solução.",
      app: c.app,
      selo: { texto: "Garantia iService", tom: "azul" },
      titulo: pro ? "Um cliente abriu uma reclamação" : "O profissional abriu uma reclamação",
      paragrafos: [
        `${esc(texto(c.dados.autor_nome) || (pro ? "O cliente" : "O profissional"))} abriu uma reclamação pela Garantia iService sobre o pedido <b>#${esc(codigo)}</b>.`,
        "Isso não é uma punição. Nossa equipe vai ouvir os dois lados e mediar uma solução justa.",
      ],
      detalhes: [
        ["Pedido", `#${codigo}`],
        ["Serviço", texto(c.dados.servico)],
        ["Data do pedido", dataBr(c.dados.data_pedido)],
        ["Motivo", texto(c.dados.motivo)],
      ],
      passosTitulo: "O que fazer agora",
      passos: [
        { texto: "Veja os detalhes do pedido no app." },
        { texto: "Se der para resolver direto, converse pelo chat do pedido." },
        { texto: "Nossa equipe pode entrar em contato para ouvir a sua versão." },
      ],
      botao: { texto: "Ver o pedido", link: urlApp(c.app) },
    };
  },

  reclamacao_aberta: (c) => ({
    assunto: `Recebemos sua reclamação · protocolo ${texto(c.dados.protocolo)}`,
    previa: "Sua reclamação está com a nossa equipe. Guarde o número do protocolo.",
    app: c.app,
    selo: { texto: "Garantia iService", tom: "azul" },
    titulo: "Sua reclamação está com a gente",
    paragrafos: ["Obrigado por avisar. A Garantia iService existe justamente para isso: nossa equipe vai analisar o caso e mediar uma solução."],
    detalhes: [
      ["Protocolo", texto(c.dados.protocolo)],
      ["Pedido", `#${texto(c.dados.codigo)}`],
      ["Serviço", texto(c.dados.servico)],
      ["Motivo", texto(c.dados.motivo)],
    ],
    passosTitulo: "Andamento",
    passos: [
      { texto: "Reclamação recebida", estado: "feito" },
      { texto: "Mediação pela equipe iService", estado: "atual" },
      { texto: "Resolução", estado: "proximo" },
    ],
    depois: ["Você recebe cada atualização por e-mail e no app."],
    botao: { texto: "Acompanhar no app", link: urlApp(c.app) },
  }),

  garantia: (c) => {
    const status = texto(c.dados.status);
    const selo: Conteudo["selo"] = status === "resolvida"
      ? { texto: "Resolvida", tom: "verde" }
      : status === "encerrada"
      ? { texto: "Encerrada", tom: "azul" }
      : { texto: "Em mediação", tom: "laranja" };
    return {
      assunto: `${c.titulo}${texto(c.dados.protocolo) ? ` · protocolo ${texto(c.dados.protocolo)}` : ""}`,
      previa: c.corpo || "Há uma atualização na sua reclamação.",
      app: c.app,
      selo,
      titulo: status === "resolvida" ? "Sua reclamação foi resolvida" : status === "encerrada" ? "Sua reclamação foi encerrada" : "Atualização da sua reclamação",
      paragrafos: [`Há uma atualização da equipe iService sobre o pedido <b>#${esc(texto(c.dados.codigo))}</b>.`],
      destaque: c.corpo ? { rotulo: "Mensagem da equipe", texto: c.corpo, tom: selo.tom } : undefined,
      detalhes: [["Protocolo", texto(c.dados.protocolo)], ["Pedido", `#${texto(c.dados.codigo)}`], ["Serviço", texto(c.dados.servico)]],
      botao: { texto: "Ver no app", link: urlApp(c.app) },
      depois: status === "resolvida" || status === "encerrada"
        ? ["Se ainda restar alguma dúvida, é só responder este e-mail."]
        : undefined,
    };
  },

  conta_suspensa: (c) => ({
    assunto: "Sua conta iService foi suspensa",
    previa: "Se você acredita que houve um engano, fale com a gente.",
    app: c.app,
    selo: { texto: "Conta suspensa", tom: "perigo" },
    titulo: "Sua conta está suspensa",
    paragrafos: ["Para proteger a comunidade, sua conta foi suspensa e não pode ser usada por enquanto. Pedidos que ainda aguardavam resposta foram cancelados."],
    destaque: { rotulo: "Motivo", texto: c.corpo, tom: "perigo" },
    depois: ["Se você acredita que houve um engano, fale com a gente pelo WhatsApp ou responda este e-mail. Toda contestação é analisada por uma pessoa da equipe."],
    botao: { texto: "Falar com o suporte", link: SUPORTE_WHATSAPP_LINK, tom: "verde" },
  }),

  conta_reativada: (c) => ({
    assunto: "Sua conta iService foi reativada",
    previa: "Você já pode usar o iService normalmente.",
    app: c.app,
    selo: { texto: "Conta ativa", tom: "verde" },
    titulo: "Sua conta foi reativada",
    paragrafos: [
      c.app === "profissional"
        ? "Tudo certo: sua conta voltou a funcionar. Ative o modo disponível quando quiser voltar a receber pedidos."
        : "Tudo certo: sua conta voltou a funcionar e você já pode pedir serviços normalmente.",
    ],
    botao: { texto: "Abrir o iService", link: urlApp(c.app), tom: "verde" },
  }),

  exclusao_conta: (c) => {
    const dias = Number(c.dados.dias) || 30;
    return {
      assunto: "Recebemos seu pedido de exclusão de conta",
      previa: `Seus dados serão apagados em até ${dias} dias. Ainda dá para cancelar.`,
      app: c.app,
      selo: { texto: "Exclusão agendada", tom: "perigo" },
      titulo: "Sua conta será excluída",
      paragrafos: [`Como você pediu, sua conta saiu do ar. Seus dados serão apagados em até <b>${dias} dias</b>.`],
      destaque: { rotulo: "Mudou de ideia?", texto: "É só entrar de novo no app dentro desse prazo e tocar em Cancelar exclusão. Tudo volta como estava.", tom: "azul" },
      depois: ["Se não foi você quem pediu, entre no app agora, cancele a exclusão e troque sua senha."],
      botao: { texto: "Cancelar a exclusão", link: urlApp(c.app) },
    };
  },
};

// E-mails do Supabase Auth (colados no painel do Supabase em Authentication >
// Emails). Os {{ ... }} são preenchidos pelo próprio Supabase.
export const MODELOS_AUTH: Record<string, { arquivo: string; nome: string; rotulo: string; conteudo: Conteudo }> = {
  confirmation: {
    arquivo: "confirmar-email.html",
    nome: "Confirm signup",
    rotulo: "Confirmar e-mail",
    conteudo: {
      assunto: "Confirme seu e-mail no iService",
      previa: "Falta só um passo para ativar sua conta.",
      titulo: "Confirme seu e-mail",
      saudacao: "Olá!",
      paragrafos: ["Falta só um passo para ativar sua conta no iService. Toque no botão abaixo para confirmar que este e-mail é seu."],
      botao: { texto: "Confirmar meu e-mail", link: "{{ .ConfirmationURL }}" },
      linkReserva: true,
      nota: "Se você não criou uma conta no iService, pode ignorar este e-mail.",
    },
  },
  recovery: {
    arquivo: "redefinir-senha.html",
    nome: "Reset password",
    rotulo: "Redefinir senha",
    conteudo: {
      assunto: "Redefina sua senha do iService",
      previa: "Use o botão para criar uma nova senha. O link vale por 1 hora.",
      selo: { texto: "Segurança", tom: "azul" },
      titulo: "Crie uma nova senha",
      saudacao: "Olá!",
      paragrafos: ["Recebemos um pedido para redefinir a senha da sua conta. Toque no botão abaixo para criar uma nova. O link vale por 1 hora."],
      botao: { texto: "Criar nova senha", link: "{{ .ConfirmationURL }}" },
      linkReserva: true,
      nota: "Se você não pediu para trocar a senha, ignore este e-mail. Sua senha atual continua valendo.",
    },
  },
  email_change: {
    arquivo: "trocar-email.html",
    nome: "Change email address",
    rotulo: "Trocar e-mail",
    conteudo: {
      assunto: "Confirme seu novo e-mail no iService",
      previa: "Confirme a troca do e-mail da sua conta.",
      selo: { texto: "Segurança", tom: "azul" },
      titulo: "Confirme seu novo e-mail",
      saudacao: "Olá!",
      paragrafos: ["Recebemos um pedido para trocar o e-mail da sua conta de <b>{{ .Email }}</b> para <b>{{ .NewEmail }}</b>. Toque no botão para confirmar."],
      botao: { texto: "Confirmar novo e-mail", link: "{{ .ConfirmationURL }}" },
      linkReserva: true,
      nota: "Se você não pediu essa troca, não toque no botão e fale com o suporte.",
    },
  },
};

export function gerar(tipo: string, c: Contexto): { assunto: string; html: string; texto: string } | null {
  const modelo = MODELOS[tipo];
  if (!modelo) return null;
  const conteudo = modelo(c);
  conteudo.saudacao ??= primeiroNome(c.nome) ? `Olá, ${primeiroNome(c.nome)}!` : "Olá!";
  return { assunto: conteudo.assunto, html: montar(conteudo), texto: montarTexto(conteudo) };
}

// ---------------------------------------------------------------------------
// Montagem do HTML
// ---------------------------------------------------------------------------
// Parágrafos aceitam <b>; o resto do texto vindo do banco é escapado.
function linhas(s: string): string {
  return esc(s).replace(/\n/g, "<br>");
}

function selo(s: NonNullable<Conteudo["selo"]>): string {
  const t = tons(s.tom);
  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 16px 0;"><tr>
<td style="background:${t.suave};border-radius:999px;padding:6px 12px;font-family:${FONTE};font-size:12px;font-weight:700;letter-spacing:.3px;color:${t.texto};text-transform:uppercase;">
<span style="display:inline-block;width:8px;height:8px;border-radius:4px;background:${t.forte};margin-right:6px;vertical-align:1px;"></span>${esc(s.texto)}</td>
</tr></table>`;
}

function botao(b: NonNullable<Conteudo["botao"]>, appTom: Tom): string {
  const tom = b.tom ?? appTom;
  const cor = tons(tom).forte;
  // Como nos apps: texto azul-escuro sobre o laranja, branco nas outras cores.
  const corTexto = tom === "laranja" ? COR.texto : "#ffffff";
  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 8px 0;"><tr>
<td align="center" bgcolor="${cor}" style="border-radius:12px;background:${cor};">
<a href="${b.link}" target="_blank" style="display:inline-block;padding:15px 28px;font-family:${FONTE};font-size:16px;font-weight:700;color:${corTexto};text-decoration:none;border-radius:12px;">${esc(b.texto)}</a>
</td></tr></table>`;
}

function passos(titulo: string | undefined, lista: Passo[], appTom: Tom): string {
  const t = tons(appTom);
  const temEstado = lista.some((p) => p.estado);
  const itens = lista.map((p, i) => {
    // Bolinha de tamanho fixo, alinhada à primeira linha do texto.
    const bolinha = (fundo: string, borda: string, cor: string, conteudo: string, fonte = FONTE) =>
      `<td width="28" valign="top" style="width:28px;padding-top:0;"><div style="width:${borda ? 24 : 28}px;height:${borda ? 24 : 28}px;line-height:${borda ? 24 : 28}px;border-radius:14px;background:${fundo};${borda ? `border:2px solid ${borda};` : ""}text-align:center;font-family:${fonte};font-size:13px;font-weight:800;color:${cor};">${conteudo}</div></td>`;
    let bola: string;
    let corTexto = COR.texto;
    let peso = "600";
    if (!temEstado) {
      bola = bolinha(t.suave, "", t.texto, String(i + 1));
    } else if (p.estado === "feito") {
      bola = bolinha(COR.verde, "", "#ffffff", "&#10003;", "Arial,sans-serif");
    } else if (p.estado === "atual") {
      bola = bolinha("#ffffff", t.forte, t.texto, String(i + 1));
      peso = "700";
    } else {
      bola = bolinha("#ffffff", COR.linha, "#8A97AD", String(i + 1));
      corTexto = COR.textoSuave;
      peso = "500";
    }
    return `<tr><td style="padding:0 0 12px 0;"><table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>${bola}
<td style="padding:3px 0 0 12px;font-family:${FONTE};font-size:15px;line-height:1.5;color:${corTexto};font-weight:${peso};">${linhas(p.texto)}</td></tr></table></td></tr>`;
  }).join("");
  return `${titulo ? `<p style="margin:8px 0 14px 0;font-family:${FONTE};font-size:13px;font-weight:700;letter-spacing:.4px;text-transform:uppercase;color:${COR.textoSuave};">${esc(titulo)}</p>` : ""}
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:0 0 12px 0;">${itens}</table>`;
}

function detalhes(lista: [string, string][]): string {
  const linhasTabela = lista.filter(([, v]) => v && v !== "#").map(([k, v], i) =>
    `<tr><td style="padding:12px 16px;${i ? `border-top:1px solid ${COR.linha};` : ""}font-family:${FONTE};font-size:13px;color:${COR.textoSuave};width:38%;vertical-align:top;">${esc(k)}</td>
<td style="padding:12px 16px;${i ? `border-top:1px solid ${COR.linha};` : ""}font-family:${FONTE};font-size:14px;font-weight:600;color:${COR.texto};vertical-align:top;">${linhas(v)}</td></tr>`
  ).join("");
  if (!linhasTabela) return "";
  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:4px 0 22px 0;border:1px solid ${COR.linha};border-radius:12px;border-collapse:separate;">${linhasTabela}</table>`;
}

function destaque(d: NonNullable<Conteudo["destaque"]>): string {
  const t = tons(d.tom);
  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:4px 0 22px 0;"><tr>
<td style="background:${t.suave};border-left:4px solid ${t.forte};border-radius:8px;padding:16px 18px;">
<p style="margin:0 0 6px 0;font-family:${FONTE};font-size:12px;font-weight:700;letter-spacing:.4px;text-transform:uppercase;color:${t.texto};">${esc(d.rotulo)}</p>
<p style="margin:0;font-family:${FONTE};font-size:15px;line-height:1.55;color:${COR.texto};">${linhas(d.texto)}</p>
</td></tr></table>`;
}

function paragrafo(html: string): string {
  return `<p style="margin:0 0 18px 0;font-family:${FONTE};font-size:16px;line-height:1.6;color:${COR.textoSuave};">${html}</p>`;
}

export function montar(c: Conteudo): string {
  const appTom: Tom = c.app === "profissional" ? "laranja" : "azul";
  const rotuloApp = c.app === "profissional" ? "Profissional" : c.app === "cliente" ? "Cliente" : "";
  const corApp = c.app === "profissional" ? COR.laranjaTexto : COR.azul;
  const corpo = [
    c.selo ? selo(c.selo) : "",
    `<h1 style="margin:0 0 18px 0;font-family:${FONTE};font-size:26px;line-height:1.25;font-weight:800;color:${COR.texto};letter-spacing:-.3px;">${esc(c.titulo)}</h1>`,
    c.saudacao ? paragrafo(`<b style="color:${COR.texto};">${esc(c.saudacao)}</b>`) : "",
    ...c.paragrafos.map(paragrafo),
    c.destaque ? destaque(c.destaque) : "",
    c.detalhes ? detalhes(c.detalhes) : "",
    c.passos ? passos(c.passosTitulo, c.passos, appTom) : "",
    ...(c.depois ?? []).map(paragrafo),
    c.botao ? botao(c.botao, appTom) : "",
    c.botao && c.linkReserva
      ? `<p style="margin:14px 0 0 0;font-family:${FONTE};font-size:12px;line-height:1.5;color:#8A97AD;">Se o botão não funcionar, copie e cole este endereço no navegador:<br><a href="${c.botao.link}" style="color:${COR.azul};word-break:break-all;">${c.botao.link}</a></p>`
      : "",
    c.nota
      ? `<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:24px 0 0 0;"><tr><td style="border-top:1px solid ${COR.linha};padding-top:18px;font-family:${FONTE};font-size:13px;line-height:1.55;color:${COR.textoSuave};">${esc(c.nota)}</td></tr></table>`
      : "",
  ].join("\n");

  return `<!doctype html>
<html lang="pt-BR" xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="x-apple-disable-message-reformatting">
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
<title>${esc(c.assunto)}</title>
<link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@500;600;700;800&display=swap" rel="stylesheet">
<style>
  body{margin:0;padding:0;background:${COR.fundo};-webkit-text-size-adjust:100%;}
  a{color:${COR.azul};}
  @media (max-width:620px){
    .cartao{border-radius:0 !important;}
    .miolo{padding:28px 22px 30px 22px !important;}
    .topo{padding:20px 22px 0 22px !important;}
    h1{font-size:23px !important;}
  }
</style>
</head>
<body style="margin:0;padding:0;background:${COR.fundo};">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:${COR.fundo};font-size:1px;line-height:1px;">${esc(c.previa)}${"&#8199;&#847; ".repeat(40)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${COR.fundo}" style="background:${COR.fundo};">
<tr><td align="center" style="padding:28px 12px 32px 12px;">
<table role="presentation" class="cartao" width="600" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:600px;background:#ffffff;border-radius:18px;overflow:hidden;box-shadow:0 1px 3px rgba(10,31,68,.06);">
<tr><td>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
<td height="5" style="height:5px;line-height:5px;font-size:0;background:${COR.azul};" width="34%">&nbsp;</td>
<td height="5" style="height:5px;line-height:5px;font-size:0;background:${COR.laranja};" width="33%">&nbsp;</td>
<td height="5" style="height:5px;line-height:5px;font-size:0;background:${COR.verde};" width="33%">&nbsp;</td>
</tr></table>
</td></tr>
<tr><td class="topo" style="padding:24px 40px 0 40px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
<td valign="middle">
<a href="${SITE}" target="_blank" style="text-decoration:none;">
<img src="${SITE}/assets/img/icon-192.png" width="40" height="40" alt="" style="display:inline-block;vertical-align:middle;border:0;width:40px;height:40px;">
<span style="display:inline-block;vertical-align:middle;margin-left:8px;font-family:${FONTE};font-size:22px;font-weight:800;letter-spacing:-.4px;color:${COR.texto};">i<span style="color:${COR.azul};">Service</span></span>
</a>
</td>
${rotuloApp ? `<td align="right" valign="middle" style="font-family:${FONTE};font-size:12px;font-weight:700;color:${corApp};letter-spacing:.3px;">${rotuloApp}</td>` : ""}
</tr></table>
</td></tr>
<tr><td class="miolo" style="padding:30px 40px 36px 40px;">
${corpo}
<p style="margin:28px 0 0 0;font-family:${FONTE};font-size:15px;line-height:1.5;color:${COR.texto};">Abraço,<br><b>Equipe iService</b></p>
</td></tr>
<tr><td style="background:${COR.noite};padding:22px 40px;" class="topo">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
<td style="font-family:${FONTE};font-size:14px;line-height:1.6;color:#ffffff;">
<b>Precisa de ajuda?</b><br>
<span style="color:#A6B3CC;">WhatsApp</span> <a href="${SUPORTE_WHATSAPP_LINK}" style="color:#ffffff;text-decoration:none;font-weight:700;">${SUPORTE_WHATSAPP}</a>
<span style="color:#55678A;">&nbsp;·&nbsp;</span>
<span style="color:#A6B3CC;">E-mail</span> <a href="mailto:${SUPORTE_EMAIL}" style="color:#ffffff;text-decoration:none;font-weight:700;">${SUPORTE_EMAIL}</a>
</td></tr></table>
</td></tr>
</table>
<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:600px;">
<tr><td align="center" style="padding:22px 24px 0 24px;font-family:${FONTE};font-size:12px;line-height:1.6;color:#8A97AD;">
iService · Profissionais para o que você precisa, ainda hoje.<br>
Você recebeu este e-mail porque tem uma conta no iService. Avisos sobre a sua conta são enviados mesmo com as notificações desligadas.<br>
<a href="${SITE}" style="color:#8A97AD;">iservice.app.br</a> &nbsp;·&nbsp; <a href="${SITE}/termos.html" style="color:#8A97AD;">Termos de uso</a> &nbsp;·&nbsp; <a href="${SITE}/privacidade.html" style="color:#8A97AD;">Privacidade</a> &nbsp;·&nbsp; <a href="${INSTAGRAM}" style="color:#8A97AD;">Instagram</a>
</td></tr>
</table>
</td></tr>
</table>
</body>
</html>`;
}

function semTags(s: string): string {
  return s.replace(/<br>/g, "\n").replace(/<[^>]+>/g, "");
}

export function montarTexto(c: Conteudo): string {
  const partes: string[] = [c.titulo.toUpperCase(), ""];
  if (c.saudacao) partes.push(c.saudacao, "");
  for (const p of c.paragrafos) partes.push(semTags(p), "");
  if (c.destaque) partes.push(`${c.destaque.rotulo}: ${c.destaque.texto}`, "");
  for (const [k, v] of c.detalhes ?? []) if (v && v !== "#") partes.push(`${k}: ${v}`);
  if (c.detalhes) partes.push("");
  if (c.passos) {
    if (c.passosTitulo) partes.push(c.passosTitulo);
    c.passos.forEach((p, i) => partes.push(`${p.estado === "feito" ? "[ok]" : `${i + 1}.`} ${p.texto}`));
    partes.push("");
  }
  for (const p of c.depois ?? []) partes.push(semTags(p), "");
  if (c.botao) partes.push(`${c.botao.texto}: ${c.botao.link}`, "");
  if (c.nota) partes.push(c.nota, "");
  partes.push("Abraço,", "Equipe iService", "");
  partes.push(`Precisa de ajuda? WhatsApp ${SUPORTE_WHATSAPP} · ${SUPORTE_EMAIL}`);
  partes.push(SITE);
  return partes.join("\n");
}
