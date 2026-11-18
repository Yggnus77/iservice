'use client';

import { useState, type ReactNode } from 'react';
import {
  ArrowRightLeft, BriefcaseBusiness, Camera, Copy, Crown, Headset, Hourglass, KeyRound, Loader2, Mail, MailCheck, Megaphone, MessageCircle,
  ShieldCheck, ShieldUser, Trash2, UserCog, UserPlus, UsersRound,
} from 'lucide-react';
import { Cabecalho, usePainel, type Cargo } from '@/components/Painel';
import { DialogoFoto } from '@/components/FotoPerfil';
import { Carregando, Dialogo, ErroCaixa, Pessoa, Selo, Vazio, useAcao, useAviso, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { data, haQuanto, type Tom } from '@/lib/formatos';

type Membro = {
  email: string; nome: string; papel: Cargo; cargo_nome?: string; usuario_id: string | null; foto_url: string | null;
  situacao: 'ativo' | 'convite_pendente'; convidado_por: string | null; convidado_em: string; entrou_em: string | null;
  ultimo_acesso: string | null; voce: boolean; pode_gerir?: boolean; pode_foto?: boolean;
};

/** Os cargos, na ordem em que aparecem. O que cada um pode fazer é conferido também no banco. */
const cargos: { id: Cargo; nome: string; tom: Tom; icone: ReactNode; resumo: string }[] = [
  { id: 'dono', nome: 'Dono', tom: 'azul', icone: <Crown />, resumo: 'Tudo, inclusive Configurações e os gerentes.' },
  { id: 'gerente', nome: 'Gerente geral', tom: 'roxo', icone: <BriefcaseBusiness />,
    resumo: 'Operação, Crescimento, Profissões, Preços e Comunicados. Convida e remove Responsáveis, Suporte e Marketing. Não entra em Configurações.' },
  { id: 'responsavel', nome: 'Responsável de setor', tom: 'verde', icone: <ShieldUser />,
    resumo: 'Toda a Operação: e-mails de todos, aprova cadastros, decide a Garantia, resolve denúncias e suspende contas. Vê o próprio time na Equipe.' },
  { id: 'suporte', nome: 'Suporte', tom: 'laranja', icone: <Headset />,
    resumo: 'Atende os próprios e-mails e as emergências, consulta pedidos e pessoas e registra reclamações. CPF e documentos aparecem mascarados.' },
  { id: 'marketing', nome: 'Marketing', tom: 'neutro', icone: <Megaphone />,
    resumo: 'Buscas e mapa, Site e downloads, Avaliações e Comunicados. Não vê dados pessoais.' },
];
const cargoDe = (id: Cargo) => cargos.find((c) => c.id === id) ?? cargos[3];
const nivel: Record<Cargo, number> = { dono: 4, gerente: 3, responsavel: 2, suporte: 1, marketing: 1 };

function SeloCargo({ papel }: { papel: Cargo }) {
  const c = cargoDe(papel);
  return <Selo tom={c.tom} icone={c.icone}>{c.nome}</Selo>;
}

/** Lista de cargos para escolher, com o que cada um faz. */
function EscolherCargo({ opcoes, valor, mudar }: { opcoes: Cargo[]; valor: Cargo; mudar: (c: Cargo) => void }) {
  return (
    <div role="radiogroup" aria-label="Cargo" style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      {cargos.filter((c) => opcoes.includes(c.id)).map((c) => (
        <label key={c.id} className={`opcao-cargo ${valor === c.id ? 'marcada' : ''}`}>
          <input type="radio" name="cargo" value={c.id} checked={valor === c.id} onChange={() => mudar(c.id)} />
          <span className={`icone-cargo ${c.tom}`}>{c.icone}</span>
          <span><strong>{c.nome}</strong><small>{c.resumo}</small></span>
        </label>
      ))}
    </div>
  );
}

const ENDERECO = 'https://iservice.app.br/admin/';

function mensagemConvite(m: { nome: string; email: string; situacao: Membro['situacao']; papel?: Cargo }) {
  const primeiro = m.nome.trim().split(/\s+/)[0];
  const cargo = m.papel ? ` como ${cargoDe(m.papel).nome}` : '';
  if (m.situacao === 'ativo') {
    return `Olá, ${primeiro}! Seu acesso ao painel da equipe iService foi liberado.\n\n` +
      `Entre em ${ENDERECO} com o e-mail ${m.email} e a senha que você já usa no iService.`;
  }
  return `Olá, ${primeiro}! Você foi convidado(a) para a equipe do iService${cargo}.\n\n` +
    `1. Acesse ${ENDERECO}\n` +
    `2. Toque em "Primeiro acesso" e crie a sua senha usando este e-mail: ${m.email}\n` +
    `3. Abra o e-mail de confirmação que vamos te enviar.\n\n` +
    `Pronto: o painel abre com o seu acesso.`;
}

function Compartilhar({ m }: { m: { nome: string; email: string; situacao: Membro['situacao']; papel?: Cargo } }) {
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
  const [cargoNovo, setCargoNovo] = useState<Cargo>('suporte');
  const [enviar, setEnviar] = useState<{ nome: string; email: string; situacao: Membro['situacao']; papel?: Cargo; novo?: boolean } | null>(null);
  const [remover, setRemover] = useState<Membro | null>(null);
  const [foto, setFoto] = useState<Membro | null>(null);
  const [mudar, setMudar] = useState<Membro | null>(null);
  const [cargoMudar, setCargoMudar] = useState<Cargo>('suporte');
  const [passarDono, setPassarDono] = useState(false);
  const [novoDono, setNovoDono] = useState('');
  const painel = usePainel();
  const meuCargo: Cargo = painel.acesso?.cargo ?? 'dono';
  const podeGerirEquipe = painel.pode('equipe_gerir');
  // Cargos que eu posso dar: só os abaixo do meu (o dono passa a posição por um botão próprio).
  const cargosQuePossoDar = cargos.map((c) => c.id).filter((c) => c !== 'dono' && nivel[meuCargo] > nivel[c]);
  // A própria foto sempre; a de um colega conforme o cargo (o banco confere de novo).
  const podeFoto = (m: Membro) => !!m.usuario_id && (m.voce || (m.pode_foto ?? (m.papel !== 'dono' && m.situacao === 'ativo')));
  const podeGerir = (m: Membro) => !m.voce && (m.pode_gerir ?? m.papel !== 'dono');
  const candidatosDono = dados?.filter((m) => !m.voce && m.situacao === 'ativo') ?? [];

  const ativos = dados?.filter((m) => m.situacao === 'ativo').length ?? 0;
  const pendentes = dados?.filter((m) => m.situacao === 'convite_pendente').length ?? 0;
  const emailOk = /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim());

  const criarConvite = async () => {
    let situacao: Membro['situacao'] = 'convite_pendente';
    const ok = await executar(async () => {
      situacao = await rpc<Membro['situacao']>('admin_convidar_equipe', { p_email: email.trim(), p_nome: nome.trim(), p_cargo: cargoNovo });
    });
    if (!ok) return;
    setConvidar(false);
    setEnviar({ nome: nome.trim(), email: email.trim().toLowerCase(), situacao, papel: cargoNovo, novo: true });
    setNome(''); setEmail(''); setCargoNovo('suporte');
    recarregar();
  };

  const abrirMudar = (m: Membro) => { setCargoMudar(m.papel === 'dono' ? 'gerente' : m.papel); setMudar(m); };
  const confirmarMudar = async () => {
    if (!mudar) return;
    const ok = await executar(() => rpc('admin_mudar_cargo', { p_email: mudar.email, p_cargo: cargoMudar }),
      `${mudar.nome} agora é ${cargoDe(cargoMudar).nome}.`);
    if (ok) { setMudar(null); recarregar(); }
  };

  const confirmarPassarDono = async () => {
    const alvo = candidatosDono.find((m) => m.email === novoDono);
    if (!alvo) return;
    const ok = await executar(() => rpc('admin_transferir_dono', { p_email: alvo.email }),
      `${alvo.nome} agora é o dono do painel. Você passou a Gerente geral.`);
    if (ok) { setPassarDono(false); window.location.reload(); }
  };

  const confirmarRemocao = async () => {
    if (!remover) return;
    const ok = await executar(() => rpc('admin_remover_equipe', { p_email: remover.email }),
      remover.situacao === 'ativo' ? `${remover.nome} não tem mais acesso ao painel.` : 'Convite cancelado.');
    if (ok) { setRemover(null); recarregar(); }
  };

  return (
    <>
      <Cabecalho ajuda={<>Quem da equipe tem acesso ao painel e com qual cargo. Cada cargo vê só o que precisa (o Suporte não vê documentos, o Marketing não vê dados pessoais). Convide pelo e-mail: a pessoa cria a senha no primeiro acesso.</>} titulo="Equipe"
        texto={meuCargo === 'responsavel' ? 'O seu time de Atendimento. Cada pessoa tem o próprio login e o acesso do próprio cargo.'
          : 'Cada pessoa tem o próprio login e vê só o que o cargo dela permite.'}
        acoes={<>
          {meuCargo === 'dono' && painel.acesso ? (
            <button className="botao contorno" onClick={() => { setNovoDono(''); setPassarDono(true); }}><ArrowRightLeft /> Passar a posição de dono</button>
          ) : null}
          {podeGerirEquipe ? <button className="botao primario" onClick={() => { setCargoNovo('suporte'); setConvidar(true); }}><UserPlus /> Convidar pessoa</button> : null}
        </>} />

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
                  <thead><tr><th>Pessoa</th><th>Cargo</th><th>Situação</th><th>Último acesso</th><th /></tr></thead>
                  <tbody>
                    {dados.map((m) => (
                      <tr key={m.email}>
                        <td><Pessoa nome={m.voce ? `${m.nome} (você)` : m.nome} foto={m.voce ? painel.foto : m.foto_url} sub={m.email} /></td>
                        <td><SeloCargo papel={m.papel} /></td>
                        <td>
                          <div className="linha-flex" style={{ gap: 6 }}>
                            {m.situacao === 'ativo' ? <Selo tom="verde" icone={<ShieldCheck />}>Com acesso</Selo> : <Selo tom="laranja" icone={<Hourglass />}>Aguardando primeiro acesso</Selo>}
                          </div>
                          {m.papel !== 'dono' ? <div className="texto-fraco" style={{ marginTop: 4 }}>Convidado em {data(m.convidado_em)}{m.convidado_por ? ` por ${m.convidado_por}` : ''}</div> : null}
                        </td>
                        <td className="fraco" style={{ whiteSpace: 'nowrap' }}>{m.ultimo_acesso ? haQuanto(m.ultimo_acesso) : 'Nunca'}</td>
                        <td>
                          <div className="linha-flex" style={{ gap: 6, justifyContent: 'flex-end', flexWrap: 'wrap', maxWidth: 300, marginLeft: 'auto' }}>
                            {podeFoto(m) ? (
                              <button className="botao contorno pequeno" onClick={() => setFoto(m)}
                                title={m.voce ? 'Sua foto de perfil' : `Foto de perfil de ${m.nome}`} aria-label={m.voce ? 'Trocar sua foto de perfil' : `Trocar a foto de ${m.nome}`}>
                                <Camera /> Foto
                              </button>
                            ) : null}
                            {podeGerir(m) && painel.acesso ? (
                              <button className="botao contorno pequeno" onClick={() => abrirMudar(m)} title="Mudar o cargo" aria-label={`Mudar o cargo de ${m.nome}`}>
                                <UserCog /> Cargo
                              </button>
                            ) : null}
                            {podeGerir(m) ? (
                              <button className="botao contorno pequeno" onClick={() => setEnviar(m)} title="Mandar as instruções de acesso">
                                <MailCheck /> {m.situacao === 'ativo' ? 'Instruções' : 'Reenviar'}
                              </button>
                            ) : null}
                            {podeGerir(m) ? (
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
              <div>Cada um vê e faz só o que o cargo permite, e o banco confere isso em cada ação. Tudo fica no Registro da equipe com o nome de quem fez. Se a pessoa já tem conta no app com esse e-mail, o acesso sai na hora.</div>
            </div>
          </div>
        </section>

        <section className="cartao">
          <div className="titulo"><div><h2>Cargos</h2><p>O que cada cargo vê e pode fazer no painel.</p></div></div>
          <div className="corpo">
            <ul className="lista-cargos">
              {cargos.map((c) => (
                <li key={c.id}>
                  <span className={`icone-cargo ${c.tom}`}>{c.icone}</span>
                  <div><strong>{c.nome}{c.id === meuCargo && painel.acesso ? <span className="texto-fraco"> · seu cargo</span> : null}</strong><p>{c.resumo}</p></div>
                </li>
              ))}
            </ul>
          </div>
        </section>
      </div>

      <Dialogo aberto={convidar} fechar={() => setConvidar(false)} titulo="Convidar para a equipe" icone={<UserPlus />}
        texto="Escolha o cargo: a pessoa vê só o que ele permite. Dá para mudar depois."
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
          {painel.acesso ? (
            <div className="campo">
              <span className="rotulo">Cargo</span>
              <EscolherCargo opcoes={cargosQuePossoDar} valor={cargoNovo} mudar={setCargoNovo} />
            </div>
          ) : null}
          <button type="submit" hidden />
        </form>
      </Dialogo>

      <Dialogo aberto={!!enviar} fechar={() => setEnviar(null)} largo icone={<MailCheck />}
        titulo={enviar?.novo ? (enviar.situacao === 'ativo' ? `Acesso liberado para ${enviar.nome}` : `Convite criado para ${enviar?.nome}`) : `Instruções para ${enviar?.nome}`}
        texto={enviar?.situacao === 'ativo' ? 'Este e-mail já tinha conta iService, então o acesso já está valendo.' : 'Mande a mensagem abaixo. O acesso é liberado quando a pessoa criar a senha e confirmar o e-mail.'}
        rodape={<button className="botao primario" onClick={() => setEnviar(null)}>Concluir</button>}>
        {enviar ? <Compartilhar m={enviar} /> : null}
      </Dialogo>

      <Dialogo aberto={!!mudar} fechar={() => setMudar(null)} titulo={`Cargo de ${mudar?.nome ?? ''}`} icone={<UserCog />}
        texto="O novo acesso vale na próxima vez que a pessoa abrir ou recarregar o painel."
        rodape={<>
          <button className="botao contorno" onClick={() => setMudar(null)}>Cancelar</button>
          <button className="botao primario" disabled={ocupado || cargoMudar === mudar?.papel} onClick={confirmarMudar}>
            {ocupado ? <Loader2 className="girar" /> : <UserCog />} Salvar cargo
          </button>
        </>}>
        <EscolherCargo opcoes={cargosQuePossoDar} valor={cargoMudar} mudar={setCargoMudar} />
      </Dialogo>

      <Dialogo aberto={passarDono} fechar={() => setPassarDono(false)} titulo="Passar a posição de dono" icone={<Crown />}
        texto="A pessoa escolhida vira a dona do painel, com Configurações e os gerentes. Você passa a Gerente geral e não consegue desfazer sozinho."
        rodape={<>
          <button className="botao contorno" onClick={() => setPassarDono(false)}>Cancelar</button>
          <button className="botao perigo" disabled={ocupado || !novoDono} onClick={confirmarPassarDono}>
            {ocupado ? <Loader2 className="girar" /> : <Crown />} Passar a posição
          </button>
        </>}>
        {candidatosDono.length ? (
          <div className="campo">
            <label htmlFor="novo-dono">Novo dono</label>
            <select id="novo-dono" className="entrada" value={novoDono} onChange={(e) => setNovoDono(e.target.value)}>
              <option value="">Escolha alguém da equipe</option>
              {candidatosDono.map((m) => <option key={m.email} value={m.email}>{m.nome} · {cargoDe(m.papel).nome}</option>)}
            </select>
          </div>
        ) : <p className="texto-fraco">Só dá para passar para alguém da equipe que já fez o primeiro acesso.</p>}
      </Dialogo>

      <DialogoFoto
        pessoa={foto?.usuario_id ? { id: foto.usuario_id, nome: foto.nome, foto: foto.voce ? painel.foto : foto.foto_url } : null}
        propria={!!foto?.voce} fechar={() => setFoto(null)}
        salvo={(url) => { if (foto?.voce) painel.mudarFoto(url); recarregar(); }} />

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
