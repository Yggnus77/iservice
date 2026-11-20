'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { AlertTriangle, BadgeCheck, CircleDollarSign, Clock, Lock, Percent, RefreshCw, Search, Undo2, Wallet } from 'lucide-react';
import { Cabecalho } from '@/components/Painel';
import { Carregando, ErroCaixa, SeloStatus, Vazio, useAcao, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { dataHora, moeda, numero, type Tom } from '@/lib/formatos';

type Item = {
  id: string; pedido_id: string; tipo: 'principal' | 'complemento'; status: string; valor: number; valor_profissional: number;
  valor_plataforma: number; estornado_valor: number; criado_em: string; pago_em: string | null; liberado_em: string | null;
  vence_em: string | null; erro: string | null; cliente: string | null; profissional: string | null; pedido_status: string;
};
type Dados = {
  ativo: boolean;
  resumo: { aguardando: number; guardado: number; liberado_mes: number; taxa_mes: number; estornado_mes: number; com_erro: number };
  contas: { total: number; aprovadas: number; pendentes: number; com_problema: number };
  itens: Item[];
};

const statusPagamento: Record<string, { rotulo: string; tom: Tom }> = {
  criando: { rotulo: 'Criando cobrança', tom: 'neutro' },
  aguardando: { rotulo: 'Aguardando o cliente', tom: 'laranja' },
  pago: { rotulo: 'Pago, guardado', tom: 'azul' },
  a_liberar: { rotulo: 'Liberando', tom: 'azul' },
  liberado: { rotulo: 'Repassado', tom: 'verde' },
  estornado: { rotulo: 'Estornado', tom: 'neutro' },
  cancelado: { rotulo: 'Cancelado', tom: 'neutro' },
  falhou: { rotulo: 'Falhou', tom: 'vermelho' },
};

function Numero({ rotulo, valor, detalhe, icone, cor, fundo }: { rotulo: string; valor: string; detalhe?: string; icone: React.ReactNode; cor: string; fundo: string }) {
  return (
    <div className="cartao numero">
      <span className="rotulo"><span className="icone" style={{ color: cor, background: fundo }}>{icone}</span>{rotulo}</span>
      <span className="valor">{valor}</span>
      {detalhe ? <span className="detalhe">{detalhe}</span> : null}
    </div>
  );
}

export default function Pagamentos() {
  const router = useRouter();
  const [status, setStatus] = useState('');
  const [texto, setTexto] = useState('');
  const [busca, setBusca] = useState('');
  useEffect(() => { const t = setTimeout(() => setBusca(texto), 300); return () => clearTimeout(t); }, [texto]);
  const c = useCarregar(() => rpc<Dados>('admin_pagamentos', { p_status: status || null, p_busca: busca || null }), [status, busca]);
  const { executar, ocupado } = useAcao();
  const d = c.dados;

  return (
    <>
      <Cabecalho
        ajuda={<>O cliente paga pelo app logo depois do aceite. O valor fica guardado até o serviço ser concluído; aí a parte do profissional vai para a conta dele no Asaas e a taxa de serviço fica com o iService. Pedido cancelado é estornado. <strong>Refazer</strong> tenta de novo uma cobrança ou um repasse que deu erro.</>}
        titulo="Pagamentos"
        texto="Cobranças, valores guardados, repasses aos profissionais e estornos." />

      {c.erro ? <ErroCaixa erro={c.erro} tentar={c.recarregar} /> : !d ? <Carregando /> : (
        <>
          {!d.ativo ? (
            <div className="alerta-faixa laranja">
              <Lock size={20} />
              <div><strong>O pagamento pelo app ainda está desligado.</strong> Ele liga com o CNPJ e a conta jurídica no Asaas
                (Configurações, <span className="mono">pagamento_ativo</span> e <span className="mono">taxa_servico_ativa</span>).</div>
            </div>
          ) : null}
          <div className="grade g4" style={{ marginBottom: 18 }}>
            <Numero rotulo="Guardado até concluir" valor={moeda(d.resumo.guardado)} icone={<Wallet />} cor="#0046b8" fundo="#e8f0fc"
              detalhe={`${numero(d.resumo.aguardando)} cobrança(s) esperando o cliente pagar`} />
            <Numero rotulo="Repassado no mês" valor={moeda(d.resumo.liberado_mes)} icone={<CircleDollarSign />} cor="#00873A" fundo="#e6f6ec"
              detalhe="Para as contas dos profissionais" />
            <Numero rotulo="Taxa de serviço no mês" valor={moeda(d.resumo.taxa_mes)} icone={<Percent />} cor="#5b3cc4" fundo="#efeafd"
              detalhe={`Estornado no mês: ${moeda(d.resumo.estornado_mes)}`} />
            <Numero rotulo="Contas de recebimento" valor={`${numero(d.contas.aprovadas)} de ${numero(d.contas.total)}`} icone={<BadgeCheck />} cor="#b25f00" fundo="#fff4e5"
              detalhe={`${numero(d.contas.pendentes)} esperando o profissional ativar${d.contas.com_problema ? ` · ${numero(d.contas.com_problema)} com problema` : ''}`} />
          </div>

          <div className="filtros">
            <select className="entrada" value={status} onChange={(e) => setStatus(e.target.value)} aria-label="Situação">
              <option value="">Todas as situações</option>
              <option value="com_erro">Com erro ({numero(d.resumo.com_erro)})</option>
              {Object.entries(statusPagamento).map(([k, v]) => <option key={k} value={k}>{v.rotulo}</option>)}
            </select>
            <span className="espaco" />
            <div className="busca"><Search /><input className="entrada" placeholder="Cliente, profissional ou pedido" value={texto} onChange={(e) => setTexto(e.target.value)} aria-label="Buscar pagamento" /></div>
          </div>

          <section className="cartao">
            <div className="corpo sem-espaco">
              {!d.itens.length ? (
                <Vazio icone={<CircleDollarSign size={24} />} titulo="Nenhum pagamento" texto={d.ativo ? undefined : 'Os pagamentos aparecem aqui quando o pagamento pelo app for ligado.'} />
              ) : (
                <div className="tabela-rolagem">
                  <table className="tabela">
                    <thead><tr><th>Cliente</th><th>Profissional</th><th className="num">Cliente pagou</th><th className="num">Profissional</th><th className="num">Taxa</th><th>Quando</th><th>Situação</th><th></th></tr></thead>
                    <tbody>
                      {d.itens.map((g) => (
                        <tr key={g.id} className="clicavel" onClick={() => router.push(`/pedido/?id=${g.pedido_id}`)}>
                          <td>{g.cliente ?? '—'}{g.tipo === 'complemento' ? <div className="fraco">Complemento</div> : null}</td>
                          <td>{g.profissional ?? '—'}</td>
                          <td className="num">{moeda(g.valor)}{g.estornado_valor > 0 ? <div className="fraco"><Undo2 size={12} /> {moeda(g.estornado_valor)}</div> : null}</td>
                          <td className="num">{moeda(g.valor_profissional)}</td>
                          <td className="num">{moeda(g.valor_plataforma)}</td>
                          <td className="fraco">
                            {dataHora(g.liberado_em ?? g.pago_em ?? g.criado_em)}
                            {g.status === 'aguardando' && g.vence_em ? <div><Clock size={12} /> vence {dataHora(g.vence_em)}</div> : null}
                          </td>
                          <td>
                            <SeloStatus mapa={statusPagamento} valor={g.status} />
                            {g.erro ? <div className="fraco" title={g.erro}><AlertTriangle size={12} color="#c62828" /> erro no Asaas</div> : null}
                          </td>
                          <td>
                            {g.erro || g.status === 'falhou' ? (
                              <button className="botao contorno pequeno" disabled={ocupado}
                                onClick={(e) => { e.stopPropagation(); executar(async () => { await rpc('admin_pagamento_refazer', { p_pagamento: g.id }); c.recarregar(); }, 'Pedido de nova tentativa enviado.'); }}>
                                <RefreshCw /> Refazer
                              </button>
                            ) : null}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          </section>
        </>
      )}
    </>
  );
}
