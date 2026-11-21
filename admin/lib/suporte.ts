import { FunctionsHttpError } from '@supabase/supabase-js';
import { db, ErroPainel } from './supabase';
import type { Tom } from './formatos';

export type StatusConversa = 'aberto' | 'em_atendimento' | 'encerrado';

export const statusConversa: Record<StatusConversa, { rotulo: string; tom: Tom }> = {
  aberto: { rotulo: 'Em aberto', tom: 'laranja' },
  em_atendimento: { rotulo: 'Em atendimento', tom: 'azul' },
  encerrado: { rotulo: 'Encerrado', tom: 'verde' },
};

export type ItemConversa = {
  id: number; protocolo: string; assunto: string; contato_email: string | null; contato_nome: string | null; usuario_id: string | null;
  foto_url: string | null; e_profissional: boolean; status: StatusConversa; responsavel: string | null; responsavel_nome: string | null;
  nao_lida: boolean; mensagens: number; criada_em: string; ultima_mensagem_em: string; previa: string; ultima_direcao: 'recebida' | 'enviada' | null;
  total: number; canal?: Canal; contato_telefone?: string | null;
};

export type Canal = 'email' | 'whatsapp';

export type Anexo = { nome: string; tipo: string; tamanho: number; caminho: string | null };

export type Mensagem = {
  id: number; direcao: 'recebida' | 'enviada' | 'nota' | 'evento'; de_email: string | null; de_nome: string | null;
  para: string[]; cc: string[]; assunto: string | null; texto: string | null; tem_html: boolean; autor_nome: string | null;
  envio: 'enviando' | 'enviado' | 'erro' | null; erro: string | null; anexos: Anexo[]; criada_em: string;
  entregue_em?: string | null; lida_em?: string | null;
};

export type Conversa = {
  id: number; protocolo: string; assunto: string; contato_email: string | null; contato_nome: string | null; status: StatusConversa;
  responsavel: string | null; responsavel_nome: string | null; nao_lida: boolean; criada_em: string; ultima_mensagem_em: string;
  encerrada_em: string | null; eu: string | null; outras: number;
  canal?: Canal; contato_telefone?: string | null; janela_ate?: string | null; whatsapp_ativo?: boolean;
  pessoa: { id: string; nome: string; foto_url: string | null; e_profissional: boolean; telefone: string | null; pedidos: number } | null;
  mensagens: Mensagem[];
};

export type MembroRodizio = {
  email: string; nome: string; foto_url: string | null; ativo: boolean; recebe_emails: boolean; ultima_atribuicao: string | null;
  aberto: number; em_atendimento: number; encerrado_7d: number; voce: boolean;
};

type RespostaEnvio = { enviado?: boolean; conversa_id?: number; erro?: string };

async function invocar(funcao: 'responder-suporte' | 'whatsapp', corpo: Record<string, unknown>) {
  const { data, error } = await db().functions.invoke<RespostaEnvio>(funcao, { body: corpo });
  if (error) {
    let msg = 'Não foi possível enviar. Confira a internet e tente de novo.';
    let conversa: number | undefined;
    if (error instanceof FunctionsHttpError) {
      const r = await (error.context as Response).json().catch(() => null) as { erro?: string; conversa_id?: number } | null;
      if (r?.erro) msg = r.erro;
      conversa = r?.conversa_id;
    } else if (/Failed to send|fetch/i.test(error.message)) {
      msg = funcao === 'whatsapp'
        ? 'O WhatsApp do atendimento ainda não foi ligado. Ele entra no ar depois do CNPJ e da verificação na Meta.'
        : 'A função de envio ainda não foi publicada no Supabase ou está fora do ar.';
    }
    const e = new ErroPainel(msg, 'envio');
    (e as ErroPainel & { conversa?: number }).conversa = conversa;
    throw e;
  }
  return data!;
}

/** Envia pela função responder-suporte (resposta, e-mail novo ou nova tentativa). */
export function enviarEmail(corpo: { conversa_id?: number | null; texto?: string; para?: string; assunto?: string; reenviar?: number }) {
  return invocar('responder-suporte', corpo);
}

/** Envia pelo WhatsApp do atendimento (função whatsapp, API oficial da Meta). */
export function enviarWhatsapp(corpo: { conversa_id?: number; texto?: string; reenviar?: number }) {
  return invocar('whatsapp', corpo);
}

/**
 * Separa a parte nova da mensagem do histórico citado ("Em ... escreveu:", linhas com ">").
 * Devolve [nova, citada].
 */
export function separarCitacao(texto: string): [string, string] {
  const linhas = texto.replace(/\r\n/g, '\n').split('\n');
  const inicio = linhas.findIndex((l, i) =>
    /^\s*(Em|On|El)\s.+(escreveu|wrote|escribió)\s*:\s*$/i.test(l) ||
    // Gmail quebra "Em ..., Fulano <x@y>\nescreveu:" em duas linhas
    (/^\s*(escreveu|wrote)\s*:\s*$/i.test(l) && i > 0) ||
    /^-{2,}\s*(Mensagem original|Original Message|Forwarded message|Mensagem encaminhada)/i.test(l) ||
    /^_{10,}\s*$/.test(l) ||
    /^\s*De:\s.+/.test(l) && linhas.slice(i + 1, i + 4).some((x) => /^\s*(Enviado|Enviada|Data|Para|Assunto):/i.test(x)));
  let corte = inicio;
  if (corte > 0 && /^\s*(escreveu|wrote)\s*:\s*$/i.test(linhas[corte])) corte -= 1;
  if (corte < 0) {
    // Só citação com ">" no fim.
    let i = linhas.length - 1;
    while (i >= 0 && (/^\s*>/.test(linhas[i]) || !linhas[i].trim())) i--;
    if (i < linhas.length - 1 && linhas.slice(i + 1).some((l) => /^\s*>/.test(l))) corte = i + 1;
  }
  if (corte <= 0) return [texto.trim(), ''];
  return [linhas.slice(0, corte).join('\n').trim(), linhas.slice(corte).join('\n').trim()];
}

export function tamanhoArquivo(b: number): string {
  if (!b) return '';
  if (b < 1024) return `${b} B`;
  if (b < 1024 * 1024) return `${Math.round(b / 1024)} KB`;
  return `${(b / 1024 / 1024).toFixed(1).replace('.', ',')} MB`;
}
