// WhatsApp do atendimento dentro do painel (API oficial da Meta, WhatsApp Cloud API).
//
// Três caminhos nesta mesma função:
//   GET  ?hub.mode=subscribe...  confirmação do webhook pela Meta (uma vez, ao configurar)
//   POST da Meta (webhook)       mensagens recebidas e avisos de entregue/lida/falhou
//   POST do painel (com login)   resposta escrita pela equipe na caixa do suporte
//
// As mensagens entram na mesma caixa dos e-mails (rodízio, prazos, cargos).
// Ligações continuam no celular: a API não atende ligações.
//
// Publicar:  supabase functions deploy whatsapp --no-verify-jwt
// Segredos (só depois do CNPJ e da verificação da empresa na Meta):
//   WHATSAPP_TOKEN            token permanente de um usuário do sistema (Meta Business)
//   WHATSAPP_PHONE_NUMBER_ID  id do número no app da Meta (não é o número em si)
//   WHATSAPP_APP_SECRET       chave secreta do app (confere a assinatura dos avisos)
//   WHATSAPP_VERIFY_TOKEN     palavra combinada para confirmar o webhook (qualquer texto longo)
// Ligar no banco: app_config whatsapp_ativo = true.
import { createClient } from "npm:@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL")!;
const publica = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const chave = (() => {
  const novas = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (novas) {
    const k = JSON.parse(novas) as Record<string, string>;
    if (k["default"]) return k["default"];
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
})();
const db = createClient(url, chave, { auth: { persistSession: false } });

const GRAPH = "https://graph.facebook.com/v23.0";
const TOKEN = Deno.env.get("WHATSAPP_TOKEN") ?? "";
const NUMERO_ID = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID") ?? "";
const SEGREDO_APP = Deno.env.get("WHATSAPP_APP_SECRET") ?? "";
const TOKEN_VERIFICACAO = Deno.env.get("WHATSAPP_VERIFY_TOKEN") ?? "";
const CONFIGURADO = !!(TOKEN && NUMERO_ID && SEGREDO_APP);

const LIMITE_ANEXO = 15 * 1024 * 1024;
const ORIGENS = new Set(["https://iservice.app.br", "https://www.iservice.app.br", "http://localhost:3100"]);

function cors(req: Request): Record<string, string> {
  const origem = req.headers.get("origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ORIGENS.has(origem) ? origem : "https://iservice.app.br",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    Vary: "Origin",
  };
}

// ---------------------------------------------------------------------------
// Assinatura da Meta (X-Hub-Signature-256 = HMAC-SHA256 do corpo com a chave do app)
// ---------------------------------------------------------------------------
async function assinaturaValida(corpo: string, cabecalho: string | null): Promise<boolean> {
  if (!SEGREDO_APP || !cabecalho?.startsWith("sha256=")) return false;
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(SEGREDO_APP), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const assinatura = new Uint8Array(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(corpo)));
  const esperado = Array.from(assinatura, (b) => b.toString(16).padStart(2, "0")).join("");
  const recebido = cabecalho.slice(7).toLowerCase();
  if (recebido.length !== esperado.length) return false;
  let dif = 0;
  for (let i = 0; i < esperado.length; i++) dif |= esperado.charCodeAt(i) ^ recebido.charCodeAt(i);
  return dif === 0;
}

