'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import {
  BadgeCheck, ClipboardList, Globe, Flag, Gauge, History, LayoutGrid, Loader2, LogOut, Map as MapaIcone, Megaphone, Menu,
  ShieldAlert, ShieldCheck, Siren, Star, Tags, Users, Settings, Lock, Mail, MailCheck, CheckCircle2, UserRound, UsersRound, Camera, Lightbulb,
  BellRing, LineChart, Search, UserPlus, Headset, LifeBuoy,
} from 'lucide-react';
import { db, rpc, ErroPainel } from '@/lib/supabase';
import { Avatar, Avisos, Carregando } from './ui';
import { DialogoFoto } from './FotoPerfil';
import { Ajuda } from './Ajuda';
import { BuscaGlobal } from './BuscaGlobal';
import { AlertaEmergencia } from './AlertaEmergencia';

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
  /** Caixa de e-mail do suporte (vem de admin_suporte_contagem). */
  emails?: ContagemEmails;
  /** Fila "Precisa de atenção" (vem de admin_atencao_contagem). */
  atencao?: { pedidos: number; profissionais: number; documentos: number; total: number };
};

export type ContagemEmails = {
  aberto: number; em_atendimento: number; encerrado: number; meus_aberto: number; meus_em_atendimento: number;
  meus_nao_lidos: number; meus_pendentes: number; sem_responsavel: number; eu: string | null;
};

/** Permissões de cada cargo (a lista completa está no banco, em cargo_permissoes). */
export type Permissao =
  | 'inicio' | 'emails' | 'emails_todos' | 'cadastros' | 'cadastros_decidir' | 'dados_pessoais' | 'pedidos' | 'emergencias'
  | 'garantia' | 'garantia_decidir' | 'avaliacoes' | 'avaliacoes_moderar' | 'denuncias' | 'pessoas' | 'pessoas_suspender'
  | 'crescimento' | 'comunicados' | 'catalogo' | 'precos' | 'configuracoes' | 'equipe' | 'equipe_gerir' | 'registro' | 'registro_completo'
  | 'relatorios' | 'captacao';

export type Cargo = 'dono' | 'gerente' | 'responsavel' | 'suporte' | 'marketing' | 'captacao';
export type MeuAcesso = { cargo: Cargo; cargo_nome: string; permissoes: Permissao[] };

type Ctx = {
  resumo: Resumo | null; atualizarResumo: () => void; usuarioId: string; nome: string;
  foto: string | null; mudarFoto: (url: string | null) => void;
  /** null enquanto o SQL dos cargos não foi aplicado: aí tudo continua liberado, como antes. */
  acesso: MeuAcesso | null;
  pode: (p: Permissao) => boolean;
  podeRota: (href: string) => boolean;
};
const PainelCtx = createContext<Ctx>({
  resumo: null, atualizarResumo: () => {}, usuarioId: '', nome: '', foto: null, mudarFoto: () => {},
  acesso: null, pode: () => true, podeRota: () => true,
});
export const usePainel = () => useContext(PainelCtx);

