'use client';

import { useEffect, useState } from 'react';
import { CalendarClock, Loader2 } from 'lucide-react';
import { rpc } from '@/lib/supabase';
import { hojeISO } from '@/lib/formatos';
import { Dialogo, useAcao } from './ui';

export type ItemValidade = { tipo: 'documento' | 'certificacao'; id: number; nome: string; valido_ate: string | null };

function somarMeses(iso: string, meses: number) {
  const d = new Date(iso + 'T12:00:00');
  d.setMonth(d.getMonth() + meses);
  return d.toISOString().slice(0, 10);
}

/** Muda (ou tira) a data de validade de um documento ou certificação aprovado. */
export function DialogoValidade({ item, fechar, salvo }: { item: ItemValidade | null; fechar: () => void; salvo: () => void }) {
  const [valor, setValor] = useState('');
  const { executar, ocupado } = useAcao();
  useEffect(() => { if (item) setValor(item.valido_ate ?? ''); }, [item]);
  const hoje = hojeISO();
  const salvar = async (v: string | null) => {
    const ok = await executar(() => rpc('admin_definir_validade', { p_tipo: item!.tipo, p_id: item!.id, p_valido_ate: v }),
      v ? 'Validade salva.' : 'Validade removida.');
    if (ok) { fechar(); salvo(); }
  };
  return (
    <Dialogo aberto={!!item} fechar={fechar} titulo="Validade do documento" icone={<CalendarClock />}
      texto={<>{item?.nome}. O profissional recebe um aviso no app 30 dias antes de vencer e outro no dia.</>}
      rodape={<>
        {item?.valido_ate ? <button className="botao fantasma" disabled={ocupado} onClick={() => salvar(null)}>Não vence</button> : null}
        <span className="espaco" />
        <button className="botao contorno" onClick={fechar}>Cancelar</button>
        <button className="botao primario" disabled={ocupado || !valor} onClick={() => salvar(valor)}>{ocupado ? <Loader2 className="girar" /> : null}Salvar</button>
      </>}>
      <div className="campo">
        <label htmlFor="validade-data">Vale até</label>
        <input id="validade-data" type="date" className="entrada" value={valor} min={hoje} onChange={(e) => setValor(e.target.value)} />
      </div>
      <div className="linha-flex">
        {[3, 6, 12, 24].map((m) => (
          <button key={m} className="botao contorno pequeno" onClick={() => setValor(somarMeses(hoje, m))}>{m < 12 ? `${m} meses` : m === 12 ? '1 ano' : '2 anos'}</button>
        ))}
      </div>
    </Dialogo>
  );
}
