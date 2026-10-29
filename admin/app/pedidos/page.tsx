'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useEffect, useState } from 'react';
import { ClipboardList, Search, ShieldCheck, Siren } from 'lucide-react';
import { Cabecalho } from '@/components/Painel';
import { Carregando, ErroCaixa, SeloStatus, Vazio, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { dataHora, moeda, numero, quandoPedido, statusPedido } from '@/lib/formatos';

type Linha = {
  id: string; codigo: string; status: string; quando: string; criado_em: string; cliente_id: string; cliente: string; profissional_id: string;
  profissional: string; profissao: string; especialidade: string | null; regiao: string | null; valor: number | null;
  tem_reclamacao: boolean; tem_emergencia: boolean; total: number;
};
const POR_PAGINA = 50;

function Lista() {
  const router = useRouter();
  const inicial = useSearchParams().get('status') ?? '';
  const [status, setStatus] = useState(inicial);
  const [texto, setTexto] = useState('');
  const [busca, setBusca] = useState('');
  const [inicio, setInicio] = useState('');
  const [fim, setFim] = useState('');
  const [pagina, setPagina] = useState(0);
  useEffect(() => { const t = setTimeout(() => { setBusca(texto); setPagina(0); }, 300); return () => clearTimeout(t); }, [texto]);
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Linha[]>('admin_pedidos', {
    p_status: status || null, p_texto: busca || null, p_inicio: inicio || null, p_fim: fim || null, p_limite: POR_PAGINA, p_pular: pagina * POR_PAGINA,
  }), [status, busca, inicio, fim, pagina]);
  const total = dados?.[0]?.total ?? 0;

  return (
    <>
      <Cabecalho titulo="Pedidos" texto="Todos os pedidos. Cada um vai só para o profissional que o cliente escolheu." />
      <div className="filtros">
        <select className="entrada" value={status} onChange={(e) => { setStatus(e.target.value); setPagina(0); }} aria-label="Situação">
          <option value="">Todas as situações</option>
          <option value="andamento">Em andamento (todos)</option>
          {Object.entries(statusPedido).map(([k, v]) => <option key={k} value={k}>{v.rotulo}</option>)}
        </select>
        <input className="entrada" type="date" value={inicio} onChange={(e) => { setInicio(e.target.value); setPagina(0); }} aria-label="De" />
        <span className="texto-fraco">até</span>
        <input className="entrada" type="date" value={fim} onChange={(e) => { setFim(e.target.value); setPagina(0); }} aria-label="Até" />
        <span className="espaco" />
        <div className="busca"><Search /><input className="entrada" placeholder="Código ou nome" value={texto} onChange={(e) => setTexto(e.target.value)} aria-label="Buscar pedido" /></div>
      </div>
      <section className="cartao">
        <div className="corpo sem-espaco">
          {erro ? <div style={{ padding: 16 }}><ErroCaixa erro={erro} tentar={recarregar} /></div> : carregando && !dados ? <Carregando /> : !dados?.length ? (
            <Vazio icone={<ClipboardList size={24} />} titulo="Nenhum pedido encontrado" />
          ) : (
            <div className="tabela-rolagem">
              <table className="tabela">
                <thead><tr><th>Pedido</th><th>Cliente</th><th>Profissional</th><th>Região</th><th>Quando</th><th className="num">Valor</th><th>Feito em</th><th>Situação</th></tr></thead>
                <tbody>
                  {dados.map((p) => (
                    <tr key={p.id} className="clicavel" onClick={() => router.push(`/pedido/?id=${p.id}`)}>
                      <td>
                        <span className="linha-flex" style={{ gap: 6 }}>
                          <span className="mono forte">{p.codigo}</span>
                          {p.tem_emergencia ? <Siren size={15} color="#c62828" aria-label="Teve emergência" /> : null}
                          {p.tem_reclamacao ? <ShieldCheck size={15} color="#0046b8" aria-label="Tem reclamação" /> : null}
                        </span>
                        <div className="fraco">{p.profissao}{p.especialidade ? ` · ${p.especialidade}` : ''}</div>
                      </td>
                      <td>{p.cliente}</td>
                      <td>{p.profissional}</td>
                      <td className="fraco">{p.regiao ?? '—'}</td>
                      <td>{quandoPedido[p.quando] ?? p.quando}</td>
                      <td className="num">{moeda(p.valor)}</td>
                      <td className="fraco">{dataHora(p.criado_em)}</td>
                      <td><SeloStatus mapa={statusPedido} valor={p.status} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </section>
      {total > POR_PAGINA ? (
        <div className="linha-flex" style={{ marginTop: 14, justifyContent: 'flex-end' }}>
          <span className="texto-fraco">{pagina * POR_PAGINA + 1}–{Math.min(total, (pagina + 1) * POR_PAGINA)} de {numero(total)}</span>
          <button className="botao contorno pequeno" disabled={pagina === 0} onClick={() => setPagina(pagina - 1)}>Anterior</button>
          <button className="botao contorno pequeno" disabled={(pagina + 1) * POR_PAGINA >= total} onClick={() => setPagina(pagina + 1)}>Próxima</button>
        </div>
      ) : null}
    </>
  );
}

export default function Pagina() {
  return <Suspense fallback={<Carregando />}><Lista /></Suspense>;
}