// ---------------------------------------------------------------------------
// Envio pela API da Meta
// ---------------------------------------------------------------------------
async function enviarTexto(para: string, texto: string): Promise<{ ok: true; id: string } | { ok: false; erro: string }> {
  const resp = await fetch(`${GRAPH}/${NUMERO_ID}/messages`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${TOKEN}` },
    body: JSON.stringify({ messaging_product: "whatsapp", recipient_type: "individual", to: para, type: "text", text: { preview_url: true, body: texto } }),
  });
  const corpo = (await resp.json().catch(() => ({}))) as { messages?: { id: string }[]; error?: { message?: string; code?: number } };
  const id = corpo.messages?.[0]?.id;
  if (!resp.ok || !id) {
    console.error("WhatsApp envio", resp.status, JSON.stringify(corpo));
    return { ok: false, erro: traduzirErro(corpo.error?.code, corpo.error?.message ?? `${resp.status}`) };
  }
  return { ok: true, id };
}

/** Os erros mais comuns da Meta, em português. */
function traduzirErro(codigo: number | undefined, original: string): string {
  switch (codigo) {
    case 131047: return "Passaram 24 horas desde a última mensagem do cliente. Só com modelo aprovado.";
    case 131026: return "O número não tem WhatsApp ou não pode receber mensagens.";
    case 131051: return "Tipo de mensagem não aceito.";
    case 131056: return "Muitas mensagens seguidas para este número. Espere um pouco.";
    case 190: return "O token do WhatsApp venceu. Gere um token permanente na Meta.";
    case 131031: return "A conta do WhatsApp Business está bloqueada na Meta.";
    case 131042: return "Problema de pagamento na conta da Meta.";
    default: return original.slice(0, 300);
  }
}

// ---------------------------------------------------------------------------
// Mensagens recebidas
// ---------------------------------------------------------------------------
type MsgMeta = {
  id: string; from: string; timestamp?: string; type: string;
  text?: { body?: string };
  image?: Midia; audio?: Midia; video?: Midia; document?: Midia & { filename?: string }; sticker?: Midia;
  location?: { latitude?: number; longitude?: number; name?: string; address?: string };
  contacts?: { name?: { formatted_name?: string }; phones?: { phone?: string }[] }[];
  button?: { text?: string };
  interactive?: { button_reply?: { title?: string }; list_reply?: { title?: string } };
  reaction?: { emoji?: string };
};
type Midia = { id: string; mime_type?: string; caption?: string };
type Anexo = { nome: string; tipo: string; tamanho: number; caminho: string | null };

function nomeSeguro(n: string): string {
  return n.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^\w.-]+/g, "_").slice(0, 80) || "arquivo";
}

const EXTENSAO: Record<string, string> = {
  "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "audio/ogg": "ogg", "audio/mpeg": "mp3", "audio/mp4": "m4a",
  "audio/aac": "aac", "video/mp4": "mp4", "video/3gpp": "3gp", "application/pdf": "pdf",
};

/** Baixa a foto, o áudio, o vídeo ou o documento da Meta e guarda no Storage privado do suporte. */
async function guardarMidia(m: Midia & { filename?: string }, tipo: string, wamid: string): Promise<Anexo> {
  const mime = (m.mime_type ?? "application/octet-stream").split(";")[0].trim();
  const nome = m.filename || `${tipo}.${EXTENSAO[mime] ?? "bin"}`;
  const item: Anexo = { nome, tipo: mime, tamanho: 0, caminho: null };
  try {
    const info = await fetch(`${GRAPH}/${m.id}`, { headers: { Authorization: `Bearer ${TOKEN}` } });
    if (!info.ok) { console.error("Mídia info", info.status); return item; }
    const { url: endereco, file_size } = (await info.json()) as { url?: string; file_size?: number };
    if (!endereco || (file_size ?? 0) > LIMITE_ANEXO) { item.tamanho = file_size ?? 0; return item; }
    const arq = await fetch(endereco, { headers: { Authorization: `Bearer ${TOKEN}` } });
    if (!arq.ok) { console.error("Mídia download", arq.status); return item; }
    const bytes = new Uint8Array(await arq.arrayBuffer());
    item.tamanho = bytes.length;
    if (bytes.length > LIMITE_ANEXO) return item;
    const caminho = `whatsapp/${nomeSeguro(wamid)}/${nomeSeguro(nome)}`;
    const { error } = await db.storage.from("suporte").upload(caminho, bytes, { contentType: mime, upsert: true });
    if (!error) item.caminho = caminho;
    else console.error("Storage", error.message);
  } catch (e) {
    console.error("Mídia", String(e));
  }
  return item;
}

/** Texto que aparece no painel para cada tipo de mensagem. */
async function lerMensagem(m: MsgMeta): Promise<{ texto: string; anexos: Anexo[] }> {
  const anexos: Anexo[] = [];
  const rotulos: Record<string, string> = { image: "Foto", audio: "Áudio", video: "Vídeo", document: "Documento", sticker: "Figurinha" };
  switch (m.type) {
    case "text":
      return { texto: m.text?.body ?? "", anexos };
    case "image": case "audio": case "video": case "document": case "sticker": {
      const midia = m[m.type as "image"];
      if (midia?.id) anexos.push(await guardarMidia(midia, m.type, m.id));
      const legenda = midia?.caption?.trim();
      return { texto: legenda ? legenda : `[${rotulos[m.type]}]`, anexos };
    }
    case "location": {
      const l = m.location ?? {};
      const mapa = l.latitude != null ? `https://www.google.com/maps?q=${l.latitude},${l.longitude}` : "";
      return { texto: ["[Localização]", l.name, l.address, mapa].filter(Boolean).join("\n"), anexos };
    }
    case "contacts":
      return { texto: "[Contato] " + (m.contacts ?? []).map((c) => `${c.name?.formatted_name ?? ""} ${c.phones?.map((p) => p.phone).join(", ") ?? ""}`.trim()).join("; "), anexos };
    case "button":
      return { texto: m.button?.text ?? "[Botão]", anexos };
    case "interactive":
      return { texto: m.interactive?.button_reply?.title ?? m.interactive?.list_reply?.title ?? "[Resposta]", anexos };
    case "reaction":
      return { texto: `[Reagiu com ${m.reaction?.emoji ?? "um emoji"}]`, anexos };
    default:
      return { texto: "[Mensagem que o painel ainda não mostra. Veja no celular do atendimento.]", anexos };
  }
}

