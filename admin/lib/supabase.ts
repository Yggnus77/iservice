import { createClient, type SupabaseClient } from '@supabase/supabase-js';

// A chave publicável é a mesma dos apps (pública por natureza). O que protege os
// dados são as regras do banco: cada função admin_* confere se quem chama é da equipe.
const URL = process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://aurjqwqqrxaexmwozezr.supabase.co';
const CHAVE = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || 'sb_publishable_Gc3o5rwSwK-ID6cYTGPmZA_8NO1hqkW';

let cliente: SupabaseClient | null = null;

export function db(): SupabaseClient {
  if (!cliente) {
    cliente = createClient(URL, CHAVE, {
      auth: { persistSession: true, autoRefreshToken: true, storageKey: 'iservice-admin' },
    });
  }
  return cliente;
}

export const SUPABASE_URL = URL;

/** Erro do banco já traduzido para uma frase. */
export class ErroPainel extends Error {
  codigo?: string;
  constructor(mensagem: string, codigo?: string) {
    super(mensagem);
    this.codigo = codigo;
  }
}

type ErroBanco = { message: string; details?: string | null; code?: string };

export function traduzirErro(e: ErroBanco): ErroPainel {
  // Função ausente = o SQL do painel ainda não foi aplicado no Supabase.
  if (e.code === 'PGRST202' || e.code === '42883' || /Could not find the function/i.test(e.message)) {
    return new ErroPainel('O banco ainda não tem as funções do painel. Aplique o SQL do painel no Supabase.', 'sql_pendente');
  }
  if (e.code === 'P0001') return new ErroPainel(e.message, e.details ?? undefined);
  if (/JWT|not authenticated/i.test(e.message)) return new ErroPainel('Sua sessão expirou. Entre de novo.', 'sessao');
  if (/Failed to fetch|NetworkError/i.test(e.message)) return new ErroPainel('Sem conexão com o servidor. Confira a internet.', 'rede');
  return new ErroPainel(e.message, e.code);
}

/** Chama uma função do banco e devolve o resultado, ou lança ErroPainel. */
export async function rpc<T>(nome: string, params?: Record<string, unknown>): Promise<T> {
  const { data, error } = await db().rpc(nome, params);
  if (error) throw traduzirErro(error);
  return data as T;
}
