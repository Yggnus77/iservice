'use client';

import { useState } from 'react';
import { CalendarDays, Plus, Save, Trash2 } from 'lucide-react';
import { Cabecalho } from '@/components/Painel';
import { Carregando, ErroCaixa, Selo, useAcao, useCarregar } from '@/components/ui';
import { db, traduzirErro } from '@/lib/supabase';
import { dataHora } from '@/lib/formatos';

type Config = { chave: string; valor: unknown; descricao: string | null; atualizado_em: string };

// Chaves que mudam regras sensíveis ficam marcadas para a equipe pensar duas vezes.
const sensiveis = new Set(['cobranca_ativa', 'prazo_resposta_min', 'dias_garantia', 'dias_exclusao_conta', 'acrescimo_fora_horario', 'horario_comercial', 'piso_preco_percentual', 'deslocamento_base', 'deslocamento_por_km', 'taxa_servico', 'taxa_servico_ativa']);

function Linha({ c, salvo }: { c: Config; salvo: () => void }) {
  const original = JSON.stringify(c.valor);
  const [texto, setTexto] = useState(typeof c.valor === 'string' ? c.valor : original);
  const [erroJson, setErroJson] = useState('');
  const { executar, ocupado } = useAcao();
  const booleano = typeof c.valor === 'boolean';
  const texto_ = typeof c.valor === 'string';

  const salvar = async (valor: unknown) => {
    const ok = await executar(async () => {
      const { error } = await db().from('app_config').update({ valor, atualizado_em: new Date().toISOString() }).eq('chave', c.chave);
      if (error) throw traduzirErro(error);
    }, 'Configuração salva.');
    if (ok) salvo();
  };
  const salvarTexto = () => {
    if (texto_) return salvar(texto);
    try { setErroJson(''); salvar(JSON.parse(texto)); } catch { setErroJson('Valor inválido. Use número, true/false, "texto" ou JSON.'); }
  };
  const mudou = texto_ ? texto !== c.valor : texto !== original;

  return (
    <tr>
      <td style={{ width: '34%' }}>
        <strong className="mono">{c.chave}</strong> {sensiveis.has(c.chave) ? <Selo tom="laranja">regra sensível</Selo> : null}
        <div className="fraco">{c.descricao}</div>
      </td>
      <td>
        {booleano ? (
          <select className="entrada" value={String(c.valor)} disabled={ocupado} onChange={(e) => salvar(e.target.value === 'true')}>
            <option value="true">Ligado</option><option value="false">Desligado</option>
          </select>
        ) : (
          <div className="linha-flex">
            <input className="entrada mono" style={{ flex: 1, minWidth: 200 }} value={texto} onChange={(e) => setTexto(e.target.value)} aria-label={c.chave} />
            <button className="botao contorno pequeno" disabled={!mudou || ocupado} onClick={salvarTexto}><Save /> Salvar</button>
          </div>
        )}
        {erroJson ? <div className="texto-fraco" style={{ color: 'var(--perigo)' }}>{erroJson}</div> : null}
      </td>
      <td className="fraco" style={{ whiteSpace: 'nowrap' }}>{dataHora(c.atualizado_em)}</td>
    </tr>
  );
}

export default function Configuracoes() {
  const { dados, erro, carregando, recarregar } = useCarregar(async () => {
    const { data, error } = await db().from('app_config').select('chave, valor, descricao, atualizado_em').order('chave');
    if (error) throw traduzirErro(error);
    return data as Config[];
  }, []);
  return (
    <>
      <Cabecalho ajuda={<>Valores que os apps leem na hora, sem precisar publicar versão nova. Mude com cuidado: vale para todo mundo assim que salvar. Só o dono tem acesso a esta tela.</>} titulo="Configurações" texto="Valores que os apps e o banco leem na hora: taxa de urgência, prazos, WhatsApp do suporte e outros." />
      {erro ? <ErroCaixa erro={erro} tentar={recarregar} /> : carregando && !dados ? <Carregando /> : (
        <section className="cartao">
          <div className="corpo sem-espaco">
            <div className="tabela-rolagem">
              <table className="tabela">
                <thead><tr><th>Configuração</th><th>Valor</th><th>Alterada em</th></tr></thead>
                <tbody>{dados?.map((c) => <Linha key={c.chave + c.atualizado_em} c={c} salvo={recarregar} />)}</tbody>
              </table>
            </div>
          </div>
        </section>
      )}
      <Feriados />
    </>
  );
}

type Feriado = { data: string; nome: string };

/** Dias em que todo serviço tem o acréscimo fora do horário comercial. */
function Feriados() {
  const { dados, erro, carregando, recarregar } = useCarregar(async () => {
    const { data, error } = await db().from('feriados').select('data, nome').gte('data', new Date().toISOString().slice(0, 10)).order('data');
    if (error) throw traduzirErro(error);
    return data as Feriado[];
  }, []);
  const { executar, ocupado } = useAcao();
  const [data, setData] = useState('');
  const [nome, setNome] = useState('');
  const incluir = async () => {
    const ok = await executar(async () => {
      const { error } = await db().from('feriados').upsert({ data, nome: nome.trim() });
      if (error) throw traduzirErro(error);
    }, 'Feriado salvo.');
    if (ok) { setData(''); setNome(''); recarregar(); }
  };
  const remover = async (f: Feriado) => {
    const ok = await executar(async () => {
      const { error } = await db().from('feriados').delete().eq('data', f.data);
      if (error) throw traduzirErro(error);
    }, 'Feriado removido.');
    if (ok) recarregar();
  };
  const dia = (d: string) => new Date(`${d}T12:00:00`).toLocaleDateString('pt-BR', { weekday: 'short', day: '2-digit', month: 'short', year: 'numeric' });
  return (
    <section className="cartao" style={{ marginTop: 24 }}>
      <div className="corpo">
        <h2 style={{ margin: 0, display: 'flex', alignItems: 'center', gap: 8 }}><CalendarDays size={18} /> Feriados</h2>
        <p className="texto-suave" style={{ margin: '6px 0 12px' }}>
          Nestes dias todo serviço tem o acréscimo fora do horário comercial (acrescimo_fora_horario), e o cliente vê o valor antes de pedir.
        </p>
        <div className="linha-flex" style={{ gap: 8, flexWrap: 'wrap' }}>
          <input className="entrada" type="date" value={data} onChange={(e) => setData(e.target.value)} aria-label="Data do feriado" />
          <input className="entrada" style={{ flex: 1, minWidth: 200 }} placeholder="Nome (ex.: Aniversário da cidade)" value={nome} onChange={(e) => setNome(e.target.value)} aria-label="Nome do feriado" />
          <button className="botao primario" disabled={ocupado || !data || nome.trim().length < 2} onClick={incluir}><Plus /> Incluir</button>
        </div>
      </div>
      <div className="corpo sem-espaco">
        {erro ? <div style={{ padding: 16 }}><ErroCaixa erro={erro} tentar={recarregar} /></div> : carregando && !dados ? <Carregando /> : (
          <div className="tabela-rolagem">
            <table className="tabela">
              <thead><tr><th>Dia</th><th>Feriado</th><th></th></tr></thead>
              <tbody>
                {dados?.map((f) => (
                  <tr key={f.data}>
                    <td style={{ whiteSpace: 'nowrap' }}>{dia(f.data)}</td>
                    <td>{f.nome}</td>
                    <td style={{ textAlign: 'right' }}><button className="botao fantasma pequeno" disabled={ocupado} onClick={() => remover(f)} aria-label={`Remover ${f.nome}`}><Trash2 /></button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </section>
  );
}
