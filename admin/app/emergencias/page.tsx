'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import { Check, MapPin, MessageCircle, Phone, Siren } from 'lucide-react';
import { Cabecalho, usePainel } from '@/components/Painel';
import { Abas, Carregando, DialogoTexto, ErroCaixa, Selo, Vazio, useAcao, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { dataHora, haQuanto, telefone, whatsapp } from '@/lib/formatos';

type Emergencia = {
  id: number; pedido_id: string | null; codigo: string | null; usuario_id: string; usuario: string; telefone: string | null; papel: string | null;
  lat: number | null; lng: number | null; criada_em: string; atendida_em: string | null; atendida_por: string | null; nota_atendimento: string | null;
};

export default function Emergencias() {
  const { atualizarResumo } = usePainel();
  const [abertas, setAbertas] = useState<'abertas' | 'todas'>('abertas');
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Emergencia[]>('admin_emergencias', { p_abertas: abertas === 'abertas' }), [abertas]);
  const { executar } = useAcao();
  const [atender, setAtender] = useState<Emergencia | null>(null);
  // Atualiza sozinho a cada 20 s enquanto a tela está aberta.
  useEffect(() => { const t = setInterval(recarregar, 20000); return () => clearInterval(t); }, [recarregar]);

  return (
    <>
      <Cabecalho titulo="Emergências" texto="Acionamentos do botão de emergência nos apps. Ligue para a pessoa imediatamente e, se for o caso, oriente a chamar o 190."
        acoes={<Abas ativa={abertas} mudar={setAbertas} abas={[{ id: 'abertas', rotulo: 'Abertas' }, { id: 'todas', rotulo: 'Todas' }]} />} />
      {erro ? <ErroCaixa erro={erro} tentar={recarregar} /> : carregando && !dados ? <Carregando /> : !dados?.length ? (
        <section className="cartao"><Vazio icone={<Siren size={24} />} titulo="Nenhuma emergência aberta" texto="Esta tela se atualiza sozinha a cada 20 segundos." /></section>
      ) : (
        <div className="grade g2">
          {dados.map((e) => {
            const zap = whatsapp(e.telefone);
            return (
              <section key={e.id} className="cartao" style={e.atendida_em ? undefined : { borderColor: '#f1b5b5', boxShadow: '0 0 0 3px rgba(198,40,40,.08)' }}>
                <div className="titulo">
                  <div>
                    <h2>{e.usuario}{e.papel ? <span className="texto-fraco"> · {e.papel}</span> : null}</h2>
                    <p>{dataHora(e.criada_em)} ({haQuanto(e.criada_em)})</p>
                  </div>
                  {e.atendida_em ? <Selo tom="verde">Atendida</Selo> : <Selo tom="vermelho" icone={<Siren />}>Aberta</Selo>}
                </div>
                <div className="corpo" style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                  <div className="linha-flex">
                    {e.telefone ? <a className="botao primario" href={`tel:${e.telefone}`}><Phone /> {telefone(e.telefone)}</a> : <span className="texto-suave">Sem telefone</span>}
                    {zap ? <a className="botao contorno" href={zap} target="_blank" rel="noreferrer"><MessageCircle /> WhatsApp</a> : null}
                    {e.lat != null ? <a className="botao contorno" target="_blank" rel="noreferrer" href={`https://www.google.com/maps/search/?api=1&query=${e.lat},${e.lng}`}><MapPin /> Local</a> : null}
                    {e.pedido_id ? <Link className="botao fantasma" href={`/pedido/?id=${e.pedido_id}`}>Pedido <span className="mono">{e.codigo}</span></Link> : null}
                  </div>
                  {e.atendida_em ? (
                    <div className="texto-suave">Atendida por {e.atendida_por ?? 'equipe'} em {dataHora(e.atendida_em)}{e.nota_atendimento ? `: ${e.nota_atendimento}` : ''}</div>
                  ) : <button className="botao sucesso" onClick={() => setAtender(e)}><Check /> Marcar como atendida</button>}
                </div>
              </section>
            );
          })}
        </div>
      )}
      <DialogoTexto aberto={!!atender} fechar={() => setAtender(null)} titulo="Registrar o atendimento" rotulo="O que foi feito"
        placeholder="Ex.: liguei, a cliente está bem; foi um engano." botao="Marcar como atendida" tom="sucesso"
        confirmar={async (v) => {
          const ok = await executar(() => rpc('admin_atender_emergencia', { p_emergencia: atender!.id, p_nota: v }), 'Emergência marcada como atendida.');
          if (ok) { recarregar(); atualizarResumo(); }
          return ok;
        }} />
    </>
  );
}
