'use client';

import { useCallback, useEffect, useId, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import { CircleHelp } from 'lucide-react';

/**
 * Botão "?" com uma explicação curta. Abre ao clicar (ou tocar, no celular) e fecha
 * ao clicar fora, apertar Esc ou rolar a página. O texto deve dizer o que é e o que fazer.
 */
export function Ajuda({ children, titulo, claro }: { children: ReactNode; titulo?: string; claro?: boolean }) {
  const [aberta, setAberta] = useState(false);
  const [pos, setPos] = useState<{ top: number; left: number; acima: boolean } | null>(null);
  const botao = useRef<HTMLButtonElement>(null);
  const balao = useRef<HTMLDivElement>(null);
  const id = useId();

  const posicionar = useCallback(() => {
    const b = botao.current?.getBoundingClientRect();
    if (!b) return;
    const largura = Math.min(320, window.innerWidth - 24);
    const altura = balao.current?.offsetHeight ?? 120;
    let left = b.left + b.width / 2 - largura / 2;
    left = Math.max(12, Math.min(left, window.innerWidth - largura - 12));
    const acima = b.bottom + altura + 12 > window.innerHeight && b.top - altura - 12 > 0;
    setPos({ top: acima ? b.top - altura - 8 : b.bottom + 8, left, acima });
  }, []);

  useLayoutEffect(() => { if (aberta) posicionar(); }, [aberta, posicionar]);

  useEffect(() => {
    if (!aberta) return;
    const fora = (e: MouseEvent | TouchEvent) => {
      const alvo = e.target as Node;
      if (!balao.current?.contains(alvo) && !botao.current?.contains(alvo)) setAberta(false);
    };
    const tecla = (e: KeyboardEvent) => { if (e.key === 'Escape') { setAberta(false); botao.current?.focus(); } };
    const fechar = () => setAberta(false);
    document.addEventListener('mousedown', fora);
    document.addEventListener('touchstart', fora);
    document.addEventListener('keydown', tecla);
    window.addEventListener('scroll', fechar, true);
    window.addEventListener('resize', fechar);
    return () => {
      document.removeEventListener('mousedown', fora);
      document.removeEventListener('touchstart', fora);
      document.removeEventListener('keydown', tecla);
      window.removeEventListener('scroll', fechar, true);
      window.removeEventListener('resize', fechar);
    };
  }, [aberta]);

  return (
    <>
      <button ref={botao} type="button" className={`ajuda-botao ${claro ? 'claro' : ''} ${aberta ? 'aberta' : ''}`}
        aria-label={titulo ? `O que é: ${titulo}` : 'Explicação'} aria-expanded={aberta} aria-controls={aberta ? id : undefined}
        onClick={(e) => { e.preventDefault(); e.stopPropagation(); setAberta((v) => !v); }}>
        <CircleHelp />
      </button>
      {aberta ? (
        <div ref={balao} id={id} role="tooltip" className="ajuda-balao" onClick={(e) => e.stopPropagation()}
          style={{ top: pos?.top ?? -9999, left: pos?.left ?? -9999, width: Math.min(320, typeof window === 'undefined' ? 320 : window.innerWidth - 24) }}>
          {titulo ? <strong>{titulo}</strong> : null}
          <div>{children}</div>
        </div>
      ) : null}
    </>
  );
}
