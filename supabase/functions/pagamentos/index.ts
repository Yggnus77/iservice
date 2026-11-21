// Pagamento pelo app com o Asaas: cobra o cliente, guarda o valor até o serviço ser
// concluído, transfere a parte do profissional e estorna pedidos cancelados.
//
// Quem chama:
//   - o banco (public.chamar_funcao('pagamentos', ...)), com a senha interna do Vault;
//   - o Asaas (webhook de cobranças), com o token do webhook no cabeçalho asaas-access-token.
//
// Publicar:  supabase functions deploy pagamentos --no-verify-jwt
// Segredos (Supabase > Edge Functions > Secrets), só quando houver CNPJ e conta no Asaas:
//   ASAAS_API_KEY        chave de API da conta principal (jurídica) do iService
//   ASAAS_AMBIENTE       "producao" ou "sandbox" (padrão: sandbox)
//   ASAAS_WEBHOOK_TOKEN  token escolhido ao cadastrar o webhook no Asaas
//   ASAAS_RENDA_PADRAO   renda mensal informada ao criar a subconta do profissional (padrão 3000)
// Webhook no Asaas: URL https://<projeto>.supabase.co/functions/v1/pagamentos,
//   eventos de cobrança (PAYMENT_*) e de situação de conta (ACCOUNT_STATUS_*),
//   com o mesmo token de ASAAS_WEBHOOK_TOKEN.
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

const API = Deno.env.get("ASAAS_AMBIENTE") === "producao" ? "https://api.asaas.com/v3" : "https://api-sandbox.asaas.com/v3";
const CHAVE_ASAAS = Deno.env.get("ASAAS_API_KEY") ?? "";
const TOKEN_WEBHOOK = Deno.env.get("ASAAS_WEBHOOK_TOKEN") ?? "";
const RENDA_PADRAO = Number(Deno.env.get("ASAAS_RENDA_PADRAO") ?? "3000");

async function asaas<T = Record<string, unknown>>(metodo: string, caminho: string, corpo?: unknown): Promise<T> {
  const r = await fetch(API + caminho, {
    method: metodo,
    headers: { "Content-Type": "application/json", "access_token": CHAVE_ASAAS, "User-Agent": "iservice" },
    body: corpo === undefined ? undefined : JSON.stringify(corpo),
  });
  const texto = await r.text();
  if (!r.ok) throw new Error(`Asaas ${metodo} ${caminho}: ${r.status} ${texto.slice(0, 500)}`);
  return (texto ? JSON.parse(texto) : {}) as T;
}

let segredo: string | null = null;
async function doBanco(req: Request): Promise<boolean> {
  const recebido = req.headers.get("x-iservice-segredo");
  if (!recebido) return false;
  if (!segredo) {
    const { data, error } = await db.rpc("segredo_funcoes");
    if (error || !data) return false;
    segredo = data as string;
  }
  return recebido === segredo;
}

const hoje = (dias = 0) => new Date(Date.now() + dias * 86400000 - 3 * 3600000).toISOString().slice(0, 10);
const so = (s: unknown) => String(s ?? "").replace(/\D/g, "");

// ---------------------------------------------------------------------------
// Cliente no Asaas (criado uma vez por pessoa)
async function clienteAsaas(usuarioId: string): Promise<string> {
  const { data: ja } = await db.from("clientes_pagamento").select("asaas_cliente_id").eq("usuario_id", usuarioId).maybeSingle();
  if (ja) return ja.asaas_cliente_id;
  const { data: p, error } = await db.from("perfis").select("nome, cpf, email, telefone").eq("id", usuarioId).single();
  if (error) throw error;
  const c = await asaas<{ id: string }>("POST", "/customers", {
    name: p.nome, cpfCnpj: p.cpf, email: p.email, mobilePhone: so(p.telefone).replace(/^55/, ""),
    externalReference: usuarioId, notificationDisabled: true,
  });
  await db.from("clientes_pagamento").insert({ usuario_id: usuarioId, asaas_cliente_id: c.id });
  return c.id;
}

