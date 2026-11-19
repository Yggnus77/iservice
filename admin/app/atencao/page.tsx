'use client';

import Link from 'next/link';
import { useState } from 'react';
import {
  AlertTriangle, BadgeCheck, CalendarClock, Car, CheckCheck, ClipboardList, Clock, FileWarning, Hourglass, MessageCircleWarning,
  RotateCw, ShieldAlert, Star, TriangleAlert, UserRound, UserX,
} from 'lucide-react';
import { Cabecalho, usePainel } from '@/components/Painel';
import { Ajuda } from '@/components/Ajuda';
import { Abas, Carregando, DialogoTexto, ErroCaixa, Pessoa, Selo, SeloStatus, Vazio, useAcao, useAviso, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { data, dataHora, haQuanto, statusPedido } from '@/lib/formatos';
import { DialogoValidade } from '@/components/Validade';

export type ItemPedido = {
  chave: string; tipo: string; texto: string; gravidade: number; desde: string | null; pedido_id: string; codigo: string; status: string;
  quando: string; combinado_para: string | null; profissao: string; regiao: string | null; cliente_id: string; cliente: string;
  profissional_id: string; profissional: string;
};
export type Motivo = { codigo: string; nivel: 'alto' | 'medio'; texto: string };
export type ItemProfissional = {
  chave: string; profissional_id: string; nome: string; foto_url: string | null; nota_media: number; total_avaliacoes: number;
  advertencias: number; motivos: Motivo[]; gravidade: number;
};
export type ItemDocumento = {
  chave: string; tipo: 'documento' | 'certificacao'; id: number; profissional_id: string; nome: string; foto_url: string | null; documento: string;
  tipo_documento: string; valido_ate: string; dias: number; vencido: boolean; avisado_em: string | null; novo_enviado: boolean;
};
type Atencao = { pedidos: ItemPedido[] | null; profissionais: ItemProfissional[] | null; documentos: ItemDocumento[] | null };
type Aba = 'pedidos' | 'profissionais' | 'documentos';

const iconePedido: Record<string, React.ReactNode> = {
  nao_saiu: <CalendarClock />, demorando_chegar: <Car />, servico_longo: <Hourglass />, cancelou_apos_aceite: <UserX />,
  cliente_sem_atendimento: <MessageCircleWarning />,
};
const dicaPedido: Record<string, string> = {
  nao_saiu: 'Ligue para o profissional e confirme se ele vai. Se não for, avise o cliente e ajude a pedir a outro.',
  demorando_chegar: 'Confira com o profissional onde ele está e avise o cliente da nova previsão.',
  servico_longo: 'Pode ter esquecido de tocar em "Concluir". Confirme com os dois e peça para concluir no app.',
  cancelou_apos_aceite: 'Fale com o cliente: peça desculpas e ajude a encontrar outro profissional. Veja se o profissional está cancelando muito.',
  cliente_sem_atendimento: 'O cliente ficou sem ninguém. Uma ligação ou mensagem ajudando a pedir a outro profissional recupera esse cliente.',
};
const iconeMotivo: Record<string, React.ReactNode> = {
  cancelou: <UserX />, denuncia: <ShieldAlert />, garantia: <AlertTriangle />, nota: <Star />, sem_resposta: <Clock />, aceite: <TriangleAlert />,
};

function JaTratei({ chave, feito, rotulo = 'Já tratei' }: { chave: string; feito: () => void; rotulo?: string }) {
  const [aberto, setAberto] = useState(false);
  const { executar } = useAcao();
  return (
    <>
      <button className="botao contorno pequeno" onClick={() => setAberto(true)}><CheckCheck /> {rotulo}</button>
      <DialogoTexto aberto={aberto} fechar={() => setAberto(false)} titulo="Marcar como tratado"
        texto="O item sai da fila e fica no registro da equipe com o seu nome. Se o problema mudar, ele volta."
        rotulo="O que foi feito (opcional)" placeholder="Ex.: liguei para o cliente e ele pediu a outro profissional" botao="Marcar como tratado"
        obrigatorio={false} sugestoes={['Liguei e resolvi', 'Mandei mensagem no WhatsApp', 'Não precisa de ação']}
        confirmar={async (v) => {
          const ok = await executar(() => rpc('admin_atencao_tratado', { p_chave: chave, p_observacao: v || null }), 'Marcado como tratado.');
          if (ok) feito();
          return ok;
        }} />
    </>
  );
}

export default function PrecisaDeAtencao() {
  const { pode, atualizarResumo } = usePainel();
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Atencao>('admin_atencao'), []);
  const [aba, setAba] = useState<Aba | null>(null);
  const [advertir, setAdvertir] = useState<ItemProfissional | null>(null);
  const [validade, setValidade] = useState<ItemDocumento | null>(null);
  const [novoDoc, setNovoDoc] = useState<ItemDocumento | null>(null);
  const { executar } = useAcao();
  const avisar = useAviso();
  const fim = () => { recarregar(); atualizarResumo(); };

  const abas = ([
    { id: 'pedidos', rotulo: 'Pedidos', n: dados?.pedidos?.length, pode: dados?.pedidos != null },
    { id: 'profissionais', rotulo: 'Profissionais', n: dados?.profissionais?.length, pode: dados?.profissionais != null },
    { id: 'documentos', rotulo: 'Documentos vencendo', n: dados?.documentos?.length, pode: dados?.documentos != null },
  ] as { id: Aba; rotulo: string; n?: number; pode: boolean }[]).filter((a) => a.pode);
  const ativa: Aba = aba ?? abas.find((a) => a.n)?.id ?? abas[0]?.id ?? 'pedidos';

  return (
    <>
      <Cabecalho titulo="Precisa de atenção"
        texto="O que está travado ou dando errado agora, para a equipe agir antes de o cliente reclamar."
        ajuda={<>
          O painel procura sozinho, o tempo todo: pedidos parados, profissionais com sinais de problema e documentos perto de vencer.
          Resolva o item (ligação, mensagem, advertência) e toque em <strong>Já tratei</strong>. Ele sai da fila e fica no registro
          da equipe com o seu nome. Se o problema mudar ou voltar depois de 30 dias, ele aparece de novo.
        </>}
        acoes={<button className="botao contorno" onClick={fim} disabled={carregando}><RotateCw /> Atualizar</button>} />

      {erro ? <ErroCaixa erro={erro} tentar={recarregar} /> : !dados ? <Carregando /> : (
        <>
          <div className="filtros"><Abas<Aba> ativa={ativa} mudar={setAba} abas={abas.map(({ id, rotulo, n }) => ({ id, rotulo, n }))} /></div>

          {ativa === 'pedidos' && dados.pedidos ? (
            <section className="cartao">
              <div className="titulo"><div>
                <h2 className="com-ajuda">Pedidos travados e clientes sem atendimento
                  <Ajuda titulo="O que entra aqui">
                    <strong>Não saiu na hora:</strong> aceito e o profissional não saiu para o local (20 min depois do horário marcado, ou 40 min no urgente).<br />
                    <strong>Demorando a chegar:</strong> “a caminho” há mais de 1h30.<br />
                    <strong>Serviço longo:</strong> em andamento há mais de 10 horas.<br />
                    <strong>Cancelou depois de aceitar:</strong> nas últimas 24 horas.<br />
                    <strong>Cliente sem atendimento:</strong> o pedido foi recusado ou ninguém respondeu, e o cliente não pediu a outro (24 horas).
                  </Ajuda>
                </h2>
                <p>Os mais graves primeiro. Abra o pedido para ver a conversa e o WhatsApp das duas partes.</p>
              </div></div>
              <div className="corpo sem-espaco">
                {dados.pedidos.length === 0 ? <Vazio icone={<ClipboardList size={24} />} titulo="Nenhum pedido travado" texto="Tudo andando como deveria." /> : (
                  <ul className="fila">
                    {dados.pedidos.map((p) => (
                      <li key={p.chave}>
                        <span className={`marca-gravidade ${p.gravidade >= 2 ? 'alto' : 'medio'}`}>{iconePedido[p.tipo] ?? <AlertTriangle />}</span>
                        <div className="meio-item">
                          <strong>{p.texto}</strong>
                          <span className="linha-flex" style={{ gap: 8 }}>
                            <span className="mono forte">{p.codigo}</span> · {p.profissao}{p.regiao ? ` · ${p.regiao}` : ''}
                            <SeloStatus mapa={statusPedido} valor={p.status} />
                          </span>
                          <span className="texto-suave">
                            Cliente <Link href={`/pessoa/?id=${p.cliente_id}`}>{p.cliente}</Link> · Profissional <Link href={`/pessoa/?id=${p.profissional_id}`}>{p.profissional}</Link>
                            {p.desde ? <> · {p.tipo === 'nao_saiu' && p.combinado_para ? `marcado para ${dataHora(p.combinado_para)}` : haQuanto(p.desde)}</> : null}
                          </span>
                          <span className="texto-fraco" style={{ fontSize: 12.5 }}>O que fazer: {dicaPedido[p.tipo]}</span>
                        </div>
                        <div className="botoes-item">
                          <Link className="botao primario pequeno" href={`/pedido/?id=${p.pedido_id}`}>Abrir pedido</Link>
                          <JaTratei chave={p.chave} feito={fim} />
                        </div>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </section>
          ) : null}

          {ativa === 'profissionais' && dados.profissionais ? (
            <section className="cartao">
              <div className="titulo"><div>
                <h2 className="com-ajuda">Profissionais com sinais de problema
                  <Ajuda titulo="Como o alerta é calculado">
                    Vermelho (grave): cancelou 3 ou mais serviços depois de aceitar em 30 dias, tem denúncia aberta,
                    2 ou mais reclamações da Garantia em 90 dias, ou nota abaixo de 3,5 nas últimas 10 avaliações.<br />
                    Laranja (atenção): nota abaixo de 4,0, deixou 3 ou mais pedidos sem resposta, ou aceitou menos da metade dos pedidos em 30 dias.<br />
                    Converse com o profissional primeiro. Se repetir, use <strong>Advertir</strong>; em caso grave, suspenda pela ficha.
                  </Ajuda>
                </h2>
                <p>Antes de virar reclamação: converse, advirta ou suspenda.</p>
              </div></div>
              <div className="corpo sem-espaco">
                {dados.profissionais.length === 0 ? <Vazio icone={<BadgeCheck size={24} />} titulo="Nenhum alerta" texto="Nenhum profissional com sinais de problema agora." /> : (
                  <ul className="fila">
                    {dados.profissionais.map((p) => (
                      <li key={p.chave}>
                        <span className={`marca-gravidade ${p.gravidade >= 2 ? 'alto' : 'medio'}`}><UserRound /></span>
                        <div className="meio-item">
                          <Pessoa nome={p.nome} foto={p.foto_url}
                            sub={<>{p.total_avaliacoes ? <>Nota {Number(p.nota_media).toFixed(1)} ({p.total_avaliacoes})</> : 'Sem avaliações'}
                              {p.advertencias ? <> · {p.advertencias} {p.advertencias === 1 ? 'advertência' : 'advertências'} em 90 dias</> : null}</>} />
                          <span className="linha-flex" style={{ gap: 6, marginTop: 4 }}>
                            {p.motivos.map((m) => <Selo key={m.codigo} tom={m.nivel === 'alto' ? 'vermelho' : 'laranja'} icone={iconeMotivo[m.codigo]}>{m.texto}</Selo>)}
                          </span>
                        </div>
                        <div className="botoes-item">
                          <Link className="botao primario pequeno" href={`/pessoa/?id=${p.profissional_id}`}>Ver conta</Link>
                          {pode('pessoas_suspender') ? <button className="botao contorno pequeno" onClick={() => setAdvertir(p)}><TriangleAlert /> Advertir</button> : null}
                          <JaTratei chave={p.chave} feito={fim} rotulo="Já conversei" />
                        </div>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </section>
          ) : null}

          {ativa === 'documentos' && dados.documentos ? (
            <section className="cartao">
              <div className="titulo"><div>
                <h2 className="com-ajuda">Documentos e certificações vencendo
                  <Ajuda titulo="Validade dos documentos">
                    As certidões aprovadas valem 12 meses e os documentos 24 meses; vencido, o perfil sai das buscas até chegar um novo. Certificações têm a data que a equipe colocar.
                    O profissional recebe um aviso no app 30 dias antes e outro no dia em que vence.
                    Use <strong>Pedir documento novo</strong> para ele mandar outro pelo app, e <strong>Mudar validade</strong> se a data estiver errada.
                  </Ajuda>
                </h2>
                <p>Vencem nos próximos 30 dias ou já venceram.</p>
              </div></div>
              <div className="corpo sem-espaco">
                {dados.documentos.length === 0 ? <Vazio icone={<FileWarning size={24} />} titulo="Nada vencendo" texto="Nenhum documento vence nos próximos 30 dias." /> : (
                  <ul className="fila">
                    {dados.documentos.map((d) => (
                      <li key={d.chave}>
                        <span className={`marca-gravidade ${d.vencido ? 'alto' : 'medio'}`}><FileWarning /></span>
                        <div className="meio-item">
                          <Pessoa nome={d.nome} foto={d.foto_url} sub={d.documento} />
                          <span className="linha-flex" style={{ gap: 6, marginTop: 4 }}>
                            <Selo tom={d.vencido ? 'vermelho' : 'laranja'}>
                              {d.vencido ? `Venceu em ${data(d.valido_ate)}` : d.dias === 0 ? 'Vence hoje' : `Vence em ${d.dias} ${d.dias === 1 ? 'dia' : 'dias'} (${data(d.valido_ate)})`}
                            </Selo>
                            {d.novo_enviado ? <Selo tom="azul">Já mandou um novo, falta conferir</Selo> : null}
                            {d.avisado_em ? <Selo>Avisado no app {haQuanto(d.avisado_em)}</Selo> : null}
                          </span>
                        </div>
                        <div className="botoes-item">
                          <Link className="botao primario pequeno" href={`/cadastro/?id=${d.profissional_id}`}>Ver cadastro</Link>
                          {pode('cadastros_decidir') && d.tipo === 'documento' && !d.novo_enviado
                            ? <button className="botao contorno pequeno" onClick={() => setNovoDoc(d)}>Pedir documento novo</button> : null}
                          {pode('cadastros_decidir') ? <button className="botao contorno pequeno" onClick={() => setValidade(d)}>Mudar validade</button> : null}
                          <JaTratei chave={d.chave} feito={fim} />
                        </div>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </section>
          ) : null}
        </>
      )}

      <DialogoTexto aberto={!!advertir} fechar={() => setAdvertir(null)} titulo={`Advertir ${advertir?.nome.split(' ')[0] ?? ''}?`}
        texto="A pessoa recebe um aviso no app com o motivo e fica sabendo que, se repetir, a conta pode ser suspensa. Fica na ficha dela."
        rotulo="Motivo (a pessoa vai ler)" botao="Enviar advertência" tom="perigo"
        inicial={advertir?.motivos[0]?.texto ?? ''}
        sugestoes={['Cancelou serviços depois de aceitar', 'Deixou clientes sem resposta', 'Atrasos sem avisar o cliente', 'Reclamações sobre a qualidade do serviço']}
        confirmar={async (v) => {
          const ok = await executar(async () => {
            const n = await rpc<number>('admin_advertir', { p_usuario: advertir!.profissional_id, p_motivo: v });
            avisar((n % 3 === 0 ? `Advertência enviada. Foi a ${n}ª: a conta ficou suspensa por 30 dias, como manda a Política de Verificação.` : `Advertência enviada (${n}ª). Na 3ª, a conta é suspensa por 30 dias.`));
          });
          if (ok) fim();
          return ok;
        }} />

      <DialogoTexto aberto={!!novoDoc} fechar={() => setNovoDoc(null)} titulo="Pedir documento novo"
        texto="O profissional recebe um aviso no app para enviar de novo. O documento atual fica marcado para reenviar."
        rotulo="Mensagem para o profissional" botao="Pedir documento novo"
        inicial={novoDoc ? `${novoDoc.vencido ? 'A validade terminou' : 'A validade está terminando'} em ${data(novoDoc.valido_ate)}. Envie uma via atualizada pelo app.` : ''}
        confirmar={async (v) => {
          const ok = await executar(() => rpc('admin_revisar_documento', { p_documento: novoDoc!.id, p_aprovar: false, p_observacao: v }), 'Pedido enviado ao profissional.');
          if (ok) fim();
          return ok;
        }} />

      <DialogoValidade item={validade ? { tipo: validade.tipo, id: validade.id, nome: validade.documento, valido_ate: validade.valido_ate } : null}
        fechar={() => setValidade(null)} salvo={fim} />
    </>
  );
}
