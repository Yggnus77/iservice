'use client';

import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from 'react';
import { AlertTriangle, CheckCircle2, Download, FileText, Inbox, Loader2, RotateCw, X, ZoomIn, ZoomOut } from 'lucide-react';
import { iniciais, type Tom } from '@/lib/formatos';
import { ErroPainel } from '@/lib/supabase';
import { urlArquivo, urlFoto, ePdf } from '@/lib/arquivos';

export function Selo({ tom = 'neutro', children, icone }: { tom?: Tom; children: ReactNode; icone?: ReactNode }) {
  return <span className={`selo ${tom}`}>{icone}{children}</span>;
}

export function SeloStatus({ mapa, valor }: { mapa: Record<string, { rotulo: string; tom: Tom }>; valor?: string | null }) {
  const s = (valor && mapa[valor]) || { rotulo: valor || '—', tom: 'neutro' as Tom };
  return <Selo tom={s.tom}>{s.rotulo}</Selo>;
}

export function Avatar({ nome, foto, tamanho = 36 }: { nome?: string | null; foto?: string | null; tamanho?: number }) {
  const [falhou, setFalhou] = useState(false);
  const url = urlFoto(foto);
  return (
    <span className="avatar" style={{ width: tamanho, height: tamanho, fontSize: tamanho * 0.36 }}>
      {url && !falhou ? <img src={url} alt="" onError={() => setFalhou(true)} /> : iniciais(nome)}
    </span>
  );
}

export function Pessoa({ nome, sub, foto, tamanho }: { nome?: string | null; sub?: ReactNode; foto?: string | null; tamanho?: number }) {
  return (
    <span className="pessoa">
      <Avatar nome={nome} foto={foto} tamanho={tamanho} />
      <span style={{ minWidth: 0 }}>
        <span className="nome">{nome || 'Sem nome'}</span>
        {sub ? <span className="sub">{sub}</span> : null}
      </span>
    </span>
  );
}

export function Vazio({ titulo, texto, icone }: { titulo: string; texto?: string; icone?: ReactNode }) {
  return (
    <div className="vazio">
      <div className="icone">{icone ?? <Inbox size={24} />}</div>
      <strong>{titulo}</strong>
      {texto ? <span>{texto}</span> : null}
    </div>
  );
}

export function Carregando({ texto = 'Carregando…' }: { texto?: string }) {
  return (
    <div className="carregando" role="status">
      <Loader2 size={18} className="girar" /> {texto}
    </div>
  );
}

export function ErroCaixa({ erro, tentar }: { erro: unknown; tentar?: () => void }) {
  const msg = erro instanceof Error ? erro.message : String(erro);
  return (
    <div className="erro-caixa" role="alert">
      <AlertTriangle size={20} style={{ flex: 'none', marginTop: 1 }} />
      <div style={{ flex: 1 }}>
        <strong>Não foi possível carregar.</strong>
        <div>{msg}</div>
      </div>
      {tentar ? <button className="botao contorno pequeno" onClick={tentar}><RotateCw /> Tentar de novo</button> : null}
    </div>
  );
}

export function Estrelas({ nota }: { nota: number }) {
  return <span className="estrelas" aria-label={`${nota} de 5 estrelas`}>{'★'.repeat(nota)}<span style={{ color: '#d5dbe6' }}>{'★'.repeat(5 - nota)}</span></span>;
}

export function Interruptor({ ligado, mudar, rotulo, desativado }: { ligado: boolean; mudar: (v: boolean) => void; rotulo: string; desativado?: boolean }) {
  return (
    <label className="interruptor" title={rotulo}>
      <input type="checkbox" checked={ligado} disabled={desativado} onChange={(e) => mudar(e.target.checked)} aria-label={rotulo} />
      <span />
    </label>
  );
}

export function Abas<T extends string>({ abas, ativa, mudar }: { abas: { id: T; rotulo: string; n?: number }[]; ativa: T; mudar: (v: T) => void }) {
  return (
    <div className="abas" role="tablist">
      {abas.map((a) => (
        <button key={a.id} role="tab" aria-selected={a.id === ativa} className={a.id === ativa ? 'ativa' : ''} onClick={() => mudar(a.id)}>
          {a.rotulo}
          {a.n !== undefined ? <span className="n">{a.n}</span> : null}
        </button>
      ))}
    </div>
  );
}

