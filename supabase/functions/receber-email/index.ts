// Recebe os e-mails que chegam em qualquer endereço @iservice.app.br e coloca na caixa
// de suporte do painel (aba E-mails). O Resend chama esta função a cada e-mail recebido
// (webhook "email.received"); ela busca o conteúdo, guarda os anexos e entrega no rodízio.
//
// Publicar:  supabase functions deploy receber-email --no-verify-jwt
// Segredos:  RESEND_WEBHOOK_SECRET = "Signing secret" do webhook no Resend (whsec_...)
//            RESEND_API_KEY        = chave do Resend com permissão "Full access"
//                                    (a de "Sending access" não lê e-mails recebidos)
//            RESEND_LEITURA_KEY    = opcional: chave "Full access" separada, se preferir
//                                    manter a RESEND_API_KEY só com envio
import { createClient } from "npm:@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL")!;
const chave = (() => {
  const novas = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (novas) {
    const k = JSON.parse(novas) as Record<string, string>;
    if (k["default"]) return k["default"];
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
})();
const db = createClient(url, chave, { auth: { persistSession: false } });

const LIMITE_ANEXO = 15 * 1024 * 1024; // igual ao limite do bucket "suporte"
const LIMITE_TOTAL = 40 * 1024 * 1024;

// ---------------------------------------------------------------------------
// Assinatura do webhook (padrão Svix, usado pelo Resend)
// ---------------------------------------------------------------------------
function base64ParaBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function bytesParaBase64(bytes: ArrayBuffer): string {
  let s = "";
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return btoa(s);
}

function iguais(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

async function assinaturaValida(req: Request, corpo: string): Promise<boolean> {
  const segredo = Deno.env.get("RESEND_WEBHOOK_SECRET");
  const id = req.headers.get("svix-id");
  const quando = req.headers.get("svix-timestamp");
  const assinaturas = req.headers.get("svix-signature");
  if (!segredo || !id || !quando || !assinaturas) return false;
  // Recusa avisos com mais de 5 minutos de diferença (proteção contra reenvio malicioso).
  if (Math.abs(Date.now() / 1000 - Number(quando)) > 300) return false;
  const chaveHmac = await crypto.subtle.importKey(
    "raw", base64ParaBytes(segredo.replace(/^whsec_/, "")), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const esperado = bytesParaBase64(await crypto.subtle.sign("HMAC", chaveHmac, new TextEncoder().encode(`${id}.${quando}.${corpo}`)));
  return assinaturas.split(" ").some((a) => {
    const [versao, valor] = a.split(",");
    return versao === "v1" && !!valor && iguais(valor, esperado);
  });
}

// ---------------------------------------------------------------------------
// Utilidades de e-mail
// ---------------------------------------------------------------------------
/** "Maria Souza <maria@x.com>" -> { email, nome } */
function separarEndereco(v: string): { email: string; nome: string | null } {
  const m = v.match(/^\s*"?([^"<]*?)"?\s*<([^>]+)>\s*$/);
  if (m) return { email: m[2].trim().toLowerCase(), nome: m[1].trim() || null };
  return { email: v.trim().toLowerCase(), nome: null };
}

function cabecalho(headers: Record<string, unknown> | null | undefined, nome: string): string {
  if (!headers) return "";
  for (const [k, v] of Object.entries(headers)) {
    if (k.toLowerCase() === nome) return Array.isArray(v) ? v.join(" ") : String(v ?? "");
  }
  return "";
}

/** Message-IDs de In-Reply-To e References, sem os sinais < >. */
function idsDeMensagem(...valores: string[]): string[] {
  const ids = new Set<string>();
  for (const v of valores) for (const m of v.matchAll(/<([^<>\s]+)>/g)) ids.add(m[1]);
  return [...ids];
}

/** Texto simples a partir do HTML, para quando o e-mail chega sem a versão em texto. */
function htmlParaTexto(html: string): string {
  return html
    .replace(/<(style|script|head)[\s\S]*?<\/\1>/gi, "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|div|tr|li|h[1-6]|blockquote)>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
}

function nomeSeguro(nome: string): string {
  return (nome || "anexo").normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^\w.\-]+/g, "_").slice(-120);
}

type Anexo = { id: string; filename: string; content_type: string; size?: number; download_url?: string };

async function guardarAnexos(emailId: string, chaveResend: string): Promise<{ nome: string; tipo: string; tamanho: number; caminho: string | null }[]> {
  const resp = await fetch(`https://api.resend.com/emails/receiving/${emailId}/attachments`, {
    headers: { Authorization: `Bearer ${chaveResend}` },
  });
  if (!resp.ok) {
    console.error("Anexos", resp.status, await resp.text().catch(() => ""));
    return [];
  }
  const lista = ((await resp.json()) as { data?: Anexo[] }).data ?? [];
  const guardados = [];
  let total = 0;
  for (const a of lista) {
    const item = { nome: a.filename || "anexo", tipo: a.content_type || "application/octet-stream", tamanho: a.size ?? 0, caminho: null as string | null };
    if (a.download_url && (a.size ?? 0) <= LIMITE_ANEXO && total + (a.size ?? 0) <= LIMITE_TOTAL) {
      try {
        const arq = await fetch(a.download_url);
        if (arq.ok) {
          const bytes = new Uint8Array(await arq.arrayBuffer());
          if (bytes.length <= LIMITE_ANEXO) {
            const caminho = `recebidos/${emailId}/${a.id}-${nomeSeguro(item.nome)}`;
            const { error } = await db.storage.from("suporte").upload(caminho, bytes, { contentType: item.tipo, upsert: true });
            if (!error) { item.caminho = caminho; item.tamanho = bytes.length; total += bytes.length; }
            else console.error("Storage", error.message);
          }
        }
      } catch (e) {
        console.error("Baixar anexo", String(e));
      }
    }
    guardados.push(item);
  }
  return guardados;
}

// ---------------------------------------------------------------------------
Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Use POST", { status: 405 });
  const corpo = await req.text();
  if (!(await assinaturaValida(req, corpo))) return new Response("Assinatura inválida", { status: 401 });

  const evento = JSON.parse(corpo) as { type?: string; data?: { email_id?: string } };
  if (evento.type !== "email.received" || !evento.data?.email_id) return Response.json({ ignorado: evento.type });
  const emailId = evento.data.email_id;

  const chaveResend = Deno.env.get("RESEND_LEITURA_KEY") ?? Deno.env.get("RESEND_API_KEY");
  if (!chaveResend) return new Response("RESEND_API_KEY não configurado", { status: 503 });

  const resp = await fetch(`https://api.resend.com/emails/receiving/${emailId}`, {
    headers: { Authorization: `Bearer ${chaveResend}` },
  });
  if (!resp.ok) {
    const erro = await resp.text().catch(() => "");
    console.error("Resend receiving", resp.status, erro);
    // 5xx faz o Resend tentar de novo mais tarde.
    return new Response("Falha ao ler o e-mail", { status: 502 });
  }
  const email = (await resp.json()) as {
    from: string; to?: string[]; cc?: string[]; reply_to?: string[]; subject?: string; html?: string | null; text?: string | null;
    headers?: Record<string, unknown>; message_id?: string; attachments?: unknown[];
  };

  // Se o remetente pediu resposta em outro endereço (Reply-To), é com esse que conversamos.
  const responderPara = email.reply_to?.[0] ? separarEndereco(email.reply_to[0]) : null;
  const remetente = separarEndereco(email.from ?? "");
  const contato = responderPara?.email && !responderPara.email.endsWith("@iservice.app.br") ? { ...responderPara, nome: responderPara.nome ?? remetente.nome } : remetente;

  // Avisos automáticos de "não entregue" e respostas automáticas de férias continuam
  // entrando (a equipe precisa saber), mas nunca geram resposta automática nossa.
  const anexos = email.attachments?.length ? await guardarAnexos(emailId, chaveResend) : [];
  const texto = email.text?.trim() || (email.html ? htmlParaTexto(email.html) : "");

  const { data, error } = await db.rpc("suporte_receber", {
    p: {
      id_externo: emailId,
      message_id: (email.message_id ?? "").replace(/^<|>$/g, ""),
      referencias: idsDeMensagem(cabecalho(email.headers, "in-reply-to"), cabecalho(email.headers, "references")),
      de_email: contato.email,
      de_nome: contato.nome,
      para: (email.to ?? []).map((x) => separarEndereco(x).email),
      cc: (email.cc ?? []).map((x) => separarEndereco(x).email),
      assunto: email.subject ?? "",
      texto,
      html: email.html ?? null,
      anexos,
    },
  });
  if (error) {
    console.error("suporte_receber", error.message);
    return new Response("Falha ao guardar", { status: 500 });
  }

  // Fora do horário de atendimento, a conversa nova recebe uma resposta automática
  // com o horário de volta. Nunca responde a respostas automáticas e listas.
  const automatico = /auto-(replied|generated)/i.test(cabecalho(email.headers, "auto-submitted")) ||
    /bulk|junk|list|auto_reply/i.test(cabecalho(email.headers, "precedence")) ||
    cabecalho(email.headers, "list-id") !== "" || cabecalho(email.headers, "x-autoreply") !== "";
  const resultado = data as { conversa_id?: number; nova?: boolean } | null;
  if (resultado?.nova && resultado.conversa_id && !automatico) {
    await respostaAutomatica(resultado.conversa_id).catch((e) => console.error("resposta automática", String(e)));
  }
  return Response.json(data);
});

