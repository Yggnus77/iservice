'use client';

import { useMemo, useState } from 'react';
import { Pencil, Tags } from 'lucide-react';
import { Cabecalho } from '@/components/Painel';
import { Carregando, Dialogo, ErroCaixa, Vazio, useAcao, useCarregar } from '@/components/ui';
import { db, rpc } from '@/lib/supabase';
import { dataHora } from '@/lib/formatos';

type Celula = {
  especialidade_id: number; especialidade: string; faixa: number; minimo: number; maximo: number; amostras: number; estimada: boolean;
  ajuste_minimo: number | null; ajuste_maximo: number | null; ajustado_em: string | null;
};

const nomesFaixa = ['', 'Faixa 1', 'Faixa 2', 'Faixa 3', 'Faixa 4', 'Faixa 5'];
const exemplosFaixa = ['', 'Plano Piloto, Lagos, Sudoeste', 'Guará, Águas Claras, Cruzeiro', 'Taguatinga, Sobradinho, Paranoá', 'Ceilândia, Samambaia, Gama', 'Entorno (GO)'];
const real = (v: number) => `R$ ${Math.round(Number(v)).toLocaleString('pt-BR')}`;

export default function Precos() {
  const profissoes = useCarregar(async () => {
    const { data } = await db().from('profissoes').select('id, nome').order('ordem');
    return (data ?? []) as { id: string; nome: string }[];
  }, []);
  const [profissao, setProfissao] = useState('eletricista');
  const tabela = useCarregar(() => rpc<Celula[]>('admin_tabela_precos', { p_profissao: profissao }), [profissao]);
  const { executar, ocupado } = useAcao();
  const [editar, setEditar] = useState<Celula | null>(null);
  const [min, setMin] = useState('');
  const [max, setMax] = useState('');

  const linhas = useMemo(() => {
    const m = new Map<number, { nome: string; c: Record<number, Celula> }>();
    (tabela.dados ?? []).forEach((c) => {
      const l = m.get(c.especialidade_id) ?? { nome: c.especialidade, c: {} };
      l.c[c.faixa] = c;
      m.set(c.especialidade_id, l);
    });
    return [...m.entries()];
  }, [tabela.dados]);

  const abrir = (c: Celula) => {
    setEditar(c);
    setMin(String(Math.round(c.ajuste_minimo ?? c.minimo)));
    setMax(String(Math.round(c.ajuste_maximo ?? c.maximo)));
  };
  const salvar = async (remover = false) => {
    if (!editar) return;
    const ok = await executar(() => rpc('admin_ajustar_preco', {
      p_especialidade: editar.especialidade_id, p_faixa: editar.faixa, p_minimo: remover ? null : Number(min), p_maximo: remover ? null : Number(max),
    }), remover ? 'Ajuste removido; volta a valer o cálculo.' : 'Faixa ajustada. Já vale nos apps.');
    if (ok) { setEditar(null); tabela.recarregar(); }
  };

  return (
    <>
      <Cabecalho titulo="Preços de referência" texto="A faixa comum (P25 a P75) que o app mostra para cada especialidade e região. O profissional sempre define o próprio preço."
        acoes={<select className="entrada" value={profissao} onChange={(e) => setProfissao(e.target.value)} aria-label="Profissão">
          {profissoes.dados?.map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}
        </select>} />
      <div className="linha-flex texto-suave" style={{ marginBottom: 14, gap: 18 }}>
        <span><strong style={{ color: 'var(--verde-texto)' }}>●</strong> Calculada com 5+ preços reais</span>
        <span><strong style={{ color: 'var(--texto-fraco)' }}>●</strong> Estimada pela base (poucos preços)</span>
        <span><strong style={{ color: 'var(--azul)' }}>●</strong> Ajustada pela equipe</span>
      </div>
      <section className="cartao">
        <div className="corpo sem-espaco">
          {tabela.erro ? <div style={{ padding: 16 }}><ErroCaixa erro={tabela.erro} tentar={tabela.recarregar} /></div> : tabela.carregando && !tabela.dados ? <Carregando /> :
            !linhas.length ? <Vazio icone={<Tags size={24} />} titulo="Sem especialidades nesta profissão" /> : (
              <div className="tabela-rolagem">
                <table className="tabela">
                  <thead>
                    <tr><th>Especialidade</th>{[1, 2, 3, 4, 5].map((f) => <th key={f} title={exemplosFaixa[f]}>{nomesFaixa[f]}<div style={{ textTransform: 'none', letterSpacing: 0, fontWeight: 500 }}>{exemplosFaixa[f]}</div></th>)}</tr>
                  </thead>
                  <tbody>
                    {linhas.map(([id, l]) => (
                      <tr key={id}>
                        <td><strong>{l.nome}</strong></td>
                        {[1, 2, 3, 4, 5].map((f) => {
                          const c = l.c[f];
                          if (!c) return <td key={f}>—</td>;
                          const aj = c.ajuste_minimo != null;
                          const cor = aj ? 'var(--azul)' : c.estimada ? 'var(--texto-fraco)' : 'var(--verde-texto)';
                          return (
                            <td key={f}>
                              <button onClick={() => abrir(c)} className="botao fantasma pequeno" style={{ height: 'auto', padding: '6px 8px', flexDirection: 'column', alignItems: 'flex-start', gap: 0 }}
                                title={aj ? `Ajustado em ${dataHora(c.ajustado_em)}. Calculado: ${real(c.minimo)} a ${real(c.maximo)}` : `${c.amostras} preços reais`}>
                                <span style={{ color: cor, fontWeight: 700, whiteSpace: 'nowrap' }}>
                                  {real(aj ? c.ajuste_minimo! : c.minimo)} a {real(aj ? c.ajuste_maximo! : c.maximo)} <Pencil size={11} style={{ opacity: 0.5 }} />
                                </span>
                                <span className="texto-fraco" style={{ fontSize: 11 }}>{aj ? 'ajustada' : `${c.amostras} ${c.amostras === 1 ? 'preço' : 'preços'}`}</span>
                              </button>
                            </td>
                          );
                        })}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
        </div>
      </section>
      <Dialogo aberto={!!editar} fechar={() => setEditar(null)} titulo={editar ? `${editar.especialidade} · ${nomesFaixa[editar.faixa]}` : ''}
        texto={editar ? <>Calculado agora: {real(editar.minimo)} a {real(editar.maximo)} ({editar.amostras} {editar.amostras === 1 ? 'preço real' : 'preços reais'}{editar.estimada ? ', estimado' : ''}).</> : null}
        rodape={<>
          {editar?.ajuste_minimo != null ? <button className="botao contorno perigo-texto" disabled={ocupado} onClick={() => salvar(true)}>Remover ajuste</button> : null}
          <span className="espaco" />
          <button className="botao contorno" onClick={() => setEditar(null)}>Cancelar</button>
          <button className="botao primario" disabled={ocupado || !(Number(min) > 0) || Number(max) < Number(min)} onClick={() => salvar()}>Salvar faixa</button>
        </>}>
        <div className="grade g2">
          <div className="campo"><label htmlFor="p-min">De (R$)</label><input id="p-min" className="entrada" type="number" min={1} value={min} onChange={(e) => setMin(e.target.value)} /></div>
          <div className="campo"><label htmlFor="p-max">Até (R$)</label><input id="p-max" className="entrada" type="number" min={1} value={max} onChange={(e) => setMax(e.target.value)} /></div>
        </div>
        <span className="texto-fraco">O ajuste vale para todas as regiões desta faixa e substitui o cálculo até ser removido.</span>
      </Dialogo>
    </>
  );
}