// Cobrança (Pix ou cartão, o cliente escolhe na tela) de um pagamento já registrado no banco.
async function cobrar(pagamentoId: string) {
  const { data: g } = await db.from("pagamentos").select("*, pedidos(id, codigo, cliente_id)").eq("id", pagamentoId).single();
  if (!g || g.asaas_cobranca_id || !["criando", "falhou"].includes(g.status)) return;
  try {
    const cliente = await clienteAsaas(g.pedidos.cliente_id);
    const c = await asaas<{ id: string; invoiceUrl: string }>("POST", "/payments", {
      customer: cliente, billingType: "UNDEFINED", value: Number(g.valor), dueDate: hoje(1),
      description: `iService, pedido ${g.pedidos.codigo}${g.tipo === "complemento" ? " (complemento)" : ""}`,
      externalReference: g.id,
    });
    const pix = await asaas<{ payload: string; encodedImage: string }>("GET", `/payments/${c.id}/pixQrCode`).catch(() => null);
    await db.from("pagamentos").update({
      status: "aguardando", asaas_cobranca_id: c.id, link_pagamento: c.invoiceUrl,
      pix_copia_cola: pix?.payload ?? null, pix_imagem: pix?.encodedImage ?? null, erro: null, atualizado_em: new Date().toISOString(),
    }).eq("id", g.id);
    await db.rpc("notificar", {
      p_usuario: g.pedidos.cliente_id, p_tipo: "pagamento", p_titulo: "Pague para confirmar o seu pedido",
      p_corpo: "O profissional aceitou. Pague pelo app com Pix ou cartão para ele sair até você.", p_dados: { pedido_id: g.pedidos.id },
    }).then(() => {}, () => {});
  } catch (e) {
    await db.from("pagamentos").update({ status: "falhou", erro: String(e).slice(0, 500) }).eq("id", g.id);
  }
}

// Serviço concluído: acerta o valor final (estorno parcial ou complemento) e libera ao profissional.
async function concluir(pedidoId: string) {
  const { data: ped } = await db.from("pedidos").select("*").eq("id", pedidoId).single();
  if (!ped) return;
  const { data: principal } = await db.from("pagamentos").select("*").eq("pedido_id", pedidoId).eq("tipo", "principal").maybeSingle();
  const { data: finais } = await db.rpc("valores_pagamento_final", { p_pedido_id: pedidoId });
  const final = Array.isArray(finais) ? finais[0] : finais;

  if (!principal) {
    // Sem preço antes: cobra agora o valor informado ao concluir.
    if (final?.valor > 0) {
      const { data: novo } = await db.from("pagamentos").insert({
        pedido_id: pedidoId, valor: final.valor, valor_profissional: final.valor_profissional, valor_plataforma: final.valor_plataforma,
      }).select("id").single();
      if (novo) await cobrar(novo.id);
    }
    return;
  }
  if (final && principal.status === "pago") {
    const diferenca = Math.round((Number(final.valor) - Number(principal.valor)) * 100) / 100;
    if (diferenca < -0.009 && principal.asaas_cobranca_id) {
      await asaas("POST", `/payments/${principal.asaas_cobranca_id}/refund`, { value: -diferenca, description: "Ajuste ao valor final" });
      await db.from("pagamentos").update({
        estornado_valor: -diferenca, valor: final.valor, valor_profissional: final.valor_profissional, valor_plataforma: final.valor_plataforma,
      }).eq("id", principal.id);
    } else if (diferenca > 0.009) {
      const taxa = Math.round((Number(final.valor_plataforma) - Number(principal.valor_plataforma)) * 100) / 100;
      const { data: comp } = await db.from("pagamentos").insert({
        pedido_id: pedidoId, tipo: "complemento", valor: diferenca, valor_profissional: diferenca - Math.max(0, taxa), valor_plataforma: Math.max(0, taxa),
      }).select("id").single();
      if (comp) await cobrar(comp.id);
    }
  }
  await db.from("pagamentos").update({ status: "a_liberar" }).eq("pedido_id", pedidoId).eq("status", "pago");
  await liberarPendentes(pedidoId);
}

