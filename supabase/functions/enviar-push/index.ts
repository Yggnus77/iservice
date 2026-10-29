// Envia as notificações do iService como push (Firebase Cloud Messaging, API v1).
// O banco chama esta função a cada linha nova em public.notificacoes
// (gatilho notificacao_push -> chamar_funcao('enviar-push')).
//
// Publicar:  supabase functions deploy enviar-push
// Segredo:   FCM_CONTA_SERVICO = conteúdo do JSON da conta de serviço do Firebase
//            (Firebase > Configurações do projeto > Contas de serviço > Gerar nova chave privada).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const url = Deno.env.get("SUPABASE_URL")!;
const chave = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(url, chave, { auth: { persistSession: false } });

type ContaServico = { project_id: string; client_email: string; private_key: string; token_uri?: string };

let acesso: { token: string; expira: number } | null = null;

function base64url(dados: ArrayBuffer | string): string {
  const bytes = typeof dados === "string" ? new TextEncoder().encode(dados) : new Uint8Array(dados);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// Token OAuth do Google a partir da conta de serviço (JWT assinado com RS256).
async function tokenGoogle(conta: ContaServico): Promise<string> {
  const agora = Math.floor(Date.now() / 1000);
  if (acesso && acesso.expira > agora + 60) return acesso.token;
  const tokenUri = conta.token_uri ?? "https://oauth2.googleapis.com/token";
  const cabecalho = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const corpo = base64url(JSON.stringify({
    iss: conta.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: tokenUri,
    iat: agora,
    exp: agora + 3600,
  }));
  const pem = conta.private_key.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const chavePrivada = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const assinatura = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", chavePrivada, new TextEncoder().encode(`${cabecalho}.${corpo}`));
  const resp = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${cabecalho}.${corpo}.${base64url(assinatura)}`,
    }),
  });
  if (!resp.ok) throw new Error(`Google OAuth: ${resp.status} ${await resp.text()}`);
  const j = await resp.json();
  acesso = { token: j.access_token, expira: agora + (j.expires_in ?? 3600) };
  return acesso.token;
}

Deno.serve(async (req) => {
  // Só o banco (com a chave service_role) pode chamar.
  if (req.headers.get("Authorization") !== `Bearer ${chave}`) {
    return new Response("Não autorizado", { status: 401 });
  }
  const bruto = Deno.env.get("FCM_CONTA_SERVICO");
  if (!bruto) return new Response("FCM_CONTA_SERVICO não configurado", { status: 503 });
  const conta = JSON.parse(bruto) as ContaServico;

  const { notificacao_id } = (await req.json().catch(() => ({}))) as { notificacao_id?: number };
  if (!notificacao_id) return new Response("notificacao_id obrigatório", { status: 400 });

  const { data: n, error } = await db.from("notificacoes").select("*").eq("id", notificacao_id).maybeSingle();
  if (error) return new Response(error.message, { status: 500 });
  if (!n) return new Response("Notificação não encontrada", { status: 404 });

  const { data: aparelhos } = await db.from("dispositivos").select("token").eq("usuario_id", n.usuario_id);
  if (!aparelhos?.length) return Response.json({ enviados: 0 });

  // Os valores de "data" no FCM precisam ser texto.
  const dados: Record<string, string> = { tipo: String(n.tipo), notificacao_id: String(n.id) };
  for (const [k, v] of Object.entries(n.dados ?? {})) {
    if (v !== null && v !== undefined) dados[k] = typeof v === "string" ? v : JSON.stringify(v);
  }

  const token = await tokenGoogle(conta);
  let enviados = 0;
  const invalidos: string[] = [];
  for (const { token: destino } of aparelhos) {
    const resp = await fetch(`https://fcm.googleapis.com/v1/projects/${conta.project_id}/messages:send`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({
        message: {
          token: destino,
          notification: { title: n.titulo, body: n.corpo },
          data: dados,
          android: { priority: "high", notification: { sound: "default" } },
          apns: { payload: { aps: { sound: "default" } } },
        },
      }),
    });
    if (resp.ok) {
      enviados++;
      continue;
    }
    const texto = await resp.text();
    // Aplicativo desinstalado ou token vencido: tira da lista.
    if (resp.status === 404 || texto.includes("UNREGISTERED") || texto.includes("registration token is not a valid")) {
      invalidos.push(destino);
    } else {
      console.error("FCM", resp.status, texto);
    }
  }
  if (invalidos.length) await db.from("dispositivos").delete().in("token", invalidos);
  return Response.json({ enviados, removidos: invalidos.length });
});
