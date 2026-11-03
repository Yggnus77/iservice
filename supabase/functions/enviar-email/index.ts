// Envia os e-mails de cada etapa do iService (cadastro, garantia, conta) pelo Resend.
// O banco chama esta função quando nasce uma notificação de um tipo que tem e-mail
// (gatilho notificacao_email -> chamar_funcao('enviar-email')). Os textos ficam em modelos.ts.
//
// Publicar:  supabase functions deploy enviar-email --no-verify-jwt
// Segredos:  RESEND_API_KEY   = chave da conta no resend.com (domínio iservice.app.br verificado)
//            EMAIL_REMETENTE  = opcional, padrão "iService <nao-responda@iservice.app.br>"
import { createClient } from "npm:@supabase/supabase-js@2";
import { type App, gerar, SUPORTE_EMAIL } from "./modelos.ts";

const url = Deno.env.get("SUPABASE_URL")!;
// Chave secreta nova (sb_secret_...); a service_role antiga só como reserva.
const chave = (() => {
  const novas = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (novas) {
    const k = JSON.parse(novas) as Record<string, string>;
    if (k["default"]) return k["default"];
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
})();
const db = createClient(url, chave, { auth: { persistSession: false } });

// Só o banco pode chamar: ele manda a senha interna do Vault (public.chamar_funcao).
let segredo: string | null = null;
async function autorizado(req: Request): Promise<boolean> {
  const recebido = req.headers.get("x-iservice-segredo");
  if (!recebido) return false;
  if (!segredo) {
    const { data, error } = await db.rpc("segredo_funcoes");
    if (error || !data) return false;
    segredo = data as string;
  }
  return recebido === segredo;
}

// Completa os dados da notificação com o que o e-mail mostra (pedido, reclamação, profissões).
async function completarDados(n: { usuario_id: string; tipo: string; dados: Record<string, unknown> | null }) {
  const dados: Record<string, unknown> = { ...(n.dados ?? {}) };
  if (dados.pedido_id) {
    const { data: p } = await db.from("pedidos")
      .select("codigo, criado_em, cliente_id, profissional_id, profissoes(nome)")
      .eq("id", String(dados.pedido_id)).maybeSingle();
    if (p) {
      dados.codigo = p.codigo;
      dados.data_pedido = p.criado_em;
      dados.servico = (p.profissoes as { nome?: string } | null)?.nome ?? "";
      dados.papel = p.profissional_id === n.usuario_id ? "profissional" : "cliente";
    }
  }
  if (dados.reclamacao_id) {
    const { data: r } = await db.from("reclamacoes").select("id, motivo, status, autor_id").eq("id", Number(dados.reclamacao_id)).maybeSingle();
    if (r) {
      dados.protocolo = `G-${String(r.id).padStart(5, "0")}`;
      dados.motivo = r.motivo;
      dados.status ??= r.status;
      if (r.autor_id !== n.usuario_id) {
        const { data: autor } = await db.from("perfis").select("nome").eq("id", r.autor_id).maybeSingle();
        dados.autor_nome = (autor?.nome ?? "").trim().split(/\s+/)[0] ?? "";
      }
    }
  }
  if (n.tipo === "cadastro_recebido") {
    const { data: ps } = await db.from("profissional_profissoes").select("profissoes(nome)").eq("profissional_id", n.usuario_id);
    dados.profissoes = (ps ?? []).map((x) => (x.profissoes as { nome?: string } | null)?.nome).filter(Boolean).join(", ");
  }
  if (n.tipo === "exclusao_conta") {
    const { data: cfg } = await db.from("app_config").select("valor").eq("chave", "dias_exclusao_conta").maybeSingle();
    if (cfg?.valor) dados.dias = Number(cfg.valor);
  }
  return dados;
}

Deno.serve(async (req) => {
  if (!(await autorizado(req))) {
    return new Response("Não autorizado", { status: 401 });
  }
  const { notificacao_id } = (await req.json().catch(() => ({}))) as { notificacao_id?: number };
  if (!notificacao_id) return new Response("notificacao_id obrigatório", { status: 400 });

  const { data: n, error } = await db.from("notificacoes").select("*").eq("id", notificacao_id).maybeSingle();
  if (error) return new Response(error.message, { status: 500 });
  if (!n) return new Response("Notificação não encontrada", { status: 404 });

  const { data: perfil } = await db.from("perfis").select("nome, email, e_profissional").eq("id", n.usuario_id).maybeSingle();
  if (!perfil?.email) return Response.json({ enviado: false, motivo: "sem e-mail" });

  const dados = await completarDados(n);
  const { data: pro } = await db.from("profissionais").select("id").eq("id", n.usuario_id).maybeSingle();
  const app: App = dados.papel === "cliente" || dados.papel === "profissional"
    ? dados.papel
    : pro ? "profissional" : "cliente";

  const email = gerar(n.tipo, { nome: perfil.nome ?? "", app, titulo: n.titulo, corpo: n.corpo ?? "", dados });
  if (!email) return Response.json({ enviado: false, motivo: "tipo sem e-mail" });

  // Um e-mail por notificação, mesmo se a função for chamada duas vezes.
  const { error: dup } = await db.from("emails_enviados").insert({
    notificacao_id: n.id, usuario_id: n.usuario_id, tipo: n.tipo, para: perfil.email, assunto: email.assunto,
  });
  if (dup) return Response.json({ enviado: false, motivo: dup.code === "23505" ? "já enviado" : dup.message });

  const chaveResend = Deno.env.get("RESEND_API_KEY");
  if (!chaveResend) {
    await db.from("emails_enviados").update({ status: "sem_chave" }).eq("notificacao_id", n.id);
    return new Response("RESEND_API_KEY não configurado", { status: 503 });
  }
  const resp = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${chaveResend}` },
    body: JSON.stringify({
      from: Deno.env.get("EMAIL_REMETENTE") ?? "iService <nao-responda@iservice.app.br>",
      to: [perfil.email],
      reply_to: SUPORTE_EMAIL,
      subject: email.assunto,
      html: email.html,
      text: email.texto,
      tags: [{ name: "tipo", value: n.tipo }],
    }),
  });
  const corpo = await resp.json().catch(() => ({}));
  if (!resp.ok) {
    console.error("Resend", resp.status, JSON.stringify(corpo));
    await db.from("emails_enviados").update({ status: "erro", erro: `${resp.status} ${JSON.stringify(corpo)}`.slice(0, 500) })
      .eq("notificacao_id", n.id);
    return new Response("Falha ao enviar", { status: 502 });
  }
  await db.from("emails_enviados").update({ status: "enviado", id_externo: corpo.id ?? null, enviado_em: new Date().toISOString() })
    .eq("notificacao_id", n.id);
  return Response.json({ enviado: true });
});
