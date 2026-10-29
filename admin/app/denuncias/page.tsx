'use client';

import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { Suspense, useState } from 'react';
import { Eye, EyeOff, Flag, Star } from 'lucide-react';
import { Cabecalho, usePainel } from '@/components/Painel';
import { Abas, Carregando, DialogoTexto, ErroCaixa, Estrelas, Miniatura, Selo, SeloStatus, Vazio, useAcao, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { dataHora, haQuanto, statusDenuncia } from '@/lib/formatos';

type Denuncia = {
  id: number; motivo: string; descricao: string; status: string; resolucao: string | null; pedido_id: string | null; codigo: string | null;
  autor_id: string | null; autor: string | null; alvo_id: string; alvo: string; alvo_profissional: boolean; denuncias_do_alvo: number;
  criada_em: string; resolvida_em: string | null;
};
type Suspeita = {
  pedido_id: string; codigo: string; nota: number; comentario: string | null; fotos: string[]; oculta: boolean; motivo_ocultacao: string | null;
  cliente_id: string; cliente: string; profissional_id: string; profissional: string; criada_em: string; sinais: string[];
};

function Denuncias() {
  const { atualizarResumo } = usePainel();
  const [filtro, setFiltro] = useState<'abertas' | 'todas'>('abertas');
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Denuncia[]>('admin_denuncias', { p_status: filtro }), [filtro]);
  const { executar, ocupado } = useAcao();
  const [decidir, setDecidir] = useState<{ d: Denuncia; status: 'procedente' | 'improcedente' } | null>(null);

  const analisar = async (d: Denuncia) => {
    if (await executar(() => rpc('admin_resolver_denuncia', { p_denuncia: d.id, p_status: 'em_analise' }), 'Denúncia em análise.')) recarregar();
  };

  return (
    <>
      <div className="filtros"><Abas ativa={filtro} mudar={setFiltro} abas={[{ id: 'abertas', rotulo: 'Abertas' }, { id: 'todas', rotulo: 'Todas' }]} /></div>
      {erro ? <ErroCaixa erro={erro} tentar={recarregar} /> : carregando && !dados ? <Carregando /> : !dados?.length ? (
        <section className="cartao"><Vazio icone={<Flag size={24} />} titulo="Nenhuma denúncia aberta" /></section>
      ) : (
        <div className="pilha">
          {dados.map((d) => (
            <section className="cartao" key={d.id}>
              <div className="titulo">
                <div>
                  <h2>{d.motivo}</h2>
                  <p>Contra <Link href={`/pessoa/?id=${d.alvo_id}`}>{d.alvo}</Link> ({d.alvo_profissional ? 'profissional' : 'cliente'})
                    {' · '}por {d.autor_id ? <Link href={`/pessoa/?id=${d.autor_id}`}>{d.autor}</Link> : 'conta excluída'} · {haQuanto(d.criada_em)}
                    {d.pedido_id ? <> · pedido <Link className="mono" href={`/pedido/?id=${d.pedido_id}`}>{d.codigo}</Link></> : null}</p>
                </div>
                <div className="linha-flex">
                  {d.denuncias_do_alvo > 1 ? <Selo tom="vermelho">{d.denuncias_do_alvo} denúncias contra esta pessoa</Selo> : null}
                  <SeloStatus mapa={statusDenuncia} valor={d.status} />
                </div>
              </div>
              <div className="corpo" style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                {d.descricao ? <div className="citacao">{d.descricao}</div> : <span className="texto-suave">Sem descrição.</span>}
                {d.resolucao ? <div><strong>Decisão:</strong> {d.resolucao}</div> : null}
                {d.status === 'aberta' || d.status === 'em_analise' ? (
                  <div className="linha-flex">
                    {d.status === 'aberta' ? <button className="botao contorno pequeno" disabled={ocupado} onClick={() => analisar(d)}>Começar análise</button> : null}
                    <span className="espaco" />
                    <button className="botao contorno pequeno" disabled={ocupado} onClick={() => setDecidir({ d, status: 'improcedente' })}>Improcedente</button>
                    <button className="botao perigo pequeno" disabled={ocupado} onClick={() => setDecidir({ d, status: 'procedente' })}>Procedente</button>
                  </div>
                ) : null}
              </div>
            </section>
          ))}
        </div>
      )}
      <DialogoTexto aberto={!!decidir} fechar={() => setDecidir(null)}
        titulo={decidir?.status === 'procedente' ? 'Denúncia procedente' : 'Denúncia improcedente'}
        texto={decidir?.status === 'procedente' ? <>Se for grave, suspenda a conta na <Link href={`/pessoa/?id=${decidir.d.alvo_id}`}>ficha da pessoa</Link>.</> : null}
        rotulo="O que foi decidido" botao="Salvar decisão" tom={decidir?.status === 'procedente' ? 'perigo' : 'primario'}
        sugestoes={decidir?.status === 'procedente' ? ['Advertência enviada.', 'Conta suspensa.'] : ['Não encontramos indícios.', 'Mal-entendido resolvido entre as partes.']}
        confirmar={async (v) => {
          const ok = await executar(() => rpc('admin_resolver_denuncia', { p_denuncia: decidir!.d.id, p_status: decidir!.status, p_resolucao: v }), 'Decisão salva.');
          if (ok) { recarregar(); atualizarResumo(); }
          return ok;
        }} />
    </>
  );
}