// ---------------------------------------------------------------------------
// Resposta automática fora do horário
// ---------------------------------------------------------------------------
const DIAS = ["", "segunda", "terça", "quarta", "quinta", "sexta", "sábado", "domingo"];

function hora(h: string): string {
  const [hh, mm] = h.split(":");
  return mm === "00" ? `${Number(hh)}h` : `${Number(hh)}h${mm}`;
}

/** "de segunda a sábado, das 8h às 20h" */
export function textoHorario(h: { dias?: number[]; inicio?: string; fim?: string }): string {
  const dias = [...new Set(h.dias ?? [])].sort((a, b) => a - b);
  const seguidos = dias.length > 1 && dias.every((d, i) => i === 0 || d === dias[i - 1] + 1);
  const quando = dias.length === 7
    ? "todos os dias"
    : seguidos
    ? `de ${DIAS[dias[0]]} a ${DIAS[dias[dias.length - 1]]}`
    : dias.map((d) => DIAS[d]).join(", ").replace(/, ([^,]*)$/, " e $1");
  return `${quando}, das ${hora(h.inicio ?? "08:00")} às ${hora(h.fim ?? "20:00")}`;
}

async function respostaAutomatica(conversa: number) {
  const { data, error } = await db.rpc("suporte_resposta_automatica", { p_conversa: conversa });
  if (error) throw error;
  const r = data as {
    enviar: boolean; para?: string; nome?: string | null; assunto?: string; protocolo?: string;
    in_reply_to?: string | null; horario?: { dias?: number[]; inicio?: string; fim?: string }; whatsapp?: string;
  };
  if (!r?.enviar || !r.para) return;
  const chaveEnvio = Deno.env.get("RESEND_API_KEY");
  if (!chaveEnvio) return;
  const remetente = Deno.env.get("SUPORTE_REMETENTE") ?? "suporte@iservice.app.br";
  const primeiro = (r.nome ?? "").trim().split(/\s+/)[0];
  const linhas = [
    primeiro ? `Olá, ${primeiro}!` : "Olá!",
    "",
    `Recebemos a sua mensagem (protocolo ${r.protocolo}). Agora estamos fora do horário de atendimento, que é ${textoHorario(r.horario ?? {})}, no horário de Brasília.`,
    "Assim que voltarmos, uma pessoa da nossa equipe responde por aqui. Não precisa mandar de novo.",
    "",
    "Se for uma emergência durante um serviço, use o botão de emergência no pedido, no app. Ele funciona 24 horas. Se houver risco, ligue para o 190 (polícia) ou o 192 (SAMU).",
    "",
    "Equipe iService",
    "iservice.app.br",
  ];
  const texto = linhas.join("\n");
  const html = `<div style="font-family:Montserrat,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:15px;line-height:1.6;color:#0A1F44;">${
    linhas.map((l) => l ? `<p style="margin:0 0 4px 0;">${l.replace(/&/g, "&amp;").replace(/</g, "&lt;")}</p>` : "<br>").join("")
  }</div>`;
  const headers: Record<string, string> = { "Auto-Submitted": "auto-replied", "X-Auto-Response-Suppress": "All" };
  if (r.in_reply_to) {
    headers["In-Reply-To"] = `<${r.in_reply_to}>`;
    headers["References"] = `<${r.in_reply_to}>`;
  }
  const resp = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${chaveEnvio}`, "Idempotency-Key": `automatica-${conversa}` },
    body: JSON.stringify({
      from: `Suporte iService <${remetente}>`,
      to: [r.para],
      reply_to: remetente,
      subject: `Re: ${(r.assunto ?? "").replace(/^\s*re:\s*/i, "")} [${r.protocolo}]`,
      text: texto,
      html,
      headers,
    }),
  });
  if (!resp.ok) console.error("Resend resposta automática", resp.status, await resp.text().catch(() => ""));
}
