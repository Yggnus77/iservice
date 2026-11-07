'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import {
  BadgeCheck, BarChart3, ClipboardList, Globe, Flag, Gauge, History, LayoutGrid, Loader2, LogOut, Map as MapaIcone, Megaphone, Menu,
  ShieldAlert, ShieldCheck, Siren, Tags, Users, Settings, Lock, Mail, MailCheck, CheckCircle2, UserRound, UsersRound,
} from 'lucide-react';
import { db, rpc, ErroPainel } from '@/lib/supabase';
import { Avatar, Avisos, Carregando } from './ui';

export type Resumo = {
  dia: string;
  cadastros_em_analise: number;
  reclamacoes_abertas: number;
  denuncias_abertas: number;
  emergencias_abertas: number;
  especialidades_sugeridas: number;
  profissionais_aprovados: number;
  profissionais_disponiveis: number;
  clientes: number;
  buscas: number;
  buscas_sem_resultado: number;
  pedidos: number;
  pedidos_por_status: Record<string, number>;
  pedidos_em_andamento: number;
  concluidos: number;
  cadastros_novos_clientes: number;
  cadastros_novos_profissionais: number;
  avaliacoes: number;
  nota_media_dia: number | null;
  ultimos_7_dias: { dia: string; buscas: number; sem_resultado: number; pedidos: number; concluidos: number; cadastros: number }[];
  profissionais_por_profissao: { id: string; nome: string; ativa: boolean; aprovados: number; em_analise: number }[];
};

type Ctx = { resumo: Resumo | null; atualizarResumo: () => void; usuarioId: string; nome: string };
const PainelCtx = createContext<Ctx>({ resumo: null, atualizarResumo: () => {}, usuarioId: '', nome: '' });
export const usePainel = () => useContext(PainelCtx);

const menu: { grupo?: string; href: string; rotulo: string; icone: ReactNode; contador?: (r: Resumo) => number; alerta?: boolean }[] = [
  { href: '/', rotulo: 'Início', icone: <Gauge /> },
  { grupo: 'Operação', href: '/cadastros/', rotulo: 'Cadastros', icone: <BadgeCheck />, contador: (r) => r.cadastros_em_analise },
  { href: '/pedidos/', rotulo: 'Pedidos', icone: <ClipboardList /> },
  { href: '/emergencias/', rotulo: 'Emergências', icone: <Siren />, contador: (r) => r.emergencias_abertas, alerta: true },
  { href: '/garantia/', rotulo: 'Garantia iService', icone: <ShieldCheck />, contador: (r) => r.reclamacoes_abertas },
  { href: '/denuncias/', rotulo: 'Denúncias e avaliações', icone: <Flag />, contador: (r) => r.denuncias_abertas },
  { href: '/pessoas/', rotulo: 'Pessoas', icone: <Users /> },
  { grupo: 'Crescimento', href: '/buscas/', rotulo: 'Buscas e mapa', icone: <MapaIcone /> },
  { href: '/site/', rotulo: 'Site e downloads', icone: <Globe /> },
  { href: '/comunicados/', rotulo: 'Comunicados', icone: <Megaphone /> },
  { grupo: 'Catálogo', href: '/catalogo/', rotulo: 'Profissões e regiões', icone: <LayoutGrid />, contador: (r) => r.especialidades_sugeridas },
  { href: '/precos/', rotulo: 'Preços de referência', icone: <Tags /> },
  { href: '/configuracoes/', rotulo: 'Configurações', icone: <Settings /> },
  { grupo: 'Equipe', href: '/equipe/', rotulo: 'Equipe', icone: <UsersRound /> },
  { href: '/registro/', rotulo: 'Registro da equipe', icone: <History /> },
];

function ativo(rota: string, href: string) {
  const r = rota.replace(/^\/admin/, '') || '/';
  if (href === '/') return r === '/';
  const base = href.replace(/\/$/, '');
  return r === href || r.startsWith(base + '/') || r === base || (base === '/cadastros' && r.startsWith('/cadastro')) ||
    (base === '/pedidos' && r.startsWith('/pedido')) || (base === '/pessoas' && r.startsWith('/pessoa'));
}

type ModoEntrar = 'entrar' | 'primeiro' | 'esqueci';

function CampoIcone({ id, rotulo, icone, ...props }: { id: string; rotulo: string; icone: ReactNode } & React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <div className="campo">
      <label htmlFor={id}>{rotulo}</label>
      <div className="busca" style={{ maxWidth: 'none' }}>
        {icone}
        <input id={id} className="entrada" {...props} />
      </div>
    </div>
  );
}

const retornoPainel = () => `${window.location.origin}/admin/`;