function Avaliacoes() {
  const [ocultas, setOcultas] = useState(false);
  const [dias, setDias] = useState(30);
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Suspeita[]>('admin_avaliacoes_suspeitas', { p_dias: dias, p_incluir_ocultas: ocultas }), [dias, ocultas]);
  const { executar, ocupado } = useAcao();
  const [ocultar, setOcultar] = useState<Suspeita | null>(null);

  const mostrar = async (a: Suspeita) => {
    if (await executar(() => rpc('admin_ocultar_avaliacao', { p_pedido: a.pedido_id, p_ocultar: false }), 'A avaliação voltou a aparecer.')) recarregar();
  };

  return (
    <>
      <div className="filtros">
        <select className="entrada" value={dias} onChange={(e) => setDias(Number(e.target.value))} aria-label="Período">
          <option value={7}>Últimos 7 dias</option><option value={30}>Últimos 30 dias</option><option value={90}>Últimos 90 dias</option>
        </select>
        <label className="marcar"><input type="checkbox" checked={ocultas} onChange={(e) => setOcultas(e.target.checked)} /> Mostrar as já ocultas</label>
      </div>
      <p className="texto-suave" style={{ marginTop: -6 }}>Sinais automáticos que merecem uma olhada: notas 1 e 2, serviço concluído rápido demais, avaliações repetidas,
        conta recém-criada e contato ou link no comentário. Ocultar tira a avaliação da nota e do perfil.</p>
      {erro ? <ErroCaixa erro={erro} tentar={recarregar} /> : carregando && !dados ? <Carregando /> : !dados?.length ? (
        <section className="cartao"><Vazio icone={<Star size={24} />} titulo="Nenhuma avaliação suspeita" /></section>
      ) : (
        <div className="grade g2">
          {dados.map((a) => (
            <section className="cartao" key={a.pedido_id} style={a.oculta ? { opacity: 0.7 } : undefined}>
              <div className="titulo">
                <div><Estrelas nota={a.nota} /><p><Link href={`/pessoa/?id=${a.cliente_id}`}>{a.cliente}</Link> avaliou <Link href={`/pessoa/?id=${a.profissional_id}`}>{a.profissional}</Link> · {dataHora(a.criada_em)}</p></div>
                {a.oculta ? <Selo tom="vermelho" icone={<EyeOff />}>Oculta</Selo> : null}
              </div>
              <div className="corpo" style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                {a.comentario ? <div className="citacao">{a.comentario}</div> : <span className="texto-suave">Sem comentário.</span>}
                {a.fotos?.length ? <div className="miniaturas">{a.fotos.map((f) => <Miniatura key={f} bucket="avaliacoes" caminho={f} titulo="Foto da avaliação" />)}</div> : null}
                <div className="linha-flex" style={{ gap: 6 }}>{a.sinais.map((s) => <Selo key={s} tom="laranja">{s}</Selo>)}</div>
                {a.oculta && a.motivo_ocultacao ? <span className="texto-fraco">Motivo: {a.motivo_ocultacao}</span> : null}
                <div className="linha-flex">
                  <Link className="botao fantasma pequeno" href={`/pedido/?id=${a.pedido_id}`}>Pedido <span className="mono">{a.codigo}</span></Link>
                  <span className="espaco" />
                  {a.oculta
                    ? <button className="botao contorno pequeno" disabled={ocupado} onClick={() => mostrar(a)}><Eye /> Mostrar de novo</button>
                    : <button className="botao contorno perigo-texto pequeno" disabled={ocupado} onClick={() => setOcultar(a)}><EyeOff /> Ocultar</button>}
                </div>
              </div>
            </section>
          ))}
        </div>
      )}
      <DialogoTexto aberto={!!ocultar} fechar={() => setOcultar(null)} titulo="Ocultar avaliação" texto="Ela deixa de contar na nota e some do perfil do profissional."
        rotulo="Motivo" botao="Ocultar" tom="perigo" sugestoes={['Avaliação combinada entre as partes', 'Ofensa ou linguagem imprópria', 'Contato fora do app', 'Serviço não aconteceu']}
        confirmar={async (v) => {
          const ok = await executar(() => rpc('admin_ocultar_avaliacao', { p_pedido: ocultar!.pedido_id, p_ocultar: true, p_motivo: v }), 'Avaliação ocultada.');
          if (ok) recarregar();
          return ok;
        }} />
    </>
  );
}

function Pagina() {
  const inicial = useSearchParams().get('aba') === 'avaliacoes' ? 'avaliacoes' : 'denuncias';
  const [aba, setAba] = useState<'denuncias' | 'avaliacoes'>(inicial);
  const { resumo } = usePainel();
  return (
    <>
      <Cabecalho titulo="Denúncias e avaliações" texto="Denúncias enviadas pelos apps e avaliações que parecem fora do normal."
        acoes={<Abas ativa={aba} mudar={setAba} abas={[{ id: 'denuncias', rotulo: 'Denúncias', n: resumo?.denuncias_abertas }, { id: 'avaliacoes', rotulo: 'Avaliações suspeitas' }]} />} />
      {aba === 'denuncias' ? <Denuncias /> : <Avaliacoes />}
    </>
  );
}

export default function Envelope() {
  return <Suspense fallback={<Carregando />}><Pagina /></Suspense>;
}
