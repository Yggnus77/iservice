'use client';

import Link from 'next/link';
import { useEffect, useRef } from 'react';
import { Siren } from 'lucide-react';

/** Toca um alarme curto (três bipes). O navegador só libera som depois do primeiro clique na página. */
function tocarAlarme() {
  try {
    const Ctx = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!Ctx) return;
    const ctx = new Ctx();
    [0, 0.35, 0.7].forEach((t) => {
      const o = ctx.createOscillator();
      const g = ctx.createGain();
      o.type = 'square';
      o.frequency.setValueAtTime(880, ctx.currentTime + t);
      o.frequency.setValueAtTime(660, ctx.currentTime + t + 0.12);
      g.gain.setValueAtTime(0.0001, ctx.currentTime + t);
      g.gain.exponentialRampToValueAtTime(0.25, ctx.currentTime + t + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + t + 0.28);
      o.connect(g).connect(ctx.destination);
      o.start(ctx.currentTime + t);
      o.stop(ctx.currentTime + t + 0.3);
    });
    setTimeout(() => ctx.close().catch(() => {}), 1500);
  } catch { /* sem som, a faixa vermelha continua */ }
}

/**
 * Faixa vermelha no alto de todas as telas enquanto houver emergência aberta.
 * Quando chega uma nova, toca o alarme e mostra o aviso do sistema (se a pessoa permitiu).
 */
export function AlertaEmergencia({ abertas, semFaixa }: { abertas: number; semFaixa?: boolean }) {
  const antes = useRef<number | null>(null);
  useEffect(() => {
    if (antes.current !== null && abertas > antes.current) {
      tocarAlarme();
      try {
        if ('Notification' in window && Notification.permission === 'granted') {
          new Notification('EMERGÊNCIA no iService', { body: 'Alguém apertou o botão de emergência. Ligue agora.', requireInteraction: true });
        }
      } catch { /* alguns navegadores não deixam */ }
    }
    if (antes.current === null && abertas > 0) tocarAlarme();
    antes.current = abertas;
  }, [abertas]);

  // Pede permissão de aviso do sistema uma vez, no primeiro clique.
  useEffect(() => {
    if (!('Notification' in window) || Notification.permission !== 'default') return;
    const pedir = () => { Notification.requestPermission().catch(() => {}); window.removeEventListener('click', pedir); };
    window.addEventListener('click', pedir);
    return () => window.removeEventListener('click', pedir);
  }, []);

  if (abertas <= 0 || semFaixa) return null;
  return (
    <Link href="/emergencias/" className="alerta-faixa vermelho alerta-emergencia" role="alert">
      <Siren size={22} />
      <div>
        <strong>{abertas === 1 ? 'Emergência aberta' : `${abertas} emergências abertas`}: ligue agora</strong>
        Prazo de 15 minutos para falar com a pessoa. Toque para abrir.
      </div>
    </Link>
  );
}
