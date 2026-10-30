'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import {
  BadgeCheck, BarChart3, ClipboardList, Globe, Flag, Gauge, History, LayoutGrid, Loader2, LogOut, Map as MapaIcone, Megaphone, Menu,
  ShieldAlert, ShieldCheck, Siren, Tags, Users, Settings, Lock, Mail, CheckCircle2,
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
  { href: '/registro/', rotulo: 'Registro da equipe', icone: <History /> },
];

function ativo(rota: string, href: string) {
  const r = rota.replace(/^\/admin/, '') || '/';
  if (href === '/') return r === '/';
  const base = href.replace(/\/$/, '');
  return r === href || r.startsWith(base + '/') || r === base || (base === '/cadastros' && r.startsWith('/cadastro')) ||
    (base === '/pedidos' && r.startsWith('/pedido')) || (base === '/pessoas' && r.startsWith('/pessoa'));
}

function Entrar() {
  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  const [erro, setErro] = useState('');
  const [ocupado, setOcupado] = useState(false);
  const enviar = async (e: React.FormEvent) => {
    e.preventDefault();
    setOcupado(true);
    setErro('');
    const { error } = await db().auth.signInWithPassword({ email: email.trim(), password: senha });
    setOcupado(false);
    if (error) setErro(/Invalid login/i.test(error.message) ? 'E-mail ou senha incorretos.' : /banned/i.test(error.message) ? 'Esta conta está suspensa.' : error.message);
  };
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
            <h1>Entrar</h1>
            <p>Use a conta iService que tem acesso de equipe.</p>
          </div>
          <div className="campo">
            <label htmlFor="email">E-mail</label>
            <div className="busca" style={{ maxWidth: 'none' }}>
              <Mail />
              <input id="email" className="entrada" type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
            </div>
          </div>
          <div className="campo">
            <label htmlFor="senha">Senha</label>
            <div className="busca" style={{ maxWidth: 'none' }}>
              <Lock />
              <input id="senha" className="entrada" type="password" autoComplete="current-password" required value={senha} onChange={(e) => setSenha(e.target.value)} />
            </div>
          </div>
          {erro ? <div className="erro-caixa" role="alert">{erro}</div> : null}
          <button className="botao primario grande cheio" disabled={ocupado}>{ocupado ? <Loader2 className="girar" /> : null} Entrar</button>
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
            <p>Esta conta não faz parte da equipe iService. Peça para alguém da equipe liberar o seu e-mail.</p>
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
  const rota = usePathname();

  useEffect(() => {
    db().auth.getSession().then(({ data }) => setSessao(data.session));
    const { data } = db().auth.onAuthStateChange((_e, s) => setSessao(s));
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
