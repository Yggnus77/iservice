'use client';

import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useState } from 'react';
import { AlertTriangle, Ban, BadgeCheck, MessageCircle, RotateCcw, Star } from 'lucide-react';
import { Cabecalho, usePainel } from '@/components/Painel';
import { Carregando, DialogoTexto, ErroCaixa, Pessoa, Selo, SeloStatus, useAcao, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { cpf, data, dataHora, haQuanto, idade, moeda, nomesAcao, numero, statusCadastro, statusDenuncia, statusPedido, statusReclamacao, telefone, whatsapp } from '@/lib/formatos';
import { enderecoTexto, type Ficha } from '@/lib/tipos';

function Ficha() {
  const id = useSearchParams().get('id') ?? '';
  const router = useRouter();
  const { usuarioId, atualizarResumo } = usePainel();
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Ficha>('admin_usuario', { p_id: id }), [id]);
  const { executar, ocupado } = useAcao();
  const [suspender, setSuspender] = useState(false);

  if (erro) return <ErroCaixa erro={erro} tentar={recarregar} />;
  if (carregando && !dados) return <Carregando />;
  if (!dados) return null;
  const { perfil, profissional: pro } = dados;
  const zap = whatsapp(perfil.telefone);
  const suspensa = !!perfil.suspenso_em;

  const reativar = async () => {
    if (await executar(() => rpc('admin_suspender', { p_usuario: perfil.id, p_suspender: false }), 'Conta reativada.')) { recarregar(); atualizarResumo(); }
  };

  return (
    <>
      <Cabecalho voltar={{ href: '/pessoas/', rotulo: 'Pessoas' }} titulo={perfil.nome || 'Sem nome'}
        texto={<span className="linha-flex" style={{ marginTop: 4 }}>
          {pro ? <SeloStatus mapa={statusCadastro} valor={pro.status} /> : null}
          {perfil.e_cliente ? <Selo tom="azul">Cliente</Selo> : null}
          {perfil.e_admin ? <Selo tom="roxo">Equipe</Selo> : null}
          {suspensa ? <Selo tom="vermelho">Suspensa {haQuanto(perfil.suspenso_em)}</Selo> : null}
          {perfil.exclusao_solicitada_em ? <Selo tom="laranja">Pediu exclusão da conta {haQuanto(perfil.exclusao_solicitada_em)}</Selo> : null}
          <span className="texto-fraco">Na plataforma desde {data(perfil.criado_em)}</span>
        </span>}
        acoes={<>
          {zap ? <a className="botao contorno" href={zap} target="_blank" rel="noreferrer"><MessageCircle /> WhatsApp</a> : null}
          {pro ? <Link className="botao contorno" href={`/cadastro/?id=${perfil.id}`}><BadgeCheck /> Documentos e cadastro</Link> : null}
          {perfil.id !== usuarioId ? (suspensa
            ? <button className="botao sucesso" disabled={ocupado} onClick={reativar}><RotateCcw /> Reativar conta</button>
            : <button className="botao contorno perigo-texto" disabled={ocupado} onClick={() => setSuspender(true)}><Ban /> Suspender conta</button>) : null}
        </>} />

      {suspensa ? <div className="alerta-faixa vermelho"><Ban /><div><strong>Conta suspensa</strong>{perfil.motivo_suspensao}. A pessoa não consegue entrar nos apps, fazer pedidos nem mandar mensagens.</div></div> : null}

      <div className="grade lado">
        <div className="pilha">
          {pro ? (
            <section className="cartao">
              <div className="titulo"><div><h2>Desempenho como profissional</h2><p>{pro.profissoes.map((p) => p.nome).join(', ') || 'Sem profissão'}</p></div>
                {pro.total_avaliacoes ? <span className="linha-flex forte"><Star size={16} color="#ffb400" fill="#ffb400" /> {Number(pro.nota_media).toFixed(1)} ({pro.total_avaliacoes})</span> : null}
              </div>
              <div className="corpo">
                <div className="grade g4">
                  <div><div className="texto-fraco">Serviços concluídos</div><div className="forte" style={{ fontSize: 22 }}>{numero(pro.servicos_concluidos)}</div></div>
                  <div><div className="texto-fraco">Pedidos recebidos</div><div className="forte" style={{ fontSize: 22 }}>{numero(pro.pedidos_recebidos)}</div></div>
                  <div><div className="texto-fraco">Taxa de aceite</div><div className="forte" style={{ fontSize: 22 }}>{pro.pedidos_recebidos ? Math.round((pro.pedidos_aceitos / pro.pedidos_recebidos) * 100) + '%' : '—'}</div></div>
                  <div><div className="texto-fraco">Cancelou depois de aceitar</div><div className="forte" style={{ fontSize: 22, color: pro.cancelados_pelo_profissional > 2 ? 'var(--perigo)' : undefined }}>{numero(pro.cancelados_pelo_profissional)}</div></div>
                </div>
              </div>
            </section>
          ) : null}

          <section className="cartao">
            <div className="titulo"><div><h2>Pedidos recentes</h2><p>Os 30 últimos, como cliente ou profissional.</p></div></div>
            <div className="corpo sem-espaco">
              {dados.pedidos.length === 0 ? <div className="vazio">Nenhum pedido ainda.</div> : (
                <div className="tabela-rolagem">
                  <table className="tabela">
                    <thead><tr><th>Pedido</th><th>Papel</th><th>Com</th><th>Valor</th><th>Data</th><th>Situação</th></tr></thead>
                    <tbody>
                      {dados.pedidos.map((p) => (
                        <tr key={p.id} className="clicavel" onClick={() => router.push(`/pedido/?id=${p.id}`)}>
                          <td><span className="mono forte">{p.codigo}</span><div className="fraco">{p.profissao}</div></td>
                          <td>{p.papel === 'cliente' ? 'Cliente' : 'Profissional'}</td>
                          <td>{p.outra_parte}</td>
                          <td>{moeda(p.valor)}</td>
                          <td className="fraco">{dataHora(p.criado_em)}</td>
                          <td><SeloStatus mapa={statusPedido} valor={p.status} /></td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          </section>

          <div className="grade g2">
            <section className="cartao">
              <div className="titulo"><div><h2>Denúncias recebidas</h2></div><Selo tom={dados.denuncias_recebidas.length ? 'vermelho' : 'neutro'}>{dados.denuncias_recebidas.length}</Selo></div>
              <div className="corpo">
                {dados.denuncias_recebidas.length === 0 ? <span className="texto-suave">Nenhuma.</span> : (
                  <ul className="lista-simples">
                    {dados.denuncias_recebidas.map((d) => <li key={d.id}><span style={{ flex: 1 }}>{d.motivo}<div className="texto-fraco">{dataHora(d.criada_em)}</div></span><SeloStatus mapa={statusDenuncia} valor={d.status} /></li>)}
                  </ul>
                )}
              </div>
            </section>
            <section className="cartao">
              <div className="titulo"><div><h2>Reclamações da garantia</h2></div><Selo>{dados.reclamacoes.length}</Selo></div>
              <div className="corpo">
                {dados.reclamacoes.length === 0 ? <span className="texto-suave">Nenhuma.</span> : (
                  <ul className="lista-simples">
                    {dados.reclamacoes.map((r) => <li key={r.id}><span style={{ flex: 1 }}>{r.motivo}<div className="texto-fraco">{dataHora(r.criada_em)}</div></span><SeloStatus mapa={statusReclamacao} valor={r.status} /></li>)}
                  </ul>
                )}
              </div>
            </section>
          </div>
        </div>

        <div className="pilha">
          <section className="cartao">
            <div className="titulo"><Pessoa nome={perfil.nome} foto={perfil.foto_url} sub={perfil.email} tamanho={44} /></div>
            <div className="corpo">
              <dl className="dados">
                <div><dt>CPF</dt><dd className="mono">{cpf(perfil.cpf)}</dd></div>
                <div><dt>Nascimento</dt><dd>{data(perfil.nascimento)}{perfil.nascimento ? ` · ${idade(perfil.nascimento)}` : ''}</dd></div>
                <div><dt>Telefone</dt><dd>{telefone(perfil.telefone)}</dd></div>
                <div><dt>Código de indicação</dt><dd className="mono">{perfil.codigo_indicacao ?? '—'}</dd></div>
              </dl>
              <div className="separador" style={{ margin: '16px 0' }} />
              <dl className="dados uma">
                {dados.enderecos.length === 0 ? <div><dt>Endereço</dt><dd>—</dd></div> : dados.enderecos.map((e) => (
                  <div key={e.id}><dt>{e.rotulo}{e.principal ? ' · principal' : ''}</dt><dd>{enderecoTexto(e)}</dd></div>
                ))}
              </dl>
            </div>
          </section>

          <section className="cartao">
            <div className="titulo"><div><h2>Histórico da equipe</h2><p>O que a equipe já fez nesta conta.</p></div></div>
            <div className="corpo">
              {dados.acoes.length === 0 ? <span className="texto-suave">Nenhuma ação ainda.</span> : (
                <ul className="tempo">
                  {dados.acoes.map((a, i) => (
                    <li key={i}><span className="ponto fraco" /><div><strong>{nomesAcao[a.acao] ?? a.acao}</strong>
                      <span>{a.admin ?? 'Equipe'} · {dataHora(a.criada_em)}</span>
                      {typeof a.dados?.motivo === 'string' && a.dados.motivo ? <div className="texto-suave" style={{ fontSize: 12.5 }}>{a.dados.motivo}</div> : null}
                      {typeof a.dados?.observacao === 'string' && a.dados.observacao ? <div className="texto-suave" style={{ fontSize: 12.5 }}>{a.dados.observacao}</div> : null}
                    </div></li>
                  ))}
                </ul>
              )}
            </div>
          </section>
        </div>
      </div>

      <DialogoTexto aberto={suspender} fechar={() => setSuspender(false)} titulo={`Suspender ${perfil.nome.split(' ')[0] || 'esta conta'}?`}
        texto={<><AlertTriangle size={14} style={{ verticalAlign: -2 }} /> A pessoa sai na hora: não entra mais nos apps, some das buscas e pedidos ainda não aceitos são cancelados. Dá para reativar depois.</>}
        rotulo="Motivo (fica no registro da equipe)" botao="Suspender conta" tom="perigo"
        sugestoes={['Denúncias confirmadas', 'Documento falso', 'Pediu pagamento por fora do combinado', 'Comportamento inadequado']}
        confirmar={async (v) => {
          const ok = await executar(() => rpc('admin_suspender', { p_usuario: perfil.id, p_suspender: true, p_motivo: v }), 'Conta suspensa.');
          if (ok) { recarregar(); atualizarResumo(); }
          return ok;
        }} />
    </>
  );
}

export default function Pagina() {
  return <Suspense fallback={<Carregando />}><Ficha /></Suspense>;
}