// Transfere ao profissional os pagamentos "a_liberar" (de um pedido ou de todos).
async function liberarPendentes(pedidoId?: string) {
  let q = db.from("pagamentos").select("id, valor_profissional, pedidos(profissional_id)").eq("status", "a_liberar").limit(50);
  if (pedidoId) q = q.eq("pedido_id", pedidoId);
  const { data: lista } = await q;
  for (const g of lista ?? []) {
    const { data: conta } = await db.from("contas_recebimento").select("asaas_carteira_id, status")
      .eq("profissional_id", g.pedidos.profissional_id).maybeSingle();
    if (!conta?.asaas_carteira_id || conta.status !== "ativa") continue; // tenta de novo no próximo ciclo
    try {
      const t = await asaas<{ id: string }>("POST", "/transfers", { value: Number(g.valor_profissional), walletId: conta.asaas_carteira_id });
      await db.from("pagamentos").update({ status: "liberado", asaas_transferencia_id: t.id, liberado_em: new Date().toISOString(), erro: null }).eq("id", g.id);
    } catch (e) {
      await db.from("pagamentos").update({ erro: String(e).slice(0, 500) }).eq("id", g.id);
    }
  }
}

// Pedido cancelado: estorna o que foi pago e cancela o que ainda não foi.
// Cancelamento em cima da hora ou cliente ausente (pedidos.taxa_cancelamento): o deslocamento
// fica com o profissional e só o resto volta ao cliente.
async function estornar(pedidoId: string) {
  const { data: ped } = await db.from("pedidos").select("taxa_cancelamento").eq("id", pedidoId).maybeSingle();
  let reter = Number(ped?.taxa_cancelamento ?? 0);
  const { data: lista } = await db.from("pagamentos").select("*").eq("pedido_id", pedidoId).in("status", ["criando", "aguardando", "falhou", "pago"]);
  for (const g of lista ?? []) {
    try {
      if (g.status === "pago" && g.asaas_cobranca_id) {
        const fica = Math.min(reter, Number(g.valor));
        reter -= fica;
        if (fica > 0.009) {
          const volta = Math.round((Number(g.valor) - fica) * 100) / 100;
          if (volta > 0.009) await asaas("POST", `/payments/${g.asaas_cobranca_id}/refund`, { value: volta, description: "Cancelamento: deslocamento fica com o profissional" });
          await db.from("pagamentos").update({
            status: "a_liberar", estornado_valor: volta, valor: fica, valor_profissional: fica, valor_plataforma: 0,
          }).eq("id", g.id);
          continue;
        }
        await asaas("POST", `/payments/${g.asaas_cobranca_id}/refund`, { description: "Pedido cancelado" });
        await db.from("pagamentos").update({ status: "estornado", estornado_valor: g.valor }).eq("id", g.id);
      } else {
        if (g.asaas_cobranca_id) await asaas("DELETE", `/payments/${g.asaas_cobranca_id}`).catch(() => {});
        await db.from("pagamentos").update({ status: "cancelado" }).eq("id", g.id);
      }
    } catch (e) {
      await db.from("pagamentos").update({ erro: String(e).slice(0, 500) }).eq("id", g.id);
    }
  }
  await liberarPendentes(pedidoId);
}

