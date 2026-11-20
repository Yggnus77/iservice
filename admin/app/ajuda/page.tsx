'use client';

import { useMemo, useState } from 'react';
import { EyeOff, LifeBuoy, Pencil, Plus, Trash2 } from 'lucide-react';
import { Cabecalho } from '@/components/Painel';
import { Abas, Carregando, Dialogo, ErroCaixa, Interruptor, Selo, Vazio, useAcao, useCarregar } from '@/components/ui';
import { db, rpc } from '@/lib/supabase';

type Publico = 'cliente' | 'profissional' | 'todos';
type Pergunta = { id: number; publico: Publico; categoria: string; pergunta: string; resposta: string; ordem: number; ativa: boolean };

const PUBLICOS: Record<Publico, string> = { cliente: 'Clientes', profissional: 'Profissionais', todos: 'Todos' };

function Editor({ p, fechar, salvo }: { p: Partial<Pergunta> | null; fechar: () => void; salvo: () => void }) {
  const [f, setF] = useState<Partial<Pergunta>>(p ?? {});
  const { executar, ocupado } = useAcao();
  const muda = <K extends keyof Pergunta>(k: K, v: Pergunta[K]) => setF((x) => ({ ...x, [k]: v }));
  // Reabre com os dados certos a cada pergunta escolhida.
  const chave = p ? `${p.id ?? 'nova'}` : '';
  const [ultima, setUltima] = useState(chave);
  if (chave !== ultima) { setUltima(chave); setF(p ?? {}); }

  const salvar = async () => {
    const ok = await executar(() => rpc('admin_salvar_pergunta', {
      p_id: f.id ?? null, p_publico: f.publico ?? 'todos', p_categoria: f.categoria ?? 'Geral', p_pergunta: f.pergunta ?? '',
      p_resposta: f.resposta ?? '', p_ordem: f.ordem ?? 100, p_ativa: f.ativa ?? true,
    }), 'Pergunta salva. Já aparece nos apps.');
    if (ok) { salvo(); fechar(); }
  };

  return (
    <Dialogo aberto={!!p} fechar={fechar} titulo={f.id ? 'Editar pergunta' : 'Nova pergunta'} largo icone={<LifeBuoy />}
      rodape={<><button className="botao fantasma" onClick={fechar}>Cancelar</button>
        <button className="botao primario" disabled={ocupado || (f.pergunta ?? '').trim().length < 5 || (f.resposta ?? '').trim().length < 5} onClick={salvar}>Salvar</button></>}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div className="grade g2">
          <div className="campo">
            <label htmlFor="aj-publico">Para quem</label>
            <select id="aj-publico" className="entrada" value={f.publico ?? 'todos'} onChange={(e) => muda('publico', e.target.value as Publico)}>
              <option value="cliente">Clientes</option><option value="profissional">Profissionais</option><option value="todos">Todos</option>
            </select>
          </div>
          <div className="campo">
            <label htmlFor="aj-cat">Assunto</label>
            <input id="aj-cat" className="entrada" maxLength={40} placeholder="Ex.: Pedidos, Pagamento, Segurança" value={f.categoria ?? ''} onChange={(e) => muda('categoria', e.target.value)} />
          </div>
        </div>
        <div className="campo">
          <label htmlFor="aj-perg">Pergunta</label>
          <input id="aj-perg" className="entrada" maxLength={200} value={f.pergunta ?? ''} onChange={(e) => muda('pergunta', e.target.value)} />
        </div>
        <div className="campo">
          <label htmlFor="aj-resp">Resposta</label>
          <textarea id="aj-resp" className="entrada" rows={6} maxLength={2000} value={f.resposta ?? ''} onChange={(e) => muda('resposta', e.target.value)} />
          <span className="ajuda">Escreva como se falasse com a pessoa: frases curtas e o caminho exato no app.</span>
        </div>
        <div className="linha-flex">
          <div className="campo" style={{ width: 140 }}>
            <label htmlFor="aj-ordem">Ordem</label>
            <input id="aj-ordem" className="entrada" type="number" min={0} max={999} value={f.ordem ?? 100} onChange={(e) => muda('ordem', Number(e.target.value))} />
          </div>
          <span className="espaco" />
          <span className="texto-suave">Aparece nos apps</span>
          <Interruptor ligado={f.ativa ?? true} mudar={(v) => muda('ativa', v)} rotulo="Aparece nos apps" />
        </div>
      </div>
    </Dialogo>
  );
}

