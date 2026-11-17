'use client';

import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  AlertTriangle, ArrowLeftRight, CheckCircle2, ChevronLeft, Code, Download, Inbox, Loader2, Mail, MailPlus, Paperclip,
  RotateCcw, Search, Send, Shuffle, StickyNote, UserCheck,
} from 'lucide-react';
import { Cabecalho, usePainel } from '@/components/Painel';
import { Abas, Avatar, Carregando, Dialogo, ErroCaixa, Interruptor, Pessoa, Selo, SeloStatus, Vazio, useAcao, useAviso, useCarregar } from '@/components/ui';
import { rpc, ErroPainel } from '@/lib/supabase';
import { urlArquivo } from '@/lib/arquivos';
import { dataHora, haQuanto } from '@/lib/formatos';
import {
  enviarEmail, separarCitacao, statusConversa, tamanhoArquivo,
  type Anexo, type Conversa, type ItemConversa, type Mensagem, type MembroRodizio, type StatusConversa,
} from '@/lib/suporte';

const ENDERECO = 'suporte@iservice.app.br';
const ATUALIZAR_MS = 30000;

// ------------------------------------------------------------------ lista
function ItemLista({ c, ativo, mostrarResponsavel, abrir }: { c: ItemConversa; ativo: boolean; mostrarResponsavel: boolean; abrir: () => void }) {
  const nome = c.contato_nome || c.contato_email;
  return (
    <button className={`caixa-item ${ativo ? 'ativo' : ''} ${c.nao_lida ? 'nao-lida' : ''}`} onClick={abrir} aria-current={ativo ? 'true' : undefined}>
      <Avatar nome={nome} foto={c.foto_url} tamanho={38} />
      <span className="caixa-item-meio">
        <span className="caixa-item-topo">
          <strong>{nome}</strong>
          <time dateTime={c.ultima_mensagem_em} title={dataHora(c.ultima_mensagem_em)}>{haQuanto(c.ultima_mensagem_em)}</time>
        </span>
        <span className="caixa-item-assunto">{c.assunto}</span>
        <span className="caixa-item-previa">{c.ultima_direcao === 'enviada' ? 'Você: ' : ''}{c.previa || 'Sem texto'}</span>
        <span className="caixa-item-rodape">
          <span className="mono">{c.protocolo}</span>
          {c.assunto.startsWith('Reclamação pelo site') ? <Selo tom="vermelho">Reclamação · site</Selo> : null}
          {c.usuario_id ? <Selo tom={c.e_profissional ? 'laranja' : 'azul'}>{c.e_profissional ? 'Profissional' : 'Cliente'}</Selo> : null}
          {mostrarResponsavel ? (c.responsavel_nome
            ? <span className="texto-fraco">{c.responsavel_nome.split(' ')[0]}</span>
            : <Selo tom="vermelho">Sem responsável</Selo>) : null}
        </span>
      </span>
      {c.nao_lida ? <span className="caixa-ponto" aria-label="Não lida" /> : null}
    </button>
  );
}

// ------------------------------------------------------------------ mensagens
function AnexoLink({ a }: { a: Anexo }) {
  const avisar = useAviso();
  const abrir = async () => {
    const url = await urlArquivo('suporte', a.caminho);
    if (url) window.open(url, '_blank', 'noopener');
    else avisar('Não foi possível abrir o anexo.', true);
  };
  if (!a.caminho) {
    return <span className="caixa-anexo indisponivel" title="Grande demais para guardar. Peça para a pessoa mandar de outro jeito."><Paperclip /> {a.nome} <small>não guardado</small></span>;
  }
  return <button className="caixa-anexo" onClick={abrir}><Download /> {a.nome} {a.tamanho ? <small>{tamanhoArquivo(a.tamanho)}</small> : null}</button>;
}

