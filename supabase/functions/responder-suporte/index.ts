// Envia pelo Resend as respostas que a equipe escreve na aba E-mails do painel.
// O painel chama esta função com o login de quem está escrevendo; quem confere se a
// pessoa é da equipe é o próprio banco (admin_suporte_preparar_envio).
//
// Publicar:  supabase functions deploy responder-suporte --no-verify-jwt
// Segredos:  RESEND_API_KEY (o mesmo da enviar-email; com "Full access" também
//            guardamos o Message-ID, que mantém a conversa agrupada no e-mail do cliente)
//            SUPORTE_REMETENTE = opcional, padrão "suporte@iservice.app.br"
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
const servico = createClient(url, chave, { auth: { persistSession: false } });

const SITE = "https://iservice.app.br";
const REMETENTE = Deno.env.get("SUPORTE_REMETENTE") ?? "suporte@iservice.app.br";
const FONTE = "Montserrat, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";
const ORIGENS = new Set(["https://iservice.app.br", "https://www.iservice.app.br", "http://localhost:3100"]);

function cors(req: Request): Record<string, string> {
  const origem = req.headers.get("origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ORIGENS.has(origem) ? origem : "https://iservice.app.br",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  };
}

function esc(s: unknown): string {
  return String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

/** Texto digitado -> parágrafos em HTML, com links clicáveis. */
function paragrafos(texto: string): string {
  return texto.trim().split(/\n{2,}/).map((p) => {
    const html = esc(p).replace(/\n/g, "<br>").replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" style="color:#0052CC;">$1</a>');
    return `<p style="margin:0 0 16px 0;">${html}</p>`;
  }).join("\n");
}

function quando(v: string): string {
  return new Date(v).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
}

type Envio = {
  mensagem_id: number; conversa_id: number; protocolo: string; para: string; contato_nome: string | null;
  assunto: string; texto: string; autor_nome: string; in_reply_to: string | null; referencias: string[];
  citacao: { de: string; quando: string; texto: string | null } | null;
};

function montarHtml(e: Envio): string {
  const citacao = e.citacao?.texto
    ? `<div style="margin:28px 0 0 0;padding:0 0 0 14px;border-left:3px solid #E1E6EF;color:#7A879D;font-size:13px;line-height:1.55;">
<div style="margin:0 0 6px 0;">Em ${esc(quando(e.citacao.quando))}, ${esc(e.citacao.de)} escreveu:</div>
${esc(e.citacao.texto).replace(/\n/g, "<br>")}
</div>`
    : "";
  return `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><title>${esc(e.assunto)}</title></head>
<body style="margin:0;padding:0;background:#ffffff;">
<div style="max-width:620px;padding:8px 4px 24px 4px;font-family:${FONTE};font-size:15px;line-height:1.6;color:#0A1F44;">
${paragrafos(e.texto)}
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:26px 0 0 0;"><tr>
<td valign="middle" style="padding:0 12px 0 0;"><img src="${SITE}/assets/img/icon-192.png" width="36" height="36" alt="" style="display:block;border:0;width:36px;height:36px;"></td>
<td valign="middle" style="font-family:${FONTE};font-size:14px;line-height:1.4;color:#0A1F44;">
<b>${esc(e.autor_nome)}</b><br>
<span style="color:#4A5B78;">Suporte i<span style="color:#0052CC;">Service</span> · <a href="${SITE}" style="color:#4A5B78;text-decoration:none;">iservice.app.br</a></span>
</td></tr></table>
<p style="margin:18px 0 0 0;font-size:12px;color:#8A97AD;">Protocolo ${esc(e.protocolo)} · Para continuar este atendimento, é só responder este e-mail.</p>
${citacao}
</div>
</body></html>`;
}

function montarTexto(e: Envio): string {
  const partes = [e.texto.trim(), "", e.autor_nome, "Suporte iService · iservice.app.br", "", `Protocolo ${e.protocolo} · Para continuar este atendimento, é só responder este e-mail.`];
  if (e.citacao?.texto) {
    partes.push("", `Em ${quando(e.citacao.quando)}, ${e.citacao.de} escreveu:`, ...e.citacao.texto.split("\n").map((l) => `> ${l}`));
  }
  return partes.join("\n");
}

Deno.serve(async (req) => {
  const h = cors(req);
  if (req.method === "OPTIONS") return new Response("ok", { headers: h });
  if (req.method !== "POST") return new Response("Use POST", { status: 405, headers: h });
  const resposta = (corpo: unknown, status = 200) => Response.json(corpo, { status, headers: h });

  const autorizacao = req.headers.get("authorization");
  if (!autorizacao) return resposta({ erro: "Entre no painel de novo." }, 401);
  const comoUsuario = createClient(url, req.headers.get("apikey") || publica, {
    auth: { persistSession: false },
    global: { headers: { Authorization: autorizacao } },
  });

  const pedido = (await req.json().catch(() => ({}))) as {
    conversa_id?: number | null; texto?: string; para?: string; assunto?: string; reenviar?: number;
  };

  // O banco confere se quem chama é da equipe e registra a mensagem como "enviando".
  const { data, error } = pedido.reenviar
    ? await comoUsuario.rpc("admin_suporte_preparar_reenvio", { p_mensagem: pedido.reenviar })
    : await comoUsuario.rpc("admin_suporte_preparar_envio", {
      p_id: pedido.conversa_id ?? null, p_texto: pedido.texto ?? "", p_para: pedido.para ?? null, p_assunto: pedido.assunto ?? null,
    });
  if (error) return resposta({ erro: error.message, codigo: error.details ?? error.code }, error.code === "P0001" ? 400 : 401);
  const envio = data as Envio;

  const chaveResend = Deno.env.get("RESEND_API_KEY");
  const falhar = async (motivo: string) => {
    await servico.rpc("suporte_resultado_envio", { p_mensagem: envio.mensagem_id, p_ok: false, p_erro: motivo });
    return resposta({ erro: "Não foi possível enviar agora. A mensagem ficou salva e você pode tentar de novo.", conversa_id: envio.conversa_id }, 502);
  };
  if (!chaveResend) return falhar("RESEND_API_KEY não configurado");

  const headers: Record<string, string> = {};
  if (envio.in_reply_to) headers["In-Reply-To"] = `<${envio.in_reply_to}>`;
  if (envio.referencias?.length) headers["References"] = envio.referencias.map((r) => `<${r}>`).join(" ");

  const resp = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${chaveResend}`, "Idempotency-Key": `suporte-${envio.mensagem_id}-${Math.floor(Date.now() / 60000)}` },
    body: JSON.stringify({
      from: `${envio.autor_nome.replace(/["<>]/g, "")} · iService <${REMETENTE}>`,
      to: [envio.para],
      reply_to: REMETENTE,
      subject: envio.assunto,
      html: montarHtml(envio),
      text: montarTexto(envio),
      headers,
      tags: [{ name: "tipo", value: "suporte" }],
    }),
  });
  const corpo = (await resp.json().catch(() => ({}))) as { id?: string; message?: string };
  if (!resp.ok || !corpo.id) {
    console.error("Resend", resp.status, JSON.stringify(corpo));
    return falhar(`${resp.status} ${corpo.message ?? ""}`.trim());
  }

  // O Message-ID que o Resend deu ao e-mail: é por ele que a resposta do cliente volta para esta conversa.
  let messageId: string | null = null;
  try {
    const r = await fetch(`https://api.resend.com/emails/${corpo.id}`, { headers: { Authorization: `Bearer ${chaveResend}` } });
    if (r.ok) messageId = (((await r.json()) as { message_id?: string }).message_id ?? "").replace(/^<|>$/g, "") || null;
  } catch { /* sem Message-ID, o protocolo no assunto ainda agrupa a conversa */ }

  await servico.rpc("suporte_resultado_envio", { p_mensagem: envio.mensagem_id, p_ok: true, p_id_externo: corpo.id, p_message_id: messageId });
  return resposta({ enviado: true, conversa_id: envio.conversa_id, mensagem_id: envio.mensagem_id });
});
