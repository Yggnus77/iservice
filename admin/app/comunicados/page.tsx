'use client';

import { useEffect, useState } from 'react';
import { Bell, Loader2, Megaphone, Send, Users } from 'lucide-react';
import { Cabecalho } from '@/components/Painel';
import { Carregando, Dialogo, ErroCaixa, Selo, Vazio, useAcao, useAviso, useCarregar } from '@/components/ui';
import { db, rpc } from '@/lib/supabase';
import { dataHora, numero } from '@/lib/formatos';

type Comunicado = { id: number; titulo: string; corpo: string; profissao: string | null; regiao: string | null; publico: string; destinatarios: number; admin: string | null; criado_em: string };
type Opcao = { id: string; nome: string };

const publicos: Record<string, string> = {
  aprovados: 'Profissionais aprovados',
  disponiveis: 'Aprovados e disponíveis agora',
  em_analise: 'Cadastros ainda não aprovados',
  todos: 'Todos os profissionais',
};

export default function Comunicados() {
  const opcoes = useCarregar(async () => {
    const [p, r] = await Promise.all([
      db().from('profissoes').select('id, nome').order('ordem'),
      db().from('regioes').select('id, nome').order('ordem'),
    ]);
    return { profissoes: (p.data ?? []) as Opcao[], regioes: (r.data ?? []) as Opcao[] };
  }, []);
  const historico = useCarregar(() => rpc<Comunicado[]>('admin_comunicados'), []);
  const [profissao, setProfissao] = useState('');
  const [regiao, setRegiao] = useState('');
  const [publico, setPublico] = useState('aprovados');
  const [titulo, setTitulo] = useState('');
  const [corpo, setCorpo] = useState('');
  const [alcance, setAlcance] = useState<number | null>(null);
  const [confirmar, setConfirmar] = useState(false);
  const { executar, ocupado } = useAcao();
  const avisar = useAviso();

  useEffect(() => {
    setAlcance(null);
    const t = setTimeout(() => {
      rpc<number>('admin_contar_publico', { p_profissao: profissao || null, p_regiao: regiao || null, p_publico: publico }).then(setAlcance).catch(() => setAlcance(null));
    }, 250);
    return () => clearTimeout(t);
  }, [profissao, regiao, publico]);

  const nomeProf = opcoes.dados?.profissoes.find((p) => p.id === profissao)?.nome;
  const nomeReg = opcoes.dados?.regioes.find((r) => r.id === regiao)?.nome;
  const grupo = [publicos[publico], nomeProf && `de ${nomeProf}`, nomeReg && `em ${nomeReg}`].filter(Boolean).join(' ');

  const enviar = async () => {
    let n = 0;
    const ok = await executar(async () => { n = await rpc<number>('admin_enviar_comunicado', {
      p_titulo: titulo, p_corpo: corpo, p_profissao: profissao || null, p_regiao: regiao || null, p_publico: publico,
    }); });
    setConfirmar(false);
    if (ok) {
      setTitulo(''); setCorpo('');
      historico.recarregar();
      avisar(`Comunicado enviado para ${n} ${n === 1 ? 'profissional' : 'profissionais'}.`);
    }
  };

  return (
    <>
      <Cabecalho titulo="Comunicados" texto="Envie um aviso para um grupo de profissionais, por exemplo os eletricistas de Ceilândia." />
      <div className="grade lado">
        <section className="cartao">
          <div className="titulo"><div><h2>Novo comunicado</h2><p>Chega como notificação dentro do app Profissional.</p></div></div>
          <div className="corpo" style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            <div className="grade g3">
              <div className="campo">
                <label htmlFor="c-prof">Profissão</label>
                <select id="c-prof" className="entrada" value={profissao} onChange={(e) => setProfissao(e.target.value)}>
                  <option value="">Todas</option>
                  {opcoes.dados?.profissoes.map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}
                </select>
              </div>
              <div className="campo">
                <label htmlFor="c-reg">Região</label>
                <select id="c-reg" className="entrada" value={regiao} onChange={(e) => setRegiao(e.target.value)}>
                  <option value="">Brasília e Entorno (todas)</option>
                  {opcoes.dados?.regioes.map((r) => <option key={r.id} value={r.id}>{r.nome}</option>)}
                </select>
              </div>
              <div className="campo">
                <label htmlFor="c-pub">Quem recebe</label>
                <select id="c-pub" className="entrada" value={publico} onChange={(e) => setPublico(e.target.value)}>
                  {Object.entries(publicos).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </div>
            </div>
            <div className="alerta-faixa azul" style={{ margin: 0 }}>
              <Users />
              <div><strong>{alcance === null ? 'Contando…' : `${numero(alcance)} ${alcance === 1 ? 'profissional recebe' : 'profissionais recebem'}`}</strong>{grupo}</div>
            </div>
            <div className="campo">
              <label htmlFor="c-tit">Título</label>
              <input id="c-tit" className="entrada" maxLength={120} value={titulo} onChange={(e) => setTitulo(e.target.value)} placeholder="Ex.: Muitos pedidos previstos para sábado" />
            </div>
            <div className="campo">
              <label htmlFor="c-corpo">Mensagem</label>
              <textarea id="c-corpo" className="entrada" maxLength={1000} value={corpo} onChange={(e) => setCorpo(e.target.value)}
                placeholder="Ex.: Fique disponível no app entre 8h e 18h para receber mais pedidos na sua região." />
              <span className="ajuda">{corpo.length}/1000</span>
            </div>
            <button className="botao primario" style={{ alignSelf: 'flex-end' }} disabled={!titulo.trim() || !corpo.trim() || !alcance} onClick={() => setConfirmar(true)}>
              <Send /> Revisar e enviar
            </button>
          </div>
        </section>

        <section className="cartao">
          <div className="titulo"><div><h2>Prévia</h2><p>Como aparece no celular.</p></div></div>
          <div className="corpo">
            <div style={{ background: 'var(--azul-escuro)', borderRadius: 18, padding: 16 }}>
              <div style={{ background: '#fff', borderRadius: 14, padding: 14, display: 'flex', gap: 12 }}>
                <span style={{ width: 38, height: 38, borderRadius: 10, background: 'var(--laranja-suave)', color: 'var(--laranja-texto)', display: 'grid', placeItems: 'center', flex: 'none' }}><Bell size={18} /></span>
                <div style={{ minWidth: 0 }}>
                  <strong style={{ display: 'block' }}>{titulo || 'Título do comunicado'}</strong>
                  <span className="texto-suave" style={{ whiteSpace: 'pre-wrap' }}>{corpo || 'A mensagem aparece aqui.'}</span>
                </div>
              </div>
            </div>
            <p className="texto-fraco" style={{ marginTop: 12 }}>Por enquanto o aviso fica nas notificações do app. Quando o envio de push estiver ligado, chega também com o celular bloqueado.</p>
          </div>
        </section>
      </div>

      <section className="cartao" style={{ marginTop: 18 }}>
        <div className="titulo"><div><h2>Enviados</h2></div></div>
        <div className="corpo sem-espaco">
          {historico.erro ? <div style={{ padding: 16 }}><ErroCaixa erro={historico.erro} tentar={historico.recarregar} /></div> : historico.carregando && !historico.dados ? <Carregando /> :
            !historico.dados?.length ? <Vazio icone={<Megaphone size={24} />} titulo="Nenhum comunicado enviado ainda" /> : (
              <div className="tabela-rolagem">
                <table className="tabela">
                  <thead><tr><th>Comunicado</th><th>Grupo</th><th className="num">Recebeu</th><th>Por</th><th>Quando</th></tr></thead>
                  <tbody>
                    {historico.dados.map((c) => (
                      <tr key={c.id}>
                        <td><strong>{c.titulo}</strong><div className="fraco" style={{ maxWidth: 420, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{c.corpo}</div></td>
                        <td><div className="linha-flex" style={{ gap: 6 }}><Selo>{publicos[c.publico] ?? c.publico}</Selo>{c.profissao ? <Selo tom="azul">{c.profissao}</Selo> : null}{c.regiao ? <Selo tom="roxo">{c.regiao}</Selo> : null}</div></td>
                        <td className="num">{numero(c.destinatarios)}</td>
                        <td>{c.admin ?? '—'}</td>
                        <td className="fraco">{dataHora(c.criado_em)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
        </div>
      </section>

      <Dialogo aberto={confirmar} fechar={() => setConfirmar(false)} titulo={`Enviar para ${numero(alcance ?? 0)} ${alcance === 1 ? 'profissional' : 'profissionais'}?`}
        texto={<>{grupo}. Depois de enviado não dá para desfazer.</>}
        rodape={<>
          <button className="botao contorno" onClick={() => setConfirmar(false)}>Voltar</button>
          <button className="botao primario" disabled={ocupado} onClick={enviar}>{ocupado ? <Loader2 className="girar" /> : <Send />} Enviar agora</button>
        </>}>
        <div className="citacao"><strong>{titulo}</strong>{'\n'}{corpo}</div>
      </Dialogo>
    </>
  );
}
