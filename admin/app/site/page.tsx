'use client';

import { useState } from 'react';
import { Download, Eye, Smartphone, UserPlus } from 'lucide-react';
import { Cabecalho } from '@/components/Painel';
import { Abas, Carregando, ErroCaixa, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { diaCurto, numero } from '@/lib/formatos';

type Dia = { dia: string; visitas: number; baixar_cliente: number; baixar_profissional: number; cadastros_clientes: number; cadastros_profissionais: number };
type Site = { inicio: string; fim: string; dias: Dia[]; por_plataforma: Record<string, number>; paginas: { pagina: string; visitas: number }[] };

const nomesPagina: Record<string, string> = {
  '/': 'Página inicial', '/index.html': 'Página inicial', '/termos.html': 'Termos de Uso', '/privacidade.html': 'Privacidade',
  '/excluir-conta.html': 'Excluir conta', '/404.html': 'Página não encontrada',
};

function Numero({ rotulo, valor, detalhe, icone, cor, fundo }: { rotulo: string; valor: string; detalhe?: string; icone: React.ReactNode; cor: string; fundo: string }) {
  return (
    <div className="cartao numero">
      <span className="rotulo"><span className="icone" style={{ color: cor, background: fundo }}>{icone}</span>{rotulo}</span>
      <span className="valor">{valor}</span>
      {detalhe ? <span className="detalhe">{detalhe}</span> : null}
    </div>
  );
}

export default function SiteEDownloads() {
  const [periodo, setPeriodo] = useState<'7' | '30' | '90'>('30');
  const site = useCarregar(() => rpc<Site>('admin_site', { p_dias: Number(periodo) }), [periodo]);
  const s = site.dados;

  const soma = (f: (d: Dia) => number) => (s?.dias ?? []).reduce((a, d) => a + Number(f(d)), 0);
  const visitas = soma((d) => d.visitas);
  const baixarCli = soma((d) => d.baixar_cliente);
  const baixarPro = soma((d) => d.baixar_profissional);
  const cadastros = soma((d) => d.cadastros_clientes + d.cadastros_profissionais);
  const plat = s?.por_plataforma ?? {};
  const pct = (a: number, b: number) => (b ? `${Math.round((a / b) * 100)}%` : '—');

  const dias = s?.dias ?? [];
  const compacto = dias.length > 14;
  const passoRotulo = dias.length > 31 ? 14 : dias.length > 14 ? 5 : 1;
  const maxVis = Math.max(1, ...dias.map((d) => d.visitas));
  const maxBx = Math.max(1, ...dias.map((d) => Math.max(d.baixar_cliente, d.baixar_profissional)));

  return (
    <>
      <Cabecalho titulo="Site e downloads" texto="Quem visitou iservice.app.br e clicou para baixar os apps. Cada pessoa conta uma vez por dia, sem cookies." />
      <div className="filtros">
        <Abas ativa={periodo} mudar={setPeriodo} abas={[{ id: '7', rotulo: '7 dias' }, { id: '30', rotulo: '30 dias' }, { id: '90', rotulo: '90 dias' }]} />
      </div>

      {site.erro ? <ErroCaixa erro={site.erro} tentar={site.recarregar} /> : !s ? <Carregando /> : (
        <>
          <div className="grade g4" style={{ marginBottom: 18 }}>
            <Numero rotulo="Visitas ao site" valor={numero(visitas)} icone={<Eye />} cor="#0046b8" fundo="#e8f0fc"
              detalhe={`Média de ${numero(Math.round(visitas / Math.max(1, dias.length)))} por dia`} />
            <Numero rotulo="Baixaram o app Cliente" valor={numero(baixarCli)} icone={<Download />} cor="#0046b8" fundo="#e8f0fc"
              detalhe={`${numero(plat.cliente_android ?? 0)} Android · ${numero(plat.cliente_navegador ?? 0)} pelo navegador`} />
            <Numero rotulo="Baixaram o app Profissional" valor={numero(baixarPro)} icone={<Smartphone />} cor="#b25f00" fundo="#fff4e5"
              detalhe={`${numero(plat.profissional_android ?? 0)} Android · ${numero(plat.profissional_navegador ?? 0)} pelo navegador`} />
            <Numero rotulo="Cadastros novos" valor={numero(cadastros)} icone={<UserPlus />} cor="#5b3cc4" fundo="#efeafd"
              detalhe={`${pct(baixarCli + baixarPro, visitas)} dos visitantes clicaram para baixar`} />
          </div>

          <div className="grade lado">
            <div className="pilha">
              <section className="cartao">
                <div className="titulo"><div><h2>Visitas por dia</h2><p>Pessoas diferentes que abriram o site em cada dia.</p></div></div>
                <div className="corpo">
                  <div className="barras" role="img" aria-label="Visitas por dia" style={compacto ? { gap: 3 } : undefined}>
                    {dias.map((d, i) => (
                      <div className="coluna" key={d.dia} style={{ minWidth: 0 }}>
                        <span className="dica">{diaCurto(d.dia)}: {d.visitas} visitas</span>
                        {compacto ? null : <span className="val">{d.visitas}</span>}
                        <div className="barra" style={{ height: `${(d.visitas / maxVis) * 100}%` }} />
                        <span className="rot" style={{ whiteSpace: 'nowrap', visibility: i % passoRotulo === (dias.length - 1) % passoRotulo ? 'visible' : 'hidden' }}>{diaCurto(d.dia)}</span>
                      </div>
                    ))}
                  </div>
                </div>
              </section>
              <section className="cartao">
                <div className="titulo">
                  <div><h2>Cliques em “Baixar” por dia</h2><p>Quem escolheu um dos apps na janela de download.</p></div>
                  <div className="legenda"><span><i style={{ background: 'var(--azul)' }} />Cliente</span><span><i style={{ background: 'var(--laranja)' }} />Profissional</span></div>
                </div>
                <div className="corpo">
                  <div className="barras" role="img" aria-label="Cliques em baixar por dia" style={compacto ? { gap: 3 } : undefined}>
                    {dias.map((d, i) => (
                      <div className="coluna" key={d.dia} style={{ minWidth: 0 }}>
                        <span className="dica">{diaCurto(d.dia)}: {d.baixar_cliente} Cliente · {d.baixar_profissional} Profissional · {d.cadastros_clientes + d.cadastros_profissionais} cadastros</span>
                        {compacto ? null : <span className="val">{d.baixar_cliente + d.baixar_profissional}</span>}
                        <div className="dupla">
                          <div className="barra" style={{ height: `${(d.baixar_cliente / maxBx) * 100}%` }} />
                          <div className="barra sem" style={{ height: `${(d.baixar_profissional / maxBx) * 100}%` }} />
                        </div>
                        <span className="rot" style={{ whiteSpace: 'nowrap', visibility: i % passoRotulo === (dias.length - 1) % passoRotulo ? 'visible' : 'hidden' }}>{diaCurto(d.dia)}</span>
                      </div>
                    ))}
                  </div>
                </div>
              </section>
            </div>

            <section className="cartao">
              <div className="titulo"><div><h2>Páginas mais vistas</h2><p>No período escolhido.</p></div></div>
              <div className="corpo">
                {!s.paginas.length ? <span className="texto-suave">Nenhuma visita registrada ainda.</span> : s.paginas.map((p) => (
                  <div className="meta" key={p.pagina}>
                    <span className="nome">{nomesPagina[p.pagina] ?? p.pagina}</span>
                    <span className="trilho"><i className="a" style={{ width: `${(p.visitas / Math.max(1, s.paginas[0].visitas)) * 100}%` }} /></span>
                    <span className="valor">{numero(p.visitas)}</span>
                  </div>
                ))}
                <div className="separador" />
                <p className="texto-suave" style={{ fontSize: 13 }}>
                  “Pelo navegador” é quem tem iPhone e abriu a versão web. A contagem começou em 30/10/2026.
                </p>
              </div>
            </section>
          </div>
        </>
      )}
    </>
  );
}
