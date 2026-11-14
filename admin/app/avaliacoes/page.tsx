'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { ArrowDownWideNarrow, ArrowUpWideNarrow, ClipboardCheck, Search, Star, ThumbsDown, Timer, UserRound, Wrench } from 'lucide-react';
import { Cabecalho } from '@/components/Painel';
import { Abas, Carregando, ErroCaixa, Estrelas, Pessoa, Selo, Vazio, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { data, dataHora, numero } from '@/lib/formatos';

type Resumo = {
  media_profissionais: number | null; total_profissionais: number; media_clientes: number | null; total_clientes: number;
  baixas: number; horas_trabalhadas: number; sem_avaliacao: number;
};
type Ranking = {
  id: string; nome: string; foto_url: string | null; nota: number; total: number; notas_baixas: number; cinco_estrelas: number;
  servicos: number; minutos_trabalhados: number | null; ultima_avaliacao: string | null; situacao: string | null;
};
type Recente = {
  direcao: 'cliente_avalia' | 'profissional_avalia'; pedido_id: string; codigo: string; nota: number; comentario: string | null;
  autor_id: string; autor: string; autor_foto: string | null; avaliado_id: string; avaliado: string; avaliado_foto: string | null;
  minutos_trabalhados: number | null; oculta: boolean; criada_em: string;
};
type Aba = 'profissionais' | 'clientes' | 'recentes';
type Ordem = 'melhores' | 'piores';

const horas = (min?: number | null) => (min == null ? '—' : min < 60 ? `${min} min` : `${numero(Math.floor(min / 60))} h`);
const media = (v?: number | null) => (v == null ? '—' : Number(v).toFixed(1).replace('.', ','));
const tomNota = (n: number) => (n >= 4.5 ? 'verde' : n >= 3.5 ? 'azul' : n >= 2.5 ? 'laranja' : 'vermelho');

function Numero({ rotulo, valor, detalhe, icone, cor, fundo }: { rotulo: string; valor: React.ReactNode; detalhe?: React.ReactNode; icone: React.ReactNode; cor: string; fundo: string }) {
  return (
    <div className="cartao numero">
      <span className="rotulo"><span className="icone" style={{ color: cor, background: fundo }}>{icone}</span>{rotulo}</span>
      <span className="valor">{valor}</span>
      {detalhe ? <span className="detalhe">{detalhe}</span> : null}
    </div>
  );
}

function NotaMedia({ nota, total }: { nota: number; total: number }) {
  return (
    <span className="linha-flex" style={{ gap: 6 }}>
      <Star size={15} color="#ffb400" fill="#ffb400" />
      <strong>{media(nota)}</strong>
      <span className="texto-fraco">({numero(total)})</span>
    </span>
  );
}

export default function Avaliacoes() {
  const router = useRouter();
  const [aba, setAba] = useState<Aba>('profissionais');
  const [ordem, setOrdem] = useState<Ordem>('melhores');
  const [minimo, setMinimo] = useState(1);
  const [texto, setTexto] = useState('');
  const [busca, setBusca] = useState('');
  const [direcao, setDirecao] = useState<'todas' | 'cliente_avalia' | 'profissional_avalia'>('todas');
  const [soBaixas, setSoBaixas] = useState(false);
  useEffect(() => { const t = setTimeout(() => setBusca(texto), 300); return () => clearTimeout(t); }, [texto]);

  const resumo = useCarregar(() => rpc<Resumo>('admin_resumo_avaliacoes', { p_dias: 30 }), []);
  const ranking = useCarregar(
    () => (aba === 'recentes' ? Promise.resolve([] as Ranking[]) : rpc<Ranking[]>('admin_ranking_avaliacoes', {
      p_tipo: aba, p_ordem: ordem, p_min_avaliacoes: minimo, p_texto: busca || null, p_limite: 100,
    })),
    [aba, ordem, minimo, busca]);
  const recentes = useCarregar(
    () => (aba !== 'recentes' ? Promise.resolve([] as Recente[]) : rpc<Recente[]>('admin_avaliacoes_recentes', {
      p_direcao: direcao, p_so_baixas: soBaixas, p_dias: 90, p_limite: 200,
    })),
    [aba, direcao, soBaixas]);
  const r = resumo.dados;

  return (
    <>
      <Cabecalho titulo="Avaliações"
        texto="As notas nos dois sentidos: clientes avaliam profissionais e profissionais avaliam clientes. Use para premiar os melhores e acompanhar de perto os piores." />

      <div className="grade g4" style={{ marginBottom: 18 }}>
        <Numero rotulo="Nota média dos profissionais" valor={media(r?.media_profissionais)} icone={<Wrench />} cor="#b25f00" fundo="#fff4e5"
          detalhe={`${numero(r?.total_profissionais ?? 0)} avaliações nos últimos 30 dias`} />
        <Numero rotulo="Nota média dos clientes" valor={media(r?.media_clientes)} icone={<UserRound />} cor="#0046b8" fundo="#e8f0fc"
          detalhe={`${numero(r?.total_clientes ?? 0)} avaliações nos últimos 30 dias`} />
        <Numero rotulo="Notas 1 ou 2 estrelas" valor={numero(r?.baixas ?? 0)} icone={<ThumbsDown />} cor="#c62828" fundo="#fdecec"
          detalhe="Nos dois sentidos, últimos 30 dias" />
        <Numero rotulo="Horas trabalhadas" valor={`${numero(r?.horas_trabalhadas ?? 0)} h`} icone={<Timer />} cor="#00873a" fundo="#e6f9ee"
          detalhe={`${numero(r?.sem_avaliacao ?? 0)} serviços concluídos ainda sem avaliação`} />
      </div>

      <div className="filtros">
        <Abas<Aba> ativa={aba} mudar={setAba} abas={[
          { id: 'profissionais', rotulo: 'Profissionais' }, { id: 'clientes', rotulo: 'Clientes' }, { id: 'recentes', rotulo: 'Avaliações recentes' },
        ]} />
        <span className="espaco" />
        {aba === 'recentes' ? (
          <>
            <Abas ativa={direcao} mudar={setDirecao} abas={[
              { id: 'todas', rotulo: 'Todas' }, { id: 'cliente_avalia', rotulo: 'Cliente avaliou' }, { id: 'profissional_avalia', rotulo: 'Profissional avaliou' },
            ]} />
            <label className="linha-flex" style={{ gap: 6 }}>
              <input type="checkbox" checked={soBaixas} onChange={(e) => setSoBaixas(e.target.checked)} /> Só 1 e 2 estrelas
            </label>
          </>
        ) : (
          <>
            <div className="linha-flex" style={{ gap: 6 }}>
              <button className={`botao pequeno ${ordem === 'melhores' ? '' : 'contorno'}`} onClick={() => setOrdem('melhores')}><ArrowDownWideNarrow size={14} /> Melhores</button>
              <button className={`botao pequeno ${ordem === 'piores' ? '' : 'contorno'}`} onClick={() => setOrdem('piores')}><ArrowUpWideNarrow size={14} /> Piores</button>
            </div>
            <select className="entrada" style={{ width: 'auto' }} value={minimo} onChange={(e) => setMinimo(Number(e.target.value))} aria-label="Mínimo de avaliações">
              <option value={1}>1+ avaliação</option>
              <option value={3}>3+ avaliações</option>
              <option value={5}>5+ avaliações</option>
              <option value={10}>10+ avaliações</option>
            </select>
            <div className="busca"><Search /><input className="entrada" placeholder="Buscar pelo nome" value={texto} onChange={(e) => setTexto(e.target.value)} aria-label="Buscar pelo nome" /></div>
          </>
        )}
      </div>

      <section className="cartao">
        <div className="corpo sem-espaco">
          {aba === 'recentes' ? (
            recentes.erro ? <div style={{ padding: 16 }}><ErroCaixa erro={recentes.erro} tentar={recentes.recarregar} /></div>
              : recentes.carregando && !recentes.dados ? <Carregando />
              : !recentes.dados?.length ? <Vazio icone={<Star size={24} />} titulo="Nenhuma avaliação" texto="As avaliações dos últimos 90 dias aparecem aqui." />
              : (
                <div className="tabela-rolagem">
                  <table className="tabela">
                    <thead><tr><th>Quem avaliou</th><th>Avaliado</th><th>Nota</th><th>Comentário</th><th>Pedido</th><th>Quando</th></tr></thead>
                    <tbody>
                      {recentes.dados.map((a) => (
                        <tr key={`${a.direcao}-${a.pedido_id}`}>
                          <td><Pessoa nome={a.autor} foto={a.autor_foto} sub={a.direcao === 'cliente_avalia' ? 'Cliente' : 'Profissional'} /></td>
                          <td><Link href={`/pessoa/?id=${a.avaliado_id}`}><Pessoa nome={a.avaliado} foto={a.avaliado_foto} sub={a.direcao === 'cliente_avalia' ? 'Profissional' : 'Cliente'} /></Link></td>
                          <td><Estrelas nota={a.nota} />{a.oculta ? <> <Selo tom="neutro">Oculta</Selo></> : null}</td>
                          <td style={{ maxWidth: 340 }}>{a.comentario ?? <span className="texto-fraco">Sem comentário</span>}</td>
                          <td><Link href={`/pedido/?id=${a.pedido_id}`} className="mono">{a.codigo}</Link>{a.minutos_trabalhados != null ? <div className="texto-fraco">{horas(a.minutos_trabalhados)} de trabalho</div> : null}</td>
                          <td className="fraco">{dataHora(a.criada_em)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )
          ) : ranking.erro ? <div style={{ padding: 16 }}><ErroCaixa erro={ranking.erro} tentar={ranking.recarregar} /></div>
            : ranking.carregando && !ranking.dados ? <Carregando />
            : !ranking.dados?.length ? (
              <Vazio icone={<ClipboardCheck size={24} />} titulo={aba === 'clientes' ? 'Nenhum cliente avaliado ainda' : 'Nenhum profissional avaliado ainda'}
                texto="Assim que os serviços forem concluídos e avaliados, o ranking aparece aqui." />
            ) : (
              <div className="tabela-rolagem">
                <table className="tabela">
                  <thead>
                    <tr>
                      <th className="num">#</th><th>{aba === 'clientes' ? 'Cliente' : 'Profissional'}</th><th>Nota</th>
                      <th className="num">5 estrelas</th><th className="num">1 ou 2 estrelas</th>
                      <th className="num">Serviços</th>{aba === 'profissionais' ? <th className="num">Horas trabalhadas</th> : null}<th>Última avaliação</th>
                    </tr>
                  </thead>
                  <tbody>
                    {ranking.dados.map((l, i) => (
                      <tr key={l.id} className="clicavel" onClick={() => router.push(`/pessoa/?id=${l.id}`)}>
                        <td className="num fraco">{i + 1}</td>
                        <td><Pessoa nome={l.nome} foto={l.foto_url} sub={l.situacao && l.situacao !== 'aprovado' ? l.situacao : undefined} /></td>
                        <td><span className="linha-flex" style={{ gap: 8 }}><NotaMedia nota={l.nota} total={l.total} /><Selo tom={tomNota(Number(l.nota))}>{Math.round(Number(l.nota))} estrelas</Selo></span></td>
                        <td className="num">{numero(l.cinco_estrelas)}</td>
                        <td className="num">{l.notas_baixas ? <strong style={{ color: '#c62828' }}>{numero(l.notas_baixas)}</strong> : '0'}</td>
                        <td className="num">{numero(l.servicos)}</td>
                        {aba === 'profissionais' ? <td className="num">{horas(l.minutos_trabalhados)}</td> : null}
                        <td className="fraco">{data(l.ultima_avaliacao)}</td>
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
