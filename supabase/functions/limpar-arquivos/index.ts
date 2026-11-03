// Apaga do Storage os arquivos das contas excluídas (foto, documentos, selfie,
// portfólio e fotos de avaliação). O Supabase não deixa apagar arquivos por SQL,
// então excluir_contas_vencidas() põe o usuário na fila public.arquivos_a_apagar
// e esta função esvazia a fila pela API do Storage.
//
// Publicar:  supabase functions deploy limpar-arquivos --no-verify-jwt
// Agendar:   cron iservice-limpar-arquivos (migração 20261029000900), todo dia às 07:00.
import { createClient } from "npm:@supabase/supabase-js@2";

const BUCKETS = ["fotos", "portfolio", "avaliacoes", "pedidos", "documentos"];

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

async function listarTudo(bucket: string, pasta: string): Promise<string[]> {
  const caminhos: string[] = [];
  for (let pagina = 0; ; pagina++) {
    const { data, error } = await db.storage.from(bucket).list(pasta, { limit: 100, offset: pagina * 100 });
    if (error) throw error;
    for (const item of data ?? []) {
      const caminho = `${pasta}/${item.name}`;
      // Sem id é uma subpasta (ex.: fotos de avaliação por pedido).
      if (item.id == null) caminhos.push(...(await listarTudo(bucket, caminho)));
      else caminhos.push(caminho);
    }
    if (!data || data.length < 100) return caminhos;
  }
}

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

Deno.serve(async (req) => {
  if (!(await autorizado(req))) {
    return new Response("Não autorizado", { status: 401 });
  }

  const { data: fila, error } = await db.from("arquivos_a_apagar").select("usuario_id").limit(50);
  if (error) return new Response(error.message, { status: 500 });

  const resultado: Record<string, number> = {};
  for (const { usuario_id } of fila ?? []) {
    let apagados = 0;
    for (const bucket of BUCKETS) {
      const caminhos = await listarTudo(bucket, usuario_id);
      for (let i = 0; i < caminhos.length; i += 100) {
        const { error: e } = await db.storage.from(bucket).remove(caminhos.slice(i, i + 100));
        if (e) return new Response(e.message, { status: 500 });
      }
      apagados += caminhos.length;
    }
    await db.from("arquivos_a_apagar").delete().eq("usuario_id", usuario_id);
    resultado[usuario_id] = apagados;
  }
  return Response.json({ contas: Object.keys(resultado).length, arquivos: resultado });
});
