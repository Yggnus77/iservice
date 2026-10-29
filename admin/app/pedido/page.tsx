'use client';

import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { Suspense } from 'react';
import { Lock, MapPin, MessageCircle, ShieldCheck, Siren } from 'lucide-react';
import { Cabecalho } from '@/components/Painel';
import { Carregando, ErroCaixa, Estrelas, Miniatura, Pessoa, Selo, SeloStatus, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { dataHora, moeda, quandoPedido, statusPedido, statusReclamacao, statusDenuncia, whatsapp } from '@/lib/formatos';

type Parte = { id: string; nome: string; telefone: string | null; email: string | null; foto_url: string | null };
type Detalhe = {
  pedido: {
    id: string; codigo: string; status: string; quando: string; janela: string | null; combinado_para: string | null; descricao: string; fotos: string[];
    endereco_texto: string; regiao: string | null; distancia_km: number | null; preco_informado: number | null; taxa_urgencia: number; valor_cobrado: number | null;
    forma_pagamento: string | null; motivo: string | null; criado_em: string; responder_ate: string; aceito_em: string | null; a_caminho_em: string | null;
    iniciado_em: string | null; concluido_em: string | null; encerrado_em: string | null; profissao: string; especialidade: string | null; lat: number; lng: number;
    cancelado_por: string | null;
  };
  cliente: Parte; profissional: Parte;
  avaliacao: { nota: number; comentario: string | null; fotos: string[]; resposta: string | null; criada_em: string; oculta: boolean; motivo_ocultacao: string | null } | null;
  reclamacoes: { id: number; motivo: string; descricao: string; status: string; resolucao: string | null; criada_em: string; autor_id: string; fotos: string[] }[];
  emergencias: { id: number; usuario_id: string; criada_em: string; atendida_em: string | null; nota_atendimento: string | null }[];
  denuncias: { id: number; motivo: string; status: string; criada_em: string }[];
  conversa_liberada: boolean;
  mensagens: { autor_id: string; texto: string; criada_em: string }[] | null;
  total_mensagens: number;
};

function ParteCartao({ titulo, p }: { titulo: string; p: Parte }) {
  const zap = whatsapp(p.telefone);
  return (
    <div className="linha-flex" style={{ justifyContent: 'space-between' }}>
      <Link href={`/pessoa/?id=${p.id}`} style={{ color: 'inherit', textDecoration: 'none' }}><Pessoa nome={p.nome} foto={p.foto_url} sub={titulo} tamanho={40} /></Link>
      {zap ? <a className="botao contorno pequeno" href={zap} target="_blank" rel="noreferrer"><MessageCircle /> WhatsApp</a> : null}
    </div>
  );
}

function Detalhes() {
  const id = useSearchParams().get('id') ?? '';
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Detalhe>('admin_pedido', { p_id: id }), [id]);
  if (erro) return <ErroCaixa erro={erro} tentar={recarregar} />;
  if (carregando && !dados) return <Carregando />;
  if (!dados) return null;
  const p = dados.pedido;

  const etapas = [
    { t: 'Pedido feito', v: p.criado_em },
    { t: 'Aceito pelo profissional', v: p.aceito_em },
    { t: 'Profissional a caminho', v: p.a_caminho_em },
    { t: 'Atendimento iniciado', v: p.iniciado_em },
    { t: 'Serviço concluído', v: p.concluido_em },
  ];
  if (p.encerrado_em) etapas.push({ t: statusPedido[p.status]?.rotulo ?? 'Encerrado', v: p.encerrado_em });

  return (
    <>
      <Cabecalho voltar={{ href: '/pedidos/', rotulo: 'Pedidos' }} titulo={`Pedido ${p.codigo}`}
        texto={<span className="linha-flex" style={{ marginTop: 4 }}>
          <SeloStatus mapa={statusPedido} valor={p.status} />
          <span className="texto-suave">{p.profissao}{p.especialidade ? ` · ${p.especialidade}` : ''} · {quandoPedido[p.quando]}{p.janela ? ` (${p.janela})` : ''}
            {p.combinado_para ? ` · ${dataHora(p.combinado_para)}` : ''}</span>
        </span>} />

      {dados.emergencias.length ? (
        <Link href="/emergencias/" className="alerta-faixa vermelho" style={{ textDecoration: 'none' }}><Siren /><div><strong>Botão de emergência acionado neste pedido</strong>
          {dados.emergencias.map((e) => `${dataHora(e.criada_em)}${e.atendida_em ? ' (atendida)' : ' (aberta)'}`).join(' · ')}</div></Link>
      ) : null}

      <div className="grade lado">
        <div className="pilha">
          <section className="cartao">
            <div className="titulo"><div><h2>O que o cliente pediu</h2></div></div>
            <div className="corpo">
              <div className="citacao">{p.descricao || 'Sem descrição.'}</div>
              {p.fotos?.length ? <div className="miniaturas" style={{ marginTop: 12 }}>{p.fotos.map((f, i) => <Miniatura key={f} bucket="pedidos" caminho={f} titulo={`Foto ${i + 1} do pedido`} />)}</div> : null}
              <dl className="dados" style={{ marginTop: 16 }}>
                <div><dt>Local</dt><dd>{p.endereco_texto}{p.regiao && !p.endereco_texto?.includes(p.regiao) ? ` · ${p.regiao}` : ''}</dd></div>
                <div><dt>Distância do profissional</dt><dd>{p.distancia_km != null ? `${p.distancia_km} km` : '—'}</dd></div>
                <div><dt>Preço informado</dt><dd>{moeda(p.preco_informado)}{p.taxa_urgencia ? ` + ${moeda(p.taxa_urgencia)} de urgência` : ''}</dd></div>
                <div><dt>Valor cobrado</dt><dd>{moeda(p.valor_cobrado)}{p.forma_pagamento ? ` · ${p.forma_pagamento}` : ''}</dd></div>
              </dl>
              {p.motivo ? <div className="alerta-faixa laranja" style={{ marginTop: 16, marginBottom: 0 }}><div><strong>Motivo do encerramento</strong>{p.motivo}</div></div> : null}
              <a className="botao contorno pequeno" style={{ marginTop: 14 }} target="_blank" rel="noreferrer" href={`https://www.google.com/maps/search/?api=1&query=${p.lat},${p.lng}`}><MapPin /> Ver local no mapa</a>
            </div>
          </section>

          {dados.reclamacoes.length ? (
            <section className="cartao">
              <div className="titulo"><div><h2>Garantia iService</h2></div><Link className="botao contorno pequeno" href="/garantia/"><ShieldCheck /> Abrir mediação</Link></div>
              <div className="corpo">
                {dados.reclamacoes.map((r) => (
                  <div key={r.id} style={{ marginBottom: 12 }}>
                    <div className="linha-flex"><strong>{r.motivo}</strong><SeloStatus mapa={statusReclamacao} valor={r.status} /><span className="texto-fraco">{dataHora(r.criada_em)}</span></div>
                    <div className="citacao" style={{ marginTop: 8 }}>{r.descricao}</div>
                    {r.resolucao ? <p><strong>Resolução:</strong> {r.resolucao}</p> : null}
                  </div>
                ))}
              </div>
            </section>
          ) : null}

          <section className="cartao">
            <div className="titulo"><div><h2>Conversa</h2><p>{dados.total_mensagens} {dados.total_mensagens === 1 ? 'mensagem' : 'mensagens'}</p></div></div>
            <div className="corpo">
              {!dados.conversa_liberada ? (
                <div className="linha-flex texto-suave"><Lock size={16} /> Por privacidade, a conversa só fica visível quando há reclamação, denúncia ou emergência neste pedido.</div>
              ) : !dados.mensagens?.length ? <span className="texto-suave">Nenhuma mensagem.</span> : (
                <div className="conversa">
                  {dados.mensagens.map((m, i) => (
                    <div key={i} className={`balao ${m.autor_id === dados.profissional.id ? 'direita' : ''}`}>
                      {m.texto}
                      <small>{m.autor_id === dados.profissional.id ? dados.profissional.nome : dados.cliente.nome} · {dataHora(m.criada_em)}</small>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </section>
        </div>

        <div className="pilha">
          <section className="cartao">
            <div className="corpo" style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              <ParteCartao titulo="Cliente" p={dados.cliente} />
              <div className="separador" />
              <ParteCartao titulo="Profissional" p={dados.profissional} />
            </div>
          </section>
          <section className="cartao">
            <div className="titulo"><div><h2>Linha do tempo</h2></div></div>
            <div className="corpo">
              <ul className="tempo">
                {etapas.map((e) => (
                  <li key={e.t}><span className={`ponto ${e.v ? '' : 'fraco'}`} /><div><strong style={{ color: e.v ? undefined : 'var(--texto-fraco)' }}>{e.t}</strong><span>{e.v ? dataHora(e.v) : '—'}</span></div></li>
                ))}
              </ul>
            </div>
          </section>
          <section className="cartao">
            <div className="titulo"><div><h2>Avaliação</h2></div>{dados.avaliacao?.oculta ? <Selo tom="vermelho">Oculta</Selo> : null}</div>
            <div className="corpo">
              {!dados.avaliacao ? <span className="texto-suave">Ainda não avaliado.</span> : <>
                <Estrelas nota={dados.avaliacao.nota} />
                {dados.avaliacao.comentario ? <div className="citacao" style={{ marginTop: 8 }}>{dados.avaliacao.comentario}</div> : null}
                {dados.avaliacao.resposta ? <p className="texto-suave"><strong>Resposta do profissional:</strong> {dados.avaliacao.resposta}</p> : null}
                {dados.avaliacao.oculta ? <p className="texto-fraco">Motivo para ocultar: {dados.avaliacao.motivo_ocultacao}</p> : null}
              </>}
            </div>
          </section>
          {dados.denuncias.length ? (
            <section className="cartao">
              <div className="titulo"><div><h2>Denúncias</h2></div><Link className="botao contorno pequeno" href="/denuncias/">Ver fila</Link></div>
              <div className="corpo">
                <ul className="lista-simples">
                  {dados.denuncias.map((d) => <li key={d.id}><span style={{ flex: 1 }}>{d.motivo}<div className="texto-fraco">{dataHora(d.criada_em)}</div></span><SeloStatus mapa={statusDenuncia} valor={d.status} /></li>)}
                </ul>
              </div>
            </section>
          ) : null}
        </div>
      </div>
    </>
  );
}

export default function Pagina() {
  return <Suspense fallback={<Carregando />}><Detalhes /></Suspense>;
}
