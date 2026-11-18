'use client';

import { useState } from 'react';
import { Pin, PinOff, StickyNote, Trash2 } from 'lucide-react';
import { rpc } from '@/lib/supabase';
import { dataHora } from '@/lib/formatos';
import { Ajuda } from './Ajuda';
import { Avatar, Carregando, useAcao, useCarregar } from './ui';

type Nota = { id: number; texto: string; fixada: boolean; criada_em: string; autor: string; autor_foto: string | null; minha: boolean; pode_apagar: boolean };

/** Recados internos da equipe sobre uma pessoa ou um pedido. O cliente e o profissional nunca veem. */
export function Anotacoes({ tipo, alvo }: { tipo: 'pessoa' | 'pedido'; alvo: string }) {
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Nota[]>('admin_notas', { p_tipo: tipo, p_alvo: alvo }), [tipo, alvo]);
  const { executar, ocupado } = useAcao();
  const [texto, setTexto] = useState('');

  // Sem o SQL das ferramentas de gestão, o cartão não aparece.
  if (erro) return null;

  const salvar = async () => {
    const t = texto.trim();
    if (!t) return;
    if (await executar(() => rpc('admin_anotar', { p_tipo: tipo, p_alvo: alvo, p_texto: t }), 'Anotação salva. Só a equipe vê.')) {
      setTexto('');
      recarregar();
    }
  };

  return (
    <section className="cartao">
      <div className="titulo">
        <div>
          <h2 className="com-ajuda">
            <StickyNote size={16} /> Anotações da equipe
            <Ajuda titulo="Anotações da equipe">
              Recados para quem atender {tipo === 'pessoa' ? 'esta pessoa' : 'este pedido'} depois de você, como
              “ligou reclamando dia 10, prometemos retorno”. Só a equipe vê. Fixe no topo o que todo mundo precisa ler primeiro.
            </Ajuda>
          </h2>
          <p>Só a equipe vê.</p>
        </div>
      </div>
      <div className="corpo">
        <div className="nota-nova">
          <textarea className="entrada" rows={2} maxLength={2000} value={texto} onChange={(e) => setTexto(e.target.value)}
            placeholder="Escreva um recado para a equipe…" aria-label="Nova anotação"
            onKeyDown={(e) => { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); salvar(); } }} />
          <button className="botao primario pequeno" disabled={ocupado || !texto.trim()} onClick={salvar}>Salvar</button>
        </div>
        {carregando && !dados ? <Carregando /> : !dados?.length ? (
          <span className="texto-suave">Nenhuma anotação ainda.</span>
        ) : (
          <ul className="notas">
            {dados.map((n) => (
              <li key={n.id} className={n.fixada ? 'fixada' : ''}>
                <Avatar nome={n.autor} foto={n.autor_foto} tamanho={28} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div className="nota-cab">
                    <strong>{n.minha ? 'Você' : n.autor}</strong>
                    <span className="texto-fraco">{dataHora(n.criada_em)}</span>
                    {n.fixada ? <span className="selo azul"><Pin /> Fixada</span> : null}
                    <span className="espaco" />
                    <button className="botao fantasma pequeno" disabled={ocupado} title={n.fixada ? 'Tirar do topo' : 'Fixar no topo'}
                      aria-label={n.fixada ? 'Tirar do topo' : 'Fixar no topo'}
                      onClick={async () => { if (await executar(() => rpc('admin_fixar_nota', { p_id: n.id, p_fixada: !n.fixada }))) recarregar(); }}>
                      {n.fixada ? <PinOff /> : <Pin />}
                    </button>
                    {n.pode_apagar ? (
                      <button className="botao fantasma pequeno" disabled={ocupado} title="Apagar" aria-label="Apagar anotação"
                        onClick={async () => {
                          if (!window.confirm('Apagar esta anotação?')) return;
                          if (await executar(() => rpc('admin_apagar_nota', { p_id: n.id }), 'Anotação apagada.')) recarregar();
                        }}>
                        <Trash2 />
                      </button>
                    ) : null}
                  </div>
                  <div className="nota-texto">{n.texto}</div>
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  );
}
