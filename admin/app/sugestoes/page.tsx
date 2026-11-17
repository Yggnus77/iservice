'use client';

import { useState } from 'react';
import { Briefcase, Lightbulb, Trash2, UserRound, Users } from 'lucide-react';
import { Cabecalho } from '@/components/Painel';
import { Abas, Carregando, ErroCaixa, Selo, Vazio, useAcao, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { dataHora, haQuanto, numero } from '@/lib/formatos';

type ItemRanking = {
  chave: string; nome: string; total: number; clientes: number; profissionais: number; ultima: string; ja_existe: boolean;
  regioes: { nome: string; total: number }[];
};
type Recente = { id: number; criada_em: string; profissao: string; perfil: 'cliente' | 'profissional'; cidade: string | null; contato: string | null };
type Dados = {
  total: number; clientes: number; profissionais: number; diferentes: number;
  ranking: ItemRanking[]; recentes: Recente[]; contato_mascarado: boolean; pode_apagar: boolean;
};
type Periodo = '30' | '90' | '365' | 'tudo';

function Numero({ rotulo, valor, detalhe, icone, cor, fundo }: { rotulo: string; valor: string; detalhe?: string; icone: React.ReactNode; cor: string; fundo: string }) {
  return (
    <div className="cartao numero">
      <span className="rotulo"><span className="icone" style={{ color: cor, background: fundo }}>{icone}</span>{rotulo}</span>
      <span className="valor">{valor}</span>
      {detalhe ? <span className="detalhe">{detalhe}</span> : null}
    </div>
  );
}

export default function SugestoesDeProfissoes() {
  const [periodo, setPeriodo] = useState<Periodo>('90');
  const [todas, setTodas] = useState(false);
  const carga = useCarregar(() => rpc<Dados>('admin_sugestoes_profissao', { p_dias: periodo === 'tudo' ? null : Number(periodo) }), [periodo]);
  const { executar, ocupado } = useAcao();
  const d = carga.dados;
  const maior = Math.max(1, ...(d?.ranking ?? []).map((r) => r.total));
  const pct = (a: number, b: number) => (b ? `${Math.round((a / b) * 100)}%` : '—');

  const apagar = async (r: Recente) => {
    if (!window.confirm(`Apagar a sugestão "${r.profissao}"? Use só para spam ou brincadeira.`)) return;
    if (await executar(() => rpc('admin_apagar_sugestao', { p_id: r.id }), 'Sugestão apagada.')) carga.recarregar();
  };

  return (
    <>
      <Cabecalho titulo="Sugestões de profissões"
        texto="O que visitantes do site pediram em “Não achou sua profissão? Sugira”. As mais pedidas ficam no topo." />
      <div className="filtros">
        <Abas ativa={periodo} mudar={setPeriodo}
          abas={[{ id: '30', rotulo: '30 dias' }, { id: '90', rotulo: '90 dias' }, { id: '365', rotulo: '12 meses' }, { id: 'tudo', rotulo: 'Tudo' }]} />
      </div>

      {carga.erro ? <ErroCaixa erro={carga.erro} tentar={carga.recarregar} /> : !d ? <Carregando /> : (
        <>
          <div className="grade g4" style={{ marginBottom: 18 }}>
            <Numero rotulo="Sugestões recebidas" valor={numero(d.total)} icone={<Lightbulb />} cor="#0046b8" fundo="#e8f0fc"
              detalhe="Cada pessoa conta uma vez por profissão no dia" />
            <Numero rotulo="Profissões diferentes" valor={numero(d.diferentes)} icone={<Briefcase />} cor="#5b3cc4" fundo="#efeafd"
              detalhe={d.ranking[0] ? `A mais pedida: ${d.ranking[0].nome}` : undefined} />
            <Numero rotulo="Vieram de clientes" valor={numero(d.clientes)} icone={<UserRound />} cor="#0046b8" fundo="#e8f0fc"
              detalhe={`${pct(d.clientes, d.total)} das sugestões`} />
            <Numero rotulo="Vieram de profissionais" valor={numero(d.profissionais)} icone={<Users />} cor="#b25f00" fundo="#fff4e5"
              detalhe={`${pct(d.profissionais, d.total)} das sugestões`} />
          </div>

          <div className="grade lado">
            <section className="cartao">
              <div className="titulo">
                <div><h2>Mais pedidas</h2><p>Grafias parecidas (com ou sem acento, maiúsculas) contam juntas.</p></div>
                <div className="legenda"><span><i style={{ background: 'var(--azul)' }} />Clientes</span><span><i style={{ background: 'var(--laranja)' }} />Profissionais</span></div>
              </div>
              <div className="corpo sem-espaco">
                {!d.ranking.length ? (
                  <div className="corpo"><Vazio titulo="Nenhuma sugestão ainda" texto="Quando alguém sugerir uma profissão pelo site, ela aparece aqui." icone={<Lightbulb />} /></div>
                ) : (
                  <div className="tabela-rolagem">
                    <table className="tabela sugestoes">
                      <thead><tr><th style={{ width: 36 }}>#</th><th>Profissão</th><th style={{ minWidth: 180 }}>Pedidos</th><th>Onde</th><th>Última</th></tr></thead>
                      <tbody>
                        {d.ranking.map((r, i) => (
                          <tr key={r.chave}>
                            <td className="fraco">{i + 1}</td>
                            <td>
                              <div className="linha-flex" style={{ gap: 8 }}>
                                <strong>{r.nome}</strong>
                                {r.ja_existe ? <Selo tom="verde">Já existe</Selo> : null}
                              </div>
                            </td>
                            <td>
                              <div className="sugestao-barra" title={`${r.clientes} de clientes · ${r.profissionais} de profissionais`}>
                                <span className="trilho" style={{ width: `${(r.total / maior) * 100}%` }}>
                                  {r.clientes ? <i className="a" style={{ flex: r.clientes }} /> : null}
                                  {r.profissionais ? <i className="b" style={{ flex: r.profissionais }} /> : null}
                                </span>
                                <strong>{numero(r.total)}</strong>
                              </div>
                              <span className="fraco">{r.clientes} cliente{r.clientes === 1 ? '' : 's'} · {r.profissionais} profissiona{r.profissionais === 1 ? 'l' : 'is'}</span>
                            </td>
                            <td className="fraco">{r.regioes.map((g) => `${g.nome}${g.total > 1 ? ` (${g.total})` : ''}`).join(', ') || '—'}</td>
                            <td className="fraco" title={dataHora(r.ultima)} style={{ whiteSpace: 'nowrap' }}>{haQuanto(r.ultima)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            </section>

            <section className="cartao">
              <div className="titulo"><div><h2>Últimas sugestões</h2><p>{d.contato_mascarado ? 'O contato aparece em parte para o seu cargo.' : 'O contato é opcional: a pessoa pediu para ser avisada.'}</p></div></div>
              <div className="corpo sem-espaco">
                {!d.recentes.length ? <div className="corpo"><span className="texto-suave">Nada no período.</span></div> : (
                  <ul className="lista-sugestoes">
                    {(todas ? d.recentes : d.recentes.slice(0, 12)).map((r) => (
                      <li key={r.id}>
                        <div style={{ minWidth: 0, flex: 1 }}>
                          <div className="linha-flex" style={{ gap: 8 }}>
                            <strong>{r.profissao}</strong>
                            <Selo tom={r.perfil === 'profissional' ? 'laranja' : 'azul'}>{r.perfil === 'profissional' ? 'Profissional' : 'Cliente'}</Selo>
                          </div>
                          <span className="fraco">
                            {[r.cidade, r.contato, haQuanto(r.criada_em)].filter(Boolean).join(' · ')}
                          </span>
                        </div>
                        {d.pode_apagar ? (
                          <button className="botao fantasma pequeno" onClick={() => apagar(r)} disabled={ocupado} aria-label={`Apagar a sugestão ${r.profissao}`} title="Apagar (spam)">
                            <Trash2 />
                          </button>
                        ) : null}
                      </li>
                    ))}
                  </ul>
                )}
                {d.recentes.length > 12 ? (
                  <div className="corpo" style={{ paddingTop: 12, paddingBottom: 14 }}>
                    <button className="botao contorno pequeno cheio" onClick={() => setTodas(!todas)}>
                      {todas ? 'Mostrar menos' : `Ver as ${d.recentes.length} últimas`}
                    </button>
                  </div>
                ) : null}
              </div>
            </section>
          </div>
        </>
      )}
    </>
  );
}