// ------------------------------------------------------------- carregar dados
export function useCarregar<T>(buscar: () => Promise<T>, deps: unknown[]) {
  const [dados, setDados] = useState<T | null>(null);
  const [erro, setErro] = useState<unknown>(null);
  const [carregando, setCarregando] = useState(true);
  const seq = useRef(0);
  const recarregar = useCallback(() => {
    const n = ++seq.current;
    setCarregando(true);
    setErro(null);
    buscar()
      .then((d) => { if (n === seq.current) setDados(d); })
      .catch((e) => { if (n === seq.current) setErro(e); })
      .finally(() => { if (n === seq.current) setCarregando(false); });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  useEffect(() => { recarregar(); }, [recarregar]);
  return { dados, erro, carregando, recarregar, setDados };
}

// ------------------------------------------------------------- avisos (toast)
type Aviso = { id: number; texto: string; erro?: boolean };
const AvisosCtx = createContext<(texto: string, erro?: boolean) => void>(() => {});
export const useAviso = () => useContext(AvisosCtx);

export function Avisos({ children }: { children: ReactNode }) {
  const [lista, setLista] = useState<Aviso[]>([]);
  const avisar = useCallback((texto: string, erro?: boolean) => {
    const id = Date.now() + Math.random();
    setLista((l) => [...l, { id, texto, erro }]);
    setTimeout(() => setLista((l) => l.filter((a) => a.id !== id)), erro ? 6000 : 3500);
  }, []);
  return (
    <AvisosCtx.Provider value={avisar}>
      {children}
      <div className="avisos" aria-live="polite">
        {lista.map((a) => (
          <div key={a.id} className={`aviso ${a.erro ? 'erro' : ''}`}>
            {a.erro ? <AlertTriangle /> : <CheckCircle2 />} {a.texto}
          </div>
        ))}
      </div>
    </AvisosCtx.Provider>
  );
}

/** Executa uma ação do painel com aviso de sucesso/erro. Devolve true se deu certo. */
export function useAcao() {
  const avisar = useAviso();
  const [ocupado, setOcupado] = useState(false);
  const executar = useCallback(async (fn: () => Promise<unknown>, sucesso?: string) => {
    setOcupado(true);
    try {
      await fn();
      if (sucesso) avisar(sucesso);
      return true;
    } catch (e) {
      avisar(e instanceof ErroPainel || e instanceof Error ? e.message : 'Algo deu errado.', true);
      return false;
    } finally {
      setOcupado(false);
    }
  }, [avisar]);
  return { executar, ocupado };
}

// ------------------------------------------------------------- diálogos
export function Dialogo({ aberto, fechar, titulo, texto, children, rodape, largo, icone }: {
  aberto: boolean; fechar: () => void; titulo: string; texto?: ReactNode; children?: ReactNode; rodape?: ReactNode; largo?: boolean; icone?: ReactNode;
}) {
  useEffect(() => {
    if (!aberto) return;
    const tecla = (e: KeyboardEvent) => { if (e.key === 'Escape') fechar(); };
    window.addEventListener('keydown', tecla);
    return () => window.removeEventListener('keydown', tecla);
  }, [aberto, fechar]);
  if (!aberto) return null;
  return (
    <div className="dialogo-fundo" onMouseDown={(e) => { if (e.target === e.currentTarget) fechar(); }}>
      <div className={`dialogo ${largo ? 'largo' : ''}`} role="dialog" aria-modal="true" aria-label={titulo}>
        <div className="cab">
          {icone}
          <div style={{ flex: 1 }}>
            <h3>{titulo}</h3>
            {texto ? <p>{texto}</p> : null}
          </div>
          <button className="botao fantasma pequeno" onClick={fechar} aria-label="Fechar"><X /></button>
        </div>
        {children ? <div className="meio">{children}</div> : null}
        {rodape ? <div className="pe">{rodape}</div> : null}
      </div>
    </div>
  );
}

/** Pede um texto (motivo, observação) antes de confirmar uma ação. */
export function DialogoTexto({ aberto, fechar, titulo, texto, rotulo, placeholder, confirmar, botao, tom = 'primario', obrigatorio = true, sugestoes, inicial = '' }: {
  aberto: boolean; fechar: () => void; titulo: string; texto?: ReactNode; rotulo: string; placeholder?: string;
  confirmar: (valor: string) => Promise<boolean | void>; botao: string; tom?: 'primario' | 'perigo' | 'sucesso'; obrigatorio?: boolean;
  sugestoes?: string[]; inicial?: string;
}) {
  const [valor, setValor] = useState(inicial);
  const [ocupado, setOcupado] = useState(false);
  useEffect(() => { if (aberto) setValor(inicial); }, [aberto, inicial]);
  const enviar = async () => {
    setOcupado(true);
    const ok = await confirmar(valor.trim());
    setOcupado(false);
    if (ok !== false) fechar();
  };
  return (
    <Dialogo aberto={aberto} fechar={fechar} titulo={titulo} texto={texto}
      rodape={<>
        <button className="botao contorno" onClick={fechar}>Cancelar</button>
        <button className={`botao ${tom}`} disabled={ocupado || (obrigatorio && !valor.trim())} onClick={enviar}>
          {ocupado ? <Loader2 className="girar" /> : null}{botao}
        </button>
      </>}>
      <div className="campo">
        <label htmlFor="dlg-texto">{rotulo}</label>
        <textarea id="dlg-texto" className="entrada" value={valor} placeholder={placeholder} onChange={(e) => setValor(e.target.value)} autoFocus />
      </div>
      {sugestoes?.length ? (
        <div className="linha-flex">
          {sugestoes.map((s) => <button key={s} className="botao contorno pequeno" onClick={() => setValor(s)}>{s}</button>)}
        </div>
      ) : null}
    </Dialogo>
  );
}

// ------------------------------------------------------------- arquivos
export function useUrlArquivo(bucket: string, caminho?: string | null) {
  const [url, setUrl] = useState<string | null>(null);
  const [falhou, setFalhou] = useState(false);
  useEffect(() => {
    let vivo = true;
    setUrl(null);
    setFalhou(false);
    urlArquivo(bucket, caminho).then((u) => { if (vivo) { setUrl(u); setFalhou(!u); } });
    return () => { vivo = false; };
  }, [bucket, caminho]);
  return { url, falhou };
}

export function Visor({ itens, inicio = 0, fechar }: { itens: { titulo: string; url: string | null; caminho?: string | null }[]; inicio?: number; fechar: () => void }) {
  const [zoom, setZoom] = useState(1);
  const [giro, setGiro] = useState(0);
  const [i, setI] = useState(inicio);
  useEffect(() => {
    const tecla = (e: KeyboardEvent) => {
      if (e.key === 'Escape') fechar();
      if (e.key === 'ArrowRight') setI((x) => Math.min(itens.length - 1, x + 1));
      if (e.key === 'ArrowLeft') setI((x) => Math.max(0, x - 1));
    };
    window.addEventListener('keydown', tecla);
    return () => window.removeEventListener('keydown', tecla);
  }, [fechar, itens.length]);
  const atual = itens[i];
  if (!atual) return null;
  return (
    <div className="visor" role="dialog" aria-modal="true" aria-label={atual.titulo}>
      <div className="barra">
        <strong>{atual.titulo}{itens.length > 1 ? ` (${i + 1} de ${itens.length})` : ''}</strong>
        {itens.length > 1 ? <>
          <button onClick={() => setI(Math.max(0, i - 1))} disabled={i === 0}>‹ Anterior</button>
          <button onClick={() => setI(Math.min(itens.length - 1, i + 1))} disabled={i === itens.length - 1}>Próximo ›</button>
        </> : null}
        <button onClick={() => setZoom((z) => Math.max(0.5, z - 0.25))} aria-label="Diminuir"><ZoomOut size={16} /></button>
        <button onClick={() => setZoom((z) => Math.min(4, z + 0.25))} aria-label="Aumentar"><ZoomIn size={16} /></button>
        <button onClick={() => setGiro((g) => (g + 90) % 360)} aria-label="Girar"><RotateCw size={16} /></button>
        {atual.url ? <a href={atual.url} target="_blank" rel="noreferrer"><Download size={16} /> Abrir</a> : null}
        <button onClick={fechar} aria-label="Fechar"><X size={16} /></button>
      </div>
      <div className="area">
        {!atual.url ? <Carregando /> : ePdf(atual.caminho) ? <iframe src={atual.url} title={atual.titulo} /> :
          <img src={atual.url} alt={atual.titulo} style={{ transform: `scale(${zoom}) rotate(${giro}deg)` }} />}
      </div>
    </div>
  );
}

/** Miniatura de um arquivo do Storage, que abre no visor ao clicar. */
export function Miniatura({ bucket, caminho, titulo, aoAbrir }: { bucket: string; caminho: string; titulo: string; aoAbrir?: (url: string | null) => void }) {
  const { url, falhou } = useUrlArquivo(bucket, caminho);
  const [aberto, setAberto] = useState(false);
  if (ePdf(caminho)) {
    return <button className="botao contorno pequeno" onClick={() => url && window.open(url, '_blank')}><FileText /> {titulo}</button>;
  }
  return (
    <>
      {falhou ? <span className="texto-fraco">Arquivo indisponível</span> :
        url ? <img src={url} alt={titulo} onClick={() => (aoAbrir ? aoAbrir(url) : setAberto(true))} /> : <span className="esqueleto" style={{ width: 72, height: 72, display: 'inline-block' }} />}
      {aberto ? <Visor itens={[{ titulo, url, caminho }]} fechar={() => setAberto(false)} /> : null}
    </>
  );
}
