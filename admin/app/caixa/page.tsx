'use client';

import Link from 'next/link';
import { Fragment, useEffect, useMemo, useState } from 'react';
import {
  ArrowDownRight, ArrowUpRight, BadgeCheck, CircleDollarSign, Crown, Download, Hourglass, Loader2, Lock, Minus, Percent, Receipt,
  Settings2, Target, TrendingUp, Undo2, UserRound, Wallet,
} from 'lucide-react';
import { Cabecalho } from '@/components/Painel';
import { Ajuda } from '@/components/Ajuda';
import { Carregando, Dialogo, ErroCaixa, Vazio, useAcao, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { dataHora, diasAtrasISO, hojeISO, moeda, numero } from '@/lib/formatos';
import { baixarPlanilha, dataHoraPlanilha, type Celula } from '@/lib/planilha';

type Totais = { taxas: number; assinaturas: number; bruto: number; tarifas: number; liquido: number; pedidos_pagos?: number; mensalidades?: number; tarifa_estimada?: boolean | null };
type Mes = {
  mes: string; taxas: number; assinaturas: number; tarifas: number; liquido: number; pedidos_pagos: number; valor_servicos: number;
  pedidos_feitos: number; servicos_concluidos: number; assinantes: number; visitas_site: number; clientes_novos: number;
  clientes_primeiro_pedido: number; profissionais_novos: number; profissionais_aprovados: number; assinantes_novos: number; assinaturas_canceladas: number;
};
type Lancamento = { quando: string; tipo: 'taxa' | 'assinatura'; descricao: string; pessoa: string; bruto: number; tarifa: number; estimada: boolean; liquido: number };
type Caixa = {
  inicio: string; fim: string; pagamento_ativo: boolean; assinaturas_ativas: boolean;
  tarifa_fixa: number; tarifa_percentual: number; meta_mensal: number;
  atual: Totais; anterior: Totais; a_receber: number; estornado: number; mes_atual_liquido: number;
  por_mes: Mes[];
  cadastros: {
    profissionais_aprovados: number; profissionais_vip: number; profissionais_premium: number; profissionais_atrasados: number;
    profissionais_gratis: number; profissionais_em_analise: number; profissionais_preenchendo: number; profissionais_suspensos: number;
  };
  clientes: { ativos: number; ja_pagaram: number; pagaram_no_periodo: number; pediram_sem_pagar: number };
  lancamentos: Lancamento[];
};

type Periodo = 'mes' | 'mes_passado' | '30' | '90' | 'ano' | 'outro';
function intervalo(p: Periodo, ini: string, fim: string): [string, string] {
  const hoje = hojeISO();
  if (p === '30') return [diasAtrasISO(29), hoje];
  if (p === '90') return [diasAtrasISO(89), hoje];
  if (p === 'ano') return [hoje.slice(0, 4) + '-01-01', hoje];
  if (p === 'mes_passado') {
    const d = new Date(hoje.slice(0, 8) + '01T12:00:00');
    d.setDate(0);
    const f = d.toISOString().slice(0, 10);
    return [f.slice(0, 8) + '01', f];
  }
  if (p === 'outro') return [ini || hoje.slice(0, 8) + '01', fim || hoje];
  return [hoje.slice(0, 8) + '01', hoje];
}

const n = (v: unknown) => Number(v ?? 0);
const mesNome = (iso: string, longo = false) => new Date(iso.slice(0, 10) + 'T12:00:00')
  .toLocaleDateString('pt-BR', longo ? { month: 'long', year: 'numeric' } : { month: 'short', year: '2-digit' }).replace('.', '');
const pctTxt = (a: number, b: number) => (b ? `${Math.round((a / b) * 100)}%` : '—');

function Variacao({ atual, anterior }: { atual: number; anterior: number }) {
  if (!anterior) return atual ? <span className="variacao igual">novo</span> : null;
  const v = Math.round(((atual - anterior) / anterior) * 100);
  if (v === 0) return <span className="variacao igual"><Minus /> igual</span>;
  return <span className={`variacao ${v > 0 ? 'sobe' : 'desce'}`}>{v > 0 ? <ArrowUpRight /> : <ArrowDownRight />}{Math.abs(v)}%</span>;
}

function Cartao({ rotulo, valor, icone, cor, fundo, ajuda, detalhe }: {
  rotulo: string; valor: React.ReactNode; icone: React.ReactNode; cor: string; fundo: string; ajuda: React.ReactNode; detalhe?: React.ReactNode;
}) {
  return (
    <div className="cartao numero">
      <span className="rotulo"><span className="icone" style={{ color: cor, background: fundo }}>{icone}</span>{rotulo}<Ajuda titulo={rotulo}>{ajuda}</Ajuda></span>
      <span className="valor">{valor}</span>
      {detalhe ? <span className="detalhe linha-flex" style={{ gap: 6, flexWrap: 'wrap' }}>{detalhe}</span> : null}
    </div>
  );
}

/** Projeção simples do próximo mês: média dos 3 últimos meses fechados mais a tendência entre eles. */
function projecao(meses: Mes[]): number | null {
  const fechados = meses.slice(0, -1).slice(-3).map((m) => n(m.liquido));
  if (fechados.length < 3 || fechados.every((v) => v === 0)) return null;
  const media = fechados.reduce((a, b) => a + b, 0) / 3;
  const tendencia = (fechados[2] - fechados[0]) / 2;
  return Math.max(0, media + tendencia * 2);
}

/** Linhas da tabela de indicadores mês a mês. */
const indicadores: { grupo: string; rotulo: string; valor: (m: Mes) => number | null; dinheiro?: boolean; ajuda?: string }[] = [
  { grupo: 'Resultado', rotulo: 'Receita líquida', valor: (m) => n(m.liquido), dinheiro: true, ajuda: 'Taxas e assinaturas menos as tarifas do Asaas.' },
  { grupo: 'Resultado', rotulo: 'Taxas de serviço', valor: (m) => n(m.taxas), dinheiro: true },
  { grupo: 'Resultado', rotulo: 'Assinaturas', valor: (m) => n(m.assinaturas), dinheiro: true },
  { grupo: 'Resultado', rotulo: 'Tarifas do Asaas', valor: (m) => n(m.tarifas), dinheiro: true },
  { grupo: 'Resultado', rotulo: 'Valor dos serviços pagos', valor: (m) => n(m.valor_servicos), dinheiro: true, ajuda: 'Tudo o que os clientes pagaram pelos serviços concluídos (o que passa pela plataforma).' },
  { grupo: 'Resultado', rotulo: 'Pedidos pagos', valor: (m) => n(m.pedidos_pagos) },
  { grupo: 'Resultado', rotulo: 'Taxa média por pedido', valor: (m) => (n(m.pedidos_pagos) ? n(m.taxas) / n(m.pedidos_pagos) : null), dinheiro: true },
  { grupo: 'Resultado', rotulo: 'Pedidos feitos', valor: (m) => n(m.pedidos_feitos) },
  { grupo: 'Resultado', rotulo: 'Serviços concluídos', valor: (m) => n(m.servicos_concluidos) },
  { grupo: 'Resultado', rotulo: 'Assinantes no fim do mês', valor: (m) => n(m.assinantes) },
  { grupo: 'Prospecção', rotulo: 'Visitas ao site', valor: (m) => n(m.visitas_site) },
  { grupo: 'Prospecção', rotulo: 'Clientes novos', valor: (m) => n(m.clientes_novos) },
  { grupo: 'Prospecção', rotulo: 'Clientes no primeiro pedido', valor: (m) => n(m.clientes_primeiro_pedido), ajuda: 'Clientes que fizeram o primeiro pedido da vida no mês.' },
  { grupo: 'Prospecção', rotulo: 'Profissionais cadastrados', valor: (m) => n(m.profissionais_novos) },
  { grupo: 'Prospecção', rotulo: 'Profissionais aprovados', valor: (m) => n(m.profissionais_aprovados) },
  { grupo: 'Prospecção', rotulo: 'Assinantes novos', valor: (m) => n(m.assinantes_novos) },
  { grupo: 'Prospecção', rotulo: 'Assinaturas canceladas', valor: (m) => n(m.assinaturas_canceladas) },
];
const fmt = (v: number | null, dinheiro?: boolean) => (v == null ? '—' : dinheiro ? moeda(v) : numero(v));

function Ajustes({ aberto, fechar, d, salvo }: { aberto: boolean; fechar: () => void; d: Caixa; salvo: () => void }) {
  const { executar, ocupado } = useAcao();
  const [meta, setMeta] = useState('');
  const [fixa, setFixa] = useState('');
  const [pct, setPct] = useState('');
  useEffect(() => {
    if (!aberto) return;
    setMeta(String(n(d.meta_mensal)).replace('.', ','));
    setFixa(String(n(d.tarifa_fixa)).replace('.', ','));
    setPct(String(n(d.tarifa_percentual)).replace('.', ','));
  }, [aberto, d]);
  const num = (t: string) => Number(t.replace(/\./g, '').replace(',', '.'));
  const valido = [meta, fixa, pct].every((t) => t.trim() !== '' && Number.isFinite(num(t)) && num(t) >= 0);
  const salvar = async () => {
    const ok = await executar(() => rpc('admin_caixa_ajustes', { p_meta: num(meta), p_tarifa_fixa: num(fixa), p_tarifa_percentual: num(pct) }), 'Ajustes do Caixa salvos.');
    if (ok) salvo();
  };
  return (
    <Dialogo aberto={aberto} fechar={fechar} titulo="Meta e tarifas" icone={<Settings2 />}
      texto="A meta aparece na barra do mês. As tarifas valem como estimativa enquanto o Asaas não informar a tarifa real de cada cobrança."
      rodape={<>
        <button className="botao contorno" onClick={fechar}>Cancelar</button>
        <button className="botao primario" disabled={ocupado || !valido} onClick={salvar}>{ocupado ? <Loader2 className="girar" /> : null} Salvar</button>
      </>}>
      <div className="campo"><label htmlFor="cx-meta">Meta de receita líquida por mês (R$)</label>
        <input id="cx-meta" className="entrada" inputMode="decimal" value={meta} onChange={(e) => setMeta(e.target.value)} placeholder="Ex.: 5000" /></div>
      <div className="campo"><label htmlFor="cx-fixa">Tarifa do Asaas por cobrança (R$)</label>
        <input id="cx-fixa" className="entrada" inputMode="decimal" value={fixa} onChange={(e) => setFixa(e.target.value)} placeholder="Ex.: 1,99" /></div>
      <div className="campo"><label htmlFor="cx-pct">Parte em % do valor cobrado (cartão)</label>
        <input id="cx-pct" className="entrada" inputMode="decimal" value={pct} onChange={(e) => setPct(e.target.value)} placeholder="0 para só Pix" /></div>
    </Dialogo>
  );
}

export default function CaixaPagina() {
  const [periodo, setPeriodo] = useState<Periodo>('mes');
  const [ini, setIni] = useState(hojeISO().slice(0, 8) + '01');
  const [fim, setFim] = useState(hojeISO());
  const [inicio, termino] = useMemo(() => intervalo(periodo, ini, fim), [periodo, ini, fim]);
  const { dados: d, erro, carregando, recarregar } = useCarregar(() => rpc<Caixa>('admin_caixa', { p_inicio: inicio, p_fim: termino }), [inicio, termino]);
  const { executar, ocupado } = useAcao();
  const [ajustes, setAjustes] = useState(false);

  const meses = d?.por_mes ?? [];
  const maxMes = Math.max(1, ...meses.map((m) => n(m.taxas) + n(m.assinaturas)));
  const proj = projecao(meses);
  const meta = n(d?.meta_mensal);
  const nomeArq = `caixa-iservice-${inicio}-a-${termino}`;

  const baixarLancamentos = () => executar(async () => {
    const linhas = await rpc<Lancamento[]>('admin_caixa_planilha', { p_inicio: inicio, p_fim: termino });
    const L: Celula[][] = [['Data', 'Tipo', 'Descrição', 'Quem', 'Bruto (R$)', 'Tarifa Asaas (R$)', 'Tarifa estimada', 'Líquido (R$)']];
    for (const l of linhas) L.push([dataHoraPlanilha(l.quando), l.tipo === 'taxa' ? 'Taxa de serviço' : 'Assinatura', l.descricao, l.pessoa, n(l.bruto), n(l.tarifa), l.estimada, n(l.liquido)]);
    L.push([]);
    L.push(['Total', '', '', '', linhas.reduce((a, l) => a + n(l.bruto), 0), linhas.reduce((a, l) => a + n(l.tarifa), 0), '', linhas.reduce((a, l) => a + n(l.liquido), 0)]);
    baixarPlanilha(`lancamentos-${nomeArq}`, L);
  });
  const baixarIndicadores = () => {
    const L: Celula[][] = [['Indicador', ...meses.map((m) => mesNome(m.mes))]];
    for (const i of indicadores) L.push([`${i.grupo}: ${i.rotulo}`, ...meses.map((m) => { const v = i.valor(m); return v == null ? '' : Math.round(v * 100) / 100; })]);
    baixarPlanilha(`indicadores-mensais-iservice-${termino.slice(0, 7)}`, L);
  };

  return (
    <>
      <Cabecalho titulo="Caixa" texto="O dinheiro que fica com o iService: taxas de serviço e assinaturas, menos as tarifas do Asaas."
        ajuda={<>Uma taxa entra no Caixa quando o serviço é concluído e o valor é liberado ao profissional (antes disso ela aparece em <strong>A receber</strong>). Uma assinatura entra quando a mensalidade é paga. O líquido desconta a tarifa do Asaas: a real, quando o Asaas informa, ou a estimativa que você ajusta em <strong>Meta e tarifas</strong>.</>}
        acoes={<>
          <button className="botao contorno" onClick={() => setAjustes(true)} disabled={!d}><Settings2 /> Meta e tarifas</button>
          <button className="botao contorno" disabled={!d || ocupado} onClick={baixarLancamentos}><Download /> Lançamentos (Excel)</button>
          <button className="botao contorno" disabled={!d} onClick={baixarIndicadores}><Download /> Indicadores (Excel)</button>
        </>} />

      <div className="filtros periodo">
        <select className="entrada" value={periodo} onChange={(e) => setPeriodo(e.target.value as Periodo)} aria-label="Período">
          <option value="mes">Este mês</option>
          <option value="mes_passado">Mês passado</option>
          <option value="30">Últimos 30 dias</option>
          <option value="90">Últimos 90 dias</option>
          <option value="ano">Este ano</option>
          <option value="outro">Escolher datas</option>
        </select>
        {periodo === 'outro' ? <>
          <input className="entrada" type="date" value={ini} max={fim} onChange={(e) => setIni(e.target.value)} aria-label="De" />
          <span className="texto-suave">até</span>
          <input className="entrada" type="date" value={fim} min={ini} max={hojeISO()} onChange={(e) => setFim(e.target.value)} aria-label="Até" />
        </> : null}
      </div>

      {erro ? <ErroCaixa erro={erro} tentar={recarregar} /> : !d ? <Carregando /> : (
        <div style={{ opacity: carregando ? 0.6 : 1, transition: 'opacity .15s' }}>
          {!d.pagamento_ativo || !d.assinaturas_ativas ? (
            <div className="alerta-faixa laranja">
              <Lock size={20} />
              <div>
                {!d.pagamento_ativo ? <><strong>O pagamento pelo app ainda está desligado.</strong> As taxas de serviço começam a entrar aqui quando ele ligar (com o CNPJ e a conta jurídica no Asaas). </> : null}
                {!d.assinaturas_ativas ? <>{d.pagamento_ativo ? <strong>As assinaturas VIP e Premium ainda não são cobradas.</strong> : 'As assinaturas VIP e Premium ainda não são cobradas.'} Elas aparecem aqui sozinhas quando a cobrança for ligada.</> : null}
              </div>
            </div>
          ) : null}

          <div className="grade g4" style={{ marginBottom: 18 }}>
            <Cartao rotulo="Receita bruta" valor={moeda(d.atual.bruto)} icone={<CircleDollarSign />} cor="#0046b8" fundo="#e8f0fc"
              detalhe={<><Variacao atual={n(d.atual.bruto)} anterior={n(d.anterior.bruto)} /> contra o período anterior</>}
              ajuda="Taxas de serviço mais assinaturas recebidas no período, antes das tarifas." />
            <Cartao rotulo="Taxas de serviço" valor={moeda(d.atual.taxas)} icone={<Percent />} cor="#5b3cc4" fundo="#efeafd"
              detalhe={`${numero(n(d.atual.pedidos_pagos))} pedidos pagos${n(d.atual.pedidos_pagos) ? ` · média ${moeda(n(d.atual.taxas) / n(d.atual.pedidos_pagos))}` : ''}`}
              ajuda="Os 10% pagos pelo cliente em cada pedido, contados quando o serviço termina e o valor é liberado." />
            <Cartao rotulo="Assinaturas" valor={moeda(d.atual.assinaturas)} icone={<Crown />} cor="#b25f00" fundo="#fff4e5"
              detalhe={`${numero(n(d.atual.mensalidades))} mensalidades pagas`}
              ajuda="Mensalidades VIP e Premium pagas pelos profissionais no período." />
            <Cartao rotulo="Receita líquida" valor={moeda(d.atual.liquido)} icone={<Wallet />} cor="#00873a" fundo="#e6f6ec"
              detalhe={<><Variacao atual={n(d.atual.liquido)} anterior={n(d.anterior.liquido)} /> tarifas: {moeda(d.atual.tarifas)}{d.atual.tarifa_estimada ? ' (estimadas)' : ''}</>}
              ajuda="O que sobra para o iService depois das tarifas do Asaas." />
          </div>

          <div className="grade g4" style={{ marginBottom: 18 }}>
            <Cartao rotulo="A receber" valor={moeda(d.a_receber)} icone={<Hourglass />} cor="#0046b8" fundo="#e8f0fc"
              detalhe="Taxas de pedidos pagos que esperam o fim do serviço"
              ajuda="Taxas de pedidos que o cliente já pagou, mas o serviço ainda não terminou. Entram no Caixa quando o valor é liberado. Se o pedido for cancelado, o dinheiro volta ao cliente." />
            <Cartao rotulo="Estornado" valor={moeda(d.estornado)} icone={<Undo2 />} cor="#c62828" fundo="#fdecec"
              detalhe="Devolvido aos clientes no período"
              ajuda="Valores devolvidos a clientes (cancelamento ou Garantia). Não contam como receita." />
            <Cartao rotulo="Meta do mês" valor={meta ? pctTxt(n(d.mes_atual_liquido), meta) : 'Sem meta'} icone={<Target />} cor="#5b3cc4" fundo="#efeafd"
              detalhe={meta ? <span style={{ width: '100%' }}>
                <span className="barra-meta"><i style={{ width: `${Math.min(100, (n(d.mes_atual_liquido) / meta) * 100)}%` }} /></span>
                {moeda(d.mes_atual_liquido)} de {moeda(meta)} em {mesNome(hojeISO(), true)}
              </span> : <button className="link" onClick={() => setAjustes(true)}>Definir a meta mensal</button>}
              ajuda="Receita líquida deste mês contra a meta que você definiu em Meta e tarifas." />
            <Cartao rotulo="Projeção do próximo mês" valor={proj == null ? '—' : moeda(proj)} icone={<TrendingUp />} cor="#00873a" fundo="#e6f6ec"
              detalhe={proj == null ? 'Aparece com 3 meses de receita' : 'Média dos 3 últimos meses com a tendência'}
              ajuda="Estimativa simples: a média da receita líquida dos 3 últimos meses fechados, somada à tendência de crescimento entre eles. Serve de referência, não de promessa." />
          </div>

          <section className="cartao" style={{ marginBottom: 18 }}>
            <div className="titulo">
              <div><h2>Receita mês a mês</h2><p>Os 12 meses até {mesNome(termino, true)}. O número em cima é o líquido.</p></div>
              <div className="legenda"><span><i style={{ background: 'var(--roxo, #5b3cc4)' }} />Taxas</span><span><i style={{ background: 'var(--laranja, #ff8a00)' }} />Assinaturas</span></div>
            </div>
            <div className="corpo">
              <div className="barras" role="img" aria-label="Receita mês a mês">
                {meses.map((m) => {
                  const t = n(m.taxas); const a = n(m.assinaturas);
                  return (
                    <div className="coluna" key={m.mes}>
                      <span className="dica">{mesNome(m.mes, true)}: taxas {moeda(t)} · assinaturas {moeda(a)} · líquido {moeda(m.liquido)}</span>
                      <span className="val">{n(m.liquido) ? moeda(m.liquido).replace(',00', '') : ''}</span>
                      <div className="empilhada">
                        <div className="barra" style={{ height: `${(a / maxMes) * 100}%`, background: 'var(--laranja, #ff8a00)' }} />
                        <div className="barra" style={{ height: `${(t / maxMes) * 100}%`, background: 'var(--roxo, #5b3cc4)' }} />
                      </div>
                      <span className="rot">{mesNome(m.mes)}</span>
                    </div>
                  );
                })}
              </div>
            </div>
          </section>

          <section className="cartao" style={{ marginBottom: 18 }}>
            <div className="titulo">
              <div><h2 className="com-ajuda">Indicadores de resultado e prospecção
                <Ajuda titulo="Indicadores mensais">Resultado é o dinheiro e os serviços do mês. Prospecção é quem chegou: visitas, cadastros, aprovações e assinantes novos. Use para ver o que cresce e onde a equipe comercial deve agir.</Ajuda></h2>
                <p>Mês a mês, os 12 meses até o fim do período.</p></div>
              <button className="botao contorno pequeno" onClick={baixarIndicadores}><Download /> Excel</button>
            </div>
            <div className="corpo sem-espaco"><div className="tabela-rolagem">
              <table className="tabela indicadores-mes">
                <thead><tr><th>Indicador</th>{meses.map((m) => <th key={m.mes} style={{ textAlign: 'right' }}>{mesNome(m.mes)}</th>)}</tr></thead>
                <tbody>
                  {indicadores.map((i, k) => (
                    <Fragment key={i.rotulo}>
                      {k === 0 || indicadores[k - 1].grupo !== i.grupo ? <tr className="grupo-linha"><td colSpan={meses.length + 1}>{i.grupo}</td></tr> : null}
                      <tr>
                        <td className="forte" title={i.ajuda}>{i.rotulo}</td>
                        {meses.map((m) => <td key={m.mes} style={{ textAlign: 'right', whiteSpace: 'nowrap' }}>{fmt(i.valor(m), i.dinheiro)}</td>)}
                      </tr>
                    </Fragment>
                  ))}
                </tbody>
              </table>
            </div></div>
          </section>

          <div className="grade g2" style={{ marginBottom: 18 }}>
            <section className="cartao">
              <div className="titulo">
                <div><h2>Profissionais ativos</h2><p>Aprovados, pagantes e não pagantes.</p></div>
                <Link className="botao contorno pequeno" href="/comercial/"><Target /> Abordar quem não assina</Link>
              </div>
              <div className="corpo">
                <ul className="lista-numeros">
                  <li><span>Aprovados e ativos</span><strong>{numero(d.cadastros.profissionais_aprovados)}</strong></li>
                  <li className="sub"><span><Crown size={14} /> Pagantes VIP</span><strong>{numero(d.cadastros.profissionais_vip)}</strong></li>
                  <li className="sub"><span><Crown size={14} /> Pagantes Premium</span><strong>{numero(d.cadastros.profissionais_premium)}</strong></li>
                  <li className="sub"><span>Não pagantes (sem assinatura)</span><strong>{numero(d.cadastros.profissionais_gratis)}</strong></li>
                  {d.cadastros.profissionais_atrasados ? <li className="sub alerta"><span>Mensalidade atrasada</span><strong>{numero(d.cadastros.profissionais_atrasados)}</strong></li> : null}
                  <li><span>Conversão em assinantes</span><strong>{pctTxt(d.cadastros.profissionais_vip + d.cadastros.profissionais_premium, d.cadastros.profissionais_aprovados)}</strong></li>
                  <li><span>Em análise</span><strong>{numero(d.cadastros.profissionais_em_analise)}</strong></li>
                  <li><span>Ainda preenchendo o cadastro</span><strong>{numero(d.cadastros.profissionais_preenchendo)}</strong></li>
                  <li><span>Suspensos</span><strong>{numero(d.cadastros.profissionais_suspensos)}</strong></li>
                </ul>
              </div>
            </section>
            <section className="cartao">
              <div className="titulo"><div><h2>Clientes ativos</h2><p>Quem já pagou serviço pelo app e quem não.</p></div></div>
              <div className="corpo">
                <ul className="lista-numeros">
                  <li><span>Clientes ativos</span><strong>{numero(d.clientes.ativos)}</strong></li>
                  <li className="sub"><span>Já pagaram algum serviço</span><strong>{numero(d.clientes.ja_pagaram)}</strong></li>
                  <li className="sub"><span>Pagaram no período</span><strong>{numero(d.clientes.pagaram_no_periodo)}</strong></li>
                  <li className="sub"><span>Pediram mas nunca pagaram</span><strong>{numero(d.clientes.pediram_sem_pagar)}</strong></li>
                  <li className="sub"><span>Nunca pediram</span><strong>{numero(Math.max(0, d.clientes.ativos - d.clientes.ja_pagaram - d.clientes.pediram_sem_pagar))}</strong></li>
                  <li><span>Clientes pagantes</span><strong>{pctTxt(d.clientes.ja_pagaram, d.clientes.ativos)}</strong></li>
                </ul>
              </div>
            </section>
          </div>

          <section className="cartao">
            <div className="titulo"><div><h2>Lançamentos</h2><p>Cada taxa e mensalidade que entrou no período{d.lancamentos.length >= 500 ? ' (os 500 mais recentes; a planilha traz todos)' : ''}.</p></div></div>
            <div className="corpo sem-espaco">
              {!d.lancamentos.length ? <Vazio icone={<Receipt size={24} />} titulo="Nada entrou no período" texto={d.pagamento_ativo ? undefined : 'Os lançamentos aparecem quando o pagamento pelo app ligar.'} /> : (
                <div className="tabela-rolagem">
                  <table className="tabela">
                    <thead><tr><th>Quando</th><th>O quê</th><th>Quem</th><th style={{ textAlign: 'right' }}>Bruto</th><th style={{ textAlign: 'right' }}>Tarifa</th><th style={{ textAlign: 'right' }}>Líquido</th></tr></thead>
                    <tbody>
                      {d.lancamentos.map((l, i) => (
                        <tr key={i}>
                          <td className="fraco" style={{ whiteSpace: 'nowrap' }}>{dataHora(l.quando)}</td>
                          <td><span className="linha-flex" style={{ gap: 6 }}>{l.tipo === 'taxa' ? <Percent size={14} /> : <Crown size={14} />}{l.descricao}</span></td>
                          <td><span className="linha-flex" style={{ gap: 6 }}><UserRound size={14} />{l.pessoa}</span></td>
                          <td style={{ textAlign: 'right' }}>{moeda(l.bruto)}</td>
                          <td style={{ textAlign: 'right' }} className="fraco" title={l.estimada ? 'Tarifa estimada' : 'Tarifa informada pelo Asaas'}>{moeda(l.tarifa)}{l.estimada ? '*' : ''}</td>
                          <td style={{ textAlign: 'right' }} className="forte">{moeda(l.liquido)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          </section>
          <p className="texto-fraco" style={{ marginTop: 10 }}><BadgeCheck size={14} style={{ verticalAlign: -2 }} /> * Tarifa estimada: {moeda(d.tarifa_fixa)} por cobrança{n(d.tarifa_percentual) ? ` + ${String(d.tarifa_percentual).replace('.', ',')}%` : ''}. Muda em Meta e tarifas.</p>

          <Ajustes aberto={ajustes} fechar={() => setAjustes(false)} d={d} salvo={() => { setAjustes(false); recarregar(); }} />
        </div>
      )}
    </>
  );
}