export default function CentralDeAjuda() {
  const [aba, setAba] = useState<Publico | 'tudo'>('tudo');
  const { dados, erro, carregando, recarregar } = useCarregar(async () => {
    const { data, error } = await db().from('ajuda_perguntas').select('*').order('ordem').order('id');
    if (error) throw error;
    return data as Pergunta[];
  }, []);
  const [editar, setEditar] = useState<Partial<Pergunta> | null>(null);
  const [apagar, setApagar] = useState<Pergunta | null>(null);
  const { executar, ocupado } = useAcao();
  const lista = useMemo(() => (dados ?? []).filter((p) => aba === 'tudo' || p.publico === aba || p.publico === 'todos'), [dados, aba]);

  return (
    <>
      <Cabecalho titulo="Central de Ajuda" texto="Perguntas frequentes que aparecem nos apps e no site, antes do botão de falar com o suporte."
        ajuda={<>Uma boa Central de Ajuda resolve muitas dúvidas sem precisar de atendente. Quando a mesma pergunta chegar três vezes por e-mail ou WhatsApp, vale virar uma pergunta aqui.</>}
        acoes={<button className="botao primario" onClick={() => setEditar({ publico: 'todos', categoria: 'Geral', ordem: 100, ativa: true })}><Plus /> Nova pergunta</button>} />
      <div className="filtros">
        <Abas ativa={aba} mudar={setAba} abas={[{ id: 'tudo', rotulo: 'Todas' }, { id: 'cliente', rotulo: 'Clientes' }, { id: 'profissional', rotulo: 'Profissionais' }]} />
      </div>
      {erro ? <ErroCaixa erro={erro} tentar={recarregar} /> : carregando && !dados ? <Carregando /> : !lista.length ? (
        <section className="cartao"><Vazio icone={<LifeBuoy size={24} />} titulo="Nenhuma pergunta ainda" texto="Crie a primeira com o botão Nova pergunta." /></section>
      ) : (
        <div className="pilha">
          {lista.map((p) => (
            <section className="cartao" key={p.id} style={p.ativa ? undefined : { opacity: 0.7 }}>
              <div className="titulo">
                <div><h2>{p.pergunta}</h2><p>{p.categoria} · ordem {p.ordem}</p></div>
                <div className="linha-flex" style={{ gap: 6 }}>
                  {!p.ativa ? <Selo tom="neutro" icone={<EyeOff />}>Escondida</Selo> : null}
                  <Selo tom={p.publico === 'profissional' ? 'laranja' : p.publico === 'cliente' ? 'azul' : 'roxo'}>{PUBLICOS[p.publico]}</Selo>
                </div>
              </div>
              <div className="corpo" style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                <div style={{ whiteSpace: 'pre-wrap' }}>{p.resposta}</div>
                <div className="linha-flex">
                  <span className="espaco" />
                  <button className="botao fantasma pequeno" onClick={() => setApagar(p)}><Trash2 /> Apagar</button>
                  <button className="botao contorno pequeno" onClick={() => setEditar(p)}><Pencil /> Editar</button>
                </div>
              </div>
            </section>
          ))}
        </div>
      )}
      <Editor p={editar} fechar={() => setEditar(null)} salvo={recarregar} />
      <Dialogo aberto={!!apagar} fechar={() => setApagar(null)} titulo="Apagar esta pergunta?" texto={apagar?.pergunta}
        rodape={<><button className="botao fantasma" onClick={() => setApagar(null)}>Cancelar</button>
          <button className="botao perigo" disabled={ocupado} onClick={async () => {
            if (await executar(() => rpc('admin_apagar_pergunta', { p_id: apagar!.id }), 'Pergunta apagada.')) { setApagar(null); recarregar(); }
          }}>Apagar</button></>}>
        <p className="texto-suave" style={{ margin: 0 }}>Se só quiser tirar dos apps por um tempo, edite e desligue “Aparece nos apps”.</p>
      </Dialogo>
    </>
  );
}