// ---------------------------------------------------------------------------
// Resposta automática fora do horário
// ---------------------------------------------------------------------------
const DIAS = ["", "segunda", "terça", "quarta", "quinta", "sexta", "sábado", "domingo"];
function hora(h: string): string {
  const [hh, mm] = h.split(":");
  return mm === "00" ? `${Number(hh)}h` : `${Number(hh)}h${mm}`;
}
function textoHorario(h: { dias?: number[]; inicio?: string; fim?: string }): string {
  const dias = [...new Set(h.dias ?? [])].sort((a, b) => a - b);
  const seguidos = dias.length > 1 && dias.every((d, i) => i === 0 || d === dias[i - 1] + 1);
  const quando = dias.length === 7 ? "todos os dias"
    : seguidos ? `de ${DIAS[dias[0]]} a ${DIAS[dias[dias.length - 1]]}`
    : dias.map((d) => DIAS[d]).join(", ").replace(/, ([^,]*)$/, " e $1");
  return `${quando}, das ${hora(h.inicio ?? "08:00")} às ${hora(h.fim ?? "20:00")}`;
}

async function respostaAutomatica(conversa: number) {
  const { data, error } = await db.rpc("suporte_resposta_automatica_whatsapp", { p_conversa: conversa });
  if (error) throw error;
  const r = data as { enviar: boolean; para?: string; nome?: string | null; protocolo?: string; horario?: { dias?: number[]; inicio?: string; fim?: string } };
  if (!r?.enviar || !r.para) return;
  const primeiro = (r.nome ?? "").trim().split(/\s+/)[0];
  const texto = [
    primeiro ? `Olá, ${primeiro}!` : "Olá!",
    "",
    `Recebemos a sua mensagem (protocolo ${r.protocolo}). Agora estamos fora do horário de atendimento, que é ${textoHorario(r.horario ?? {})}, no horário de Brasília.`,
    "Assim que voltarmos, uma pessoa da nossa equipe responde por aqui.",
    "",
    "Se for uma emergência durante um serviço, use o botão de emergência no pedido, no app. Ele funciona 24 horas. Se houver risco, ligue 190 (polícia) ou 192 (SAMU).",
    "",
    "Equipe iService",
  ].join("\n");
  const envio = await enviarTexto(r.para, texto);
  if (!envio.ok) console.error("resposta automática", envio.erro);
}

