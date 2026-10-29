'use client';

import Link from 'next/link';
import { History } from 'lucide-react';
import { Cabecalho } from '@/components/Painel';
import { Carregando, ErroCaixa, Vazio, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { dataHora, nomesAcao } from '@/lib/formatos';

type Acao = { id: number; admin: string | null; acao: string; alvo: string | null; alvo_nome: string | null; dados: Record<string, unknown>; criada_em: string };

function detalhe(a: Acao): string {
  const d = a.dados ?? {};
  const partes: string[] = [];
  for (const k of ['motivo', 'observacao', 'resolucao', 'nota', 'titulo', 'tipo', 'status']) {
    if (typeof d[k] === 'string' && d[k]) partes.push(String(d[k]));
  }
  if (typeof d.destinatarios === 'number') partes.push(`${d.destinatarios} destinatários`);
  if (a.acao === 'ajustar_preco') partes.push(d.minimo == null ? 'ajuste removido' : `faixa ${d.faixa}: R$ ${d.minimo} a R$ ${d.maximo}`);
  const depois = d.depois as Record<string, unknown> | undefined;
  const antes = d.antes as Record<string, unknown> | undefined;
  if (depois && antes) {
    const mud = Object.keys(depois).filter((k) => JSON.stringify(depois[k]) !== JSON.stringify(antes[k]) && !['atualizado_em'].includes(k));
    partes.push(mud.map((k) => `${k}: ${JSON.stringify(antes[k])} → ${JSON.stringify(depois[k])}`).join(', '));
  } else if (depois) {
    partes.push(String(depois.nome ?? depois.chave ?? ''));
  }
  return partes.filter(Boolean).join(' · ');
}

export default function Registro() {
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Acao[]>('admin_registro', { p_limite: 300 }), []);
  return (
    <>
      <Cabecalho titulo="Registro da equipe" texto="Tudo o que a equipe fez no painel, do mais recente ao mais antigo." />
      <section className="cartao">
        <div className="corpo sem-espaco">
          {erro ? <div style={{ padding: 16 }}><ErroCaixa erro={erro} tentar={recarregar} /></div> : carregando && !dados ? <Carregando /> : !dados?.length ? (
            <Vazio icone={<History size={24} />} titulo="Nada registrado ainda" />
          ) : (
            <div className="tabela-rolagem">
              <table className="tabela">
                <thead><tr><th>Quando</th><th>Quem</th><th>O que</th><th>Sobre</th><th>Detalhe</th></tr></thead>
                <tbody>
                  {dados.map((a) => (
                    <tr key={a.id}>
                      <td className="fraco" style={{ whiteSpace: 'nowrap' }}>{dataHora(a.criada_em)}</td>
                      <td>{a.admin ?? '—'}</td>
                      <td><strong>{nomesAcao[a.acao] ?? a.acao}</strong></td>
                      <td>{a.alvo_nome ? <Link href={`/pessoa/?id=${a.alvo}`}>{a.alvo_nome}</Link> : <span className="fraco mono">{a.alvo ?? '—'}</span>}</td>
                      <td className="fraco" style={{ maxWidth: 420 }}>{detalhe(a)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </section>
    </>
  );
}