function Original({ id, fechar }: { id: number | null; fechar: () => void }) {
  const { dados, erro, carregando } = useCarregar(() => (id ? rpc<string | null>('admin_suporte_html', { p_mensagem: id }) : Promise.resolve(null)), [id]);
  // Moldura isolada: sem scripts, sem acesso ao painel. Imagens de fora ficam bloqueadas (evita rastreamento).
  const doc = dados ? `<!doctype html><html><head><meta charset="utf-8"><base target="_blank"><style>body{font-family:system-ui,sans-serif;font-size:14px;color:#0a1f44;margin:16px;word-wrap:break-word}img{max-width:100%;height:auto}</style></head><body>${dados}</body></html>` : '';
  return (
    <Dialogo aberto={!!id} fechar={fechar} largo titulo="E-mail original" icone={<Code />}
      texto="Como a pessoa formatou. Imagens de outros sites não carregam, por segurança.">
      {erro ? <ErroCaixa erro={erro} /> : carregando ? <Carregando /> : dados ? (
        <iframe className="caixa-original" sandbox="allow-popups allow-popups-to-escape-sandbox" srcDoc={doc} title="E-mail original" />
      ) : <Vazio titulo="Este e-mail não tem versão formatada" />}
    </Dialogo>
  );
}

function Balao({ m, contato, reenviar, verOriginal, ocupado }: {
  m: Mensagem; contato: string; reenviar: (m: Mensagem) => void; verOriginal: (id: number) => void; ocupado: boolean;
}) {
  const [mostrarCitacao, setMostrarCitacao] = useState(false);
  const [novo, citado] = useMemo(() => (m.direcao === 'recebida' ? separarCitacao(m.texto ?? '') : [m.texto ?? '', '']), [m]);

  if (m.direcao === 'evento') {
    return <div className="caixa-evento"><span>{m.texto}{m.autor_nome ? ` · ${m.autor_nome.split(' ')[0]}` : ''} · {dataHora(m.criada_em)}</span></div>;
  }
  const classe = m.direcao === 'recebida' ? 'recebida' : m.direcao === 'nota' ? 'nota' : 'enviada';
  return (
    <div className={`caixa-msg ${classe}`}>
      <div className="caixa-msg-cab">
        {m.direcao === 'recebida' ? <strong>{m.de_nome || m.de_email || contato}</strong>
          : m.direcao === 'nota' ? <strong><StickyNote size={13} /> Nota interna de {m.autor_nome?.split(' ')[0] ?? 'equipe'}</strong>
            : <strong>{m.autor_nome ?? 'Equipe'}</strong>}
        <span className="texto-fraco">{dataHora(m.criada_em)}</span>
      </div>
      {m.direcao === 'recebida' && m.cc?.length ? <div className="texto-fraco" style={{ fontSize: 12 }}>Cópia: {m.cc.join(', ')}</div> : null}
      <div className="caixa-msg-texto">{novo || <span className="texto-fraco">Sem texto.</span>}</div>
      {citado ? (
        mostrarCitacao
          ? <div className="caixa-msg-citado">{citado}</div>
          : <button className="caixa-link" onClick={() => setMostrarCitacao(true)}>••• mostrar mensagem anterior</button>
      ) : null}
      {m.anexos?.length ? <div className="caixa-anexos">{m.anexos.map((a, i) => <AnexoLink key={i} a={a} />)}</div> : null}
      <div className="caixa-msg-pe">
        {m.direcao === 'recebida' && m.tem_html ? <button className="caixa-link" onClick={() => verOriginal(m.id)}><Code size={13} /> Ver original</button> : null}
        {m.direcao === 'enviada' ? (
          m.envio === 'erro' ? <>
            <span className="caixa-erro-envio"><AlertTriangle size={13} /> Não enviado</span>
            <button className="caixa-link" disabled={ocupado} onClick={() => reenviar(m)}><RotateCcw size={13} /> Tentar de novo</button>
          </> : m.envio === 'enviando'
            ? <span className="texto-fraco"><Loader2 size={13} className="girar" /> Enviando…</span>
            : <span className="texto-fraco"><CheckCircle2 size={13} /> Enviado para {m.para?.[0] ?? contato}</span>
        ) : null}
        {m.direcao === 'nota' ? <span className="texto-fraco">Só a equipe vê</span> : null}
      </div>
    </div>
  );
}

