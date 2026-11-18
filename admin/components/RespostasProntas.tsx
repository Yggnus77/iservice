'use client';

import { useEffect, useState } from 'react';
import { ChevronLeft, Loader2, MessageSquareText, Pencil, Plus, Search, Trash2 } from 'lucide-react';
import { rpc } from '@/lib/supabase';
import { Carregando, Dialogo, ErroCaixa, Vazio, useAcao, useCarregar } from './ui';

export type RespostaPronta = { id: number; titulo: string; texto: string; usos: number };

/** Troca {nome}, {protocolo} e {atendente} pelos dados da conversa. */
export function preencher(texto: string, v: { nome: string; protocolo: string; atendente: string }) {
  return texto.replace(/\{nome\}/gi, v.nome).replace(/\{protocolo\}/gi, v.protocolo).replace(/\{atendente\}/gi, v.atendente);
}

/**
 * Escolher uma resposta pronta para colar na caixa de texto. Quem tem "emails_todos"
 * (responsável de setor, gerente, dono) também cria, edita e apaga.
 */
export function RespostasProntas({ aberto, fechar, usar, gerir }: {
  aberto: boolean; fechar: () => void; usar: (r: RespostaPronta) => void; gerir: boolean;
}) {
  const { dados, erro, carregando, recarregar } = useCarregar(() => (aberto ? rpc<RespostaPronta[]>('admin_respostas_prontas') : Promise.resolve(null)), [aberto]);
  const { executar, ocupado } = useAcao();
  const [busca, setBusca] = useState('');
  const [editando, setEditando] = useState<Partial<RespostaPronta> | null>(null);
  useEffect(() => { if (aberto) { setBusca(''); setEditando(null); } }, [aberto]);

  const q = busca.trim().toLowerCase();
  const lista = (dados ?? []).filter((r) => !q || r.titulo.toLowerCase().includes(q) || r.texto.toLowerCase().includes(q));

  const salvar = async () => {
    if (!editando) return;
    const ok = await executar(() => rpc('admin_salvar_resposta', { p_id: editando.id ?? null, p_titulo: editando.titulo ?? '', p_texto: editando.texto ?? '' }), 'Resposta salva.');
    if (ok) { setEditando(null); recarregar(); }
  };
  const apagar = async (r: RespostaPronta) => {
    if (!window.confirm(`Apagar a resposta “${r.titulo}”?`)) return;
    if (await executar(() => rpc('admin_apagar_resposta', { p_id: r.id }), 'Resposta apagada.')) recarregar();
  };

  if (editando) {
    return (
      <Dialogo aberto={aberto} fechar={fechar} titulo={editando.id ? 'Editar resposta pronta' : 'Nova resposta pronta'} icone={<MessageSquareText />} largo
        texto={<>Use <strong>{'{nome}'}</strong> para o primeiro nome da pessoa, <strong>{'{protocolo}'}</strong> para o número do atendimento
          e <strong>{'{atendente}'}</strong> para o seu nome. Eles são trocados sozinhos na hora de usar.</>}
        rodape={<>
          <button className="botao fantasma" onClick={() => setEditando(null)}><ChevronLeft /> Voltar</button>
          <span className="espaco" />
          <button className="botao primario" disabled={ocupado || !editando.titulo?.trim() || !editando.texto?.trim()} onClick={salvar}>
            {ocupado ? <Loader2 className="girar" /> : null}Salvar
          </button>
        </>}>
        <div className="campo">
          <label htmlFor="rp-titulo">Nome (para achar na lista)</label>
          <input id="rp-titulo" className="entrada" maxLength={80} value={editando.titulo ?? ''} onChange={(e) => setEditando({ ...editando, titulo: e.target.value })}
            placeholder="Ex.: Como funciona a Garantia" autoFocus />
        </div>
        <div className="campo">
          <label htmlFor="rp-texto">Texto</label>
          <textarea id="rp-texto" className="entrada" rows={10} maxLength={5000} value={editando.texto ?? ''}
            onChange={(e) => setEditando({ ...editando, texto: e.target.value })} placeholder={'Olá, {nome}!\n\n…\n\n{atendente}'} />
        </div>
      </Dialogo>
    );
  }

  return (
    <Dialogo aberto={aberto} fechar={fechar} titulo="Respostas prontas" icone={<MessageSquareText />} largo
      texto="Escolha uma para colocar na caixa de resposta. Dá para ajustar o texto antes de enviar."
      rodape={gerir ? <><span className="espaco" /><button className="botao contorno" onClick={() => setEditando({ titulo: '', texto: '' })}><Plus /> Nova resposta</button></> : undefined}>
      <div className="busca" style={{ marginBottom: 12 }}>
        <Search />
        <input className="entrada" placeholder="Procurar resposta" value={busca} onChange={(e) => setBusca(e.target.value)} aria-label="Procurar resposta" autoFocus />
      </div>
      {erro ? <ErroCaixa erro={erro} tentar={recarregar} /> : carregando && !dados ? <Carregando /> : !lista.length ? (
        <Vazio icone={<MessageSquareText size={24} />} titulo={q ? 'Nenhuma resposta encontrada' : 'Nenhuma resposta pronta ainda'}
          texto={gerir ? 'Crie em "Nova resposta".' : 'Peça ao responsável de setor para criar.'} />
      ) : (
        <div className="respostas-lista">
          {lista.map((r) => (
            <div key={r.id} className="linha-flex" style={{ flexWrap: 'nowrap', gap: 6 }}>
              <button className="resposta-item" onClick={() => { usar(r); rpc('admin_usar_resposta', { p_id: r.id }).catch(() => {}); }}>
                <span style={{ minWidth: 0, flex: 1 }}>
                  <strong>{r.titulo}</strong>
                  <span className="previa">{r.texto.replace(/\s+/g, ' ')}</span>
                </span>
              </button>
              {gerir ? <>
                <button className="botao fantasma pequeno" title="Editar" aria-label={`Editar ${r.titulo}`} onClick={() => setEditando(r)}><Pencil /></button>
                <button className="botao fantasma pequeno" title="Apagar" aria-label={`Apagar ${r.titulo}`} disabled={ocupado} onClick={() => apagar(r)}><Trash2 /></button>
              </> : null}
            </div>
          ))}
        </div>
      )}
    </Dialogo>
  );
}
