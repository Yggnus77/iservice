'use client';

import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { Suspense, useState } from 'react';
import { AlertTriangle, Check, CheckCircle2, Columns2, ExternalLink, FileText, MapPin, MessageCircle, ShieldAlert, UserRound, X } from 'lucide-react';
import { Cabecalho, usePainel } from '@/components/Painel';
import { Carregando, DialogoTexto, ErroCaixa, Miniatura, Pessoa, Selo, SeloStatus, Visor, useAcao, useCarregar, useUrlArquivo } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { cpf, data, dataHora, haQuanto, idade, moeda, pendencia, statusCadastro, statusDocumento, telefone, tipoDocumento, whatsapp } from '@/lib/formatos';
import { urlFoto, ePdf } from '@/lib/arquivos';
import { enderecoTexto, type Documento, type Ficha } from '@/lib/tipos';

const sugestoesFoto = [
  'A foto está borrada ou escura.',
  'O documento aparece cortado.',
  'O rosto e o documento precisam aparecer juntos na selfie.',
  'O documento está vencido.',
  'A certidão precisa ser emitida nos últimos 90 dias.',
];

const ordemDocs = ['selfie_documento', 'documento_frente', 'documento_verso', 'antecedentes', 'comprovante_endereco'];

function CartaoDocumento({ doc, abrir, revisar, ocupado }: { doc: Documento; abrir: (url: string | null) => void; revisar: (d: Documento, aprovar: boolean) => void; ocupado: boolean }) {
  const { url, falhou } = useUrlArquivo('documentos', doc.arquivo_path);
  const pdf = ePdf(doc.arquivo_path);
  return (
    <div className={`doc ${doc.status}`}>
      <div className="imagem" onClick={() => abrir(url)} role="button" tabIndex={0} aria-label={`Abrir ${tipoDocumento[doc.tipo]}`}
        onKeyDown={(e) => { if (e.key === 'Enter') abrir(url); }}>
        {falhou ? <span style={{ color: '#cfdaf0' }}>Arquivo indisponível</span> : !url ? <span className="esqueleto" style={{ width: '100%', height: '100%' }} /> :
          pdf ? <span className="pdf"><FileText size={36} /> PDF · clique para abrir</span> : <img src={url} alt={tipoDocumento[doc.tipo]} />}
      </div>
      <div className="info">
        <div className="linha-flex" style={{ justifyContent: 'space-between' }}>
          <strong>{tipoDocumento[doc.tipo] ?? doc.tipo}</strong>
          <SeloStatus mapa={statusDocumento} valor={doc.status} />
        </div>
        <span className="texto-fraco">Enviado {haQuanto(doc.criado_em)}</span>
        {doc.observacao ? <span className="obs">{doc.observacao}</span> : null}
        {doc.status === 'pendente' ? (
          <div className="botoes">
            <button className="botao contorno perigo-texto pequeno" disabled={ocupado} onClick={() => revisar(doc, false)}><X /> Nova foto</button>
            <button className="botao sucesso pequeno" disabled={ocupado} onClick={() => revisar(doc, true)}><Check /> Aprovar</button>
          </div>
        ) : doc.status === 'aprovado' ? (
          <div className="botoes"><button className="botao fantasma pequeno" disabled={ocupado} onClick={() => revisar(doc, false)}>Pedir nova foto</button></div>
        ) : null}
      </div>
    </div>
  );
}

