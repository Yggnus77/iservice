'use client';

import dynamic from 'next/dynamic';
import Link from 'next/link';
import { useMemo, useState } from 'react';
import { Megaphone, SearchX } from 'lucide-react';
import { Cabecalho } from '@/components/Painel';
import { Abas, Carregando, ErroCaixa, Vazio, useCarregar } from '@/components/ui';
import { db, rpc } from '@/lib/supabase';
import { diasAtrasISO, hojeISO, numero } from '@/lib/formatos';
import type { Ponto } from '@/components/MapaCalor';

const MapaCalor = dynamic(() => import('@/components/MapaCalor'), { ssr: false, loading: () => <Carregando texto="Carregando o mapa…" /> });

type PorRegiao = { regiao_id: string | null; regiao: string | null; profissao_id: string | null; profissao: string | null; buscas: number; sem_resultado: number };
type PontoBanco = { lat: number; lng: number; total: number; sem_resultado: number };
type Profissao = { id: string; nome: string };

export default function Buscas() {
  const [periodo, setPeriodo] = useState<'1' | '7' | '30' | '90'>('30');
  const [profissao, setProfissao] = useState('');
  const [modo, setModo] = useState<'sem' | 'todas'>('sem');
  const [tudo, setTudo] = useState(false);
  const inicio = periodo === '1' ? hojeISO() : diasAtrasISO(Number(periodo) - 1);
  const fim = hojeISO();

  const profissoes = useCarregar(async () => {
    const { data } = await db().from('profissoes').select('id, nome').order('ordem');
    return (data ?? []) as Profissao[];
  }, []);
  const lista = useCarregar(() => rpc<PorRegiao[]>('admin_buscas_por_regiao', { p_inicio: inicio, p_fim: fim }), [inicio, fim]);
  const mapa = useCarregar(() => rpc<PontoBanco[]>('admin_mapa_buscas', {
    p_inicio: inicio, p_fim: fim, p_profissao: profissao || null, p_so_sem_resultado: modo === 'sem',
  }), [inicio, fim, profissao, modo]);

  const nomesProfissao = (profissoes.dados ?? []).map((p) => [p.id, p.nome] as const);

  const pontos: Ponto[] = useMemo(() => (mapa.dados ?? []).map((p) => ({
    lat: Number(p.lat), lng: Number(p.lng), total: p.total, sem: p.sem_resultado, peso: modo === 'sem' ? p.sem_resultado : p.total,
  })), [mapa.dados, modo]);

  const linhas = (lista.dados ?? []).filter((l) => !profissao || l.profissao_id === profissao);
  const totais = linhas.reduce((a, l) => ({ b: a.b + Number(l.buscas), s: a.s + Number(l.sem_resultado) }), { b: 0, s: 0 });

  // Regiões com mais buscas sem resultado (somando profissões)
  const porRegiao = useMemo(() => {
    const m = new Map<string, { nome: string; b: number; s: number }>();
    linhas.forEach((l) => {
      const k = l.regiao_id ?? '?';
      const x = m.get(k) ?? { nome: l.regiao ?? 'Fora das regiões', b: 0, s: 0 };
      x.b += Number(l.buscas); x.s += Number(l.sem_resultado);
      m.set(k, x);
    });
    return [...m.values()].sort((a, b) => b.s - a.s || b.b - a.b).slice(0, 8);
  }, [linhas]);
  const maxRegiao = Math.max(1, ...porRegiao.map((r) => r.b));

  return (
    <>
      <Cabecalho titulo="Buscas e mapa" texto="Onde os clientes procuram e não encontram ninguém: é ali que vale recrutar profissionais."
        acoes={<Link className="botao contorno" href="/comunicados/"><Megaphone /> Avisar profissionais</Link>} />
      <div className="filtros">
        <Abas ativa={periodo} mudar={setPeriodo} abas={[{ id: '1', rotulo: 'Hoje' }, { id: '7', rotulo: '7 dias' }, { id: '30', rotulo: '30 dias' }, { id: '90', rotulo: '90 dias' }]} />
        <select className="entrada" value={profissao} onChange={(e) => setProfissao(e.target.value)} aria-label="Profissão">
          <option value="">Todas as profissões</option>
          {nomesProfissao.map(([id, nome]) => <option key={id} value={id}>{nome}</option>)}
        </select>
        <span className="espaco" />
        <span className="texto-suave forte">{numero(totais.b)} buscas · {numero(totais.s)} sem resultado{totais.b ? ` (${Math.round((totais.s / totais.b) * 100)}%)` : ''}</span>
      </div>

      <div className="grade lado">
        <section className="cartao">
          <div className="titulo">
            <div><h2>Mapa de calor</h2><p>Local aproximado (cerca de 1 km) de cada busca. Passe o mouse para ver os números.</p></div>
            <Abas ativa={modo} mudar={setModo} abas={[{ id: 'sem', rotulo: 'Sem resultado' }, { id: 'todas', rotulo: 'Todas' }]} />
          </div>
          {mapa.erro ? <div className="corpo"><ErroCaixa erro={mapa.erro} tentar={mapa.recarregar} /></div> : <MapaCalor pontos={pontos} />}
        </section>

        <section className="cartao">
          <div className="titulo"><div><h2>Regiões com mais buscas sem resultado</h2><p>A parte laranja é o que ficou sem resposta.</p></div></div>
          <div className="corpo">
            {lista.carregando && !lista.dados ? <Carregando /> : !porRegiao.length ? <Vazio icone={<SearchX size={24} />} titulo="Nenhuma busca no período" /> : porRegiao.map((r) => (
              <div className="meta" key={r.nome} title={`${r.b} buscas, ${r.s} sem resultado`}>
                <span className="nome">{r.nome}</span>
                <span className="trilho">
                  {r.b - r.s > 0 ? <i className="a" style={{ width: `${((r.b - r.s) / maxRegiao) * 100}%` }} /> : null}
                  {r.s > 0 ? <i style={{ width: `${(r.s / maxRegiao) * 100}%`, background: 'var(--laranja)' }} /> : null}
                </span>
                <span className="valor">{r.s} de {r.b}</span>
              </div>
            ))}
          </div>
        </section>
      </div>

      <section className="cartao" style={{ marginTop: 18 }}>
        <div className="titulo"><div><h2>Buscas por região e profissão</h2><p>Ordenado pelas que mais ficaram sem resultado.</p></div></div>
        <div className="corpo sem-espaco">
          {lista.erro ? <div style={{ padding: 16 }}><ErroCaixa erro={lista.erro} tentar={lista.recarregar} /></div> : lista.carregando && !lista.dados ? <Carregando /> : !linhas.length ? (
            <Vazio titulo="Nenhuma busca no período" />
          ) : (
            <div className="tabela-rolagem">
              <table className="tabela">
                <thead><tr><th>Região</th><th>Profissão</th><th className="num">Buscas</th><th className="num">Sem resultado</th><th className="num">%</th></tr></thead>
                <tbody>
                  {linhas.slice(0, tudo ? 1000 : 25).map((l, i) => (
                    <tr key={i}>
                      <td>{l.regiao ?? 'Fora das regiões'}</td>
                      <td>{l.profissao ?? '—'}</td>
                      <td className="num">{numero(Number(l.buscas))}</td>
                      <td className="num" style={{ color: Number(l.sem_resultado) ? 'var(--laranja-texto)' : undefined, fontWeight: 700 }}>{numero(Number(l.sem_resultado))}</td>
                      <td className="num">{Math.round((Number(l.sem_resultado) / Number(l.buscas)) * 100)}%</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {linhas.length > 25 ? (
                <div style={{ padding: 12, textAlign: 'center', borderTop: '1px solid var(--linha)' }}>
                  <button className="botao fantasma pequeno" onClick={() => setTudo(!tudo)}>{tudo ? 'Mostrar menos' : `Mostrar todas as ${linhas.length} linhas`}</button>
                </div>
              ) : null}
            </div>
          )}
        </div>
      </section>
    </>
  );
}
