'use client';

import Link from 'next/link';
import { useEffect } from 'react';
import { BadgeCheck, ClipboardList, Flag, Search, SearchX, ShieldCheck, Siren, Star, UserPlus, Users, Wrench } from 'lucide-react';
import { Cabecalho, usePainel } from '@/components/Painel';
import { Carregando } from '@/components/ui';
import { diaCurto, numero, statusPedido } from '@/lib/formatos';

const META_POR_PROFISSAO = 15;
const META_TOTAL = 300;

function Numero({ rotulo, valor, detalhe, icone, cor, fundo, href }: {
  rotulo: string; valor: React.ReactNode; detalhe?: React.ReactNode; icone: React.ReactNode; cor: string; fundo: string; href?: string;
}) {
  const corpo = (
    <>
      <span className="rotulo"><span className="icone" style={{ color: cor, background: fundo }}>{icone}</span>{rotulo}</span>
      <span className="valor">{valor}</span>
      {detalhe ? <span className="detalhe">{detalhe}</span> : null}
    </>
  );
  return href ? <Link href={href} className="cartao numero">{corpo}</Link> : <div className="cartao numero">{corpo}</div>;
}

export default function Inicio() {
  const { resumo, atualizarResumo, nome } = usePainel();
  useEffect(() => { atualizarResumo(); }, [atualizarResumo]);
  if (!resumo) return <Carregando />;

  const dias = resumo.ultimos_7_dias;
  const maxBusca = Math.max(1, ...dias.map((d) => d.buscas));
  const maxPed = Math.max(1, ...dias.map((d) => Math.max(d.pedidos, d.concluidos)));
  const primeiroNome = nome.split(' ')[0];
  const hora = Number(new Date().toLocaleString('pt-BR', { hour: 'numeric', hour12: false, timeZone: 'America/Sao_Paulo' }));
  const saudacao = hora < 12 ? 'Bom dia' : hora < 18 ? 'Boa tarde' : 'Boa noite';
  const profs = [...resumo.profissionais_por_profissao].sort((a, b) => a.aprovados - b.aprovados);
  const completas = resumo.profissionais_por_profissao.filter((p) => p.aprovados >= META_POR_PROFISSAO).length;

  return (
    <>
      <Cabecalho titulo={`${saudacao}${primeiroNome ? ', ' + primeiroNome : ''}`}
        texto={`Resumo de hoje, ${new Date().toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'America/Sao_Paulo' })}.`} />

      {resumo.emergencias_abertas > 0 ? (
        <Link href="/emergencias/" className="alerta-faixa vermelho" style={{ textDecoration: 'none' }}>
          <Siren size={26} />
          <div><strong>{resumo.emergencias_abertas} {resumo.emergencias_abertas === 1 ? 'emergência aberta' : 'emergências abertas'}</strong>
            Alguém apertou o botão de emergência. Entre em contato agora.</div>
        </Link>
      ) : null}

      <div className="grade g4" style={{ marginBottom: 18 }}>
        <Numero href="/cadastros/" rotulo="Cadastros para aprovar" valor={numero(resumo.cadastros_em_analise)} icone={<BadgeCheck />} cor="#b25f00" fundo="#fff4e5"
          detalhe={resumo.cadastros_em_analise ? 'Quem enviou primeiro está no topo da fila' : 'Fila em dia'} />
        <Numero href="/garantia/" rotulo="Reclamações da garantia" valor={numero(resumo.reclamacoes_abertas)} icone={<ShieldCheck />} cor="#0046b8" fundo="#e8f0fc"
          detalhe="Abertas ou em mediação" />
        <Numero href="/denuncias/" rotulo="Denúncias abertas" valor={numero(resumo.denuncias_abertas)} icone={<Flag />} cor="#c62828" fundo="#fdecec" detalhe="Aguardando análise" />
        <Numero href="/pedidos/?status=andamento" rotulo="Pedidos em andamento" valor={numero(resumo.pedidos_em_andamento)} icone={<ClipboardList />} cor="#00873a" fundo="#e6f9ee"
          detalhe={`${numero(resumo.profissionais_disponiveis)} profissionais disponíveis agora`} />
      </div>

      <div className="grade g4" style={{ marginBottom: 18 }}>
        <Numero rotulo="Buscas hoje" valor={numero(resumo.buscas)} icone={<Search />} cor="#0046b8" fundo="#e8f0fc" href="/buscas/" />
        <Numero rotulo="Buscas sem resultado" valor={numero(resumo.buscas_sem_resultado)} icone={<SearchX />} cor="#b25f00" fundo="#fff4e5" href="/buscas/"
          detalhe={resumo.buscas ? `${Math.round((resumo.buscas_sem_resultado / resumo.buscas) * 100)}% das buscas: onde recrutar` : 'Nenhuma busca ainda hoje'} />
        <Numero rotulo="Pedidos hoje" valor={numero(resumo.pedidos)} icone={<ClipboardList />} cor="#00873a" fundo="#e6f9ee"
          detalhe={`${numero(resumo.concluidos)} concluídos · ${numero(resumo.avaliacoes)} avaliações${resumo.nota_media_dia ? ` (média ${Number(resumo.nota_media_dia).toFixed(1)})` : ''}`} />
        <Numero rotulo="Cadastros novos hoje" valor={numero(resumo.cadastros_novos_clientes + resumo.cadastros_novos_profissionais)} icone={<UserPlus />} cor="#5b3cc4" fundo="#efeafd"
          detalhe={`${numero(resumo.cadastros_novos_clientes)} clientes · ${numero(resumo.cadastros_novos_profissionais)} profissionais`} />
      </div>

      <div className="grade lado">
        <div className="pilha">
          <section className="cartao">
            <div className="titulo">
              <div><h2>Buscas nos últimos 7 dias</h2><p>A parte laranja são as buscas que não encontraram ninguém.</p></div>
              <div className="legenda"><span><i style={{ background: 'var(--azul)' }} />Com resultado</span><span><i style={{ background: 'var(--laranja)' }} />Sem resultado</span></div>
            </div>
            <div className="corpo">
              <div className="barras" role="img" aria-label="Buscas por dia">
                {dias.map((d) => {
                  const com = d.buscas - d.sem_resultado;
                  return (
                    <div className="coluna" key={d.dia}>
                      <span className="dica">{d.buscas} buscas · {d.sem_resultado} sem resultado</span>
                      <span className="val">{d.buscas}</span>
                      <div style={{ width: '100%', maxWidth: 44, display: 'flex', flexDirection: 'column', gap: 2, flex: 1, justifyContent: 'flex-end' }}>
                        {d.sem_resultado ? <div className="barra sem" style={{ height: `${(d.sem_resultado / maxBusca) * 100}%`, borderRadius: com ? '4px 4px 0 0' : '4px 4px 0 0' }} /> : null}
                        <div className="barra" style={{ height: `${(com / maxBusca) * 100}%`, borderRadius: d.sem_resultado ? 0 : '4px 4px 0 0' }} />
                      </div>
                      <span className="rot">{diaCurto(d.dia)}</span>
                    </div>
                  );
                })}
              </div>
            </div>
          </section>

          <section className="cartao">
            <div className="titulo">
              <div><h2>Pedidos nos últimos 7 dias</h2><p>Pedidos feitos e serviços concluídos por dia.</p></div>
              <div className="legenda"><span><i style={{ background: 'var(--azul)' }} />Feitos</span><span><i style={{ background: 'var(--verde-texto)' }} />Concluídos</span></div>
            </div>
            <div className="corpo">
              <div className="barras" role="img" aria-label="Pedidos por dia">
                {dias.map((d) => (
                  <div className="coluna" key={d.dia}>
                    <span className="dica">{d.pedidos} pedidos · {d.concluidos} concluídos · {d.cadastros} cadastros</span>
                    <span className="val">{d.pedidos}</span>
                    <div className="dupla">
                      <div className="barra" style={{ height: `${(d.pedidos / maxPed) * 100}%` }} />
                      <div className="barra" style={{ height: `${(d.concluidos / maxPed) * 100}%`, background: 'var(--verde-texto)' }} />
                    </div>
                    <span className="rot">{diaCurto(d.dia)}</span>
                  </div>
                ))}
              </div>
            </div>
          </section>

          <section className="cartao">
            <div className="titulo"><div><h2>Pedidos de hoje por situação</h2></div></div>
            <div className="corpo">
              {Object.keys(resumo.pedidos_por_status).length === 0 ? <span className="texto-suave">Nenhum pedido hoje até agora.</span> : (
                <div className="linha-flex">
                  {Object.entries(resumo.pedidos_por_status).map(([s, n]) => (
                    <Link key={s} href={`/pedidos/?status=${s}`} className={`selo ${statusPedido[s]?.tom ?? 'neutro'}`} style={{ fontSize: 13, padding: '6px 12px' }}>
                      {statusPedido[s]?.rotulo ?? s}: {n}
                    </Link>
                  ))}
                </div>
              )}
            </div>
          </section>
        </div>

        <section className="cartao">
          <div className="titulo">
            <div>
              <h2>Meta de recrutamento</h2>
              <p>{numero(resumo.profissionais_aprovados)} de {META_TOTAL} aprovados · {completas} de {resumo.profissionais_por_profissao.length} profissões com {META_POR_PROFISSAO}+</p>
            </div>
            <Wrench size={18} color="#7a879d" />
          </div>
          <div className="corpo">
            <div className="meta" style={{ paddingTop: 0 }}>
              <span className="nome forte">Total</span>
              <span className="trilho"><i className="a" style={{ width: `${Math.min(100, (resumo.profissionais_aprovados / META_TOTAL) * 100)}%` }} /></span>
              <span className="valor">{resumo.profissionais_aprovados}/{META_TOTAL}</span>
            </div>
            <div className="separador" />
            {profs.map((p) => (
              <div className="meta" key={p.id} title={`${p.aprovados} aprovados, ${p.em_analise} em análise`}>
                <span className="nome" style={{ opacity: p.ativa ? 1 : 0.5 }}>{p.nome}{p.ativa ? '' : ' (desligada)'}</span>
                <span className="trilho">
                  {p.aprovados ? <i className="a" style={{ width: `${Math.min(100, (p.aprovados / META_POR_PROFISSAO) * 100)}%` }} /> : null}
                  {p.em_analise ? <i className="b" style={{ width: `${Math.min(100 - Math.min(100, (p.aprovados / META_POR_PROFISSAO) * 100), (p.em_analise / META_POR_PROFISSAO) * 100)}%` }} /> : null}
                </span>
                <span className="valor" style={{ color: p.aprovados >= META_POR_PROFISSAO ? 'var(--verde-texto)' : undefined }}>{p.aprovados}/{META_POR_PROFISSAO}</span>
              </div>
            ))}
            <div className="legenda" style={{ marginTop: 12 }}>
              <span><i style={{ background: 'var(--azul)' }} />Aprovados</span><span><i style={{ background: '#9cbcf0' }} />Em análise</span>
            </div>
            <div className="separador" style={{ margin: '14px 0' }} />
            <div className="linha-flex texto-suave">
              <Users size={16} /> {numero(resumo.clientes)} clientes cadastrados
              <span className="espaco" />
              <Star size={16} color="#ffb400" /> <Link href="/denuncias/?aba=avaliacoes">Avaliações suspeitas</Link>
            </div>
          </div>
        </section>
      </div>
    </>
  );
}
