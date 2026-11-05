'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import { ExternalLink, Loader2, Send, ShieldCheck, StickyNote } from 'lucide-react';
import { Cabecalho, usePainel } from '@/components/Painel';
import { Abas, Carregando, ErroCaixa, Miniatura, Selo, SeloStatus, Vazio, useAcao, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { dataHora, haQuanto, moeda, statusReclamacao } from '@/lib/formatos';

// Mesmo número que vai nos e-mails da Garantia (função enviar-email).
const protocolo = (id: number) => `G-${String(id).padStart(5, '0')}`;

type Reclamacao = {
  id: number; pedido_id: string; codigo: string; motivo: string; descricao: string; fotos: string[]; status: string; resolucao: string | null;
  autor_id: string; autor: string; autor_papel: string; cliente: string; profissional: string; profissao: string; valor: number | null;
  criada_em: string; atualizada_em: string;
};
type Historico = { id: number; autor: string | null; status: string | null; texto: string; interno: boolean; criado_em: string };
type Aba = 'abertas' | 'resolvida' | 'encerrada' | 'todas';

function Mediacao({ r, aoMudar }: { r: Reclamacao; aoMudar: () => void }) {
  const { executar, ocupado } = useAcao();
  const hist = useCarregar(() => rpc<Historico[]>('admin_reclamacao_historico', { p_reclamacao: r.id }), [r.id]);
  const [texto, setTexto] = useState('');
  const [status, setStatus] = useState<string>(r.status === 'aberta' ? 'em_mediacao' : r.status);
  const [avisar, setAvisar] = useState(false);
  useEffect(() => { setTexto(''); setStatus(r.status === 'aberta' ? 'em_mediacao' : r.status); setAvisar(false); }, [r.id, r.status]);
  const fecha = status === 'resolvida' || status === 'encerrada';

  const enviar = async () => {
    const ok = await executar(() => rpc('admin_mediar_reclamacao', {
      p_reclamacao: r.id, p_status: status === r.status ? null : status, p_texto: texto, p_avisar_partes: avisar,
    }), avisar ? 'Atualização enviada ao cliente e ao profissional.' : 'Anotação salva.');
    if (ok) { setTexto(''); hist.recarregar(); aoMudar(); }
  };

  return (
    <section className="cartao" style={{ position: 'sticky', top: 16 }}>
      <div className="titulo">
        <div><h2>{r.motivo}</h2><p>Protocolo <span className="mono">{protocolo(r.id)}</span> · Pedido <Link href={`/pedido/?id=${r.pedido_id}`} className="mono">{r.codigo} <ExternalLink size={12} /></Link> · {r.profissao} · {moeda(r.valor)}</p></div>
        <SeloStatus mapa={statusReclamacao} valor={r.status} />
      </div>
      <div className="corpo" style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <dl className="dados">
          <div><dt>Aberta por</dt><dd>{r.autor} ({r.autor_papel})</dd></div>
          <div><dt>Quando</dt><dd>{dataHora(r.criada_em)}</dd></div>
          <div><dt>Cliente</dt><dd>{r.cliente}</dd></div>
          <div><dt>Profissional</dt><dd>{r.profissional}</dd></div>
        </dl>
        <div className="citacao">{r.descricao}</div>
        {r.fotos?.length ? <div className="miniaturas">{r.fotos.map((f, i) => <Miniatura key={f} bucket="pedidos" caminho={f} titulo={`Foto ${i + 1}`} />)}</div> : null}
        {r.resolucao ? <div className="alerta-faixa azul" style={{ margin: 0 }}><div><strong>Resolução</strong>{r.resolucao}</div></div> : null}

        <div className="separador" />
        <strong>Andamento da mediação</strong>
        {hist.carregando && !hist.dados ? <Carregando /> : !hist.dados?.length ? <span className="texto-suave">Nada registrado ainda.</span> : (
          <ul className="tempo">
            {hist.dados.map((h) => (
              <li key={h.id}>
                <span className={`ponto ${h.interno ? 'fraco' : ''}`} />
                <div>
                  <strong>{h.status ? `${statusReclamacao[h.status]?.rotulo ?? h.status} · ` : ''}{h.interno ? 'Anotação interna' : 'Enviado às duas partes'}</strong>
                  <span>{h.autor ?? 'Equipe'} · {dataHora(h.criado_em)}</span>
                  {h.texto ? <div style={{ marginTop: 4 }}>{h.texto}</div> : null}
                </div>
              </li>
            ))}
          </ul>
        )}

        {r.status !== 'resolvida' && r.status !== 'encerrada' ? <>
          <div className="separador" />
          <div className="campo">
            <label htmlFor="med-status">Situação</label>
            <select id="med-status" className="entrada" value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="em_mediacao">Em mediação</option>
              <option value="resolvida">Resolvida (houve acordo ou correção)</option>
              <option value="encerrada">Encerrada (sem acordo ou improcedente)</option>
            </select>
          </div>
          <div className="campo">
            <label htmlFor="med-texto">{fecha ? 'Resolução' : 'Anotação ou mensagem'}</label>
            <textarea id="med-texto" className="entrada" value={texto} onChange={(e) => setTexto(e.target.value)}
              placeholder={fecha ? 'Ex.: o profissional voltou e refez o serviço sem custo.' : 'Ex.: liguei para o profissional, ele volta amanhã às 9h.'} />
          </div>
          <label className="marcar">
            <input type="checkbox" checked={avisar} onChange={(e) => setAvisar(e.target.checked)} />
            Enviar este texto como notificação para o cliente e o profissional
          </label>
          <button className="botao primario" disabled={ocupado || (!texto.trim() && status === r.status) || (fecha && !texto.trim())} onClick={enviar}>
            {ocupado ? <Loader2 className="girar" /> : avisar ? <Send /> : <StickyNote />} {avisar ? 'Salvar e avisar as partes' : 'Salvar'}
          </button>
        </> : null}
      </div>
    </section>
  );
}

export default function Garantia() {
  const { atualizarResumo } = usePainel();
  const [aba, setAba] = useState<Aba>('abertas');
  const [sel, setSel] = useState<number | null>(null);
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Reclamacao[]>('admin_reclamacoes', { p_status: aba }), [aba]);
  const atual = dados?.find((r) => r.id === sel) ?? dados?.[0] ?? null;

  return (
    <>
      <Cabecalho titulo="Garantia iService" texto="Reclamações abertas pelos clientes ou profissionais. Medie, registre e avise as partes." />
      <div className="filtros">
        <Abas<Aba> ativa={aba} mudar={(a) => { setAba(a); setSel(null); }} abas={[
          { id: 'abertas', rotulo: 'Abertas' }, { id: 'resolvida', rotulo: 'Resolvidas' }, { id: 'encerrada', rotulo: 'Encerradas' }, { id: 'todas', rotulo: 'Todas' },
        ]} />
      </div>
      {erro ? <ErroCaixa erro={erro} tentar={recarregar} /> : carregando && !dados ? <Carregando /> : !dados?.length ? (
        <section className="cartao"><Vazio icone={<ShieldCheck size={24} />} titulo={aba === 'abertas' ? 'Nenhuma reclamação aberta' : 'Nada por aqui'} texto="Ótimo sinal." /></section>
      ) : (
        <div className="grade lado">
          <section className="cartao">
            <div className="corpo sem-espaco">
              <table className="tabela">
                <thead><tr><th>Reclamação</th><th>Partes</th><th>Aberta</th><th>Situação</th></tr></thead>
                <tbody>
                  {dados.map((r) => (
                    <tr key={r.id} className="clicavel" onClick={() => setSel(r.id)} style={atual?.id === r.id ? { background: 'var(--azul-suave)' } : undefined}>
                      <td><strong>{r.motivo}</strong><div className="fraco"><span className="mono">{protocolo(r.id)}</span> · <span className="mono">{r.codigo}</span> · {r.profissao}</div></td>
                      <td>{r.cliente}<div className="fraco">com {r.profissional}</div></td>
                      <td className="fraco">{haQuanto(r.criada_em)}{r.status === 'aberta' && Date.now() - new Date(r.criada_em).getTime() > 86400000 ? <div><Selo tom="vermelho">+24 h sem resposta</Selo></div> : null}</td>
                      <td><SeloStatus mapa={statusReclamacao} valor={r.status} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
          {atual ? <Mediacao r={atual} aoMudar={() => { recarregar(); atualizarResumo(); }} /> : null}
        </div>
      )}
    </>
  );
}