function Revisao() {
  const id = useSearchParams().get('id') ?? '';
  const { atualizarResumo } = usePainel();
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Ficha>('admin_usuario', { p_id: id }), [id]);
  const { executar, ocupado } = useAcao();
  const [recusarDoc, setRecusarDoc] = useState<Documento | null>(null);
  const [recusarCadastro, setRecusarCadastro] = useState(false);
  const [visor, setVisor] = useState<{ titulo: string; url: string | null; caminho?: string | null }[] | null>(null);
  const [comparar, setComparar] = useState(false);

  const selfie = dados?.profissional?.documentos.find((d) => d.tipo === 'selfie_documento' && d.status !== 'recusado')
    ?? dados?.profissional?.documentos.find((d) => d.tipo === 'selfie_documento');
  const frente = dados?.profissional?.documentos.find((d) => d.tipo === 'documento_frente' && d.status !== 'recusado')
    ?? dados?.profissional?.documentos.find((d) => d.tipo === 'documento_frente');
  const urlSelfie = useUrlArquivo('documentos', selfie?.arquivo_path).url;
  const urlFrente = useUrlArquivo('documentos', frente?.arquivo_path).url;

  if (erro) return <ErroCaixa erro={erro} tentar={recarregar} />;
  if (carregando && !dados) return <Carregando />;
  if (!dados) return null;
  const { perfil, profissional: pro } = dados;
  if (!pro) return <ErroCaixa erro="Esta pessoa não tem cadastro de profissional." />;

  const fim = async () => { recarregar(); atualizarResumo(); };
  const revisar = async (d: Documento, aprovar: boolean) => {
    if (!aprovar) { setRecusarDoc(d); return; }
    if (await executar(() => rpc('admin_revisar_documento', { p_documento: d.id, p_aprovar: true }), 'Documento aprovado.')) fim();
  };
  const aprovarCadastro = async () => {
    if (await executar(() => rpc('admin_decidir_cadastro', { p_profissional: perfil.id, p_aprovar: true }), `${perfil.nome.split(' ')[0]} foi aprovado e já pode atender.`)) fim();
  };
  const revisarCert = async (certId: number, aprovar: boolean) => {
    if (await executar(() => rpc('admin_revisar_certificacao', { p_certificacao: certId, p_aprovar: aprovar }), aprovar ? 'Certificação aprovada.' : 'Certificação recusada.')) fim();
  };

  const docs = [...pro.documentos].sort((a, b) => ordemDocs.indexOf(a.tipo) - ordemDocs.indexOf(b.tipo) || b.criado_em.localeCompare(a.criado_em));
  const exigeAntecedentes = pro.profissoes.some((p) => p.exige_antecedentes);
  const antecedentes = docs.find((d) => d.tipo === 'antecedentes' && d.status !== 'recusado');
  const pendencias = pro.pendencias ?? [];
  const docsPendentes = docs.filter((d) => d.status === 'pendente').length;
  const zap = whatsapp(perfil.telefone);
  const end = dados.enderecos.find((e) => e.principal) ?? dados.enderecos[0];

  return (
    <>
      <Cabecalho voltar={{ href: '/cadastros/', rotulo: 'Cadastros' }} titulo={perfil.nome || 'Sem nome'}
        texto={<span className="linha-flex" style={{ marginTop: 4 }}>
          <SeloStatus mapa={statusCadastro} valor={pro.status} />
          {perfil.suspenso_em ? <Selo tom="vermelho">Conta suspensa</Selo> : null}
          {pro.verificado ? <Selo tom="azul" icone={<CheckCircle2 />}>Verificado</Selo> : null}
          <span className="texto-fraco">Cadastro criado {haQuanto(pro.criado_em)} · atualizado {haQuanto(pro.atualizado_em)}</span>
        </span>}
        acoes={<>
          <Link className="botao contorno" href={`/pessoa/?id=${perfil.id}`}><UserRound /> Ficha completa</Link>
          {pro.status !== 'aprovado' && pro.status !== 'suspenso' ? <>
            <button className="botao contorno perigo-texto" disabled={ocupado} onClick={() => setRecusarCadastro(true)}><X /> Pedir ajustes</button>
            <button className="botao sucesso" disabled={ocupado || pendencias.length > 0} onClick={aprovarCadastro}
              title={pendencias.length ? 'Ainda há pendências no cadastro' : docsPendentes ? 'Aprova também os documentos que ainda estão pendentes' : ''}>
              <Check /> Aprovar cadastro
            </button>
          </> : null}
        </>} />

      {pro.motivo_status && pro.status !== 'aprovado' ? (
        <div className="alerta-faixa laranja"><AlertTriangle /><div><strong>Último pedido de ajuste</strong>{pro.motivo_status}</div></div>
      ) : null}
      {pendencias.length ? (
        <div className="alerta-faixa vermelho"><AlertTriangle /><div><strong>Ainda falta no cadastro</strong>{pendencias.map((p) => pendencia[p] ?? p).join(', ')}.
          O profissional precisa completar pelo app antes da aprovação.</div></div>
      ) : null}
      {exigeAntecedentes ? (
        <div className={`alerta-faixa ${antecedentes?.status === 'aprovado' ? 'azul' : 'laranja'}`}>
          <ShieldAlert />
          <div><strong>Profissão que exige certidão de antecedentes criminais</strong>
            {antecedentes ? (antecedentes.status === 'aprovado' ? 'Certidão aprovada.' : 'Confira se a certidão é recente, está no nome e CPF da pessoa e não tem registros.')
              : 'A certidão ainda não foi enviada.'}</div>
        </div>
      ) : null}

      <div className="grade lado">
        <div className="pilha">
          <section className="cartao">
            <div className="titulo">
              <div><h2>Conferência de identidade</h2><p>Compare o rosto da foto de perfil e da selfie com a foto do documento.</p></div>
              <button className="botao contorno pequeno" onClick={() => setComparar(true)}><Columns2 /> Comparar lado a lado</button>
            </div>
            <div className="corpo">
              <div className="documentos">
                <div className="doc">
                  <div className="imagem" onClick={() => setVisor([{ titulo: 'Foto de perfil', url: urlFoto(perfil.foto_url) }])}>
                    {perfil.foto_url ? <img src={urlFoto(perfil.foto_url) ?? ''} alt="Foto de perfil" /> : <span style={{ color: '#cfdaf0' }}>Sem foto</span>}
                  </div>
                  <div className="info"><strong>Foto de perfil</strong><span className="texto-fraco">Aparece para os clientes no app</span></div>
                </div>
                {docs.map((d) => (
                  <CartaoDocumento key={d.id} doc={d} ocupado={ocupado} revisar={revisar}
                    abrir={(url) => setVisor([{ titulo: tipoDocumento[d.tipo] ?? d.tipo, url, caminho: d.arquivo_path }])} />
                ))}
              </div>
            </div>
          </section>

          <section className="cartao">
            <div className="titulo"><div><h2>Profissões, especialidades e preços</h2><p>O profissional define o próprio preço.</p></div></div>
            <div className="corpo">
              {pro.profissoes.length === 0 ? <span className="texto-suave">Nenhuma profissão escolhida.</span> : pro.profissoes.map((f) => (
                <div key={f.id} style={{ marginBottom: 14 }}>
                  <div className="linha-flex" style={{ marginBottom: 8 }}>
                    <strong>{f.nome}</strong>
                    {f.principal ? <Selo tom="azul">Principal</Selo> : null}
                    {f.exige_antecedentes ? <Selo tom="roxo">Exige antecedentes</Selo> : null}
                  </div>
                  <div className="linha-flex" style={{ gap: 6 }}>
                    {f.especialidades.length ? f.especialidades.map((e) => (
                      <Selo key={e.id} tom={e.aprovada ? 'neutro' : 'laranja'}>{e.nome}: {e.preco ? moeda(e.preco) : 'sem preço'}{e.aprovada ? '' : ' (sugerida)'}</Selo>
                    )) : <span className="texto-fraco">Sem especialidades</span>}
                  </div>
                </div>
              ))}
              {pro.bio ? <><div className="separador" style={{ margin: '8px 0 14px' }} /><div className="campo"><span className="rotulo">Sobre</span><div className="citacao">{pro.bio}</div></div></> : null}
            </div>
          </section>

          <section className="cartao">
            <div className="titulo"><div><h2>Certificações</h2><p>Aparecem no perfil só depois de aprovadas.</p></div></div>
            <div className="corpo">
              {pro.certificacoes.length === 0 ? <span className="texto-suave">Nenhuma certificação enviada.</span> : (
                <ul className="lista-simples">
                  {pro.certificacoes.map((c) => (
                    <li key={c.id}>
                      <div style={{ flex: 1 }}>
                        <strong>{c.nome}</strong>
                        <div className="texto-fraco">{c.instituicao || 'Instituição não informada'} · enviada {haQuanto(c.criado_em)}</div>
                      </div>
                      {c.arquivo_path ? <div className="miniaturas"><Miniatura bucket="documentos" caminho={c.arquivo_path} titulo={c.nome} /></div> : null}
                      <SeloStatus mapa={statusDocumento} valor={c.status} />
                      {c.status === 'pendente' ? <>
                        <button className="botao contorno perigo-texto pequeno" disabled={ocupado} onClick={() => revisarCert(c.id, false)}>Recusar</button>
                        <button className="botao sucesso pequeno" disabled={ocupado} onClick={() => revisarCert(c.id, true)}>Aprovar</button>
                      </> : null}
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </section>

          {pro.portfolio.length ? (
            <section className="cartao">
              <div className="titulo"><div><h2>Portfólio</h2><p>Fotos de antes e depois que o cliente vê no perfil.</p></div></div>
              <div className="corpo">
                <div className="miniaturas">
                  {pro.portfolio.flatMap((p) => [p.antes_path && { c: p.antes_path, t: 'Antes' }, { c: p.depois_path, t: 'Depois' }].filter(Boolean).map((x) => {
                    const i = x as { c: string; t: string };
                    return <Miniatura key={p.id + i.t} bucket="portfolio" caminho={i.c} titulo={`${i.t}${p.descricao ? ': ' + p.descricao : ''}`} />;
                  }))}
                </div>
              </div>
            </section>
          ) : null}
        </div>

        <div className="pilha">
          <section className="cartao">
            <div className="titulo"><Pessoa nome={perfil.nome} foto={perfil.foto_url} sub={perfil.email} tamanho={44} /></div>
            <div className="corpo">
              <dl className="dados">
                <div><dt>CPF</dt><dd className="mono">{cpf(perfil.cpf)}</dd></div>
                <div><dt>Nascimento</dt><dd>{data(perfil.nascimento)} · {idade(perfil.nascimento)}</dd></div>
                <div><dt>Telefone</dt><dd>{telefone(perfil.telefone)} {perfil.telefone_verificado ? <Selo tom="verde">verificado</Selo> : null}</dd></div>
                <div><dt>Experiência</dt><dd>{pro.anos_experiencia != null ? `${pro.anos_experiencia} anos` : '—'}</dd></div>
              </dl>
              <dl className="dados uma" style={{ marginTop: 14 }}>
                <div><dt>Endereço</dt><dd>{end ? enderecoTexto(end) : '—'}</dd></div>
              </dl>
              {zap ? <a className="botao contorno cheio" style={{ marginTop: 16 }} href={zap} target="_blank" rel="noreferrer"><MessageCircle /> Chamar no WhatsApp</a> : null}
            </div>
          </section>

          <section className="cartao">
            <div className="titulo"><div><h2>Área de atendimento</h2></div></div>
            <div className="corpo">
              <dl className="dados">
                <div><dt>Região</dt><dd>{pro.regiao ?? '—'}</dd></div>
                <div><dt>Raio</dt><dd>{pro.area_raio_km} km</dd></div>
              </dl>
              {pro.area_lat != null ? (
                <a className="botao contorno cheio" style={{ marginTop: 14 }} target="_blank" rel="noreferrer"
                  href={`https://www.google.com/maps/search/?api=1&query=${pro.area_lat},${pro.area_lng}`}><MapPin /> Ver no mapa <ExternalLink size={14} /></a>
              ) : <span className="texto-fraco">Área ainda não definida.</span>}
            </div>
          </section>

          {dados.acoes.length ? (
            <section className="cartao">
              <div className="titulo"><div><h2>Histórico da equipe</h2></div></div>
              <div className="corpo">
                <ul className="tempo">
                  {dados.acoes.slice(0, 8).map((a, i) => (
                    <li key={i}><span className="ponto fraco" /><div><strong>{a.admin ?? 'Equipe'}: {a.acao.replace(/_/g, ' ')}</strong>
                      <span>{dataHora(a.criada_em)}{typeof a.dados?.observacao === 'string' && a.dados.observacao ? ` · ${a.dados.observacao}` : ''}
                        {typeof a.dados?.motivo === 'string' && a.dados.motivo ? ` · ${a.dados.motivo}` : ''}</span></div></li>
                  ))}
                </ul>
              </div>
            </section>
          ) : null}
        </div>
      </div>

      <DialogoTexto aberto={!!recusarDoc} fechar={() => setRecusarDoc(null)} titulo="Pedir uma nova foto"
        texto={recusarDoc ? <>O profissional recebe o aviso e envia de novo <strong>{(tipoDocumento[recusarDoc.tipo] ?? '').toLowerCase()}</strong> pelo app.</> : null}
        rotulo="O que precisa mudar" sugestoes={sugestoesFoto} botao="Pedir nova foto" tom="perigo"
        confirmar={async (v) => {
          const ok = await executar(() => rpc('admin_revisar_documento', { p_documento: recusarDoc!.id, p_aprovar: false, p_observacao: v }), 'Pedido de nova foto enviado.');
          if (ok) fim();
          return ok;
        }} />
      <DialogoTexto aberto={recusarCadastro} fechar={() => setRecusarCadastro(false)} titulo="Pedir ajustes no cadastro"
        texto="O profissional vê este texto no app e pode corrigir e reenviar." rotulo="Motivo" botao="Enviar pedido de ajuste" tom="perigo"
        sugestoes={['Os dados do documento não batem com o cadastro.', 'Complete as especialidades e os preços.', 'Escolha uma área de atendimento dentro do DF e Entorno.']}
        confirmar={async (v) => {
          const ok = await executar(() => rpc('admin_decidir_cadastro', { p_profissional: perfil.id, p_aprovar: false, p_motivo: v }), 'Pedido de ajuste enviado.');
          if (ok) fim();
          return ok;
        }} />

      {visor ? <Visor itens={visor} fechar={() => setVisor(null)} /> : null}
      {comparar ? (
        <div className="visor" role="dialog" aria-modal="true" aria-label="Comparar fotos">
          <div className="barra"><strong>Comparar: foto de perfil, selfie e documento</strong><button onClick={() => setComparar(false)} aria-label="Fechar"><X size={16} /></button></div>
          <div className="area">
            <div className="lado-a-lado" style={{ gridTemplateColumns: '1fr 1fr 1fr' }}>
              <div>Foto de perfil{perfil.foto_url ? <img src={urlFoto(perfil.foto_url) ?? ''} alt="Foto de perfil" /> : <span>Sem foto</span>}</div>
              <div>Selfie com documento{urlSelfie && !ePdf(selfie?.arquivo_path) ? <img src={urlSelfie} alt="Selfie" /> : <span>Sem selfie</span>}</div>
              <div>Documento{urlFrente && !ePdf(frente?.arquivo_path) ? <img src={urlFrente} alt="Documento" /> : <span>Sem imagem do documento</span>}</div>
            </div>
          </div>
        </div>
      ) : null}
    </>
  );
}

export default function Pagina() {
  return <Suspense fallback={<Carregando />}><Revisao /></Suspense>;
}