// ------------------------------------------------------------------ conversa aberta
function Detalhe({ id, equipe, voltar, mudou }: { id: number; equipe: MembroRodizio[]; voltar: () => void; mudou: () => void }) {
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Conversa>('admin_suporte_conversa', { p_id: id }), [id]);
  const { executar, ocupado } = useAcao();
  const avisar = useAviso();
  const [modo, setModo] = useState<'responder' | 'nota'>('responder');
  const [texto, setTexto] = useState('');
  const [enviando, setEnviando] = useState(false);
  const [original, setOriginal] = useState<number | null>(null);
  const [transferir, setTransferir] = useState(false);
  const todos = usePainel().pode('emails_todos');
  const fim = useRef<HTMLDivElement>(null);
  const primeiraCarga = useRef(true);

  useEffect(() => { setTexto(''); setModo('responder'); primeiraCarga.current = true; }, [id]);
  // Atualiza sozinho enquanto a conversa está aberta (resposta do cliente aparece sem recarregar).
  useEffect(() => {
    const t = setInterval(() => { if (document.visibilityState === 'visible') recarregar(); }, ATUALIZAR_MS);
    return () => clearInterval(t);
  }, [recarregar]);
  const qtd = dados?.mensagens.length ?? 0;
  useEffect(() => {
    if (!qtd) return;
    fim.current?.scrollIntoView({ block: 'end', behavior: primeiraCarga.current ? 'auto' : 'smooth' });
    if (primeiraCarga.current) { primeiraCarga.current = false; mudou(); }
  }, [qtd, mudou]);

  if (erro) return <div className="caixa-detalhe"><div style={{ padding: 20 }}><ErroCaixa erro={erro} tentar={recarregar} /></div></div>;
  if (!dados) return <div className="caixa-detalhe">{carregando ? <Carregando /> : null}</div>;
  const c = dados;
  const minha = c.responsavel && c.responsavel === c.eu;
  const nome = c.pessoa?.nome || c.contato_nome || c.contato_email;

  const status = async (s: StatusConversa, aviso: string) => {
    if (await executar(() => rpc('admin_suporte_status', { p_id: c.id, p_status: s }), aviso)) { recarregar(); mudou(); }
  };
  const assumir = async () => {
    if (!c.eu) return;
    if (await executar(() => rpc('admin_suporte_transferir', { p_id: c.id, p_email: c.eu }), 'A conversa agora é sua.')) { recarregar(); mudou(); }
  };
  const passar = async (email: string) => {
    const quem = equipe.find((m) => m.email === email)?.nome.split(' ')[0] ?? email;
    if (await executar(() => rpc('admin_suporte_transferir', { p_id: c.id, p_email: email }), `Conversa passada para ${quem}.`)) {
      setTransferir(false); recarregar(); mudou();
    }
  };
  const enviar = async (encerrar = false) => {
    const t = texto.trim();
    if (!t) return;
    setEnviando(true);
    try {
      if (modo === 'nota') {
        await rpc('admin_suporte_nota', { p_id: c.id, p_texto: t });
        avisar('Nota salva. Só a equipe vê.');
      } else {
        await enviarEmail({ conversa_id: c.id, texto: t });
        if (encerrar) await rpc('admin_suporte_status', { p_id: c.id, p_status: 'encerrado' });
        avisar(encerrar ? 'Resposta enviada e conversa encerrada.' : `Resposta enviada para ${c.contato_email}.`);
      }
      setTexto('');
    } catch (e) {
      avisar(e instanceof Error ? e.message : 'Algo deu errado.', true);
      // A resposta que falhou fica salva na conversa, com "Tentar de novo".
      if (modo === 'responder' && (e as ErroPainel).codigo === 'envio') setTexto('');
    } finally {
      setEnviando(false);
      recarregar(); mudou();
    }
  };
  const reenviar = async (m: Mensagem) => {
    if (await executar(() => enviarEmail({ reenviar: m.id }), 'Resposta enviada.')) mudou();
    recarregar();
  };

  return (
    <div className="caixa-detalhe">
      <div className="caixa-detalhe-cab">
        <button className="botao fantasma pequeno caixa-voltar" onClick={voltar} aria-label="Voltar para a lista"><ChevronLeft /></button>
        <div style={{ minWidth: 0, flex: 1 }}>
          <h2>{c.assunto}</h2>
          <p>
            <span className="mono">{c.protocolo}</span> · {nome}{nome !== c.contato_email ? <> &lt;{c.contato_email}&gt;</> : null}
            {c.pessoa ? <> · <Link href={`/pessoa/?id=${c.pessoa.id}`}>ver cadastro ({c.pessoa.e_profissional ? 'profissional' : 'cliente'}, {c.pessoa.pedidos} {c.pessoa.pedidos === 1 ? 'pedido' : 'pedidos'})</Link></> : <> · sem conta no app</>}
            {c.outras ? <> · {c.outras} {c.outras === 1 ? 'outra conversa' : 'outras conversas'}</> : null}
          </p>
        </div>
        <SeloStatus mapa={statusConversa} valor={c.status} />
      </div>

      <div className="caixa-acoes">
        <span className="texto-suave">
          {c.responsavel_nome ? <>Com <strong>{minha ? 'você' : c.responsavel_nome}</strong></> : <strong style={{ color: 'var(--perigo)' }}>Sem responsável</strong>}
        </span>
        <span className="espaco" />
        {!minha && (todos || !c.responsavel) ? <button className="botao contorno pequeno" disabled={ocupado} onClick={assumir}><UserCheck /> Assumir</button> : null}
        {todos || minha || !c.responsavel ? <button className="botao contorno pequeno" disabled={ocupado} onClick={() => setTransferir(true)}><ArrowLeftRight /> Passar</button> : null}
        {c.status === 'aberto' ? <button className="botao contorno pequeno" disabled={ocupado} onClick={() => status('em_atendimento', 'Em atendimento.')}>Em atendimento</button> : null}
        {c.status !== 'encerrado'
          ? <button className="botao sucesso pequeno" disabled={ocupado} onClick={() => status('encerrado', 'Conversa encerrada.')}><CheckCircle2 /> Encerrar</button>
          : <button className="botao contorno pequeno" disabled={ocupado} onClick={() => status('aberto', 'Conversa reaberta.')}><RotateCcw /> Reabrir</button>}
      </div>

      <div className="caixa-mensagens">
        {c.mensagens.map((m) => <Balao key={m.id} m={m} contato={c.contato_email} reenviar={reenviar} verOriginal={setOriginal} ocupado={ocupado} />)}
        <div ref={fim} />
      </div>

      <div className={`caixa-escrever ${modo === 'nota' ? 'nota' : ''}`}>
        <div className="caixa-escrever-abas" role="tablist">
          <button role="tab" aria-selected={modo === 'responder'} className={modo === 'responder' ? 'ativa' : ''} onClick={() => setModo('responder')}><Send size={14} /> Responder</button>
          <button role="tab" aria-selected={modo === 'nota'} className={modo === 'nota' ? 'ativa' : ''} onClick={() => setModo('nota')}><StickyNote size={14} /> Nota interna</button>
          <span className="espaco" />
          <span className="texto-fraco" style={{ fontSize: 12 }}>{modo === 'responder' ? `Para ${c.contato_email}` : 'O cliente não vê'}</span>
        </div>
        <textarea className="entrada" value={texto} onChange={(e) => setTexto(e.target.value)} rows={4} maxLength={20000}
          aria-label={modo === 'responder' ? 'Sua resposta' : 'Nota interna'}
          placeholder={modo === 'responder' ? `Olá, ${(nome.split(/[\s@]/)[0] || '').replace(/^./, (x) => x.toUpperCase())}! …` : 'Anote o que a equipe precisa saber sobre este atendimento.'}
          onKeyDown={(e) => { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); enviar(); } }} />
        <div className="linha-flex">
          <span className="texto-fraco" style={{ fontSize: 12 }}>
            {modo === 'responder' ? <>Sai de {ENDERECO} com a sua assinatura{c.status === 'aberto' ? ' e a conversa passa para Em atendimento' : ''}. Ctrl+Enter envia.</> : 'Ctrl+Enter salva.'}
          </span>
          <span className="espaco" />
          {modo === 'responder' && c.status !== 'encerrado' ? (
            <button className="botao contorno" disabled={enviando || !texto.trim()} onClick={() => enviar(true)}>
              Enviar e encerrar
            </button>
          ) : null}
          <button className="botao primario" disabled={enviando || !texto.trim()} onClick={() => enviar()}>
            {enviando ? <Loader2 className="girar" /> : modo === 'responder' ? <Send /> : <StickyNote />} {modo === 'responder' ? 'Enviar' : 'Salvar nota'}
          </button>
        </div>
      </div>

      <Original id={original} fechar={() => setOriginal(null)} />
      <Dialogo aberto={transferir} fechar={() => setTransferir(false)} titulo="Passar a conversa" icone={<ArrowLeftRight />}
        texto="Escolha quem da equipe vai cuidar deste atendimento. Fica registrado na conversa.">
        <div className="lista-simples">
          {equipe.filter((m) => m.ativo).map((m) => (
            <button key={m.email} className="caixa-pessoa-opcao" disabled={ocupado || m.email === c.responsavel} onClick={() => passar(m.email)}>
              <Pessoa nome={m.voce ? `${m.nome} (você)` : m.nome} foto={m.foto_url} sub={`${m.aberto} em aberto · ${m.em_atendimento} em atendimento`} />
              {m.email === c.responsavel ? <Selo tom="azul">Responsável agora</Selo> : null}
            </button>
          ))}
        </div>
      </Dialogo>
    </div>
  );
}

