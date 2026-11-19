'use client';

import { useState } from 'react';
import { BadgeCheck, Check, Copy, Hourglass, PencilLine, Share2 } from 'lucide-react';
import { Cabecalho } from '@/components/Painel';
import { Carregando, ErroCaixa, Vazio, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { data, numero } from '@/lib/formatos';

type Funil = { contas: number; rascunho: number; em_analise: number; aprovado: number; recusado: number; suspenso: number; indicados: number };
type Semana = { inicio: string; cadastros: number; aprovados: number; acumulado: number };
type Profissao = { id: string; nome: string; meta: number; aprovados: number; em_analise: number; rascunho: number };
type Indicador = { id: string; nome: string; codigo: string | null; indicados: number; aprovados: number };
type Captacao = { meta_total: number; meta_data: string; funil: Funil; semanas: Semana[]; profissoes: Profissao[]; indicadores: Indicador[] };

/** Meta acumulada de aprovados no fim de cada semana (Plano Diretor, tópico 3). */
const metaSemana: Record<string, number> = {
  '2026-11-23': 20, '2026-11-30': 50, '2026-12-07': 90, '2026-12-14': 150, '2026-12-21': 165, '2026-12-28': 180,
};

const linkIndicacao = (codigo: string) => `https://iservice.app.br/profissional/?indicacao=${encodeURIComponent(codigo)}`;

function Numero({ rotulo, valor, detalhe, icone, cor, fundo }: { rotulo: string; valor: string; detalhe?: string; icone: React.ReactNode; cor: string; fundo: string }) {
  return (
    <div className="cartao numero">
      <span className="rotulo"><span className="icone" style={{ color: cor, background: fundo }}>{icone}</span>{rotulo}</span>
      <span className="valor">{valor}</span>
      {detalhe ? <span className="detalhe">{detalhe}</span> : null}
    </div>
  );
}

function BotaoCopiar({ texto }: { texto: string }) {
  const [ok, setOk] = useState(false);
  return (
    <button type="button" className="botao contorno pequeno" title={texto}
      onClick={() => { void navigator.clipboard.writeText(texto).then(() => { setOk(true); setTimeout(() => setOk(false), 1800); }); }}>
      {ok ? <><Check /> Copiado</> : <><Copy /> Copiar link</>}
    </button>
  );
}

export default function Captacao() {
  const c = useCarregar(() => rpc<Captacao>('admin_captacao'), []);
  const s = c.dados;

  return (
    <>
      <Cabecalho
        ajuda={<>Acompanha a meta de profissionais aprovados antes do lançamento. Cada captador usa o próprio link de indicação: quem se cadastrar por ele aparece na tabela “Quem trouxe”, que serve para pagar o captador por aprovado.</>}
        titulo="Captação de profissionais"
        texto="Profissionais cadastrados e aprovados contra a meta, por semana, por profissão e por quem indicou." />

      {c.erro ? <ErroCaixa erro={c.erro} tentar={c.recarregar} /> : !s ? <Carregando /> : (
        <>
          <div className="grade g4" style={{ marginBottom: 18 }}>
            <Numero rotulo="Aprovados" valor={`${numero(s.funil.aprovado)} de ${numero(s.meta_total)}`} icone={<BadgeCheck />} cor="#00873A" fundo="#e6f6ec"
              detalhe={`Meta até ${data(s.meta_data)} · ${Math.min(100, Math.round((s.funil.aprovado / Math.max(1, s.meta_total)) * 100))}% feito`} />
            <Numero rotulo="Esperando análise" valor={numero(s.funil.em_analise)} icone={<Hourglass />} cor="#b25f00" fundo="#fff4e5"
              detalhe="Enviaram tudo; falta a equipe conferir" />
            <Numero rotulo="Cadastro pela metade" valor={numero(s.funil.rascunho)} icone={<PencilLine />} cor="#0046b8" fundo="#e8f0fc"
              detalhe="Criaram a conta e não terminaram" />
            <Numero rotulo="Vieram por indicação" valor={numero(s.funil.indicados)} icone={<Share2 />} cor="#5b3cc4" fundo="#efeafd"
              detalhe={`De ${numero(s.funil.contas)} contas de profissional`} />
          </div>

          <div className="grade lado">
            <div className="pilha">
              <section className="cartao">
                <div className="titulo"><div><h2>Semana a semana</h2><p>Semanas de segunda a domingo, a partir de 23/11/2026.</p></div></div>
                <div className="tabela-rolagem">
                  <table className="tabela">
                    <thead><tr><th>Semana</th><th>Cadastros novos</th><th>Aprovados</th><th>Total aprovado</th><th>Meta</th></tr></thead>
                    <tbody>
                      {s.semanas.map((w) => {
                        const meta = metaSemana[w.inicio];
                        return (
                          <tr key={w.inicio}>
                            <td>{data(w.inicio)}</td>
                            <td>{numero(w.cadastros)}</td>
                            <td>{numero(w.aprovados)}</td>
                            <td><strong>{numero(w.acumulado)}</strong></td>
                            <td>{meta ? <span style={{ color: w.acumulado >= meta ? 'var(--verde-texto, #00873A)' : undefined }}>{numero(meta)}</span> : '—'}</td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              </section>

              <section className="cartao">
                <div className="titulo"><div><h2>Quem trouxe</h2><p>Profissionais que se cadastraram com o código de indicação de alguém.</p></div></div>
                {!s.indicadores.length ? (
                  <div className="corpo"><Vazio titulo="Nenhuma indicação ainda" texto="Quando alguém se cadastrar pelo link de indicação de um captador ou profissional, aparece aqui." /></div>
                ) : (
                  <div className="tabela-rolagem">
                    <table className="tabela">
                      <thead><tr><th>Quem indicou</th><th>Código</th><th>Cadastrados</th><th>Aprovados</th><th /></tr></thead>
                      <tbody>
                        {s.indicadores.map((i) => (
                          <tr key={i.id}>
                            <td>{i.nome || 'Sem nome'}</td>
                            <td className="mono">{i.codigo ?? '—'}</td>
                            <td>{numero(i.indicados)}</td>
                            <td><strong>{numero(i.aprovados)}</strong></td>
                            <td style={{ textAlign: 'right' }}>{i.codigo ? <BotaoCopiar texto={linkIndicacao(i.codigo)} /> : null}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </section>
            </div>

            <section className="cartao">
              <div className="titulo">
                <div><h2>Por profissão</h2><p>Aprovados contra a meta de cada profissão.</p></div>
                <div className="legenda"><span><i style={{ background: 'var(--azul)' }} />Aprovados</span><span><i style={{ background: '#9cbcf0' }} />Em análise</span></div>
              </div>
              <div className="corpo">
                {s.profissoes.map((p) => {
                  const base = Math.max(1, p.meta, p.aprovados + p.em_analise);
                  return (
                    <div className="meta" key={p.id} title={`${p.aprovados} aprovados · ${p.em_analise} em análise · ${p.rascunho} pela metade`}>
                      <span className="nome">{p.nome}</span>
                      <span className="trilho">
                        {p.aprovados ? <i className="a" style={{ width: `${(p.aprovados / base) * 100}%` }} /> : null}
                        {p.em_analise ? <i className="b" style={{ width: `${(p.em_analise / base) * 100}%` }} /> : null}
                      </span>
                      <span className="valor">{numero(p.aprovados)}/{numero(p.meta)}</span>
                    </div>
                  );
                })}
                <div className="separador" />
                <p className="texto-suave" style={{ fontSize: 13 }}>
                  Um profissional com duas profissões conta nas duas. Link de indicação: iservice.app.br/profissional/?indicacao=CÓDIGO (o código de cada pessoa está na ficha dela, em Pessoas).
                </p>
              </div>
            </section>
          </div>
        </>
      )}
    </>
  );
}