// Conta de recebimento (subconta) do profissional.
async function criarConta(profissionalId: string) {
  const { data: c } = await db.from("contas_recebimento").select("*").eq("profissional_id", profissionalId).maybeSingle();
  if (c?.status === "ativa") return;
  const { data: p } = await db.from("perfis").select("nome, cpf, email, telefone, nascimento").eq("id", profissionalId).single();
  const { data: e } = await db.from("enderecos").select("logradouro, numero, bairro, cep, complemento")
    .eq("usuario_id", profissionalId).order("principal", { ascending: false }).limit(1).maybeSingle();
  try {
    const conta = await asaas<{ id: string; walletId: string; apiKey?: string }>("POST", "/accounts", {
      name: p!.nome, email: p!.email, cpfCnpj: p!.cpf, birthDate: p!.nascimento, mobilePhone: so(p!.telefone).replace(/^55/, ""),
      incomeValue: RENDA_PADRAO, address: e?.logradouro, addressNumber: e?.numero || "S/N", complement: e?.complemento ?? undefined,
      province: e?.bairro, postalCode: e?.cep,
    });
    // A chave da subconta só vem nesta resposta: guarda no Vault para conferir a situação depois.
    if (conta.apiKey) await db.rpc("guardar_chave_subconta", { p_profissional: profissionalId, p_chave: conta.apiKey });
    await db.from("contas_recebimento").upsert({
      profissional_id: profissionalId, asaas_conta_id: conta.id, asaas_carteira_id: conta.walletId, status: "ativa", erro: null,
      situacao: "aguardando_ativacao", atualizada_em: new Date().toISOString(),
    });
    await db.rpc("notificar", {
      p_usuario: profissionalId, p_tipo: "conta_recebimento", p_titulo: "Ative a sua conta de recebimento",
      p_corpo: "Criamos a sua conta no Asaas para receber pelos serviços. Abra Ganhos > Recebimentos e envie o documento e a selfie.",
      p_dados: {},
    }).then(() => {}, () => {});
  } catch (err) {
    await db.from("contas_recebimento").upsert({ profissional_id: profissionalId, status: "falhou", erro: String(err).slice(0, 500) });
  }
}

// Situação da subconta no Asaas (ativação e documentos), com a chave da própria subconta.
type Situacao = "aguardando_ativacao" | "em_analise" | "aprovada" | "recusada";
async function conferirConta(profissionalId: string) {
  const { data: chaveSub } = await db.rpc("chave_subconta", { p_profissional: profissionalId });
  if (!chaveSub) return;
  const comSub = async <T>(caminho: string): Promise<T> => {
    const r = await fetch(API + caminho, { headers: { "access_token": String(chaveSub), "User-Agent": "iservice" } });
    if (!r.ok) throw new Error(`Asaas GET ${caminho}: ${r.status}`);
    return await r.json() as T;
  };
  try {
    const st = await comSub<{ general?: string; documentation?: string }>("/myAccount/status");
    let situacao: Situacao = "em_analise";
    if (st.general === "APPROVED") situacao = "aprovada";
    else if (st.general === "REJECTED" || st.documentation === "REJECTED") situacao = "recusada";
    else if (!st.documentation || st.documentation === "PENDING") situacao = "aguardando_ativacao";
    let link: string | null = null;
    if (situacao !== "aprovada") {
      const docs = await comSub<{ data?: { onboardingUrl?: string; status?: string }[] }>("/myAccount/documents").catch(() => null);
      link = docs?.data?.find((d) => d.onboardingUrl && d.status !== "APPROVED")?.onboardingUrl ?? null;
    }
    const { data: antes } = await db.from("contas_recebimento").select("situacao").eq("profissional_id", profissionalId).single();
    await db.from("contas_recebimento").update({
      situacao, link_documentos: link, conferida_em: new Date().toISOString(),
    }).eq("profissional_id", profissionalId);
    if (antes?.situacao !== situacao && (situacao === "aprovada" || situacao === "recusada")) {
      await db.rpc("notificar", {
        p_usuario: profissionalId, p_tipo: "conta_recebimento",
        p_titulo: situacao === "aprovada" ? "Conta de recebimento aprovada" : "Precisamos de um novo documento",
        p_corpo: situacao === "aprovada"
          ? "Pronto: os pagamentos dos seus serviços já podem cair na sua conta."
          : "O Asaas não aprovou um documento. Abra Ganhos > Recebimentos e envie de novo.",
        p_dados: {},
      }).then(() => {}, () => {});
    }
  } catch (e) {
    console.error("conferirConta", profissionalId, e);
  }
}