// ------------------------------------------------------------------ diálogos da página
function Distribuicao({ aberto, fechar, equipe, recarregar }: { aberto: boolean; fechar: () => void; equipe: MembroRodizio[]; recarregar: () => void }) {
  const { executar, ocupado } = useAcao();
  const { atualizarResumo } = usePainel();
  const mudar = async (m: MembroRodizio, v: boolean) => {
    const ok = await executar(() => rpc('admin_suporte_rodizio', { p_email: m.email, p_recebe: v }),
      v ? `${m.nome.split(' ')[0]} voltou a receber e-mails.` : `${m.nome.split(' ')[0]} não recebe e-mails novos por enquanto.`);
    if (ok) { recarregar(); atualizarResumo(); }
  };
  const noRodizio = equipe.filter((m) => m.ativo && m.recebe_emails).length;
  return (
    <Dialogo aberto={aberto} fechar={fechar} largo titulo="Distribuição dos e-mails" icone={<Shuffle />}
      texto="Cada e-mail novo vai para a próxima pessoa ligada aqui, em ordem: quem recebeu há mais tempo é a próxima. Assim todos recebem a mesma quantidade."
      rodape={<button className="botao primario" onClick={fechar}>Concluir</button>}>
      {!noRodizio ? <div className="alerta-faixa laranja" style={{ margin: '0 0 12px' }}><AlertTriangle /><div>Ninguém está recebendo. Os e-mails novos ficam <strong>sem responsável</strong> até alguém ligar.</div></div> : null}
      <div className="tabela-rolagem">
        <table className="tabela">
          <thead><tr><th>Pessoa</th><th className="num">Em aberto</th><th className="num">Em atendimento</th><th className="num">Encerrados (7 dias)</th><th>Recebe</th></tr></thead>
          <tbody>
            {equipe.map((m) => (
              <tr key={m.email}>
                <td><Pessoa nome={m.voce ? `${m.nome} (você)` : m.nome} foto={m.foto_url} sub={m.ativo ? (m.ultima_atribuicao ? `Último e-mail ${haQuanto(m.ultima_atribuicao)}` : 'Ainda não recebeu') : 'Aguardando primeiro acesso'} /></td>
                <td className="num">{m.aberto}</td>
                <td className="num">{m.em_atendimento}</td>
                <td className="num">{m.encerrado_7d}</td>
                <td><Interruptor ligado={m.ativo && m.recebe_emails} desativado={!m.ativo || ocupado} mudar={(v) => mudar(m, v)} rotulo={`${m.nome} recebe e-mails novos`} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="texto-fraco" style={{ margin: '12px 0 0' }}>Desligar não tira as conversas que a pessoa já tem; use “Passar” em cada uma. Quem sai da equipe tem as conversas não encerradas redistribuídas automaticamente.</p>
    </Dialogo>
  );
}

function NovoEmail({ aberto, fechar, criado }: { aberto: boolean; fechar: () => void; criado: (id: number) => void }) {
  const [para, setPara] = useState('');
  const [assunto, setAssunto] = useState('');
  const [texto, setTexto] = useState('');
  const [enviando, setEnviando] = useState(false);
  const avisar = useAviso();
  useEffect(() => { if (aberto) { setPara(''); setAssunto(''); setTexto(''); } }, [aberto]);
  const ok = /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(para.trim()) && assunto.trim().length >= 2 && texto.trim().length > 0;
  const enviar = async () => {
    setEnviando(true);
    try {
      const r = await enviarEmail({ conversa_id: null, para: para.trim(), assunto: assunto.trim(), texto: texto.trim() });
      avisar(`E-mail enviado para ${para.trim()}.`);
      fechar();
      if (r.conversa_id) criado(r.conversa_id);
    } catch (e) {
      avisar(e instanceof Error ? e.message : 'Algo deu errado.', true);
      const conversa = (e as { conversa?: number }).conversa;
      if (conversa) { fechar(); criado(conversa); }
    } finally {
      setEnviando(false);
    }
  };
  return (
    <Dialogo aberto={aberto} fechar={fechar} largo titulo="Novo e-mail" icone={<MailPlus />}
      texto={`Sai de ${ENDERECO} com a sua assinatura. A resposta da pessoa volta para esta conversa.`}
      rodape={<>
        <button className="botao contorno" onClick={fechar}>Cancelar</button>
        <button className="botao primario" disabled={!ok || enviando} onClick={enviar}>{enviando ? <Loader2 className="girar" /> : <Send />} Enviar</button>
      </>}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div className="campo">
          <label htmlFor="novo-para">Para</label>
          <input id="novo-para" className="entrada" type="email" value={para} onChange={(e) => setPara(e.target.value)} placeholder="nome@exemplo.com" autoFocus />
        </div>
        <div className="campo">
          <label htmlFor="novo-assunto">Assunto</label>
          <input id="novo-assunto" className="entrada" maxLength={300} value={assunto} onChange={(e) => setAssunto(e.target.value)} placeholder="Ex.: Sobre o seu cadastro" />
        </div>
        <div className="campo">
          <label htmlFor="novo-texto">Mensagem</label>
          <textarea id="novo-texto" className="entrada" rows={8} maxLength={20000} value={texto} onChange={(e) => setTexto(e.target.value)} />
        </div>
      </div>
    </Dialogo>
  );
}

// ------------------------------------------------------------------ página
type Quem = 'meus' | 'todos' | 'sem_responsavel' | string;

function Pagina() {
  const params = useSearchParams();
  const router = useRouter();
  const { resumo, atualizarResumo, pode } = usePainel();
  const todos = pode('emails_todos');
  const aberta = Number(params.get('id')) || null;
  const [status, setStatus] = useState<StatusConversa>('aberto');
  const [quem, setQuem] = useState<Quem>('meus');
  const [busca, setBusca] = useState('');
  const [buscaAtiva, setBuscaAtiva] = useState('');
  const [limite, setLimite] = useState(50);
  const [distribuicao, setDistribuicao] = useState(false);
  const [novo, setNovo] = useState(false);

  useEffect(() => { const t = setTimeout(() => setBuscaAtiva(busca.trim()), 350); return () => clearTimeout(t); }, [busca]);
  useEffect(() => setLimite(50), [status, quem, buscaAtiva]);

  const lista = useCarregar(() => rpc<ItemConversa[]>('admin_suporte_conversas', {
    p_status: buscaAtiva ? 'todos' : status, p_quem: quem, p_busca: buscaAtiva || null, p_limite: limite,
  }), [status, quem, buscaAtiva, limite]);
  const equipe = useCarregar(() => rpc<MembroRodizio[]>('admin_suporte_equipe'), []);

  const recarregarLista = lista.recarregar;
  useEffect(() => {
    const t = setInterval(() => { if (document.visibilityState === 'visible') recarregarLista(); }, ATUALIZAR_MS);
    return () => clearInterval(t);
  }, [recarregarLista]);

  const abrir = useCallback((id: number | null) => {
    router.push(id ? `/emails/?id=${id}` : '/emails/', { scroll: false });
  }, [router]);
  const mudou = useCallback(() => { recarregarLista(); atualizarResumo(); equipe.recarregar(); }, [recarregarLista, atualizarResumo, equipe.recarregar]); // eslint-disable-line react-hooks/exhaustive-deps

  const e = resumo?.emails;
  const meus = quem === 'meus';
  const n = (s: StatusConversa) => (meus ? (s === 'aberto' ? e?.meus_aberto : s === 'em_atendimento' ? e?.meus_em_atendimento : undefined) : e?.[s]);
  const total = lista.dados?.[0]?.total ?? 0;
  const naoLidosMeus = e?.meus_nao_lidos ?? 0;

  return (
    <>
      <Cabecalho titulo="E-mails"
        texto={<>Tudo o que chega em <strong>{ENDERECO}</strong> e as respostas aos e-mails automáticos. Cada e-mail novo vai para uma pessoa da equipe, em rodízio.</>}
        acoes={<>
          {todos ? <button className="botao contorno" onClick={() => setDistribuicao(true)}><Shuffle /> Distribuição</button> : null}
          <button className="botao primario" onClick={() => setNovo(true)}><MailPlus /> Novo e-mail</button>
        </>} />

      {(e?.sem_responsavel ?? 0) > 0 ? (
        <div className="alerta-faixa laranja" style={{ marginTop: 0 }}>
          <AlertTriangle />
          <div><strong>{e!.sem_responsavel} {e!.sem_responsavel === 1 ? 'conversa sem responsável' : 'conversas sem responsável'}.</strong> Ninguém estava no rodízio quando chegaram.
            {' '}<button className="caixa-link" onClick={() => { setQuem('sem_responsavel'); setStatus('aberto'); }}>Ver agora</button></div>
        </div>
      ) : null}

      <div className="filtros">
        <Abas ativa={status} mudar={(v) => { setStatus(v); setBusca(''); }} abas={[
          { id: 'aberto', rotulo: 'Em aberto', n: n('aberto') },
          { id: 'em_atendimento', rotulo: 'Em atendimento', n: n('em_atendimento') },
          { id: 'encerrado', rotulo: 'Encerrado' },
        ]} />
        <select className="entrada" value={quem} onChange={(ev) => setQuem(ev.target.value)} aria-label="De quem">
          <option value="meus">Meus{naoLidosMeus ? ` (${naoLidosMeus} não lidos)` : ''}</option>
          <option value="todos">{todos ? 'Toda a equipe' : 'Meus e sem responsável'}</option>
          <option value="sem_responsavel">Sem responsável</option>
          {(todos ? equipe.dados ?? [] : []).filter((m) => m.ativo && !m.voce).map((m) => <option key={m.email} value={m.email}>{m.nome}</option>)}
        </select>
        <div className="busca">
          <Search />
          <input className="entrada" type="search" value={busca} onChange={(ev) => setBusca(ev.target.value)} placeholder="Buscar por nome, e-mail, assunto ou protocolo" aria-label="Buscar e-mails" />
        </div>
      </div>

      <section className={`cartao caixa ${aberta ? 'com-conversa' : ''}`}>
        <div className="caixa-lista">
          {buscaAtiva ? <div className="caixa-lista-aviso">Resultados em todas as situações para “{buscaAtiva}”</div> : null}
          {lista.erro ? <div style={{ padding: 16 }}><ErroCaixa erro={lista.erro} tentar={lista.recarregar} /></div>
            : lista.carregando && !lista.dados ? <Carregando />
              : !lista.dados?.length ? (
                <Vazio icone={status === 'encerrado' ? <CheckCircle2 size={24} /> : <Inbox size={24} />}
                  titulo={buscaAtiva ? 'Nada encontrado' : status === 'aberto' ? (meus ? 'Nenhum e-mail novo para você' : 'Nenhum e-mail em aberto') : status === 'em_atendimento' ? 'Nenhum atendimento em andamento' : 'Nenhuma conversa encerrada'}
                  texto={!buscaAtiva && status === 'aberto' ? 'Quando chegar um e-mail, ele aparece aqui.' : undefined} />
              ) : <>
                {lista.dados.map((c) => <ItemLista key={c.id} c={c} ativo={c.id === aberta} mostrarResponsavel={!meus} abrir={() => abrir(c.id)} />)}
                {total > lista.dados.length ? (
                  <button className="botao fantasma cheio" disabled={lista.carregando} onClick={() => setLimite((l) => l + 50)}>
                    {lista.carregando ? <Loader2 className="girar" /> : null} Mostrar mais ({total - lista.dados.length})
                  </button>
                ) : null}
              </>}
        </div>
        {aberta ? <Detalhe id={aberta} equipe={equipe.dados ?? []} voltar={() => abrir(null)} mudou={mudou} /> : (
          <div className="caixa-detalhe caixa-vazia">
            <Vazio icone={<Mail size={24} />} titulo="Escolha uma conversa" texto="As mais antigas sem resposta ficam no topo." />
          </div>
        )}
      </section>

      <Distribuicao aberto={distribuicao} fechar={() => setDistribuicao(false)} equipe={equipe.dados ?? []} recarregar={() => { equipe.recarregar(); lista.recarregar(); }} />
      <NovoEmail aberto={novo} fechar={() => setNovo(false)} criado={(id) => { setStatus('em_atendimento'); abrir(id); mudou(); }} />
    </>
  );
}

export default function Envelope() {
  return <Suspense fallback={<Carregando />}><Pagina /></Suspense>;
}
