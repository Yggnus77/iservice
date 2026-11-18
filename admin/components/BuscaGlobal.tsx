'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { ArrowRight, ClipboardList, CornerDownLeft, LayoutGrid, Loader2, Mail, Search, UserRound, X } from 'lucide-react';
import { rpc } from '@/lib/supabase';
import { haQuanto, statusPedido, telefone } from '@/lib/formatos';
import { Avatar, Selo, SeloStatus } from './ui';

type Pagina = { href: string; rotulo: string; grupo: string; icone: ReactNode };
type PessoaAchada = { id: string; nome: string; email: string | null; telefone: string | null; foto_url: string | null; e_profissional: boolean; e_cliente: boolean; suspenso: boolean };
type PedidoAchado = { id: string; codigo: string; status: string; cliente: string; profissional: string; profissao: string; criado_em: string };
type EmailAchado = { id: number; protocolo: string; assunto: string; contato_email: string; contato_nome: string | null; status: string };
type Item = { chave: string; href: string; grupo: string; conteudo: ReactNode };

const semAcento = (t: string) => t.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase();

/** Um campo só para achar pessoa, pedido, e-mail ou tela do painel. Atalho: Ctrl+K (ou /). */
export function BuscaGlobal({ paginas, podePessoas, podePedidos, podeEmails }: {
  paginas: Pagina[]; podePessoas: boolean; podePedidos: boolean; podeEmails: boolean;
}) {
  const router = useRouter();
  const [aberta, setAberta] = useState(false);
  const [texto, setTexto] = useState('');
  const [buscando, setBuscando] = useState(false);
  const [pessoas, setPessoas] = useState<PessoaAchada[]>([]);
  const [pedidos, setPedidos] = useState<PedidoAchado[]>([]);
  const [emails, setEmails] = useState<EmailAchado[]>([]);
  const [selecao, setSelecao] = useState(0);
  const campo = useRef<HTMLInputElement>(null);
  const seq = useRef(0);

  useEffect(() => {
    const tecla = (e: KeyboardEvent) => {
      const digitando = /^(INPUT|TEXTAREA|SELECT)$/.test((e.target as HTMLElement)?.tagName ?? '') || (e.target as HTMLElement)?.isContentEditable;
      if ((e.key === 'k' || e.key === 'K') && (e.ctrlKey || e.metaKey)) { e.preventDefault(); setAberta(true); }
      else if (e.key === '/' && !digitando) { e.preventDefault(); setAberta(true); }
    };
    window.addEventListener('keydown', tecla);
    return () => window.removeEventListener('keydown', tecla);
  }, []);

  useEffect(() => {
    if (aberta) { setTimeout(() => campo.current?.focus(), 10); }
    else { setTexto(''); setPessoas([]); setPedidos([]); setEmails([]); }
  }, [aberta]);

  const termo = texto.trim();
  useEffect(() => {
    if (termo.length < 2) { setPessoas([]); setPedidos([]); setEmails([]); setBuscando(false); return; }
    const n = ++seq.current;
    setBuscando(true);
    const t = setTimeout(async () => {
      const [a, b, c] = await Promise.allSettled([
        podePessoas ? rpc<PessoaAchada[]>('admin_usuarios', { p_texto: termo, p_filtro: 'todos', p_limite: 6, p_pular: 0 }) : Promise.resolve([]),
        podePedidos ? rpc<PedidoAchado[]>('admin_pedidos', { p_texto: termo, p_limite: 6, p_pular: 0 }) : Promise.resolve([]),
        podeEmails ? rpc<EmailAchado[]>('admin_suporte_conversas', { p_status: 'todos', p_quem: 'todos', p_busca: termo, p_limite: 5 }) : Promise.resolve([]),
      ]);
      if (n !== seq.current) return;
      setPessoas(a.status === 'fulfilled' ? a.value ?? [] : []);
      setPedidos(b.status === 'fulfilled' ? b.value ?? [] : []);
      setEmails(c.status === 'fulfilled' ? c.value ?? [] : []);
      setBuscando(false);
    }, 250);
    return () => clearTimeout(t);
  }, [termo, podePessoas, podePedidos, podeEmails]);

  const itens = useMemo<Item[]>(() => {
    const lista: Item[] = [];
    const q = semAcento(termo);
    if (q) {
      paginas.filter((p) => semAcento(p.rotulo).includes(q) || semAcento(p.grupo).includes(q)).slice(0, 4).forEach((p) => lista.push({
        chave: 'pg' + p.href, href: p.href, grupo: 'Telas do painel',
        conteudo: <><span className="busca-icone">{p.icone}</span><span className="busca-texto"><strong>{p.rotulo}</strong><span>{p.grupo || 'Painel'}</span></span></>,
      }));
    }
    pedidos.forEach((p) => lista.push({
      chave: 'pd' + p.id, href: `/pedido/?id=${p.id}`, grupo: 'Pedidos',
      conteudo: <><span className="busca-icone"><ClipboardList /></span>
        <span className="busca-texto"><strong><span className="mono">{p.codigo}</span> · {p.profissao}</strong><span>{p.cliente} com {p.profissional} · {haQuanto(p.criado_em)}</span></span>
        <SeloStatus mapa={statusPedido} valor={p.status} /></>,
    }));
    pessoas.forEach((p) => lista.push({
      chave: 'ps' + p.id, href: `/pessoa/?id=${p.id}`, grupo: 'Pessoas',
      conteudo: <><Avatar nome={p.nome} foto={p.foto_url} tamanho={30} />
        <span className="busca-texto"><strong>{p.nome || 'Sem nome'}</strong><span>{p.email || telefone(p.telefone)}</span></span>
        {p.suspenso ? <Selo tom="vermelho">Suspensa</Selo> : p.e_profissional ? <Selo tom="laranja">Profissional</Selo> : <Selo tom="azul">Cliente</Selo>}</>,
    }));
    emails.forEach((e) => lista.push({
      chave: 'em' + e.id, href: `/emails/?id=${e.id}`, grupo: 'E-mails',
      conteudo: <><span className="busca-icone"><Mail /></span>
        <span className="busca-texto"><strong>{e.assunto}</strong><span><span className="mono">{e.protocolo}</span> · {e.contato_nome || e.contato_email}</span></span></>,
    }));
    return lista;
  }, [termo, paginas, pedidos, pessoas, emails]);

  useEffect(() => setSelecao(0), [itens.length, termo]);

  const ir = (href: string) => { setAberta(false); router.push(href); };

  return (
    <>
      <button type="button" className="busca-gatilho" onClick={() => setAberta(true)} aria-label="Buscar no painel (Ctrl+K)">
        <Search /> <span>Buscar…</span> <kbd>Ctrl K</kbd>
      </button>
      {aberta ? createPortal(
        <div className="busca-fundo" onMouseDown={(e) => { if (e.target === e.currentTarget) setAberta(false); }}>
          <div className="busca-caixa" role="dialog" aria-modal="true" aria-label="Buscar no painel">
            <div className="busca-campo">
              {buscando ? <Loader2 className="girar" /> : <Search />}
              <input ref={campo} value={texto} onChange={(e) => setTexto(e.target.value)} aria-label="O que você procura"
                placeholder={`${podePedidos ? 'Código do pedido, ' : ''}${podePessoas ? 'nome, CPF, telefone, e-mail' : 'nome'}${podeEmails ? ', protocolo' : ''} ou uma tela`}
                onKeyDown={(e) => {
                  if (e.key === 'Escape') setAberta(false);
                  else if (e.key === 'ArrowDown') { e.preventDefault(); setSelecao((s) => Math.min(s + 1, itens.length - 1)); }
                  else if (e.key === 'ArrowUp') { e.preventDefault(); setSelecao((s) => Math.max(s - 1, 0)); }
                  else if (e.key === 'Enter' && itens[selecao]) { e.preventDefault(); ir(itens[selecao].href); }
                }} />
              <button className="botao fantasma pequeno" onClick={() => setAberta(false)} aria-label="Fechar"><X /></button>
            </div>
            <div className="busca-resultados">
              {termo.length < 2 ? (
                <div className="busca-dica">
                  <LayoutGrid size={18} />
                  <div>Digite pelo menos 2 letras. Dá para achar {[podePedidos && 'pedido pelo código', podePessoas && 'pessoa pelo nome, CPF, telefone ou e-mail',
                    podeEmails && 'e-mail pelo protocolo (S-00012)', 'qualquer tela do painel'].filter(Boolean).join(', ')}.</div>
                </div>
              ) : !itens.length && !buscando ? (
                <div className="busca-dica"><Search size={18} /><div>Nada encontrado para “{termo}”.</div></div>
              ) : itens.map((it, i) => (
                <div key={it.chave} style={{ display: 'contents' }}>
                  {it.grupo !== itens[i - 1]?.grupo ? <div className="busca-grupo">{it.grupo}</div> : null}
                  <button type="button" className={`busca-item ${i === selecao ? 'ativo' : ''}`} onMouseEnter={() => setSelecao(i)} onClick={() => ir(it.href)}>
                    {it.conteudo}
                    <span className="busca-ir">{i === selecao ? <CornerDownLeft /> : <ArrowRight />}</span>
                  </button>
                </div>
              ))}
            </div>
            <div className="busca-rodape"><span><kbd>↑</kbd><kbd>↓</kbd> escolher</span><span><kbd>Enter</kbd> abrir</span><span><kbd>Esc</kbd> fechar</span>
              <span className="espaco" /><UserRound size={13} /> só aparece o que o seu cargo pode ver</div>
          </div>
        </div>, document.body,
      ) : null}
    </>
  );
}
