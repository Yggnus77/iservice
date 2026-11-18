'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import {
  ArrowDownRight, ArrowUpRight, BadgeCheck, CircleDollarSign, ClipboardList, Download, Minus, Search, SearchX, Star, Timer, UserPlus, Users, XCircle,
} from 'lucide-react';
import { Cabecalho, usePainel } from '@/components/Painel';
import { Ajuda } from '@/components/Ajuda';
import { Carregando, ErroCaixa, Pessoa, useAcao, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { data, diasAtrasISO, diaCurto, hojeISO, moeda, numero, statusPedido, quandoPedido } from '@/lib/formatos';
import { baixarPlanilha, dataHoraPlanilha, dataPlanilha, type Celula } from '@/lib/planilha';

type Totais = {
  pedidos: number; concluidos: number; em_andamento: number; aceitos: number; recusados: number; sem_resposta: number;
  cancelados_cliente: number; cancelados_profissional: number; cancelados_equipe: number; taxa_aceite: number | null;
  tempo_resposta_min: number | null; valor_concluido: number; ticket_medio: number | null; clientes_que_pediram: number;
  profissionais_que_atenderam: number; urgentes: number; agendados: number; avaliacoes: number; nota_media: number | null;
  clientes_novos: number; profissionais_novos: number; profissionais_aprovados: number; buscas: number; buscas_sem_resultado: number;
  reclamacoes: number; denuncias: number; emergencias: number;
};
type Relatorio = {
  inicio: string; fim: string; dias: number; atual: Totais; anterior: Totais;
  por_dia: { dia: string; pedidos: number; concluidos: number; cancelados: number; buscas: number; clientes_novos: number; profissionais_novos: number }[];
  por_profissao: { id: string; nome: string; pedidos: number; concluidos: number; cancelados: number; valor: number; nota: number | null; buscas: number; buscas_sem_resultado: number; profissionais: number }[];
  por_regiao: { id: string; nome: string; pedidos: number; concluidos: number; valor: number; buscas: number; buscas_sem_resultado: number }[];
  top_profissionais: { id: string; nome: string; foto_url: string | null; concluidos: number; valor: number; nota: number | null; profissoes: string | null }[];
};
type LinhaPlanilha = {
  codigo: string; criado_em: string; status: string; quando: string; combinado_para: string | null; profissao: string; regiao: string | null;
  cliente: string | null; profissional: string | null; preco_informado: number | null; taxa_urgencia: number; taxa_fora_horario: number;
  valor_cobrado: number | null; forma_pagamento: string | null; aceito_em: string | null; concluido_em: string | null; encerrado_em: string | null;
  motivo: string | null; minutos_trabalhados: number | null; nota: number | null;
};

type Periodo = '7' | '30' | 'mes' | 'mes_passado' | '90' | 'outro';

function intervalo(p: Periodo, ini: string, fim: string): [string, string] {
  const hoje = hojeISO();
  if (p === '7') return [diasAtrasISO(6), hoje];
  if (p === '30') return [diasAtrasISO(29), hoje];
  if (p === '90') return [diasAtrasISO(89), hoje];
  if (p === 'mes') return [hoje.slice(0, 8) + '01', hoje];
  if (p === 'mes_passado') {
    const d = new Date(hoje.slice(0, 8) + '01T12:00:00');
    d.setDate(0);
    const f = d.toISOString().slice(0, 10);
    return [f.slice(0, 8) + '01', f];
  }
  return [ini || diasAtrasISO(29), fim || hoje];
}

function pct(a: number, b: number) { return b ? Math.round((a / b) * 1000) / 10 : null; }
const pctTexto = (a: number, b: number) => (pct(a, b) ?? 0).toLocaleString('pt-BR');

/** Seta com a variação contra o período anterior de mesmo tamanho. */
function Variacao({ atual, anterior, inverso, sufixo = '%' }: { atual: number | null; anterior: number | null; inverso?: boolean; sufixo?: string }) {
  if (atual == null || anterior == null) return null;
  if (!anterior) return atual ? <span className="variacao igual">novo</span> : null;
  const v = Math.round(((atual - anterior) / anterior) * 100);
  if (v === 0) return <span className="variacao igual"><Minus /> igual</span>;
  const bom = inverso ? v < 0 : v > 0;
  return <span className={`variacao ${bom ? 'sobe' : 'desce'}`}>{v > 0 ? <ArrowUpRight /> : <ArrowDownRight />}{Math.abs(v)}{sufixo}</span>;
}

function Indicador({ rotulo, valor, icone, cor, fundo, ajuda, atual, anterior, inverso, detalhe }: {
  rotulo: string; valor: React.ReactNode; icone: React.ReactNode; cor: string; fundo: string; ajuda: React.ReactNode;
  atual: number | null; anterior: number | null; inverso?: boolean; detalhe?: React.ReactNode;
}) {
  return (
    <div className="cartao numero">
      <span className="rotulo"><span className="icone" style={{ color: cor, background: fundo }}>{icone}</span>{rotulo}<Ajuda titulo={rotulo}>{ajuda}</Ajuda></span>
      <span className="valor">{valor}</span>
      <span className="detalhe linha-flex" style={{ gap: 6 }}><Variacao atual={atual} anterior={anterior} inverso={inverso} /> {detalhe ?? 'contra o período anterior'}</span>
    </div>
  );
}

export default function Relatorios() {
  const { pode } = usePainel();
  const [periodo, setPeriodo] = useState<Periodo>('30');
  const [ini, setIni] = useState(diasAtrasISO(29));
  const [fim, setFim] = useState(hojeISO());
  const [inicio, termino] = useMemo(() => intervalo(periodo, ini, fim), [periodo, ini, fim]);
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Relatorio>('admin_relatorio', { p_inicio: inicio, p_fim: termino }), [inicio, termino]);
  const { executar, ocupado } = useAcao();

  const a = dados?.atual;
  const b = dados?.anterior;
  const cancelados = a ? a.cancelados_cliente + a.cancelados_profissional + a.cancelados_equipe : 0;
  const canceladosAnt = b ? b.cancelados_cliente + b.cancelados_profissional + b.cancelados_equipe : 0;
  const maxDia = Math.max(1, ...(dados?.por_dia ?? []).map((d) => d.pedidos));
  const nomeArquivo = `iservice-${inicio}-a-${termino}`;

  const baixarRelatorio = () => {
    if (!dados || !a || !b) return;
    const L: Celula[][] = [
      ['Relatório iService'], ['Período', `${dataPlanilha(inicio)} a ${dataPlanilha(termino)}`], [],
      ['Indicador', 'Período', 'Período anterior'],
      ['Pedidos feitos', a.pedidos, b.pedidos], ['Serviços concluídos', a.concluidos, b.concluidos],
      ['Taxa de conclusão (%)', pct(a.concluidos, a.pedidos), pct(b.concluidos, b.pedidos)],
      ['Taxa de aceite (%)', a.taxa_aceite, b.taxa_aceite], ['Tempo de resposta (min, mediana)', a.tempo_resposta_min, b.tempo_resposta_min],
      ['Recusados', a.recusados, b.recusados], ['Sem resposta', a.sem_resposta, b.sem_resposta],
      ['Cancelados pelo cliente', a.cancelados_cliente, b.cancelados_cliente], ['Cancelados pelo profissional', a.cancelados_profissional, b.cancelados_profissional],
      ['Cancelados pela equipe', a.cancelados_equipe, b.cancelados_equipe],
      ['Valor dos serviços concluídos (R$)', Number(a.valor_concluido), Number(b.valor_concluido)], ['Valor médio por serviço (R$)', a.ticket_medio, b.ticket_medio],
      ['Pedidos urgentes', a.urgentes, b.urgentes], ['Pedidos agendados', a.agendados, b.agendados],
      ['Clientes que pediram', a.clientes_que_pediram, b.clientes_que_pediram], ['Profissionais que atenderam', a.profissionais_que_atenderam, b.profissionais_que_atenderam],
      ['Avaliações', a.avaliacoes, b.avaliacoes], ['Nota média', a.nota_media, b.nota_media],
      ['Clientes novos', a.clientes_novos, b.clientes_novos], ['Profissionais novos', a.profissionais_novos, b.profissionais_novos],
      ['Profissionais aprovados', a.profissionais_aprovados, b.profissionais_aprovados],
      ['Buscas', a.buscas, b.buscas], ['Buscas sem resultado', a.buscas_sem_resultado, b.buscas_sem_resultado],
      ['Reclamações da garantia', a.reclamacoes, b.reclamacoes], ['Denúncias', a.denuncias, b.denuncias], ['Emergências', a.emergencias, b.emergencias],
      [], ['Por dia'], ['Dia', 'Pedidos', 'Concluídos', 'Cancelados, recusados ou sem resposta', 'Buscas', 'Clientes novos', 'Profissionais novos'],
      ...dados.por_dia.map((d) => [dataPlanilha(d.dia), d.pedidos, d.concluidos, d.cancelados, d.buscas, d.clientes_novos, d.profissionais_novos]),
      [], ['Por profissão'], ['Profissão', 'Pedidos', 'Concluídos', 'Cancelados', 'Valor concluído (R$)', 'Nota', 'Buscas', 'Buscas sem resultado', 'Profissionais aprovados'],
      ...dados.por_profissao.map((p) => [p.nome, p.pedidos, p.concluidos, p.cancelados, Number(p.valor), p.nota, p.buscas, p.buscas_sem_resultado, p.profissionais]),
      [], ['Por região'], ['Região', 'Pedidos', 'Concluídos', 'Valor concluído (R$)', 'Buscas', 'Buscas sem resultado'],
      ...dados.por_regiao.map((r) => [r.nome, r.pedidos, r.concluidos, Number(r.valor), r.buscas, r.buscas_sem_resultado]),
      [], ['Profissionais que mais atenderam'], ['Profissional', 'Profissões', 'Serviços concluídos', 'Valor (R$)', 'Nota'],
      ...dados.top_profissionais.map((t) => [t.nome, t.profissoes, t.concluidos, Number(t.valor), t.nota]),
    ];
    baixarPlanilha(`relatorio-${nomeArquivo}`, L);
  };

  const baixarPedidos = () => executar(async () => {
    const linhas = await rpc<LinhaPlanilha[]>('admin_planilha_pedidos', { p_inicio: inicio, p_fim: termino });
    baixarPlanilha(`pedidos-${nomeArquivo}`, [
      ['Código', 'Feito em', 'Situação', 'Quando', 'Marcado para', 'Profissão', 'Região', 'Cliente', 'Profissional', 'Preço (R$)', 'Urgência (R$)',
        'Fora do horário (R$)', 'Valor cobrado (R$)', 'Pagamento', 'Aceito em', 'Concluído em', 'Encerrado em', 'Motivo', 'Minutos trabalhados', 'Nota'],
      ...linhas.map((p) => [p.codigo, dataHoraPlanilha(p.criado_em), statusPedido[p.status]?.rotulo ?? p.status, quandoPedido[p.quando] ?? p.quando,
        dataHoraPlanilha(p.combinado_para), p.profissao, p.regiao, p.cliente, p.profissional, p.preco_informado == null ? null : Number(p.preco_informado),
        Number(p.taxa_urgencia), Number(p.taxa_fora_horario), p.valor_cobrado == null ? null : Number(p.valor_cobrado), p.forma_pagamento,
        dataHoraPlanilha(p.aceito_em), dataHoraPlanilha(p.concluido_em), dataHoraPlanilha(p.encerrado_em), p.motivo, p.minutos_trabalhados, p.nota]),
    ]);
  }, 'Planilha de pedidos baixada.');

  return (
    <>
      <Cabecalho titulo="Relatórios"
        texto={dados ? `De ${data(dados.inicio)} a ${data(dados.fim)} (${dados.dias} ${dados.dias === 1 ? 'dia' : 'dias'}), comparado com os ${dados.dias} dias anteriores.` : 'Números do período, para acompanhar o crescimento.'}
        ajuda={<>
          Escolha o período e veja como a plataforma foi: pedidos, conclusões, cancelamentos, tempo de resposta, cadastros e buscas.
          A setinha compara com o período anterior do mesmo tamanho (verde é melhora, vermelho é piora).
          <strong> Baixar relatório</strong> gera uma planilha para abrir no Excel com tudo o que está na tela.
        </>}
        acoes={<>
          <button className="botao contorno" disabled={!dados} onClick={baixarRelatorio}><Download /> Baixar relatório (Excel)</button>
          {pode('pedidos') ? <button className="botao contorno" disabled={ocupado} onClick={baixarPedidos}><Download /> Baixar pedidos (Excel)</button> : null}
        </>} />

      <div className="filtros periodo">
        <select className="entrada" value={periodo} onChange={(e) => setPeriodo(e.target.value as Periodo)} aria-label="Período">
          <option value="7">Últimos 7 dias</option>
          <option value="30">Últimos 30 dias</option>
          <option value="90">Últimos 90 dias</option>
          <option value="mes">Este mês</option>
          <option value="mes_passado">Mês passado</option>
          <option value="outro">Escolher datas</option>
        </select>
        {periodo === 'outro' ? <>
          <input className="entrada" type="date" value={ini} max={fim} onChange={(e) => setIni(e.target.value)} aria-label="De" />
          <span className="texto-suave">até</span>
          <input className="entrada" type="date" value={fim} min={ini} max={hojeISO()} onChange={(e) => setFim(e.target.value)} aria-label="Até" />
        </> : null}
      </div>

      {erro ? <ErroCaixa erro={erro} tentar={recarregar} /> : !dados || !a || !b ? <Carregando /> : (
        <div style={{ opacity: carregando ? 0.6 : 1, transition: 'opacity .15s' }}>
          <div className="grade g4" style={{ marginBottom: 18 }}>
            <Indicador rotulo="Pedidos feitos" valor={numero(a.pedidos)} icone={<ClipboardList />} cor="#0046b8" fundo="#e8f0fc" atual={a.pedidos} anterior={b.pedidos}
              ajuda="Todos os pedidos que os clientes fizeram no período, em qualquer situação." />
            <Indicador rotulo="Serviços concluídos" valor={numero(a.concluidos)} icone={<BadgeCheck />} cor="#00873a" fundo="#e6f9ee" atual={a.concluidos} anterior={b.concluidos}
              detalhe={a.pedidos ? `${pctTexto(a.concluidos, a.pedidos)}% dos pedidos` : undefined}
              ajuda="Pedidos que terminaram com o serviço feito. É o número que mais importa: cliente atendido." />
            <Indicador rotulo="Valor dos serviços" valor={moeda(a.valor_concluido)} icone={<CircleDollarSign />} cor="#5b3cc4" fundo="#efeafd"
              atual={Number(a.valor_concluido)} anterior={Number(b.valor_concluido)} detalhe={a.ticket_medio ? `média de ${moeda(a.ticket_medio)} por serviço` : undefined}
              ajuda="Soma do valor dos serviços concluídos (preço do profissional mais urgência e fora do horário). O dinheiro vai direto para o profissional; serve para medir o tamanho do que passa pela plataforma." />
            <Indicador rotulo="Cancelados ou perdidos" valor={numero(cancelados + a.recusados + a.sem_resposta)} icone={<XCircle />} cor="#c62828" fundo="#fdecec"
              atual={cancelados + a.recusados + a.sem_resposta} anterior={canceladosAnt + b.recusados + b.sem_resposta} inverso
              detalhe={`${a.cancelados_profissional} pelo profissional · ${a.sem_resposta} sem resposta`}
              ajuda="Pedidos cancelados (pelo cliente, pelo profissional ou pela equipe), recusados ou que ninguém respondeu. Quanto menor, melhor." />
          </div>

          <div className="grade g4" style={{ marginBottom: 18 }}>
            <Indicador rotulo="Taxa de aceite" valor={a.taxa_aceite != null ? `${String(a.taxa_aceite).replace('.', ',')}%` : '—'} icone={<BadgeCheck />} cor="#00873a" fundo="#e6f9ee"
              atual={a.taxa_aceite} anterior={b.taxa_aceite}
              ajuda="De cada 100 pedidos que chegaram aos profissionais, quantos foram aceitos. Baixa = falta profissional disponível ou preço desalinhado." />
            <Indicador rotulo="Tempo de resposta" valor={a.tempo_resposta_min != null ? `${String(a.tempo_resposta_min).replace('.', ',')} min` : '—'} icone={<Timer />} cor="#b25f00" fundo="#fff4e5"
              atual={a.tempo_resposta_min} anterior={b.tempo_resposta_min} inverso
              ajuda="O tempo típico (mediana) que o profissional leva para responder um pedido, aceitando ou recusando. O prazo no app é de 5 minutos." />
            <Indicador rotulo="Novos cadastros" valor={numero(a.clientes_novos + a.profissionais_novos)} icone={<UserPlus />} cor="#5b3cc4" fundo="#efeafd"
              atual={a.clientes_novos + a.profissionais_novos} anterior={b.clientes_novos + b.profissionais_novos}
              detalhe={`${a.clientes_novos} clientes · ${a.profissionais_novos} profissionais · ${a.profissionais_aprovados} aprovados`}
              ajuda="Contas novas no período. Profissionais aprovados são os que passaram pela conferência e já podem atender." />
            <Indicador rotulo="Nota média" valor={a.nota_media != null ? Number(a.nota_media).toFixed(1).replace('.', ',') : '—'} icone={<Star />} cor="#b25f00" fundo="#fff4e5"
              atual={a.nota_media} anterior={b.nota_media} detalhe={`${a.avaliacoes} avaliações`}
              ajuda="Média das estrelas que os clientes deram no período (avaliações ocultas pela equipe não contam)." />
          </div>

          <div className="grade g4" style={{ marginBottom: 18 }}>
            <Indicador rotulo="Buscas" valor={numero(a.buscas)} icone={<Search />} cor="#0046b8" fundo="#e8f0fc" atual={a.buscas} anterior={b.buscas}
              detalhe={a.buscas ? `${pctTexto(a.pedidos, a.buscas)}% viraram pedido` : undefined}
              ajuda="Quantas vezes alguém procurou profissional no app. Comparar com os pedidos mostra quantas buscas viram pedido." />
            <Indicador rotulo="Buscas sem resultado" valor={numero(a.buscas_sem_resultado)} icone={<SearchX />} cor="#b25f00" fundo="#fff4e5"
              atual={a.buscas_sem_resultado} anterior={b.buscas_sem_resultado} inverso detalhe={a.buscas ? `${pctTexto(a.buscas_sem_resultado, a.buscas)}% das buscas` : undefined}
              ajuda="Procuraram e não acharam ninguém perto. Mostra onde e em que profissão recrutar (veja Buscas e mapa)." />
            <Indicador rotulo="Clientes atendidos" valor={numero(a.clientes_que_pediram)} icone={<Users />} cor="#00873a" fundo="#e6f9ee"
              atual={a.clientes_que_pediram} anterior={b.clientes_que_pediram} detalhe={`${a.profissionais_que_atenderam} profissionais concluíram serviços`}
              ajuda="Clientes diferentes que fizeram pelo menos um pedido no período." />
            <Indicador rotulo="Problemas" valor={numero(a.reclamacoes + a.denuncias + a.emergencias)} icone={<XCircle />} cor="#c62828" fundo="#fdecec"
              atual={a.reclamacoes + a.denuncias + a.emergencias} anterior={b.reclamacoes + b.denuncias + b.emergencias} inverso
              detalhe={`${a.reclamacoes} garantia · ${a.denuncias} denúncias · ${a.emergencias} emergências`}
              ajuda="Reclamações da Garantia iService, denúncias e botões de emergência acionados no período." />
          </div>

          <section className="cartao" style={{ marginBottom: 18 }}>
            <div className="titulo">
              <div><h2>Pedidos por dia</h2><p>Feitos e concluídos em cada dia do período.</p></div>
              <div className="legenda"><span><i style={{ background: 'var(--azul)' }} />Feitos</span><span><i style={{ background: 'var(--verde-texto)' }} />Concluídos</span></div>
            </div>
            <div className="corpo">
              <div className={`barras ${dados.por_dia.length > 14 ? 'longas' : ''}`} role="img" aria-label="Pedidos por dia">
                {dados.por_dia.map((d, i) => (
                  <div className="coluna" key={d.dia}>
                    <span className="dica">{diaCurto(d.dia)}: {d.pedidos} pedidos · {d.concluidos} concluídos · {d.buscas} buscas</span>
                    {dados.por_dia.length <= 31 ? <span className="val">{d.pedidos || ''}</span> : null}
                    <div className="dupla">
                      <div className="barra" style={{ height: `${(d.pedidos / maxDia) * 100}%` }} />
                      <div className="barra" style={{ height: `${(d.concluidos / maxDia) * 100}%`, background: 'var(--verde-texto)' }} />
                    </div>
                    <span className="rot">{dados.por_dia.length <= 14 || i % Math.ceil(dados.por_dia.length / 10) === 0 ? diaCurto(d.dia) : ''}</span>
                  </div>
                ))}
              </div>
            </div>
          </section>

          <div className="pilha" style={{ marginBottom: 18 }}>
            <section className="cartao">
              <div className="titulo"><div><h2 className="com-ajuda">Por profissão
                <Ajuda titulo="Por profissão">Pedidos, conclusões e buscas de cada profissão. Muita busca sem resultado com poucos profissionais = profissão para recrutar primeiro.</Ajuda>
              </h2></div></div>
              <div className="corpo sem-espaco"><div className="tabela-rolagem">
                <table className="tabela">
                  <thead><tr><th>Profissão</th><th>Pedidos</th><th>Concluídos</th><th>Valor</th><th>Nota</th><th>Sem resultado</th><th>Profissionais</th></tr></thead>
                  <tbody>
                    {dados.por_profissao.map((p) => (
                      <tr key={p.id}>
                        <td className="forte">{p.nome}</td><td>{numero(p.pedidos)}</td><td>{numero(p.concluidos)}</td><td>{moeda(p.valor)}</td>
                        <td>{p.nota != null ? Number(p.nota).toFixed(1) : '—'}</td>
                        <td style={{ color: p.buscas_sem_resultado ? 'var(--laranja-texto)' : undefined }}>{numero(p.buscas_sem_resultado)}{p.buscas ? ` de ${numero(p.buscas)}` : ''}</td>
                        <td>{numero(p.profissionais)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div></div>
            </section>

            <section className="cartao">
              <div className="titulo"><div><h2 className="com-ajuda">Por região
                <Ajuda titulo="Por região">Onde os pedidos e as buscas acontecem. Use para decidir onde divulgar e onde recrutar profissionais.</Ajuda>
              </h2></div></div>
              <div className="corpo sem-espaco"><div className="tabela-rolagem">
                <table className="tabela">
                  <thead><tr><th>Região</th><th>Pedidos</th><th>Concluídos</th><th>Valor</th><th>Buscas</th><th>Sem resultado</th></tr></thead>
                  <tbody>
                    {dados.por_regiao.map((r) => (
                      <tr key={r.id}>
                        <td className="forte">{r.nome}</td><td>{numero(r.pedidos)}</td><td>{numero(r.concluidos)}</td><td>{moeda(r.valor)}</td>
                        <td>{numero(r.buscas)}</td><td style={{ color: r.buscas_sem_resultado ? 'var(--laranja-texto)' : undefined }}>{numero(r.buscas_sem_resultado)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div></div>
            </section>
          </div>

          <section className="cartao">
            <div className="titulo"><div><h2 className="com-ajuda">Profissionais que mais atenderam
              <Ajuda titulo="Quem mais atendeu">Os 15 profissionais com mais serviços concluídos no período. Bom para reconhecer, divulgar e pedir indicações.</Ajuda>
            </h2></div></div>
            <div className="corpo sem-espaco">
              {dados.top_profissionais.length === 0 ? <div className="vazio">Nenhum serviço concluído no período.</div> : (
                <div className="tabela-rolagem">
                  <table className="tabela">
                    <thead><tr><th>#</th><th>Profissional</th><th>Concluídos</th><th>Valor</th><th>Nota</th></tr></thead>
                    <tbody>
                      {dados.top_profissionais.map((t, i) => (
                        <tr key={t.id}>
                          <td className="fraco">{i + 1}</td>
                          <td>{pode('pessoas') ? <Link href={`/pessoa/?id=${t.id}`} style={{ color: 'inherit' }}><Pessoa nome={t.nome} foto={t.foto_url} sub={t.profissoes} /></Link>
                            : <Pessoa nome={t.nome} foto={t.foto_url} sub={t.profissoes} />}</td>
                          <td className="forte">{numero(t.concluidos)}</td><td>{moeda(t.valor)}</td><td>{t.nota != null ? Number(t.nota).toFixed(1) : '—'}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          </section>
        </div>
      )}
    </>
  );
}