async function receberWebhook(corpo: string) {
  const dados = JSON.parse(corpo) as {
    entry?: { changes?: { field?: string; value?: {
      metadata?: { phone_number_id?: string };
      contacts?: { wa_id?: string; profile?: { name?: string } }[];
      messages?: MsgMeta[];
      statuses?: { id: string; status: string; errors?: { code?: number; title?: string; message?: string }[] }[];
    } }[] }[];
  };
  for (const entrada of dados.entry ?? []) {
    for (const mudanca of entrada.changes ?? []) {
      const v = mudanca.value;
      if (mudanca.field !== "messages" || !v) continue;
      // Só o número do atendimento (o mesmo app da Meta pode ter outros números).
      if (v.metadata?.phone_number_id && v.metadata.phone_number_id !== NUMERO_ID) continue;

      for (const s of v.statuses ?? []) {
        const e = s.errors?.[0];
        const { error } = await db.rpc("suporte_whatsapp_status", {
          p_id_externo: s.id, p_status: s.status, p_erro: e ? traduzirErro(e.code, e.message ?? e.title ?? "") : null,
        });
        if (error) console.error("status", error.message);
      }

      for (const m of v.messages ?? []) {
        const contato = v.contacts?.find((c) => c.wa_id === m.from) ?? v.contacts?.[0];
        const { texto, anexos } = await lerMensagem(m);
        const { data, error } = await db.rpc("suporte_receber_whatsapp", {
          p: { id_externo: m.id, telefone: m.from, nome: contato?.profile?.name ?? null, texto, tipo: m.type, anexos },
        });
        if (error) { console.error("receber", error.message); throw error; }
        const r = data as { conversa_id?: number; nova?: boolean } | null;
        if (r?.nova && r.conversa_id) {
          await respostaAutomatica(r.conversa_id).catch((e) => console.error("resposta automática", String(e)));
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Rotas
// ---------------------------------------------------------------------------
Deno.serve(async (req) => {
  const h = cors(req);
  if (req.method === "OPTIONS") return new Response("ok", { headers: h });
  const resposta = (corpo: unknown, status = 200) => Response.json(corpo, { status, headers: h });

  // 1. Confirmação do webhook (a Meta chama uma vez, ao salvar a URL no app).
  if (req.method === "GET") {
    const q = new URL(req.url).searchParams;
    if (TOKEN_VERIFICACAO && q.get("hub.mode") === "subscribe" && q.get("hub.verify_token") === TOKEN_VERIFICACAO) {
      return new Response(q.get("hub.challenge") ?? "", { status: 200 });
    }
    return new Response("Não autorizado", { status: 403 });
  }
  if (req.method !== "POST") return new Response("Use POST", { status: 405, headers: h });

  // 2. Aviso da Meta: vem assinado e sem login.
  const assinatura = req.headers.get("x-hub-signature-256");
  if (assinatura) {
    const corpo = await req.text();
    if (!(await assinaturaValida(corpo, assinatura))) return new Response("Assinatura inválida", { status: 401 });
    try {
      await receberWebhook(corpo);
    } catch (e) {
      // 500 faz a Meta tentar de novo; mensagens repetidas são ignoradas pelo banco.
      console.error("webhook", String(e));
      return new Response("erro", { status: 500 });
    }
    return new Response("ok", { status: 200 });
  }

  // 3. Resposta da equipe pelo painel, com o login de quem escreve.
  const autorizacao = req.headers.get("authorization");
  if (!autorizacao) return resposta({ erro: "Entre no painel de novo." }, 401);
  if (!CONFIGURADO) {
    return resposta({ erro: "O WhatsApp do atendimento ainda não foi ligado. Ele entra no ar depois do CNPJ e da verificação na Meta." }, 503);
  }
  const comoUsuario = createClient(url, req.headers.get("apikey") || publica, {
    auth: { persistSession: false },
    global: { headers: { Authorization: autorizacao } },
  });
  const pedido = (await req.json().catch(() => ({}))) as { conversa_id?: number; texto?: string; reenviar?: number };

  // O banco confere cargo, conversa, janela de 24 h e se o WhatsApp está ligado.
  const { data, error } = await comoUsuario.rpc("admin_suporte_preparar_whatsapp", {
    p_id: pedido.conversa_id ?? null, p_texto: pedido.texto ?? null, p_reenviar: pedido.reenviar ?? null,
  });
  if (error) return resposta({ erro: error.message, codigo: error.details ?? error.code }, error.code === "P0001" ? 400 : 401);
  const envio = data as { mensagem_id: number; conversa_id: number; para: string; texto: string };

  const r = await enviarTexto(envio.para, envio.texto);
  if (!r.ok) {
    await db.rpc("suporte_resultado_envio", { p_mensagem: envio.mensagem_id, p_ok: false, p_erro: r.erro });
    return resposta({ erro: `Não foi possível enviar: ${r.erro} A mensagem ficou salva e você pode tentar de novo.`, conversa_id: envio.conversa_id }, 502);
  }
  await db.rpc("suporte_resultado_envio", { p_mensagem: envio.mensagem_id, p_ok: true, p_id_externo: r.id });
  return resposta({ enviado: true, conversa_id: envio.conversa_id, mensagem_id: envio.mensagem_id });
});