function traduzirAuth(msg: string) {
  if (/Invalid login/i.test(msg)) return 'E-mail ou senha incorretos.';
  if (/Email not confirmed/i.test(msg)) return 'Falta confirmar o e-mail. Abra o link que enviamos para a sua caixa de entrada.';
  if (/banned/i.test(msg)) return 'Esta conta está suspensa.';
  if (/at least|weak|short/i.test(msg)) return 'A senha precisa ter pelo menos 8 caracteres, com letras e números.';
  if (/rate limit|security purposes/i.test(msg)) return 'Muitas tentativas seguidas. Espere um minuto e tente de novo.';
  if (/already registered/i.test(msg)) return 'Este e-mail já tem conta iService. Use "Entrar" com a senha que você já usa.';
  return msg;
}

function Entrar() {
  const [modo, setModo] = useState<ModoEntrar>('entrar');
  const [nome, setNome] = useState('');
  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  const [senha2, setSenha2] = useState('');
  const [erro, setErro] = useState('');
  const [enviado, setEnviado] = useState('');
  const [ocupado, setOcupado] = useState(false);

  const trocar = (m: ModoEntrar) => { setModo(m); setErro(''); setEnviado(''); setSenha(''); setSenha2(''); };

  const enviar = async (e: React.FormEvent) => {
    e.preventDefault();
    setErro('');
    const mail = email.trim().toLowerCase();
    if (modo === 'primeiro') {
      if (senha.length < 8) { setErro('A senha precisa ter pelo menos 8 caracteres.'); return; }
      if (senha !== senha2) { setErro('As duas senhas não são iguais.'); return; }
    }
    setOcupado(true);
    try {
      if (modo === 'entrar') {
        const { error } = await db().auth.signInWithPassword({ email: mail, password: senha });
        if (error) setErro(traduzirAuth(error.message));
      } else if (modo === 'primeiro') {
        const { data, error } = await db().auth.signUp({
          email: mail, password: senha,
          options: { data: { nome: nome.trim(), app: 'equipe' }, emailRedirectTo: retornoPainel() },
        });
        if (error) setErro(traduzirAuth(error.message));
        else if (data.user && (data.user.identities?.length ?? 0) === 0) setErro(traduzirAuth('already registered'));
        else if (data.session) return; // confirmação desligada: já entrou
        else setEnviado(`Enviamos um e-mail para ${mail}. Abra o link "Confirmar e-mail" e o painel abre já com o seu acesso.`);
      } else {
        const { error } = await db().auth.resetPasswordForEmail(mail, { redirectTo: retornoPainel() });
        if (error) setErro(traduzirAuth(error.message));
        else setEnviado(`Se ${mail} tiver conta, chega em instantes um e-mail com o link para criar uma nova senha.`);
      }
    } finally {
      setOcupado(false);
    }
  };

  const titulos: Record<ModoEntrar, [string, string, string]> = {
    entrar: ['Entrar', 'Use a conta iService que tem acesso de equipe.', 'Entrar'],
    primeiro: ['Primeiro acesso', 'Recebeu um convite da equipe iService? Crie a sua senha com o e-mail convidado.', 'Criar minha senha'],
    esqueci: ['Esqueci minha senha', 'Mandamos um link para você criar uma senha nova.', 'Enviar link'],
  };
  const [t, sub, botao] = titulos[modo];

  return (
    <div className="entrar">
      <div className="arte">
        <div className="marca"><img src="/admin/simbolo.svg" alt="" /><strong>iService</strong></div>
        <div>
          <h2>Painel da equipe iService</h2>
          <p>Aprove profissionais com segurança, acompanhe os pedidos e cuide da garantia de cada serviço em Brasília e no Entorno.</p>
          <ul>
            <li><CheckCircle2 size={18} /> Documentos, selfie e antecedentes lado a lado</li>
            <li><CheckCircle2 size={18} /> Mediação da Garantia iService</li>
            <li><CheckCircle2 size={18} /> Mapa de onde faltam profissionais</li>
          </ul>
        </div>
        <span style={{ color: '#9fb6de', fontSize: 12.5 }}>Acesso restrito. Todas as ações ficam registradas.</span>
      </div>
      <form className="form" onSubmit={enviar}>
        <div>
          <div>
            <h1>{t}</h1>
            <p>{sub}</p>
          </div>
          {enviado ? <>
            <div className="alerta-faixa verde" role="status" style={{ margin: 0 }}><MailCheck /><div>{enviado}</div></div>
            <button type="button" className="botao contorno grande cheio" onClick={() => trocar('entrar')}>Voltar para Entrar</button>
          </> : <>
            {modo === 'primeiro' ? (
              <CampoIcone id="nome" rotulo="Seu nome" icone={<UserRound />} autoComplete="name" required minLength={2} value={nome} onChange={(e) => setNome(e.target.value)} />
            ) : null}
            <CampoIcone id="email" rotulo="E-mail" icone={<Mail />} type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
            {modo !== 'esqueci' ? (
              <CampoIcone id="senha" rotulo={modo === 'primeiro' ? 'Crie uma senha' : 'Senha'} icone={<Lock />} type="password"
                autoComplete={modo === 'primeiro' ? 'new-password' : 'current-password'} required value={senha} onChange={(e) => setSenha(e.target.value)} />
            ) : null}
            {modo === 'primeiro' ? (
              <CampoIcone id="senha2" rotulo="Repita a senha" icone={<Lock />} type="password" autoComplete="new-password" required value={senha2} onChange={(e) => setSenha2(e.target.value)} />
            ) : null}
            {erro ? <div className="erro-caixa" role="alert">{erro}</div> : null}
            <button className="botao primario grande cheio" disabled={ocupado}>{ocupado ? <Loader2 className="girar" /> : null} {botao}</button>
            <div className="entrar-links">
              {modo === 'entrar' ? <>
                <button type="button" onClick={() => trocar('primeiro')}>Primeiro acesso</button>
                <button type="button" onClick={() => trocar('esqueci')}>Esqueci minha senha</button>
              </> : <button type="button" onClick={() => trocar('entrar')}>‹ Voltar para Entrar</button>}
            </div>
          </>}
        </div>
      </form>
    </div>
  );
}

