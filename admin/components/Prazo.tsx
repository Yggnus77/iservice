'use client';

import { useEffect, useMemo, useState } from 'react';
import { AlertTriangle, CheckCircle2, Clock } from 'lucide-react';
import { Selo, useAcao } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import type { Tom } from '@/lib/formatos';

/** Atendimentos com gravidade e prazo de primeira resposta (Plano Diretor, tópico 7). */
export type TipoAtendimento = 'email' | 'garantia' | 'denuncia' | 'emergencia';
export type Prazo = { id: number; gravidade: number; prazo: string; respondida_em: string | null; atrasada: boolean };

export const GRAVIDADES: Record<number, { rotulo: string; tom: Tom; prazo: string }> = {
  1: { rotulo: 'Crítica', tom: 'vermelho', prazo: '15 minutos, 24 horas por dia' },
  2: { rotulo: 'Alta', tom: 'laranja', prazo: '1 hora de atendimento' },
  3: { rotulo: 'Média', tom: 'azul', prazo: '4 horas de atendimento' },
  4: { rotulo: 'Baixa', tom: 'neutro', prazo: '1 dia de atendimento' },
};

/** Relógio que anda a cada 30 s, para os prazos se atualizarem sozinhos. */
function useAgora(intervalo = 30000) {
  const [agora, setAgora] = useState(() => Date.now());
  useEffect(() => { const t = setInterval(() => setAgora(Date.now()), intervalo); return () => clearInterval(t); }, [intervalo]);
  return agora;
}

/** Busca gravidade e prazo de uma lista. Sem o SQL do tópico 7, devolve vazio e a tela segue como antes. */
export function usePrazos(tipo: TipoAtendimento, ids: number[]) {
  const chave = ids.join(',');
  const [prazos, setPrazos] = useState<Map<number, Prazo>>(new Map());
  const [versao, setVersao] = useState(0);
  useEffect(() => {
    if (!chave) { setPrazos(new Map()); return; }
    let vivo = true;
    rpc<Prazo[]>('admin_prazos', { p_tipo: tipo, p_ids: chave.split(',').map(Number) })
      .then((l) => { if (vivo) setPrazos(new Map(l.map((p) => [p.id, p]))); })
      .catch(() => { if (vivo) setPrazos(new Map()); });
    return () => { vivo = false; };
  }, [tipo, chave, versao]);
  return { prazos, recarregar: () => setVersao((v) => v + 1) };
}

/** Ordena pelo que vence primeiro: sem resposta antes, depois gravidade e prazo. */
export function ordenarPorPrazo<T extends { id: number }>(lista: T[], prazos: Map<number, Prazo>): T[] {
  if (!prazos.size) return lista;
  const peso = (x: T) => {
    const p = prazos.get(x.id);
    if (!p) return [2, 9, Infinity] as const;
    return [p.respondida_em ? 1 : 0, p.gravidade, new Date(p.prazo).getTime()] as const;
  };
  return [...lista].sort((a, b) => {
    const [a1, a2, a3] = peso(a);
    const [b1, b2, b3] = peso(b);
    return a1 - b1 || a3 - b3 || a2 - b2;
  });
}

function duracao(ms: number) {
  const min = Math.round(Math.abs(ms) / 60000);
  if (min < 60) return `${Math.max(min, 1)} min`;
  const h = Math.round(min / 60);
  return h < 48 ? `${h}h` : `${Math.round(h / 24)} dias`;
}

export function SeloGravidade({ gravidade }: { gravidade?: number | null }) {
  const g = gravidade ? GRAVIDADES[gravidade] : null;
  if (!g) return null;
  return <Selo tom={g.tom}>{gravidade}. {g.rotulo}</Selo>;
}

/** "Responder em 40 min", "Atrasado 2h" ou "Respondido". */
export function SeloPrazo({ p, encerrado }: { p?: Prazo | null; encerrado?: boolean }) {
  const agora = useAgora();
  if (!p) return null;
  if (p.respondida_em) {
    return p.atrasada
      ? <Selo tom="laranja" icone={<CheckCircle2 />}>Respondido fora do prazo</Selo>
      : <Selo tom="verde" icone={<CheckCircle2 />}>Respondido no prazo</Selo>;
  }
  if (encerrado) return null;
  const falta = new Date(p.prazo).getTime() - agora;
  if (falta < 0) return <Selo tom="vermelho" icone={<AlertTriangle />}>Atrasado {duracao(falta)}</Selo>;
  return <Selo tom={falta < 30 * 60000 || p.gravidade <= 2 ? 'laranja' : 'neutro'} icone={<Clock />}>Responder em {duracao(falta)}</Selo>;
}

/** Selos de gravidade e prazo lado a lado. */
export function Prazos({ p, encerrado }: { p?: Prazo | null; encerrado?: boolean }) {
  if (!p) return null;
  return <span className="linha-flex" style={{ gap: 6, display: 'inline-flex', flexWrap: 'wrap' }}><SeloGravidade gravidade={p.gravidade} /><SeloPrazo p={p} encerrado={encerrado} /></span>;
}

/** Escolher a gravidade (a equipe corrige a sugestão automática). */
export function MudarGravidade({ tipo, p, aoMudar }: { tipo: Exclude<TipoAtendimento, 'emergencia'>; p?: Prazo | null; aoMudar: () => void }) {
  const { executar, ocupado } = useAcao();
  const opcoes = useMemo(() => [1, 2, 3, 4], []);
  if (!p) return null;
  return (
    <label className="linha-flex" style={{ gap: 6 }} title="O prazo de resposta depende da gravidade">
      <span className="texto-suave">Gravidade</span>
      <select className="entrada" style={{ width: "auto" }} value={p.gravidade} disabled={ocupado} aria-label="Gravidade do atendimento"
        onChange={async (e) => {
          const g = Number(e.target.value);
          if (await executar(() => rpc('admin_definir_gravidade', { p_tipo: tipo, p_id: p.id, p_gravidade: g }), 'Gravidade atualizada.')) aoMudar();
        }}>
        {opcoes.map((g) => <option key={g} value={g}>{g}. {GRAVIDADES[g].rotulo} · {GRAVIDADES[g].prazo}</option>)}
      </select>
    </label>
  );
}
