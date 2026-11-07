'use client';

import { useState } from 'react';
import { Copy, Crown, Hourglass, KeyRound, Loader2, Mail, MailCheck, MessageCircle, ShieldCheck, Trash2, UserPlus, UsersRound } from 'lucide-react';
import { Cabecalho } from '@/components/Painel';
import { Carregando, Dialogo, ErroCaixa, Pessoa, Selo, Vazio, useAcao, useAviso, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { data, haQuanto } from '@/lib/formatos';

type Membro = {
  email: string; nome: string; papel: 'dono' | 'suporte'; usuario_id: string | null; foto_url: string | null;
  situacao: 'ativo' | 'convite_pendente'; convidado_por: string | null; convidado_em: string; entrou_em: string | null;
  ultimo_acesso: string | null; voce: boolean;
};

const ENDERECO = 'https://iservice.app.br/admin/';

function mensagemConvite(m: { nome: string; email: string; situacao: Membro['situacao'] }) {
  const primeiro = m.nome.trim().split(/\s+/)[0];
  if (m.situacao === 'ativo') {
    return `Olá, ${primeiro}! Seu acesso ao painel da equipe iService foi liberado.\n\n` +
      `Entre em ${ENDERECO} com o e-mail ${m.email} e a senha que você já usa no iService.`;
  }
  return `Olá, ${primeiro}! Você foi convidado(a) para a equipe de suporte do iService.\n\n` +
    `1. Acesse ${ENDERECO}\n` +
    `2. Toque em "Primeiro acesso" e crie a sua senha usando este e-mail: ${m.email}\n` +
    `3. Abra o e-mail de confirmação que vamos te enviar.\n\n` +
    `Pronto: o painel abre com o seu acesso.`;
}

function Compartilhar({ m }: { m: { nome: string; email: string; situacao: Membro['situacao'] } }) {
  const avisar = useAviso();
  const texto = mensagemConvite(m);
  const copiar = async () => {
    try { await navigator.clipboard.writeText(texto); avisar('Mensagem copiada.'); } catch { avisar('Não foi possível copiar. Selecione o texto e copie.', true); }
  };
  return (
    <>
      <div className="citacao" style={{ whiteSpace: 'pre-wrap' }}>{texto}</div>
      <div className="linha-flex" style={{ marginTop: 12 }}>
        <a className="botao sucesso" href={`https://wa.me/?text=${encodeURIComponent(texto)}`} target="_blank" rel="noreferrer"><MessageCircle /> WhatsApp</a>
        <a className="botao contorno" href={`mailto:${m.email}?subject=${encodeURIComponent('Seu acesso à equipe iService')}&body=${encodeURIComponent(texto)}`}><Mail /> E-mail</a>
        <button className="botao contorno" onClick={copiar}><Copy /> Copiar</button>
      </div>
    </>
  );
}

export default function Equipe() {
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Membro[]>('admin_equipe'), []);
  const { executar, ocupado } = useAcao();
  const [convidar, setConvidar] = useState(false);
  const [nome, setNome] = useState('');
  const [email, setEmail] = useState('');
  const [enviar, setEnviar] = useState<{ nome: string; email: string; situacao: Membro['situacao']; novo?: boolean } | null>(null);
  const [remover, setRemover] = useState<Membro | null>(null);

  const ativos = dados?.filter((m) => m.situacao === 'ativo').length ?? 0;
  const pendentes = dados?.filter((m) => m.situacao === 'convite_pendente').length ?? 0;
  const emailOk = /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim());

  const criarConvite = async () => {
    let situacao: Membro['situacao'] = 'convite_pendente';
    const ok = await executar(async () => {
      situacao = await rpc<Membro['situacao']>('admin_convidar_equipe', { p_email: email.trim(), p_nome: nome.trim() });
    });
    if (!ok) return;
    setConvidar(false);
    setEnviar({ nome: nome.trim(), email: email.trim().toLowerCase(), situacao, novo: true });
    setNome(''); setEmail('');
    recarregar();
  };

  const confirmarRemocao = async () => {
    if (!remover) return;
    const ok = await executar(() => rpc('admin_remover_equipe', { p_email: remover.email }),
      remover.situacao === 'ativo' ? `${remover.nome} não tem mais acesso ao painel.` : 'Convite cancelado.');
    if (ok) { setRemover(null); recarregar(); }
  };

  return (
    <>
      <Cabecalho titulo="Equipe" texto="Pessoas do suporte com o mesmo acesso que você ao painel, cada uma com o próprio login."
        acoes={<button className="botao primario" onClick={() => setConvidar(true)}><UserPlus /> Convidar pessoa</button>} />

      <div className="grade">
        <section className="cartao">
          <div className="titulo">
            <div>
              <h2>Quem tem acesso</h2>
              <p>{dados ? `${ativos} com acesso${pendentes ? ` · ${pendentes} ${pendentes === 1 ? 'convite aguardando' : 'convites aguardando'}` : ''}` : ' '}</p>
            </div>
          </div>
          <div className="corpo sem-espaco">
            {erro ? <div style={{ padding: 16 }}><ErroCaixa erro={erro} tentar={recarregar} /></div> : carregando && !dados ? <Carregando /> : !dados?.length ? (
              <Vazio icone={<UsersRound size={24} />} titulo="Ninguém na equipe ainda" texto="Convide a primeira pessoa do suporte." />
            ) : (
              <div className="tabela-rolagem">
                <table className="tabela">
                  <thead><tr><th>Pessoa</th><th>Situação</th><th>Último acesso</th><th /></tr></thead>
                  <tbody>
                    {dados.map((m) => (
                      <tr key={m.email}>
                        <td><Pessoa nome={m.voce ? `${m.nome} (você)` : m.nome} foto={m.foto_url} sub={m.email} /></td>
                        <td>
                          <div className="linha-flex" style={{ gap: 6 }}>
                            {m.papel === 'dono' ? <Selo tom="azul" icone={<Crown />}>Dono</Selo> : null}
                            {m.situacao === 'ativo' ? <Selo tom="verde" icone={<ShieldCheck />}>Com acesso</Selo> : <Selo tom="laranja" icone={<Hourglass />}>Aguardando primeiro acesso</Selo>}
                          </div>
                          {m.papel !== 'dono' ? <div className="texto-fraco" style={{ marginTop: 4 }}>Convidado em {data(m.convidado_em)}{m.convidado_por ? ` por ${m.convidado_por}` : ''}</div> : null}
                        </td>
                        <td className="fraco" style={{ whiteSpace: 'nowrap' }}>{m.ultimo_acesso ? haQuanto(m.ultimo_acesso) : 'Nunca'}</td>
                        <td>
                          <div className="linha-flex" style={{ gap: 6, justifyContent: 'flex-end', flexWrap: 'nowrap' }}>
                            {m.papel !== 'dono' ? (
                              <button className="botao contorno pequeno" onClick={() => setEnviar(m)} title="Mandar as instruções de acesso">
                                <MailCheck /> {m.situacao === 'ativo' ? 'Instruções' : 'Reenviar'}
                              </button>
                            ) : null}
                            {m.papel !== 'dono' && !m.voce ? (
                              <button className="botao fantasma pequeno" onClick={() => setRemover(m)} aria-label={`Remover ${m.nome}`} title="Remover da equipe"><Trash2 /></button>
                            ) : null}
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </section>

        <section className="cartao">
          <div className="titulo"><div><h2>Como a pessoa entra</h2><p>Cada um usa o próprio e-mail e senha.</p></div></div>
          <div className="corpo">
            <ol className="passos-equipe grade g3">
              <li><span>1</span><div><strong>Você convida</strong>Nome e e-mail da pessoa. Mande a mensagem pronta pelo WhatsApp ou e-mail.</div></li>
              <li><span>2</span><div><strong>Ela cria a senha</strong>Em iservice.app.br/admin, no botão “Primeiro acesso”, com o e-mail convidado.</div></li>
              <li><span>3</span><div><strong>Confirma o e-mail</strong>O acesso é liberado assim que ela abre o link de confirmação.</div></li>
            </ol>
            <div className="alerta-faixa azul" style={{ margin: '14px 0 0' }}>
              <KeyRound />
              <div>Todos da equipe veem e fazem o mesmo que você, e tudo fica no Registro da equipe com o nome de quem fez. Se a pessoa já tem conta no app com esse e-mail, o acesso sai na hora.</div>
            </div>
          </div>
        </section>
      </div>

      <Dialogo aberto={convidar} fechar={() => setConvidar(false)} titulo="Convidar para a equipe" icone={<UserPlus />}
        texto="A pessoa terá o mesmo acesso que você ao painel."
        rodape={<>
          <button className="botao contorno" onClick={() => setConvidar(false)}>Cancelar</button>
          <button className="botao primario" disabled={ocupado || nome.trim().length < 2 || !emailOk} onClick={criarConvite}>
            {ocupado ? <Loader2 className="girar" /> : <UserPlus />} Convidar
          </button>
        </>}>
        <form style={{ display: 'flex', flexDirection: 'column', gap: 14 }} onSubmit={(e) => { e.preventDefault(); if (nome.trim().length >= 2 && emailOk) criarConvite(); }}>
          <div className="campo">
            <label htmlFor="eq-nome">Nome</label>
            <input id="eq-nome" className="entrada" maxLength={80} value={nome} onChange={(e) => setNome(e.target.value)} placeholder="Ex.: Ana Souza" autoFocus />
          </div>
          <div className="campo">
            <label htmlFor="eq-email">E-mail</label>
            <input id="eq-email" className="entrada" type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="ana@exemplo.com" />
            <span className="ajuda">É com este e-mail que a pessoa vai entrar.</span>
          </div>
          <button type="submit" hidden />
        </form>
      </Dialogo>

      <Dialogo aberto={!!enviar} fechar={() => setEnviar(null)} largo icone={<MailCheck />}
        titulo={enviar?.novo ? (enviar.situacao === 'ativo' ? `Acesso liberado para ${enviar.nome}` : `Convite criado para ${enviar?.nome}`) : `Instruções para ${enviar?.nome}`}
        texto={enviar?.situacao === 'ativo' ? 'Este e-mail já tinha conta iService, então o acesso já está valendo.' : 'Mande a mensagem abaixo. O acesso é liberado quando a pessoa criar a senha e confirmar o e-mail.'}
        rodape={<button className="botao primario" onClick={() => setEnviar(null)}>Concluir</button>}>
        {enviar ? <Compartilhar m={enviar} /> : null}
      </Dialogo>

      <Dialogo aberto={!!remover} fechar={() => setRemover(null)} icone={<Trash2 />}
        titulo={remover?.situacao === 'ativo' ? `Remover ${remover?.nome} da equipe?` : `Cancelar o convite de ${remover?.nome}?`}
        texto={remover?.situacao === 'ativo' ? 'O acesso ao painel acaba na hora. A conta da pessoa no app continua existindo.' : 'O e-mail deixa de ter acesso ao painel, mesmo que a pessoa crie a senha depois.'}
        rodape={<>
          <button className="botao contorno" onClick={() => setRemover(null)}>Voltar</button>
          <button className="botao perigo" disabled={ocupado} onClick={confirmarRemocao}>{ocupado ? <Loader2 className="girar" /> : <Trash2 />} {remover?.situacao === 'ativo' ? 'Remover acesso' : 'Cancelar convite'}</button>
        </>} />
    </>
  );
}