/** Aberto pelo link de "Esqueci minha senha": define a senha nova. */
function NovaSenha({ pronto }: { pronto: () => void }) {
  const [senha, setSenha] = useState('');
  const [senha2, setSenha2] = useState('');
  const [erro, setErro] = useState('');
  const [ocupado, setOcupado] = useState(false);
  const enviar = async (e: React.FormEvent) => {
    e.preventDefault();
    if (senha.length < 8) { setErro('A senha precisa ter pelo menos 8 caracteres.'); return; }
    if (senha !== senha2) { setErro('As duas senhas não são iguais.'); return; }
    setOcupado(true);
    const { error } = await db().auth.updateUser({ password: senha });
    setOcupado(false);
    if (error) setErro(/different from the old/i.test(error.message) ? 'Use uma senha diferente da anterior.' : traduzirAuth(error.message));
    else pronto();
  };
  return (
    <div className="entrar" style={{ gridTemplateColumns: '1fr' }}>
      <form className="form" onSubmit={enviar}>
        <div>
          <div>
            <h1>Crie uma senha nova</h1>
            <p>Depois disso o painel abre normalmente.</p>
          </div>
          <CampoIcone id="nova" rotulo="Nova senha" icone={<Lock />} type="password" autoComplete="new-password" required value={senha} onChange={(e) => setSenha(e.target.value)} />
          <CampoIcone id="nova2" rotulo="Repita a senha" icone={<Lock />} type="password" autoComplete="new-password" required value={senha2} onChange={(e) => setSenha2(e.target.value)} />
          {erro ? <div className="erro-caixa" role="alert">{erro}</div> : null}
          <button className="botao primario grande cheio" disabled={ocupado}>{ocupado ? <Loader2 className="girar" /> : null} Salvar senha</button>
        </div>
      </form>
    </div>
  );
}

function SemAcesso({ motivo, sair }: { motivo: 'nao_admin' | 'sql_pendente'; sair: () => void }) {
  return (
    <div className="entrar" style={{ gridTemplateColumns: '1fr' }}>
      <div className="form">
        <div>
          <ShieldAlert size={40} color="#c62828" />
          {motivo === 'nao_admin' ? <>
            <h1>Sem acesso ao painel</h1>
            <p>Esta conta não faz parte da equipe iService. Peça para alguém da equipe convidar o seu e-mail na aba Equipe e entre de novo.</p>
          </> : <>
            <h1>Falta preparar o banco</h1>
            <p>O banco ainda não tem as funções do painel. Cole o arquivo <strong>aplicar-painel-admin.sql</strong> no SQL Editor do Supabase e recarregue esta página.</p>
          </>}
          <button className="botao contorno cheio" onClick={sair}><LogOut /> Sair</button>
        </div>
      </div>
    </div>
  );
}

