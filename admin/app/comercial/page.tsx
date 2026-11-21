'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import {
  Calculator, Crown, Download, Flame, Mail, MapPin, MessageCircle, Phone, Search, Snowflake, Sparkles, Target, ThermometerSun,
  TrendingUp, UserRoundX, Users,
} from 'lucide-react';
import { Cabecalho, usePainel } from '@/components/Painel';
import { Ajuda } from '@/components/Ajuda';
import { Abas, Carregando, ErroCaixa, Pessoa, Selo, Vazio, useAcao, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { data, haQuanto, moeda, numero, telefone, whatsapp, type Tom } from '@/lib/formatos';
import { baixarPlanilha, dataHoraPlanilha, type Celula } from '@/lib/planilha';

type Prioridade = 'quente' | 'morno' | 'frio';
type Oportunidade = {
  id: string; nome: string; email: string | null; telefone: string | null; foto_url: string | null;
  profissoes: string | null; regiao: string | null; nota: number | null; avaliacoes: number; servicos: number; aceite: number | null;
  pedidos_30d: number; concluidos_30d: number; ganhos_30d: number; buscas_30d: number;
  disponivel: boolean; verificado: boolean; atende_24h: boolean; raio_km: number | null;
  aprovado_em: string | null; cadastro_em: string | null; ultimo_acesso: string | null; ex_assinante_ate: string | null;
  pontos: number; prioridade: Prioridade; plano_sugerido: 'vip' | 'premium'; argumento: string | null;
};
type Grupo = { id: string; nome: string; aprovados: number; assinantes: number; nao_assinantes: number; quentes: number; buscas_30d: number; sem_resultado_30d: number };
type Comercial = {
  resumo: {
    aprovados: number; assinantes: number; vip: number; premium: number; atrasados: number; nao_assinantes: number; ex_assinantes: number;
    quentes: number; mornos: number; frios: number; sem_acesso_30d: number;
  };
  funil: { preenchendo: number; em_analise: number; aprovados: number; clientes: number };
  por_profissao: Grupo[]; por_regiao: Grupo[]; oportunidades: Oportunidade[];
};

const prioridades: Record<Prioridade, { rotulo: string; tom: Tom; icone: React.ReactNode }> = {
  quente: { rotulo: 'Quente', tom: 'vermelho', icone: <Flame /> },
  morno: { rotulo: 'Morno', tom: 'laranja', icone: <ThermometerSun /> },
  frio: { rotulo: 'Frio', tom: 'azul', icone: <Snowflake /> },
};
const n = (v: unknown) => Number(v ?? 0);
const pct = (a: number, b: number) => (b ? `${Math.round((a / b) * 100)}%` : '—');
const num = (t: string) => Number(t.replace(/\./g, '').replace(',', '.'));
const semAcento = (t: string) => t.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

function Cartao({ rotulo, valor, icone, cor, fundo, detalhe, ajuda }: {
  rotulo: string; valor: React.ReactNode; icone: React.ReactNode; cor: string; fundo: string; detalhe?: React.ReactNode; ajuda: React.ReactNode;
}) {
  return (
    <div className="cartao numero">
      <span className="rotulo"><span className="icone" style={{ color: cor, background: fundo }}>{icone}</span>{rotulo}<Ajuda titulo={rotulo}>{ajuda}</Ajuda></span>
      <span className="valor">{valor}</span>
      {detalhe ? <span className="detalhe">{detalhe}</span> : null}
    </div>
  );
}

function TabelaGrupo({ titulo, texto, linhas: todas, icone }: { titulo: string; texto: string; linhas: Grupo[]; icone: React.ReactNode }) {
  const linhas = todas.filter((l) => n(l.aprovados) || n(l.buscas_30d));
  return (
    <section className="cartao">
      <div className="titulo"><div><h2>{titulo}</h2><p>{texto}</p></div></div>
      <div className="corpo sem-espaco">{!linhas.length ? <Vazio titulo="Ainda sem profissionais nem buscas" /> : <div className="tabela-rolagem">
        <table className="tabela">
          <thead><tr>
            <th>{titulo.replace('Por ', '')}</th><th className="num">Aprovados</th><th className="num">Assinam</th><th className="num">Não assinam</th>
            <th className="num">Quentes</th><th className="num" title="Buscas de clientes nos últimos 30 dias">Buscas 30d</th><th className="num" title="Buscas que não acharam ninguém">Sem resultado</th>
          </tr></thead>
          <tbody>
            {linhas.map((l) => (
              <tr key={l.id}>
                <td className="forte" style={{ whiteSpace: 'nowrap' }}><span className="linha-flex" style={{ gap: 6 }}>{icone}{l.nome}</span></td>
                <td className="num">{numero(l.aprovados)}</td>
                <td className="num">{numero(l.assinantes)} <span className="texto-fraco">{l.aprovados ? `(${pct(l.assinantes, l.aprovados)})` : ''}</span></td>
                <td className="num forte">{numero(l.nao_assinantes)}</td>
                <td className="num">{l.quentes ? <Selo tom="vermelho">{numero(l.quentes)}</Selo> : '0'}</td>
                <td className="num">{numero(l.buscas_30d)}</td>
                <td className="num">{l.sem_resultado_30d ? <span style={{ color: '#c62828', fontWeight: 600 }}>{numero(l.sem_resultado_30d)}</span> : '0'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>}</div>
    </section>
  );
}

export default function ComercialPagina() {
  const painel = usePainel();
  const { dados: d, erro, carregando, recarregar } = useCarregar(() => rpc<Comercial>('admin_comercial'), []);
  const { executar, ocupado } = useAcao();
  const [filtro, setFiltro] = useState<'todos' | Prioridade | 'ex'>('todos');
  const [profissao, setProfissao] = useState('');
  const [regiao, setRegiao] = useState('');
  const [texto, setTexto] = useState('');
  const [limite, setLimite] = useState(50);
  const [preco, setPreco] = useState('49,90');
  const [conversao, setConversao] = useState('10');

  const lista = useMemo(() => {
    const t = semAcento(texto.trim());
    return (d?.oportunidades ?? []).filter((o) =>
      (filtro === 'todos' || (filtro === 'ex' ? !!o.ex_assinante_ate : o.prioridade === filtro))
      && (!profissao || (o.profissoes ?? '').split(', ').includes(profissao))
      && (!regiao || o.regiao === regiao)
      && (!t || semAcento(`${o.nome} ${o.email ?? ''} ${o.telefone ?? ''} ${o.profissoes ?? ''}`).includes(t)));
  }, [d, filtro, profissao, regiao, texto]);

  const registrar = (acao: 'baixar_lista' | 'contato', id?: string) => { void rpc('admin_comercial_registrar', { p_acao: acao, p_profissional: id ?? null }).catch(() => undefined); };

  const baixar = () => executar(async () => {
    const L: Celula[][] = [[
      'Prioridade', 'Pontos', 'Nome', 'Telefone', 'WhatsApp', 'E-mail', 'Profissões', 'Região', 'Plano sugerido', 'Argumento',
      'Pedidos 30d', 'Concluídos 30d', 'Ganhos 30d (R$)', 'Buscas 30d na profissão e região', 'Nota', 'Avaliações', 'Serviços concluídos', 'Aceite (%)',
      'Disponível agora', 'Verificado', 'Atende 24h', 'Raio (km)', 'Último acesso', 'Aprovado em', 'Cadastro em', 'Ex-assinante até',
    ]];
    for (const o of lista) L.push([
      prioridades[o.prioridade].rotulo, n(o.pontos), o.nome, telefone(o.telefone), whatsapp(o.telefone) ?? '', o.email ?? '', o.profissoes ?? '', o.regiao ?? '',
      o.plano_sugerido === 'premium' ? 'Premium' : 'VIP', o.argumento ?? '',
      n(o.pedidos_30d), n(o.concluidos_30d), n(o.ganhos_30d), n(o.buscas_30d), o.nota == null ? '' : n(o.nota), n(o.avaliacoes), n(o.servicos), o.aceite == null ? '' : n(o.aceite),
      o.disponivel, o.verificado, o.atende_24h, o.raio_km == null ? '' : n(o.raio_km), dataHoraPlanilha(o.ultimo_acesso), dataHoraPlanilha(o.aprovado_em),
      dataHoraPlanilha(o.cadastro_em), o.ex_assinante_ate ? dataHoraPlanilha(o.ex_assinante_ate) : '',
    ]);
    baixarPlanilha(`comercial-iservice-${new Date().toISOString().slice(0, 10)}`, L);
    registrar('baixar_lista');
  }, 'Lista baixada.');

  const r = d?.resumo;
  const precoN = num(preco); const convN = num(conversao);
  const novosAssinantes = r && Number.isFinite(convN) ? Math.round((r.nao_assinantes * Math.min(100, Math.max(0, convN))) / 100) : 0;
  const receitaSim = Number.isFinite(precoN) ? novosAssinantes * precoN : 0;
  const profissoesLista = useMemo(() => Array.from(new Set((d?.oportunidades ?? []).flatMap((o) => (o.profissoes ?? '').split(', ').filter(Boolean)))).sort(), [d]);
  const regioesLista = useMemo(() => Array.from(new Set((d?.oportunidades ?? []).map((o) => o.regiao).filter(Boolean) as string[])).sort(), [d]);

  return (
    <>
      <Cabecalho titulo="Comercial" texto="Quem ainda não assina VIP ou Premium, em ordem de quem tem mais chance de assinar, com contato e argumento de venda."
        ajuda={<>Cada profissional aprovado sem assinatura ganha pontos: movimento nos últimos 30 dias (pedidos), reputação (nota e avaliações), procura de clientes pela profissão dele na região, acesso recente ao app e se está disponível. <strong>Quente</strong> é 50 pontos ou mais, <strong>morno</strong> de 25 a 49 e <strong>frio</strong> abaixo de 25. Comece pelos quentes. O argumento de cada um é montado com os números dele. Quem baixa a lista fica no Registro da equipe.</>}
        acoes={<button className="botao contorno" disabled={!d || ocupado || !lista.length} onClick={baixar}><Download /> Baixar lista (Excel)</button>} />

      {erro ? <ErroCaixa erro={erro} tentar={recarregar} /> : !d || !r ? <Carregando /> : (
        <div style={{ opacity: carregando ? 0.6 : 1 }}>
          <div className="grade g4" style={{ marginBottom: 18 }}>
            <Cartao rotulo="Profissionais ativos" valor={numero(r.aprovados)} icone={<Users />} cor="#0046b8" fundo="#e8f0fc"
              detalhe={`${numero(r.assinantes)} pagantes · ${numero(r.nao_assinantes)} não pagantes`}
              ajuda="Profissionais aprovados, sem suspensão. Pagantes têm assinatura VIP ou Premium ativa ou atrasada." />
            <Cartao rotulo="Assinantes" valor={numero(r.assinantes)} icone={<Crown />} cor="#b25f00" fundo="#fff4e5"
              detalhe={`VIP ${numero(r.vip)} · Premium ${numero(r.premium)}${r.atrasados ? ` · ${numero(r.atrasados)} atrasados` : ''} · conversão ${pct(r.assinantes, r.aprovados)}`}
              ajuda="Quantos profissionais pagam assinatura, por plano, e quanto isso representa dos ativos." />
            <Cartao rotulo="Para abordar" valor={numero(r.nao_assinantes)} icone={<Target />} cor="#c62828" fundo="#fdecec"
              detalhe={<>{numero(r.quentes)} quentes · {numero(r.mornos)} mornos · {numero(r.frios)} frios</>}
              ajuda="Profissionais aprovados que ainda não assinam, separados pela chance de assinar." />
            <Cartao rotulo="Reativar antes" valor={numero(r.sem_acesso_30d)} icone={<UserRoundX />} cor="#5b3cc4" fundo="#efeafd"
              detalhe={`Sem entrar há 30 dias${r.ex_assinantes ? ` · ${numero(r.ex_assinantes)} ex-assinantes` : ''}`}
              ajuda="Não assinantes que não abrem o app há mais de 30 dias. Primeiro traga de volta, depois ofereça o plano. Ex-assinantes são quem cancelou." />
          </div>

          <div className="grade g2" style={{ marginBottom: 18 }}>
            <section className="cartao">
              <div className="titulo"><div><h2>Funil de cadastros</h2><p>Do cadastro ao assinante.</p></div></div>
              <div className="corpo">
                <ul className="lista-numeros">
                  <li><span>Profissionais preenchendo o cadastro</span><strong>{numero(d.funil.preenchendo)}</strong></li>
                  <li><span>Em análise</span><strong>{numero(d.funil.em_analise)}</strong></li>
                  <li><span>Aprovados e ativos</span><strong>{numero(r.aprovados)}</strong></li>
                  <li className="sub"><span>Assinantes (VIP e Premium)</span><strong>{numero(r.assinantes)} · {pct(r.assinantes, r.aprovados)}</strong></li>
                  <li className="sub"><span>Ainda não assinam</span><strong>{numero(r.nao_assinantes)}</strong></li>
                  <li><span>Clientes cadastrados</span><strong>{numero(d.funil.clientes)}</strong></li>
                </ul>
                <p className="texto-fraco" style={{ margin: '12px 0 0' }}>Quem está preenchendo ou em análise vira oportunidade quando for aprovado. Para acelerar, veja a página <Link href="/captacao/">Captação</Link>.</p>
              </div>
            </section>
            <section className="cartao">
              <div className="titulo"><div><h2 className="com-ajuda">Simulador de receita<Ajuda titulo="Simulador">Quanto entra por mês se uma parte de quem ainda não assina passar a assinar, no preço que você digitar. Serve para definir metas da equipe comercial.</Ajuda></h2><p>Se a equipe converter uma parte dos não assinantes.</p></div><Calculator size={20} /></div>
              <div className="corpo">
                <div className="grade g2" style={{ gap: 12 }}>
                  <div className="campo"><label htmlFor="sim-preco">Mensalidade (R$)</label>
                    <input id="sim-preco" className="entrada" inputMode="decimal" value={preco} onChange={(e) => setPreco(e.target.value)} /></div>
                  <div className="campo"><label htmlFor="sim-conv">Conversão (%)</label>
                    <input id="sim-conv" className="entrada" inputMode="decimal" value={conversao} onChange={(e) => setConversao(e.target.value)} /></div>
                </div>
                <ul className="lista-numeros">
                  <li><span>Novos assinantes</span><strong>{numero(novosAssinantes)} de {numero(r.nao_assinantes)}</strong></li>
                  <li><span>Receita a mais por mês</span><strong style={{ color: '#00873a' }}>{moeda(receitaSim)}</strong></li>
                  <li className="sub"><span>Em 12 meses</span><strong>{moeda(receitaSim * 12)}</strong></li>
                  <li className="sub"><span>Só com os quentes (todos assinando)</span><strong>{moeda(r.quentes * (Number.isFinite(precoN) ? precoN : 0))}/mês</strong></li>
                </ul>
              </div>
            </section>
          </div>

          <section className="cartao" style={{ marginBottom: 18 }}>
            <div className="titulo">
              <div><h2>Quem abordar</h2><p>{numero(lista.length)} de {numero(d.oportunidades.length)} profissionais sem assinatura, do mais provável ao menos provável.</p></div>
            </div>
            <div className="corpo" style={{ paddingBottom: 0 }}>
              <div className="filtros" style={{ marginBottom: 12 }}>
                <Abas ativa={filtro} mudar={(f) => { setFiltro(f); setLimite(50); }} abas={[
                  { id: 'todos', rotulo: 'Todos', n: d.oportunidades.length },
                  { id: 'quente', rotulo: 'Quentes', n: r.quentes },
                  { id: 'morno', rotulo: 'Mornos', n: r.mornos },
                  { id: 'frio', rotulo: 'Frios', n: r.frios },
                  ...(r.ex_assinantes ? [{ id: 'ex' as const, rotulo: 'Ex-assinantes', n: r.ex_assinantes }] : []),
                ]} />
                <span className="espaco" />
                <select className="entrada" value={profissao} onChange={(e) => setProfissao(e.target.value)} aria-label="Profissão" style={{ width: 'auto' }}>
                  <option value="">Todas as profissões</option>
                  {profissoesLista.map((p) => <option key={p} value={p}>{p}</option>)}
                </select>
                <select className="entrada" value={regiao} onChange={(e) => setRegiao(e.target.value)} aria-label="Região" style={{ width: 'auto' }}>
                  <option value="">Todas as regiões</option>
                  {regioesLista.map((p) => <option key={p} value={p}>{p}</option>)}
                </select>
                <div className="busca"><Search /><input className="entrada" placeholder="Nome, telefone ou e-mail" value={texto} onChange={(e) => setTexto(e.target.value)} aria-label="Buscar" /></div>
              </div>
            </div>
            <div className="corpo sem-espaco">
              {!lista.length ? (
                <Vazio icone={<Sparkles size={24} />} titulo={d.oportunidades.length ? 'Ninguém com esses filtros' : 'Todos os profissionais ativos já assinam'}
                  texto={d.oportunidades.length ? 'Mude a prioridade, a profissão ou a região.' : 'Quando houver novos aprovados sem assinatura, eles aparecem aqui.'} />
              ) : (
                <div className="tabela-rolagem">
                  <table className="tabela comercial">
                    <thead><tr>
                      <th>Profissional, argumento e contato</th><th>Prioridade e plano</th><th>Últimos 30 dias</th><th>Reputação</th><th>Último acesso</th>
                    </tr></thead>
                    <tbody>
                      {lista.slice(0, limite).map((o) => {
                        const p = prioridades[o.prioridade];
                        const zap = whatsapp(o.telefone);
                        return (
                          <tr key={o.id}>
                            <td style={{ minWidth: 260 }}>
                              <Pessoa nome={o.nome} foto={o.foto_url} sub={<>{o.profissoes ?? 'Sem profissão'}{o.regiao ? <> · <MapPin size={12} style={{ verticalAlign: -1 }} /> {o.regiao}</> : null}</>} />
                              <div className="linha-flex" style={{ gap: 4, margin: '6px 0 0', flexWrap: 'wrap' }}>
                                {o.verificado ? <Selo tom="verde">Verificado</Selo> : null}
                                {o.disponivel ? <Selo tom="azul">Disponível</Selo> : null}
                                {o.atende_24h ? <Selo tom="roxo">24h</Selo> : null}
                                {o.ex_assinante_ate ? <Selo tom="laranja">Ex-assinante</Selo> : null}
                              </div>
                              {o.argumento ? <p className="argumento">{o.argumento}</p> : null}
                              <div className="linha-flex" style={{ gap: 4, flexWrap: 'wrap', alignItems: 'center', marginTop: 8 }}>
                                {zap ? <a className="botao contorno pequeno" href={zap} target="_blank" rel="noreferrer" onClick={() => registrar('contato', o.id)} title={`WhatsApp ${telefone(o.telefone)}`} aria-label="WhatsApp"><MessageCircle /></a> : null}
                                {o.telefone ? <a className="botao contorno pequeno" href={`tel:${o.telefone.replace(/\D/g, '')}`} onClick={() => registrar('contato', o.id)} title={telefone(o.telefone)}><Phone /></a> : null}
                                {o.email ? <a className="botao contorno pequeno" href={`mailto:${o.email}`} onClick={() => registrar('contato', o.id)} title={o.email}><Mail /></a> : null}
                                {painel.pode('pessoas') ? <Link className="botao contorno pequeno" href={`/pessoa/?id=${o.id}`}>Ficha</Link> : null}
                                <span className="texto-fraco" style={{ whiteSpace: 'nowrap', marginLeft: 4 }}>{telefone(o.telefone)}</span>
                              </div>
                            </td>
                            <td style={{ whiteSpace: 'nowrap' }}>
                              <Selo tom={p.tom} icone={p.icone}>{p.rotulo}</Selo><div className="texto-fraco" style={{ margin: '4px 0 8px' }}>{numero(o.pontos)} pontos</div>
                              <div className="texto-fraco">Oferecer</div>
                              {o.plano_sugerido === 'premium' ? <Selo tom="roxo" icone={<Crown />}>Premium</Selo> : <Selo tom="laranja" icone={<Crown />}>VIP</Selo>}
                            </td>
                            <td style={{ whiteSpace: 'nowrap' }}>
                              <div className="forte">{numero(o.pedidos_30d)} pedidos</div>
                              <div className="texto-fraco">{numero(o.concluidos_30d)} concluídos</div>
                              <div className="texto-fraco">{moeda(o.ganhos_30d)} faturados</div>
                              <div className="texto-fraco" title="Buscas de clientes pela profissão dele, na região dele">{numero(o.buscas_30d)} buscas na região</div>
                            </td>
                            <td style={{ whiteSpace: 'nowrap' }}>
                              <div className="forte">{o.avaliacoes ? `★ ${n(o.nota).toFixed(1).replace('.', ',')}` : 'Sem nota'}</div>
                              <div className="texto-fraco">{numero(o.avaliacoes)} avaliações · {numero(o.servicos)} serviços</div>
                              {o.aceite != null ? <div className="texto-fraco">Aceita {o.aceite}% dos pedidos</div> : null}
                            </td>
                            <td style={{ whiteSpace: 'nowrap' }}>
                              <div>{o.ultimo_acesso ? haQuanto(o.ultimo_acesso) : 'Nunca'}</div>
                              <div className="texto-fraco">Aprovado {o.aprovado_em ? data(o.aprovado_em) : '—'}</div>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}
              {lista.length > limite ? (
                <div style={{ padding: 14, textAlign: 'center' }}>
                  <button className="botao contorno" onClick={() => setLimite((l) => l + 50)}>Mostrar mais ({numero(lista.length - limite)} restantes)</button>
                </div>
              ) : null}
            </div>
          </section>

          <div className="grade" style={{ gap: 18 }}>
            <TabelaGrupo titulo="Por profissão" texto="Só profissões com profissionais ou buscas, de quem tem mais gente para converter." linhas={d.por_profissao} icone={<TrendingUp size={14} />} />
            <TabelaGrupo titulo="Por região" texto="Só regiões com profissionais ou buscas. Buscas sem resultado mostram onde faltam profissionais." linhas={d.por_regiao} icone={<MapPin size={14} />} />
          </div>
        </div>
      )}
    </>
  );
}
