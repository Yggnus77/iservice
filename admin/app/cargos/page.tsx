'use client';

import { useEffect, useMemo, useState } from 'react';
import { KeyRound, Loader2, Lock, RotateCcw, Save } from 'lucide-react';
import { Cabecalho, usePainel, type Cargo, type Permissao } from '@/components/Painel';
import { ListaPermissoes, cargoDe, type ItemPermissao } from '@/components/Permissoes';
import { Carregando, ErroCaixa, Selo, useAcao, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { dataHora } from '@/lib/formatos';

type InfoCargo = {
  cargo: Cargo; nome: string; permissoes: Permissao[]; padrao: Permissao[]; editado: boolean;
  atualizado_em: string | null; atualizado_por: string | null; pode_editar: boolean; pessoas: number;
};
type Dados = { catalogo: ItemPermissao[]; minhas: Permissao[]; cargos: InfoCargo[] };

const mesmo = (a: Iterable<string>, b: Iterable<string>) => {
  const x = new Set(a); const y = new Set(b);
  return x.size === y.size && [...x].every((k) => y.has(k));
};

export default function Cargos() {
  const painel = usePainel();
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Dados>('admin_cargos'), []);
  const { executar, ocupado } = useAcao();
  const [escolhido, setEscolhido] = useState<Cargo>('gerente');
  const [marcadas, setMarcadas] = useState<Set<string>>(new Set());

  const info = dados?.cargos.find((c) => c.cargo === escolhido) ?? null;
  useEffect(() => { if (info) setMarcadas(new Set(info.permissoes)); }, [info]);

  const minhas = useMemo(() => new Set(dados?.minhas ?? []), [dados]);
  const mudou = !!info && !mesmo(marcadas, info.permissoes);
  const ehPadrao = !!info && mesmo(marcadas, info.padrao);
  const meuCargo = painel.acesso?.cargo;

  const travada = (p: ItemPermissao): string | null => {
    if (!info) return null;
    if (info.cargo === 'dono') return 'O dono tem sempre acesso a tudo.';
    if (!info.pode_editar) return 'Você não muda as permissões deste cargo.';
    if (p.chave === 'inicio') return 'Sempre ligado para todos.';
    if (!marcadas.has(p.chave) && !minhas.has(p.chave)) return 'Você não tem este acesso, então não pode dar.';
    if (p.chave === 'cargos' && info.cargo === meuCargo && marcadas.has('cargos')) return 'Você não tira este acesso do seu próprio cargo.';
    return null;
  };
  const marca = (p: ItemPermissao) => {
    if (!info || info.cargo === 'dono') return null;
    const noPadrao = info.padrao.includes(p.chave);
    if (marcadas.has(p.chave) && !noPadrao) return <span className="marca mais">fora do padrão</span>;
    if (!marcadas.has(p.chave) && noPadrao) return <span className="marca menos">tirado do padrão</span>;
    return null;
  };

  const salvar = async (padrao: boolean) => {
    if (!info) return;
    const ok = await executar(() => rpc('admin_salvar_cargo', { p_cargo: info.cargo, p_permissoes: padrao ? null : [...marcadas] }),
      padrao ? `${info.nome} voltou ao padrão.` : `Permissões de ${info.nome} salvas. Valem agora para ${info.pessoas === 1 ? 'a pessoa' : `as ${info.pessoas} pessoas`} do cargo.`);
    if (ok) recarregar();
  };

  return (
    <>
      <Cabecalho titulo="Cargos" texto="O que cada cargo vê e pode fazer no painel. A mudança vale na hora para todos do cargo."
        ajuda={<>Escolha um cargo e ligue ou desligue cada tela e ação. Vale para todas as pessoas daquele cargo, e o banco confere em cada ação. Para mudar só uma pessoa, use o botão <strong>Permissões</strong> na Equipe. O cargo Dono tem sempre tudo e não muda. Cada mudança fica no Registro da equipe.</>} />
      {erro ? <ErroCaixa erro={erro} tentar={recarregar} /> : carregando && !dados ? <Carregando /> : !dados ? null : (
        <div className="grade cargos-lado">
          <section className="cartao">
            <div className="titulo"><div><h2>Cargos</h2><p>Toque em um para ver e mudar.</p></div></div>
            <div className="corpo">
              <div className="escolha-cargos">
                {dados.cargos.map((c) => {
                  const v = cargoDe(c.cargo);
                  return (
                    <button key={c.cargo} aria-pressed={c.cargo === escolhido} onClick={() => setEscolhido(c.cargo)}>
                      <span className={`icone-cargo ${v.tom}`}>{v.icone}</span>
                      <span style={{ flex: 1 }}>
                        <strong>{c.nome}{c.cargo === meuCargo ? <span className="texto-fraco"> · seu cargo</span> : null}</strong>
                        <small>{c.pessoas} {c.pessoas === 1 ? 'pessoa' : 'pessoas'} · {c.cargo === 'dono' ? 'tudo' : `${c.permissoes.length} de ${dados.catalogo.length} acessos`}{c.editado ? ' · personalizado' : ''}</small>
                      </span>
                      {c.cargo === 'dono' ? <Lock size={16} aria-label="Travado" /> : null}
                    </button>
                  );
                })}
              </div>
            </div>
          </section>

          {info ? (
            <section className="cartao">
              <div className="titulo">
                <div>
                  <h2>{info.nome}</h2>
                  <p>{cargoDe(info.cargo).resumo}</p>
                </div>
                {info.cargo !== 'dono' ? (info.editado ? <Selo tom="roxo">Personalizado</Selo> : <Selo>Padrão</Selo>) : <Selo tom="azul" icone={<Lock />}>Travado</Selo>}
              </div>
              <div className="corpo">
                {info.editado && info.atualizado_em ? (
                  <p className="texto-fraco" style={{ margin: '0 0 14px' }}>Mudado em {dataHora(info.atualizado_em)}{info.atualizado_por ? ` por ${info.atualizado_por}` : ''}.</p>
                ) : null}
                <ListaPermissoes catalogo={dados.catalogo} ligadas={info.cargo === 'dono' ? new Set(dados.catalogo.map((p) => p.chave)) : marcadas}
                  travada={travada} marca={marca}
                  mudar={(chave, ligada) => setMarcadas((m) => { const n = new Set(m); if (ligada) n.add(chave); else n.delete(chave); return n; })} />
                {info.cargo !== 'dono' && info.pode_editar ? (
                  <div className="linha-flex" style={{ marginTop: 18, justifyContent: 'flex-end', flexWrap: 'wrap' }}>
                    <button className="botao contorno" disabled={ocupado || (!info.editado && ehPadrao)} onClick={() => salvar(true)}>
                      <RotateCcw /> Voltar ao padrão
                    </button>
                    <button className="botao contorno" disabled={ocupado || !mudou} onClick={() => setMarcadas(new Set(info.permissoes))}>Desfazer</button>
                    <button className="botao primario" disabled={ocupado || !mudou} onClick={() => salvar(false)}>
                      {ocupado ? <Loader2 className="girar" /> : <Save />} Salvar para o cargo
                    </button>
                  </div>
                ) : null}
                <div className="alerta-faixa azul" style={{ margin: '18px 0 0' }}>
                  <KeyRound />
                  <div>Para dar ou tirar um acesso de uma pessoa só, sem mudar o cargo inteiro, use o botão “Permissões” na tela Equipe.</div>
                </div>
              </div>
            </section>
          ) : null}
        </div>
      )}
    </>
  );
}