export default function Painel({ children }: { children: ReactNode }) {
  const [sessao, setSessao] = useState<Session | null | undefined>(undefined);
  const [acesso, setAcesso] = useState<'verificando' | 'ok' | 'nao_admin' | 'sql_pendente'>('verificando');
  const [nome, setNome] = useState('');
  const [resumo, setResumo] = useState<Resumo | null>(null);
  const [menuAberto, setMenuAberto] = useState(false);
  const [recuperando, setRecuperando] = useState(false);
  const rota = usePathname();

  useEffect(() => {
    db().auth.getSession().then(({ data }) => setSessao(data.session));
    const { data } = db().auth.onAuthStateChange((evento, s) => {
      if (evento === 'PASSWORD_RECOVERY') setRecuperando(true);
      setSessao(s);
    });
    return () => data.subscription.unsubscribe();
  }, []);

  const atualizarResumo = useCallback(() => {
    rpc<Resumo>('admin_resumo').then(setResumo).catch((e: ErroPainel) => {
      if (e.codigo === 'sql_pendente') setAcesso('sql_pendente');
    });
  }, []);

  useEffect(() => {
    if (!sessao) return;
    setAcesso('verificando');
    (async () => {
      try {
        const admin = await rpc<boolean>('e_admin');
        if (!admin) { setAcesso('nao_admin'); return; }
        const { data } = await db().from('perfis').select('nome').eq('id', sessao.user.id).maybeSingle();
        setNome(data?.nome || sessao.user.email || '');
        const r = await rpc<Resumo>('admin_resumo');
        setResumo(r);
        setAcesso('ok');
      } catch (e) {
        setAcesso((e as ErroPainel).codigo === 'sql_pendente' ? 'sql_pendente' : 'nao_admin');
      }
    })();
  }, [sessao]);

  // Contadores do menu (emergências principalmente) se atualizam sozinhos.
  useEffect(() => {
    if (acesso !== 'ok') return;
    const t = setInterval(atualizarResumo, 60000);
    return () => clearInterval(t);
  }, [acesso, atualizarResumo]);

  useEffect(() => setMenuAberto(false), [rota]);

  const sair = () => db().auth.signOut();

  if (sessao === undefined) return <Carregando />;
  if (!sessao) return <Avisos><Entrar /></Avisos>;
  if (recuperando) return <NovaSenha pronto={() => setRecuperando(false)} />;
  if (acesso === 'verificando') return <Carregando texto="Conferindo o acesso…" />;
  if (acesso !== 'ok') return <SemAcesso motivo={acesso} sair={sair} />;

  return (
    <PainelCtx.Provider value={{ resumo, atualizarResumo, usuarioId: sessao.user.id, nome }}>
      <Avisos>
        <div className="casca">
          {menuAberto ? <div className="veu" onClick={() => setMenuAberto(false)} /> : null}
          <aside className={`lateral ${menuAberto ? 'aberta' : ''}`}>
            <div className="marca">
              <img src="/admin/simbolo.svg" alt="" />
              <div><strong>iService</strong><span>Equipe</span></div>
            </div>
            <nav aria-label="Menu do painel">
              {menu.map((m) => {
                const n = resumo && m.contador ? m.contador(resumo) : 0;
                return (
                  <div key={m.href} style={{ display: 'contents' }}>
                    {m.grupo ? <div className="grupo">{m.grupo}</div> : null}
                    <Link href={m.href} className={ativo(rota, m.href) ? 'ativo' : ''}>
                      {m.icone}
                      {m.rotulo}
                      {n > 0 ? <span className={`contador ${m.alerta ? 'alerta' : ''}`}>{n}</span> : null}
                    </Link>
                  </div>
                );
              })}
            </nav>
            <div className="rodape">
              <Avatar nome={nome} tamanho={34} />
              <div className="quem"><strong>{nome}</strong><span>Equipe iService</span></div>
              <button onClick={sair} title="Sair" aria-label="Sair"><LogOut size={16} /></button>
            </div>
          </aside>
          <main className="conteudo">
            <div className="topo-movel">
              <button onClick={() => setMenuAberto(true)} aria-label="Abrir menu"><Menu /></button>
              <strong>iService · Equipe</strong>
              <span className="espaco" />
              <BarChart3 size={18} style={{ opacity: 0 }} />
            </div>
            {children}
          </main>
        </div>
      </Avisos>
    </PainelCtx.Provider>
  );
}

export function Cabecalho({ titulo, texto, acoes, voltar }: { titulo: string; texto?: ReactNode; acoes?: ReactNode; voltar?: { href: string; rotulo: string } }) {
  return (
    <>
      {voltar ? <Link className="voltar" href={voltar.href}>‹ {voltar.rotulo}</Link> : null}
      <div className="cabecalho">
        <div>
          <h1>{titulo}</h1>
          {texto ? <p>{texto}</p> : null}
        </div>
        {acoes ? <div className="acoes">{acoes}</div> : null}
      </div>
    </>
  );
}
