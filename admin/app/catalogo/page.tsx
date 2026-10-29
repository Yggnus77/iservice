'use client';

import { Fragment, useState } from 'react';
import { Check, ChevronDown, ChevronRight, LayoutGrid, MapPin, Plus, ShieldAlert, X } from 'lucide-react';
import { Cabecalho, usePainel } from '@/components/Painel';
import { Abas, Carregando, Dialogo, ErroCaixa, Interruptor, Selo, Vazio, useAcao, useCarregar } from '@/components/ui';
import { db, rpc, traduzirErro } from '@/lib/supabase';
import { moeda } from '@/lib/formatos';

type Profissao = { id: string; nome: string; icone: string; cor_inicio: string; cor_fim: string; preco_base: number; exige_antecedentes: boolean; palavras_chave: string[]; ativa: boolean; ordem: number };
type Especialidade = { id: number; profissao_id: string; nome: string; sugerida: boolean; aprovada: boolean; ordem: number };
type Regiao = { id: string; nome: string; uf: string; faixa_preco: number; ativa: boolean; ordem: number };
type Sugerida = { id: number; nome: string; profissao_id: string; profissao: string; criada_por: string | null; profissional: string | null; usando: number };

async function q<T>(p: PromiseLike<{ data: T | null; error: { message: string; code?: string } | null }>): Promise<T> {
  const { data, error } = await p;
  if (error) throw traduzirErro(error);
  return data as T;
}