// A cada 15 minutos (public.processar_pagamentos): refaz o que ficou pela metade.
async function sincronizar() {
  const { data: aConferir } = await db.from("contas_recebimento").select("profissional_id")
    .eq("status", "ativa").neq("situacao", "aprovada").order("conferida_em", { ascending: true, nullsFirst: true }).limit(20);
  for (const c of aConferir ?? []) await conferirConta(c.profissional_id);
  const { data: contas } = await db.from("contas_recebimento").select("profissional_id").neq("status", "ativa").limit(20);
  for (const c of contas ?? []) await criarConta(c.profissional_id);
  const { data: cobrancas } = await db.from("pagamentos").select("id").in("status", ["criando", "falhou"]).is("asaas_cobranca_id", null).limit(20);
  for (const g of cobrancas ?? []) await cobrar(g.id);
  await liberarPendentes();
}

// Webhook do Asaas: pagamento confirmado, estornado ou vencido.
async function webhook(evento: { event?: string; payment?: { id: string; externalReference?: string }; account?: { id?: string } }) {
  // Situação de subconta mudou: confere de novo.
  if (evento.event?.startsWith("ACCOUNT_STATUS_") && evento.account?.id) {
    const { data: c } = await db.from("contas_recebimento").select("profissional_id").eq("asaas_conta_id", evento.account.id).maybeSingle();
    if (c) await conferirConta(c.profissional_id);
    return;
  }
  const id = evento.payment?.id;
  if (!id) return;
  const { data: g } = await db.from("pagamentos").select("id, status, pedido_id, tipo, pedidos(status, profissional_id)").eq("asaas_cobranca_id", id).maybeSingle();
  if (!g) return;
  switch (evento.event) {
    case "PAYMENT_RECEIVED":
    case "PAYMENT_CONFIRMED": {
      if (!["aguardando", "falhou", "criando"].includes(g.status)) return;
      // Complemento de pedido já concluído é liberado direto.
      const concluido = g.pedidos?.status === "concluido";
      await db.from("pagamentos").update({ status: concluido ? "a_liberar" : "pago", pago_em: new Date().toISOString() }).eq("id", g.id);
      await db.rpc("notificar", {
        p_usuario: g.pedidos.profissional_id, p_tipo: "pagamento", p_titulo: "Pagamento confirmado",
        p_corpo: concluido ? "O valor vai para a sua conta de recebimento." : "O cliente pagou. Pode ir para o atendimento.",
        p_dados: { pedido_id: g.pedido_id },
      }).then(() => {}, () => {});
      if (concluido) await liberarPendentes(g.pedido_id);
      break;
    }
    case "PAYMENT_REFUNDED":
      await db.from("pagamentos").update({ status: "estornado" }).eq("id", g.id);
      break;
    case "PAYMENT_OVERDUE":
    case "PAYMENT_DELETED":
      if (g.status === "aguardando") await db.from("pagamentos").update({ status: "cancelado" }).eq("id", g.id);
      break;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Use POST", { status: 405 });
  const corpo = await req.json().catch(() => ({}));

  // Webhook do Asaas
  const tokenAsaas = req.headers.get("asaas-access-token");
  if (tokenAsaas !== null) {
    if (!TOKEN_WEBHOOK || tokenAsaas !== TOKEN_WEBHOOK) return new Response("Não autorizado", { status: 401 });
    await webhook(corpo);
    return Response.json({ ok: true });
  }

  if (!(await doBanco(req))) return new Response("Não autorizado", { status: 401 });
  if (!CHAVE_ASAAS) return Response.json({ ok: false, motivo: "ASAAS_API_KEY não configurada" });

  try {
    switch (corpo.acao) {
      case "cobrar": {
        const { data } = await db.from("pagamentos").select("id").eq("pedido_id", corpo.pedido_id).in("status", ["criando", "falhou"]);
        for (const g of data ?? []) await cobrar(g.id);
        break;
      }
      case "concluir": await concluir(corpo.pedido_id); break;
      case "estornar": await estornar(corpo.pedido_id); break;
      case "criar_conta": await criarConta(corpo.profissional_id); break;
      case "sincronizar": await sincronizar(); break;
      case "conferir_conta": await conferirConta(corpo.profissional_id); break;
      default: return new Response("Ação desconhecida", { status: 400 });
    }
    return Response.json({ ok: true });
  } catch (e) {
    console.error(e);
    return Response.json({ ok: false, erro: String(e) }, { status: 500 });
  }
});
