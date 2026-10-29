'use client';

import { useState } from 'react';
import { Save } from 'lucide-react';
import { Cabecalho } from '@/components/Painel';
import { Carregando, ErroCaixa, Selo, useAcao, useCarregar } from '@/components/ui';
import { db, traduzirErro } from '@/lib/supabase';
import { dataHora } from '@/lib/formatos';

type Config = { chave: string; valor: unknown; descricao: string | null; atualizado_em: string };

// Chaves que mudam regras sensíveis ficam marcadas para a equipe pensar duas vezes.
const sensiveis = new Set(['cobranca_ativa', 'prazo_resposta_min', 'dias_garantia', 'dias_exclusao_conta']);

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
      <Cabecalho titulo="Configurações" texto="Valores que os apps e o banco leem na hora: taxa de urgência, prazos, WhatsApp do suporte e outros." />
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
    </>
  );
}