function slug(t: string) {
  return t.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

function Profissoes() {
  const { atualizarResumo } = usePainel();
  const { dados, erro, carregando, recarregar, setDados } = useCarregar(async () => {
    const [p, e] = await Promise.all([
      q<Profissao[]>(db().from('profissoes').select('*').order('ordem')),
      q<Especialidade[]>(db().from('especialidades').select('id, profissao_id, nome, sugerida, aprovada, ordem').eq('aprovada', true).order('ordem').order('nome')),
    ]);
    return { profissoes: p, especialidades: e };
  }, []);
  const { executar } = useAcao();
  const [aberta, setAberta] = useState<string | null>(null);
  const [nova, setNova] = useState(false);
  const [novaEsp, setNovaEsp] = useState<Record<string, string>>({});
  const [form, setForm] = useState({ nome: '', preco_base: '80', icone: 'handyman', exige_antecedentes: false });

  if (erro) return <ErroCaixa erro={erro} tentar={recarregar} />;
  if (carregando && !dados) return <Carregando />;
  if (!dados) return null;

  const mudar = async (id: string, campos: Partial<Profissao>, msg: string) => {
    const antes = dados;
    setDados({ ...dados, profissoes: dados.profissoes.map((p) => (p.id === id ? { ...p, ...campos } : p)) });
    const ok = await executar(() => q(db().from('profissoes').update(campos).eq('id', id).select()), msg);
    if (!ok) setDados(antes); else atualizarResumo();
  };
  const tirarEsp = async (e: Especialidade) => {
    if (await executar(() => q(db().from('especialidades').update({ aprovada: false, revisada: true }).eq('id', e.id).select()), `"${e.nome}" saiu da lista sugerida.`)) recarregar();
  };
  const addEsp = async (profissao: string) => {
    const nome = (novaEsp[profissao] ?? '').trim();
    if (!nome) return;
    const ordem = Math.max(0, ...dados.especialidades.filter((e) => e.profissao_id === profissao).map((e) => e.ordem)) + 1;
    if (await executar(() => q(db().from('especialidades').upsert({ profissao_id: profissao, nome, sugerida: true, aprovada: true, revisada: true, ordem }, { onConflict: 'profissao_id,nome' }).select()), 'Especialidade adicionada.')) {
      setNovaEsp({ ...novaEsp, [profissao]: '' });
      recarregar();
    }
  };
  const criar = async () => {
    const id = slug(form.nome);
    const ordem = Math.max(0, ...dados.profissoes.map((p) => p.ordem)) + 1;
    const ok = await executar(() => q(db().from('profissoes').insert({
      id, nome: form.nome.trim(), icone: form.icone || 'handyman', cor_inicio: '#4a90f0', cor_fim: '#1a5bc4', preco_base: Number(form.preco_base) || 80,
      exige_antecedentes: form.exige_antecedentes, ativa: false, ordem,
    }).select()), 'Profissão criada (desligada até você ligar).');
    if (ok) { setNova(false); setForm({ nome: '', preco_base: '80', icone: 'handyman', exige_antecedentes: false }); recarregar(); }
  };

  return (
    <>
      <div className="filtros">
        <span className="texto-suave">Profissão desligada some dos apps e não recebe pedidos. Quem já trabalha nela continua cadastrado.</span>
        <span className="espaco" />
        <button className="botao primario" onClick={() => setNova(true)}><Plus /> Nova profissão</button>
      </div>
      <section className="cartao">
        <div className="corpo sem-espaco">
          <table className="tabela">
            <thead><tr><th style={{ width: 32 }} /><th>Profissão</th><th>Especialidades</th><th>Preço base</th><th>Antecedentes</th><th>Ligada</th></tr></thead>
            <tbody>
              {dados.profissoes.map((p) => {
                const esps = dados.especialidades.filter((e) => e.profissao_id === p.id);
                const ab = aberta === p.id;
                return (
                  <Fragment key={p.id}>
                    <tr className="clicavel" onClick={() => setAberta(ab ? null : p.id)}>
                      <td>{ab ? <ChevronDown size={16} /> : <ChevronRight size={16} />}</td>
                      <td>
                        <span className="linha-flex">
                          <span style={{ width: 30, height: 30, borderRadius: 9, background: `linear-gradient(135deg, ${p.cor_inicio}, ${p.cor_fim})`, flex: 'none' }} />
                          <span><strong>{p.nome}</strong><div className="fraco mono">{p.id}</div></span>
                        </span>
                      </td>
                      <td>{esps.length}</td>
                      <td onClick={(e) => e.stopPropagation()}>
                        <input className="entrada" style={{ width: 110, height: 34 }} type="number" min={1} defaultValue={p.preco_base} aria-label={`Preço base de ${p.nome}`}
                          onBlur={(e) => { const v = Number(e.target.value); if (v > 0 && v !== Number(p.preco_base)) mudar(p.id, { preco_base: v }, `Preço base de ${p.nome}: ${moeda(v)}.`); }} />
                      </td>
                      <td onClick={(e) => e.stopPropagation()}>
                        <Interruptor ligado={p.exige_antecedentes} rotulo={`${p.nome} exige antecedentes`}
                          mudar={(v) => mudar(p.id, { exige_antecedentes: v }, v ? `${p.nome} agora exige certidão de antecedentes.` : `${p.nome} não exige mais certidão.`)} />
                      </td>
                      <td onClick={(e) => e.stopPropagation()}>
                        <Interruptor ligado={p.ativa} rotulo={`${p.nome} ligada`} mudar={(v) => mudar(p.id, { ativa: v }, v ? `${p.nome} ligada nos apps.` : `${p.nome} desligada.`)} />
                      </td>
                    </tr>
                    {ab ? (
                      <tr>
                        <td />
                        <td colSpan={5} style={{ background: '#fafbfd' }}>
                          <div className="linha-flex" style={{ gap: 6, marginBottom: 10 }}>
                            {esps.map((e) => (
                              <span key={e.id} className="selo neutro" style={{ fontSize: 12.5, padding: '4px 6px 4px 11px' }}>
                                {e.nome}
                                <button onClick={() => tirarEsp(e)} aria-label={`Tirar ${e.nome}`} style={{ border: 0, background: 'none', cursor: 'pointer', padding: 0, display: 'grid', color: 'inherit' }}><X size={13} /></button>
                              </span>
                            ))}
                          </div>
                          <div className="linha-flex">
                            <input className="entrada" style={{ maxWidth: 320 }} placeholder="Nova especialidade sugerida" value={novaEsp[p.id] ?? ''}
                              onChange={(e) => setNovaEsp({ ...novaEsp, [p.id]: e.target.value })} onKeyDown={(e) => { if (e.key === 'Enter') addEsp(p.id); }} />
                            <button className="botao contorno" onClick={() => addEsp(p.id)}><Plus /> Adicionar</button>
                          </div>
                        </td>
                      </tr>
                    ) : null}
                  </Fragment>
                );
              })}
            </tbody>
          </table>
        </div>
      </section>
      <Dialogo aberto={nova} fechar={() => setNova(false)} titulo="Nova profissão" texto="Ela nasce desligada. Adicione as especialidades e ligue quando quiser que apareça nos apps."
        rodape={<><button className="botao contorno" onClick={() => setNova(false)}>Cancelar</button><button className="botao primario" disabled={!form.nome.trim()} onClick={criar}>Criar profissão</button></>}>
        <div className="campo"><label htmlFor="np-nome">Nome</label><input id="np-nome" className="entrada" value={form.nome} onChange={(e) => setForm({ ...form, nome: e.target.value })} placeholder="Ex.: Vidraceiro" /></div>
        <div className="grade g2">
          <div className="campo"><label htmlFor="np-preco">Preço base (R$)</label><input id="np-preco" className="entrada" type="number" value={form.preco_base} onChange={(e) => setForm({ ...form, preco_base: e.target.value })} />
            <span className="ajuda">Usado na faixa de referência enquanto há poucos preços reais.</span></div>
          <div className="campo"><label htmlFor="np-icone">Ícone</label><input id="np-icone" className="entrada" value={form.icone} onChange={(e) => setForm({ ...form, icone: e.target.value })} />
            <span className="ajuda">Nome do ícone Material Symbols (ex.: window, handyman).</span></div>
        </div>
        <label className="marcar"><input type="checkbox" checked={form.exige_antecedentes} onChange={(e) => setForm({ ...form, exige_antecedentes: e.target.checked })} /> Exige certidão de antecedentes</label>
      </Dialogo>
    </>
  );
}

function Sugeridas() {
  const { atualizarResumo } = usePainel();
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Sugerida[]>('admin_especialidades_sugeridas'), []);
  const { executar, ocupado } = useAcao();
  const decidir = async (s: Sugerida, aprovar: boolean) => {
    const ok = await executar(() => q(db().from('especialidades').update(aprovar ? { aprovada: true, sugerida: true, revisada: true } : { revisada: true }).eq('id', s.id).select()),
      aprovar ? `"${s.nome}" agora aparece como sugestão para todos.` : `"${s.nome}" fica só no perfil de quem criou.`);
    if (ok) { recarregar(); atualizarResumo(); }
  };
  if (erro) return <ErroCaixa erro={erro} tentar={recarregar} />;
  if (carregando && !dados) return <Carregando />;
  return (
    <>
      <p className="texto-suave" style={{ marginTop: 0 }}>Especialidades que profissionais escreveram por conta própria. Aprovar transforma em sugestão para todos daquela profissão; recusar deixa só no perfil de quem criou.</p>
      <section className="cartao">
        <div className="corpo sem-espaco">
          {!dados?.length ? <Vazio icone={<LayoutGrid size={24} />} titulo="Nenhuma sugestão nova" /> : (
            <table className="tabela">
              <thead><tr><th>Especialidade</th><th>Profissão</th><th>Criada por</th><th className="num">Usando</th><th /></tr></thead>
              <tbody>
                {dados.map((s) => (
                  <tr key={s.id}>
                    <td><strong>{s.nome}</strong></td>
                    <td>{s.profissao}</td>
                    <td>{s.profissional ?? '—'}</td>
                    <td className="num">{s.usando}</td>
                    <td style={{ textAlign: 'right' }}>
                      <span className="linha-flex" style={{ justifyContent: 'flex-end' }}>
                        <button className="botao contorno pequeno" disabled={ocupado} onClick={() => decidir(s, false)}><X /> Só no perfil dele</button>
                        <button className="botao sucesso pequeno" disabled={ocupado} onClick={() => decidir(s, true)}><Check /> Sugerir para todos</button>
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </section>
    </>
  );
}

const faixas: Record<number, string> = { 1: '1 · Plano Piloto e Lagos', 2: '2', 3: '3', 4: '4', 5: '5 · Entorno' };

function Regioes() {
  const { dados, erro, carregando, recarregar, setDados } = useCarregar(() => q<Regiao[]>(db().from('regioes').select('id, nome, uf, faixa_preco, ativa, ordem').order('ordem')), []);
  const { executar } = useAcao();
  if (erro) return <ErroCaixa erro={erro} tentar={recarregar} />;
  if (carregando && !dados) return <Carregando />;
  if (!dados) return null;
  const mudar = async (r: Regiao, campos: Partial<Regiao>, msg: string) => {
    const antes = dados;
    setDados(dados.map((x) => (x.id === r.id ? { ...x, ...campos } : x)));
    if (!(await executar(() => q(db().from('regioes').update(campos).eq('id', r.id).select()), msg))) setDados(antes);
  };
  return (
    <>
      <p className="texto-suave" style={{ marginTop: 0 }}>Região desligada não recebe pedidos novos (o cliente vê &quot;O iService ainda não atende nessa região&quot;). A faixa define o preço de referência.</p>
      <section className="cartao">
        <div className="corpo sem-espaco">
          <table className="tabela">
            <thead><tr><th>Região</th><th>UF</th><th>Faixa de preço</th><th>Atendendo</th></tr></thead>
            <tbody>
              {dados.map((r) => (
                <tr key={r.id}>
                  <td><span className="linha-flex"><MapPin size={15} color="#7a879d" /><strong>{r.nome}</strong></span></td>
                  <td>{r.uf === 'GO' ? <Selo tom="roxo">GO</Selo> : <Selo tom="azul">DF</Selo>}</td>
                  <td>
                    <select className="entrada" style={{ height: 34 }} value={r.faixa_preco} aria-label={`Faixa de ${r.nome}`}
                      onChange={(e) => mudar(r, { faixa_preco: Number(e.target.value) }, `${r.nome} agora está na faixa ${e.target.value}.`)}>
                      {[1, 2, 3, 4, 5].map((f) => <option key={f} value={f}>{faixas[f]}</option>)}
                    </select>
                  </td>
                  <td><Interruptor ligado={r.ativa} rotulo={`${r.nome} atendendo`} mudar={(v) => mudar(r, { ativa: v }, v ? `${r.nome} ligada.` : `${r.nome} desligada.`)} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </>
  );
}

export default function Catalogo() {
  const { resumo } = usePainel();
  const [aba, setAba] = useState<'profissoes' | 'sugeridas' | 'regioes'>('profissoes');
  return (
    <>
      <Cabecalho titulo="Profissões e regiões" texto="Ligue e desligue profissões e regiões, ajuste especialidades e aprove as sugeridas pelos profissionais."
        acoes={<Abas ativa={aba} mudar={setAba} abas={[
          { id: 'profissoes', rotulo: 'Profissões' },
          { id: 'sugeridas', rotulo: 'Sugeridas', n: resumo?.especialidades_sugeridas || undefined },
          { id: 'regioes', rotulo: 'Regiões' },
        ]} />} />
      {aba === 'profissoes' ? <Profissoes /> : aba === 'sugeridas' ? <Sugeridas /> : <Regioes />}
      <p className="texto-fraco" style={{ marginTop: 14 }}><ShieldAlert size={13} style={{ verticalAlign: -2 }} /> Toda mudança aqui fica no registro da equipe.</p>
    </>
  );
}
