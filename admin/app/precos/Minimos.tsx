'use client';

import { useMemo, useState } from 'react';
import { MapPin, Pencil, ShieldCheck, Trash2 } from 'lucide-react';
import { Carregando, Dialogo, ErroCaixa, Selo, useAcao, useCarregar } from '@/components/ui';
import { db, rpc } from '@/lib/supabase';
import { dataHora } from '@/lib/formatos';

type Minimo = {
  profissao_id: string; profissao: string; cobranca: 'servico' | 'hora' | 'diaria'; faixa: number; regiao_id: string | null; regiao: string | null;
  valor: number; calculado: number; abaixo: number; atualizado_em: string;
};
type Regiao = { id: string; nome: string; uf: string; faixa_preco: number };

const nomesFaixa = ['', 'Faixa 1', 'Faixa 2', 'Faixa 3', 'Faixa 4', 'Faixa 5'];
const unidade = { servico: 'por serviço', hora: 'por hora', diaria: 'por diária' } as const;
const real = (v: number) => `R$ ${Math.round(Number(v)).toLocaleString('pt-BR')}`;

/** Valor mínimo que cada profissional pode cobrar, por profissão e região. Só a equipe muda. */
export default function Minimos() {
  const tabela = useCarregar(() => rpc<Minimo[]>('admin_tabela_minimos'), []);
  const regioes = useCarregar(async () => {
    const { data } = await db().from('regioes').select('id, nome, uf, faixa_preco').order('ordem');
    return (data ?? []) as Regiao[];
  }, []);
  const { executar, ocupado } = useAcao();
  const [editar, setEditar] = useState<Minimo | null>(null);
  const [valor, setValor] = useState('');
  const [nova, setNova] = useState(false);
  const [novaForm, setNovaForm] = useState({ profissao: '', regiao: '', valor: '' });

  const { linhas, proprios } = useMemo(() => {
    const m = new Map<string, { nome: string; cobranca: Minimo['cobranca']; c: Record<number, Minimo> }>();
    const p: Minimo[] = [];
    (tabela.dados ?? []).forEach((x) => {
      if (x.regiao_id) { p.push(x); return; }
      const l = m.get(x.profissao_id) ?? { nome: x.profissao, cobranca: x.cobranca, c: {} };
      l.c[x.faixa] = x;
      m.set(x.profissao_id, l);
    });
    return { linhas: [...m.entries()], proprios: p };
  }, [tabela.dados]);

  const abrir = (x: Minimo) => { setEditar(x); setValor(String(Math.round(x.valor))); };
  const salvar = async (voltar = false) => {
    if (!editar) return;
    const ok = await executar(() => rpc('admin_definir_minimo', {
      p_profissao: editar.profissao_id,
      p_faixa: editar.regiao_id ? null : editar.faixa,
      p_regiao: editar.regiao_id,
      p_valor: voltar ? null : Number(valor),
    }), voltar ? (editar.regiao_id ? 'Mínimo da região removido; volta a valer o da faixa.' : 'Mínimo voltou ao valor da regra.') : 'Mínimo salvo. Já vale nos apps.');
    if (ok) { setEditar(null); tabela.recarregar(); }
  };
  const criarProprio = async () => {
    const ok = await executar(() => rpc('admin_definir_minimo', {
      p_profissao: novaForm.profissao, p_faixa: null, p_regiao: novaForm.regiao, p_valor: Number(novaForm.valor),
    }), 'Mínimo da região salvo. Já vale nos apps.');
    if (ok) { setNova(false); setNovaForm({ profissao: '', regiao: '', valor: '' }); tabela.recarregar(); }
  };
  const alterado = (x: Minimo) => Math.round(x.valor) !== Math.round(x.calculado);
  const unidadeDe = (id: string) => unidade[linhas.find(([p]) => p === id)?.[1].cobranca ?? 'servico'];

  return (
    <section className="cartao" style={{ marginBottom: 24 }}>
      <div className="corpo">
        <div className="linha-flex" style={{ justifyContent: 'space-between', alignItems: 'flex-start', gap: 12 }}>
          <div>
            <h2 style={{ margin: 0, display: 'flex', alignItems: 'center', gap: 8 }}><ShieldCheck size={18} /> Valores mínimos</h2>
            <p className="texto-suave" style={{ margin: '6px 0 0' }}>
              Nenhum profissional consegue salvar um preço abaixo do mínimo da região dele. O preço não conta na ordem das recomendações.
              Valores na forma de cobrança comum de cada profissão; por hora ou por diária são convertidos sozinhos.
            </p>
          </div>
          <button className="botao contorno" onClick={() => setNova(true)}><MapPin /> Mínimo de uma região</button>
        </div>
      </div>
      <div className="corpo sem-espaco">
        {tabela.erro ? <div style={{ padding: 16 }}><ErroCaixa erro={tabela.erro} tentar={tabela.recarregar} /></div> : tabela.carregando && !tabela.dados ? <Carregando /> : (
          <div className="tabela-rolagem">
            <table className="tabela">
              <thead><tr><th>Profissão</th>{[1, 2, 3, 4, 5].map((f) => <th key={f}>{nomesFaixa[f]}</th>)}</tr></thead>
              <tbody>
                {linhas.map(([id, l]) => (
                  <tr key={id}>
                    <td><strong>{l.nome}</strong><div className="texto-fraco" style={{ fontSize: 12 }}>{unidade[l.cobranca]}</div></td>
                    {[1, 2, 3, 4, 5].map((f) => {
                      const x = l.c[f];
                      if (!x) return <td key={f}>—</td>;
                      return (
                        <td key={f}>
                          <button onClick={() => abrir(x)} className="botao fantasma pequeno" style={{ height: 'auto', padding: '6px 8px', flexDirection: 'column', alignItems: 'flex-start', gap: 0 }}
                            title={`Alterado em ${dataHora(x.atualizado_em)}. Pela regra: ${real(x.calculado)}`}>
                            <span style={{ color: alterado(x) ? 'var(--azul)' : undefined, fontWeight: 700, whiteSpace: 'nowrap' }}>
                              {real(x.valor)} <Pencil size={11} style={{ opacity: 0.5 }} />
                            </span>
                            {x.abaixo > 0 ? <span style={{ fontSize: 11, color: 'var(--perigo)' }}>{x.abaixo} abaixo</span> : null}
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
      {proprios.length ? (
        <div className="corpo">
          <strong>Mínimos próprios de cada região</strong>
          <span className="texto-fraco"> · valem antes do valor da faixa</span>
          <div className="tabela-rolagem" style={{ marginTop: 8 }}>
            <table className="tabela">
              <thead><tr><th>Profissão</th><th>Região</th><th>Mínimo</th><th></th></tr></thead>
              <tbody>
                {proprios.map((x) => (
                  <tr key={`${x.profissao_id}-${x.regiao_id}`}>
                    <td>{x.profissao}</td>
                    <td>{x.regiao} <span className="texto-fraco">({nomesFaixa[x.faixa]})</span></td>
                    <td><strong>{real(x.valor)}</strong> <span className="texto-fraco">{unidade[x.cobranca]}</span> {x.abaixo > 0 ? <Selo tom="vermelho">{x.abaixo} abaixo</Selo> : null}</td>
                    <td style={{ textAlign: 'right' }}><button className="botao fantasma pequeno" onClick={() => abrir(x)}><Pencil /> Mudar</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      ) : null}

      <Dialogo aberto={!!editar} fechar={() => setEditar(null)}
        titulo={editar ? `${editar.profissao} · ${editar.regiao ?? nomesFaixa[editar.faixa]}` : ''}
        texto={editar ? <>Valor mínimo {unidade[editar.cobranca]}. Pela regra aprovada: {real(editar.calculado)}.{editar.abaixo > 0 ? ` Hoje ${editar.abaixo} ${editar.abaixo === 1 ? 'preço está' : 'preços estão'} abaixo e precisam ser corrigidos pelo profissional.` : ''}</> : null}
        rodape={<>
          {editar?.regiao_id ? (
            <button className="botao contorno perigo-texto" disabled={ocupado} onClick={() => salvar(true)}><Trash2 /> Remover</button>
          ) : editar && alterado(editar) ? (
            <button className="botao contorno" disabled={ocupado} onClick={() => salvar(true)}>Voltar à regra</button>
          ) : null}
          <span className="espaco" />
          <button className="botao contorno" onClick={() => setEditar(null)}>Cancelar</button>
          <button className="botao primario" disabled={ocupado || !(Number(valor) > 0)} onClick={() => salvar()}>Salvar mínimo</button>
        </>}>
        <div className="campo"><label htmlFor="m-valor">Mínimo (R$)</label>
          <input id="m-valor" className="entrada" type="number" min={1} value={valor} onChange={(e) => setValor(e.target.value)} />
          <span className="ajuda">Quem já cobra menos vê o aviso no app e precisa ajustar o preço.</span></div>
      </Dialogo>

      <Dialogo aberto={nova} fechar={() => setNova(false)} titulo="Mínimo de uma região"
        texto="Para uma cidade, região ou estado com realidade de preço diferente da sua faixa. Vale só ali, antes do valor da faixa."
        rodape={<>
          <span className="espaco" />
          <button className="botao contorno" onClick={() => setNova(false)}>Cancelar</button>
          <button className="botao primario" disabled={ocupado || !novaForm.profissao || !novaForm.regiao || !(Number(novaForm.valor) > 0)} onClick={criarProprio}>Salvar mínimo</button>
        </>}>
        <div className="grade g2">
          <div className="campo"><label htmlFor="mr-prof">Profissão</label>
            <select id="mr-prof" className="entrada" value={novaForm.profissao} onChange={(e) => setNovaForm({ ...novaForm, profissao: e.target.value })}>
              <option value="">Escolha</option>
              {linhas.map(([id, l]) => <option key={id} value={id}>{l.nome}</option>)}
            </select></div>
          <div className="campo"><label htmlFor="mr-reg">Região</label>
            <select id="mr-reg" className="entrada" value={novaForm.regiao} onChange={(e) => setNovaForm({ ...novaForm, regiao: e.target.value })}>
              <option value="">Escolha</option>
              {regioes.dados?.map((r) => <option key={r.id} value={r.id}>{r.nome} ({r.uf}) · {nomesFaixa[r.faixa_preco]}</option>)}
            </select></div>
        </div>
        <div className="campo"><label htmlFor="mr-valor">Mínimo (R$){novaForm.profissao ? `, ${unidadeDe(novaForm.profissao)}` : ''}</label>
          <input id="mr-valor" className="entrada" type="number" min={1} value={novaForm.valor} onChange={(e) => setNovaForm({ ...novaForm, valor: e.target.value })} /></div>
      </Dialogo>
    </section>
  );
}