/** Que permissão abre cada página do painel. */
const rotas: [string, Permissao][] = [
  ['/emails', 'emails'], ['/cadastros', 'cadastros'], ['/cadastro', 'cadastros'], ['/pedidos', 'pedidos'], ['/pedido', 'pedidos'],
  ['/emergencias', 'emergencias'], ['/garantia', 'garantia'], ['/avaliacoes', 'avaliacoes'], ['/denuncias', 'denuncias'],
  ['/pessoas', 'pessoas'], ['/pessoa', 'pessoas'], ['/buscas', 'crescimento'], ['/site', 'crescimento'], ['/sugestoes', 'crescimento'],
  ['/comunicados', 'comunicados'], ['/catalogo', 'catalogo'], ['/precos', 'precos'], ['/configuracoes', 'configuracoes'],
  ['/equipe', 'equipe'], ['/registro', 'registro'], ['/atencao', 'pedidos'], ['/relatorios', 'relatorios'], ['/captacao', 'captacao'],
  ['/ajuda', 'comunicados'], ['/atendimento', 'emergencias'],
];
export function permissaoDaRota(href: string): Permissao {
  const r = (href.replace(/^\/admin/, '').split(/[?#]/)[0] || '/').replace(/\/$/, '') || '/';
  const achou = rotas.find(([base]) => r === base);
  return achou ? achou[1] : 'inicio';
}

const menu: { grupo: string; href: string; rotulo: string; icone: ReactNode; contador?: (r: Resumo) => number; alerta?: boolean }[] = [
  { grupo: '', href: '/', rotulo: 'Início', icone: <Gauge /> },
  { grupo: 'Operação', href: '/atencao/', rotulo: 'Precisa de atenção', icone: <BellRing />, contador: (r) => r.atencao?.total ?? 0, alerta: true },
  { grupo: 'Operação', href: '/emails/', rotulo: 'E-mails', icone: <Mail />, contador: (r) => (r.emails?.meus_pendentes ?? 0) + (r.emails?.sem_responsavel ?? 0) },
  { grupo: 'Operação', href: '/cadastros/', rotulo: 'Cadastros', icone: <BadgeCheck />, contador: (r) => r.cadastros_em_analise },
  { grupo: 'Operação', href: '/pedidos/', rotulo: 'Pedidos', icone: <ClipboardList /> },
  { grupo: 'Operação', href: '/emergencias/', rotulo: 'Emergências', icone: <Siren />, contador: (r) => r.emergencias_abertas, alerta: true },
  { grupo: 'Operação', href: '/garantia/', rotulo: 'Garantia iService', icone: <ShieldCheck />, contador: (r) => r.reclamacoes_abertas },
  { grupo: 'Operação', href: '/avaliacoes/', rotulo: 'Avaliações', icone: <Star /> },
  { grupo: 'Operação', href: '/denuncias/', rotulo: 'Denúncias e avaliações', icone: <Flag />, contador: (r) => r.denuncias_abertas },
  { grupo: 'Operação', href: '/pessoas/', rotulo: 'Pessoas', icone: <Users /> },
  { grupo: 'Operação', href: '/atendimento/', rotulo: 'Horário, plantão e prazos', icone: <Headset /> },
  { grupo: 'Crescimento', href: '/relatorios/', rotulo: 'Relatórios', icone: <LineChart /> },
  { grupo: 'Crescimento', href: '/captacao/', rotulo: 'Captação', icone: <UserPlus /> },
  { grupo: 'Crescimento', href: '/buscas/', rotulo: 'Buscas e mapa', icone: <MapaIcone /> },
  { grupo: 'Crescimento', href: '/site/', rotulo: 'Site e downloads', icone: <Globe /> },
  { grupo: 'Crescimento', href: '/sugestoes/', rotulo: 'Sugestões de profissões', icone: <Lightbulb /> },
  { grupo: 'Crescimento', href: '/comunicados/', rotulo: 'Comunicados', icone: <Megaphone /> },
  { grupo: 'Crescimento', href: '/ajuda/', rotulo: 'Central de Ajuda', icone: <LifeBuoy /> },
  { grupo: 'Catálogo', href: '/catalogo/', rotulo: 'Profissões e regiões', icone: <LayoutGrid />, contador: (r) => r.especialidades_sugeridas },
  { grupo: 'Catálogo', href: '/precos/', rotulo: 'Preços e mínimos', icone: <Tags /> },
  { grupo: 'Catálogo', href: '/configuracoes/', rotulo: 'Configurações', icone: <Settings /> },
  { grupo: 'Equipe', href: '/equipe/', rotulo: 'Equipe', icone: <UsersRound /> },
  { grupo: 'Equipe', href: '/registro/', rotulo: 'Registro da equipe', icone: <History /> },
];

// A caixa de e-mail tem SQL próprio: se ainda não foi aplicado, o resto do painel segue normal.
const contagemEmails = () => rpc<ContagemEmails>('admin_suporte_contagem').catch(() => undefined);
// Sem o SQL das ferramentas de gestão, o menu segue sem a contagem.
const contagemAtencao = () => rpc<NonNullable<Resumo['atencao']>>('admin_atencao_contagem').catch(() => undefined);

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

const motivosSenha = (e: unknown): string[] =>
  e && typeof e === 'object' && 'reasons' in e && Array.isArray((e as { reasons: unknown }).reasons) ? (e as { reasons: string[] }).reasons : [];

const retornoPainel = () => `${window.location.origin}/admin/`;

/** O Supabase usa o mesmo erro "weak_password" para senha vazada, curta ou sem números; os motivos dizem qual. */
function traduzirAuth(msg: string, motivos: string[] = []) {
  if (motivos.includes('pwned') || /pwned|known to be weak|data breach/i.test(msg)) {
    return 'Essa senha já apareceu em vazamentos de dados na internet, então pode ser descoberta por outras pessoas. Por segurança, escolha outra. Uma frase longa que só você conhece funciona bem.';
  }
  if (motivos.includes('length')) return 'A senha precisa ter pelo menos 8 caracteres.';
  if (motivos.includes('characters')) return 'A senha precisa misturar letras e números.';
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
        if (error) setErro(traduzirAuth(error.message, motivosSenha(error)));
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
    if (error) setErro(/different from the old/i.test(error.message) ? 'Use uma senha diferente da anterior.' : traduzirAuth(error.message, motivosSenha(error)));
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

function SemPermissao({ cargo }: { cargo?: string }) {
  return (
    <div className="cartao" style={{ maxWidth: 520, margin: '48px auto', textAlign: 'center', padding: 32 }}>
      <Lock size={36} color="#64748b" />
      <h1 style={{ fontSize: 22, margin: '12px 0 6px' }}>Esta parte não faz parte do seu cargo</h1>
      <p style={{ color: 'var(--texto-suave)', margin: '0 0 20px' }}>
        {cargo ? <>Você entrou como <strong>{cargo}</strong>. </> : null}Se precisar deste acesso, fale com o seu gerente ou com o dono do painel.
      </p>
      <Link href="/" className="botao contorno">Voltar para o Início</Link>
    </div>
  );
}

export default function Painel({ children }: { children: ReactNode }) {
  const [sessao, setSessao] = useState<Session | null | undefined>(undefined);
  const [acesso, setAcesso] = useState<'verificando' | 'ok' | 'nao_admin' | 'sql_pendente'>('verificando');
  const [nome, setNome] = useState('');
  const [foto, setFoto] = useState<string | null>(null);
  const [editarFoto, setEditarFoto] = useState(false);
  const [resumo, setResumo] = useState<Resumo | null>(null);
  const [menuAberto, setMenuAberto] = useState(false);
  const [recuperando, setRecuperando] = useState(false);
  const [meuAcesso, setMeuAcesso] = useState<MeuAcesso | null>(null);
  const rota = usePathname();

  useEffect(() => {
    db().auth.getSession().then(({ data }) => setSessao(data.session));
    const { data } = db().auth.onAuthStateChange((evento, s) => {
      if (evento === 'PASSWORD_RECOVERY') setRecuperando(true);
      setSessao(s);
    });
    return () => data.subscription.unsubscribe();
  }, []);

  const podeEmails = !meuAcesso || meuAcesso.permissoes.includes('emails');
  const atualizarResumo = useCallback(() => {
    Promise.all([rpc<Resumo>('admin_resumo'), podeEmails ? contagemEmails() : Promise.resolve(undefined), contagemAtencao()])
      .then(([r, emails, atencao]) => setResumo({ ...r, emails, atencao })).catch((e: ErroPainel) => {
      if (e.codigo === 'sql_pendente') setAcesso('sql_pendente');
    });
  }, [podeEmails]);

  useEffect(() => {
    if (!sessao) return;
    setAcesso('verificando');
    (async () => {
      try {
        const admin = await rpc<boolean>('e_admin');
        if (!admin) { setAcesso('nao_admin'); return; }
        const { data } = await db().from('perfis').select('nome, foto_url').eq('id', sessao.user.id).maybeSingle();
        setNome(data?.nome || sessao.user.email || '');
        setFoto(data?.foto_url || null);
        // Sem o SQL dos cargos, a função não existe e o painel segue como antes (tudo liberado).
        const cargo = await rpc<MeuAcesso>('admin_meu_acesso').catch(() => null);
        setMeuAcesso(cargo);
        const podeEmails = !cargo || cargo.permissoes.includes('emails');
        const [r, emails, atencao] = await Promise.all([rpc<Resumo>('admin_resumo'), podeEmails ? contagemEmails() : Promise.resolve(undefined), contagemAtencao()]);
        setResumo({ ...r, emails, atencao });
        setAcesso('ok');
      } catch (e) {
        setAcesso((e as ErroPainel).codigo === 'sql_pendente' ? 'sql_pendente' : 'nao_admin');
      }
    })();
  }, [sessao]);

  // Contadores do menu (emergências principalmente) se atualizam sozinhos.
  useEffect(() => {
    if (acesso !== 'ok') return;
    // Quem atende emergências confere a cada 20 s; os outros, a cada minuto.
    const emergencias = !meuAcesso || meuAcesso.permissoes.includes('emergencias');
    const t = setInterval(atualizarResumo, emergencias ? 20000 : 60000);
    return () => clearInterval(t);
  }, [acesso, atualizarResumo, meuAcesso]);

  useEffect(() => setMenuAberto(false), [rota]);

  const sair = () => db().auth.signOut();

  if (sessao === undefined) return <Carregando />;
  if (!sessao) return <Avisos><Entrar /></Avisos>;
  if (recuperando) return <NovaSenha pronto={() => setRecuperando(false)} />;
  if (acesso === 'verificando') return <Carregando texto="Conferindo o acesso…" />;
  if (acesso !== 'ok') return <SemAcesso motivo={acesso} sair={sair} />;

  const pode = (p: Permissao) => !meuAcesso || meuAcesso.permissoes.includes(p);
  const podeRota = (href: string) => pode(permissaoDaRota(href));
  const itens = menu.filter((m) => podeRota(m.href));
  const liberada = podeRota(rota);

  return (
    <PainelCtx.Provider value={{ resumo, atualizarResumo, usuarioId: sessao.user.id, nome, foto, mudarFoto: setFoto, acesso: meuAcesso, pode, podeRota }}>
      <Avisos>
        <div className="casca">
          {menuAberto ? <div className="veu" onClick={() => setMenuAberto(false)} /> : null}
          <aside className={`lateral ${menuAberto ? 'aberta' : ''}`}>
            <div className="marca">
              <img src="/admin/simbolo.svg" alt="" />
              <div><strong>iService</strong><span>Equipe</span></div>
            </div>
            <BuscaGlobal paginas={itens.map((m) => ({ href: m.href, rotulo: m.rotulo, grupo: m.grupo, icone: m.icone }))}
              podePessoas={pode('pessoas')} podePedidos={pode('pedidos')} podeEmails={pode('emails')} />
            <nav aria-label="Menu do painel">
              {itens.map((m, i) => {
                const n = resumo && m.contador ? m.contador(resumo) : 0;
                const novoGrupo = m.grupo && m.grupo !== itens[i - 1]?.grupo;
                return (
                  <div key={m.href} style={{ display: 'contents' }}>
                    {novoGrupo ? <div className="grupo">{m.grupo}</div> : null}
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
              <button className="avatar-botao" onClick={() => setEditarFoto(true)}
                title={foto ? 'Trocar sua foto' : 'Colocar sua foto'} aria-label={foto ? 'Trocar sua foto de perfil' : 'Colocar sua foto de perfil'}>
                <Avatar nome={nome} foto={foto} tamanho={34} />
                <span className="lapis"><Camera /></span>
              </button>
              <div className="quem"><strong>{nome}</strong><span>{meuAcesso?.cargo_nome ?? 'Equipe iService'}</span></div>
              <button onClick={sair} title="Sair" aria-label="Sair"><LogOut size={16} /></button>
            </div>
          </aside>
          <main className="conteudo">
            <div className="topo-movel">
              <button onClick={() => setMenuAberto(true)} aria-label="Abrir menu"><Menu /></button>
              <strong>iService · Equipe</strong>
              <span className="espaco" />
              <button onClick={() => window.dispatchEvent(new KeyboardEvent('keydown', { key: 'k', ctrlKey: true }))} aria-label="Buscar no painel"><Search size={20} /></button>
            </div>
            {pode('emergencias') ? <AlertaEmergencia abertas={resumo?.emergencias_abertas ?? 0} semFaixa={rota.startsWith('/emergencias')} /> : null}
            {liberada ? children : <SemPermissao cargo={meuAcesso?.cargo_nome} />}
          </main>
        </div>
        <DialogoFoto pessoa={editarFoto ? { id: sessao.user.id, nome, foto } : null} propria
          fechar={() => setEditarFoto(false)} salvo={setFoto} />
      </Avisos>
    </PainelCtx.Provider>
  );
}

export function Cabecalho({ titulo, texto, acoes, voltar, ajuda }: {
  titulo: string; texto?: ReactNode; acoes?: ReactNode; voltar?: { href: string; rotulo: string };
  /** Explicação da tela, no botão "?" ao lado do título. */
  ajuda?: ReactNode;
}) {
  return (
    <>
      {voltar ? <Link className="voltar" href={voltar.href}>‹ {voltar.rotulo}</Link> : null}
      <div className="cabecalho">
        <div>
          <h1 className="com-ajuda">{titulo}{ajuda ? <Ajuda titulo={titulo}>{ajuda}</Ajuda> : null}</h1>
          {texto ? <p>{texto}</p> : null}
        </div>
        {acoes ? <div className="acoes">{acoes}</div> : null}
      </div>
    </>
  );
}
