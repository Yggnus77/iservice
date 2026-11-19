'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { AlertTriangle, BadgeCheck, BellRing, Clock, Search } from 'lucide-react';
import { Cabecalho, usePainel } from '@/components/Painel';
import { Abas, Carregando, ErroCaixa, Pessoa, Selo, SeloStatus, Vazio, useAcao, useCarregar } from '@/components/ui';
import { Ajuda } from '@/components/Ajuda';
import { rpc } from '@/lib/supabase';
import { haQuanto, pendencia, statusCadastro, telefone } from '@/lib/formatos';

type Linha = {
  id: string; nome: string; email: string; telefone: string; foto_url: string; status: string; motivo_status: string | null;
  profissoes: string[]; exige_antecedentes: boolean; regiao: string | null; documentos_pendentes: number; documentos_recusados: number;
  criado_em: string; atualizado_em: string; suspenso: boolean; enviado_em?: string;
};

/** Prazo da Política de Verificação: 48 horas úteis (sábado e domingo não contam). */
function prazoAnalise(enviado: string): Date {
  const d = new Date(enviado);
  let horas = 48;
  while (horas > 0) {
    d.setHours(d.getHours() + 1);
    const dia = d.getDay();
    if (dia !== 0 && dia !== 6) horas--;
  }
  return d;
}

function SeloPrazo({ enviado }: { enviado: string }) {
  const falta = prazoAnalise(enviado).getTime() - Date.now();
  const horas = Math.round(Math.abs(falta) / 3600000);
  const texto = horas < 1 ? 'menos de 1h' : horas < 48 ? `${horas}h` : `${Math.round(horas / 24)} dias`;
  if (falta < 0) return <Selo tom="vermelho" icone={<AlertTriangle />}>Atrasado {texto}</Selo>;
  return <Selo tom={falta < 12 * 3600000 ? 'laranja' : 'neutro'} icone={<Clock />}>Faltam {texto}</Selo>;
}

type Aba = 'em_analise' | 'recusado' | 'rascunho' | 'aprovado' | 'suspenso';

type Incompleto = {
  id: string; nome: string; email: string | null; telefone: string | null; foto_url: string | null; status: string; criado_em: string;
  atualizado_em: string; pendencias: string[]; profissoes: string[]; lembretes: number; ultimo_lembrete: string | null;
};

const DIA = 24 * 3600 * 1000;
const podeLembrar = (l: Incompleto) => !l.ultimo_lembrete || Date.now() - new Date(l.ultimo_lembrete).getTime() > DIA;

/** Quem começou o cadastro e parou no meio (ou precisa de ajuste), com o que falta e o lembrete. */
function Incompletos({ status, busca, alternativa }: { status: 'rascunho' | 'recusado'; busca: string; alternativa: React.ReactNode }) {
  const router = useRouter();
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Incompleto[]>('admin_cadastros_incompletos', { p_texto: busca || null }), [busca]);
  const { executar, ocupado } = useAcao();
  const [marcados, setMarcados] = useState<Set<string>>(new Set());
  useEffect(() => setMarcados(new Set()), [status, busca]);
  // Sem o SQL das ferramentas de gestão, fica a lista simples de antes.
  if (erro) return <>{alternativa}</>;
  const lista = (dados ?? []).filter((l) => l.status === status);
  const lembraveis = lista.filter(podeLembrar);
  const lembrar = async (ids: string[]) => {
    let n = 0;
    const ok = await executar(async () => { n = await rpc<number>('admin_lembrar_cadastro', { p_profissionais: ids }); });
    if (ok) { setMarcados(new Set()); recarregar(); }
    return ok ? n : -1;
  };
  const avisar = (n: number) => n >= 0 && window.alert(n === 0 ? 'Ninguém recebeu: todos já tinham recebido um lembrete nas últimas 24 horas.'
    : n === 1 ? 'Lembrete enviado para 1 profissional.' : `Lembrete enviado para ${n} profissionais.`);
  const marcar = (id: string, v: boolean) => setMarcados((m) => { const n = new Set(m); if (v) n.add(id); else n.delete(id); return n; });

  return (
    <section className="cartao">
      <div className="titulo">
        <div>
          <h2 className="com-ajuda">{status === 'rascunho' ? 'Começaram e não terminaram' : 'Precisam enviar um ajuste'}
            <Ajuda titulo="Lembrete de cadastro">
              Mostra o que falta para cada profissional terminar o cadastro. O <strong>lembrete</strong> chega como notificação no app
              dizendo exatamente o que falta. Cada pessoa recebe no máximo um lembrete por dia, para não virar incômodo.
              Quem está aqui há mais tempo costuma precisar de uma ligação.
            </Ajuda>
          </h2>
          <p>{lista.length} {lista.length === 1 ? 'profissional' : 'profissionais'} · {lembraveis.length} podem receber lembrete agora</p>
        </div>
        <div className="linha-flex">
          {marcados.size ? <button className="botao primario pequeno" disabled={ocupado} onClick={async () => avisar(await lembrar([...marcados]))}>
            <BellRing /> Lembrar {marcados.size} {marcados.size === 1 ? 'marcado' : 'marcados'}</button> : null}
          <button className="botao contorno pequeno" disabled={ocupado || !lembraveis.length}
            onClick={async () => { if (window.confirm(`Mandar lembrete para ${lembraveis.length} ${lembraveis.length === 1 ? 'profissional' : 'profissionais'}?`)) avisar(await lembrar(lembraveis.map((l) => l.id))); }}>
            <BellRing /> Lembrar todos
          </button>
        </div>
      </div>
      <div className="corpo sem-espaco">
        {carregando && !dados ? <Carregando /> : !lista.length ? <Vazio icone={<BadgeCheck size={24} />} titulo="Ninguém por aqui" /> : (
          <div className="tabela-rolagem">
            <table className="tabela">
              <thead><tr>
                <th style={{ width: 36 }}><input type="checkbox" aria-label="Marcar todos que podem receber"
                  checked={lembraveis.length > 0 && lembraveis.every((l) => marcados.has(l.id))}
                  onChange={(e) => setMarcados(e.target.checked ? new Set(lembraveis.map((l) => l.id)) : new Set())} /></th>
                <th>Profissional</th><th>O que falta</th><th>Parado</th><th>Lembrete</th><th></th>
              </tr></thead>
              <tbody>
                {lista.map((l) => (
                  <tr key={l.id} className="clicavel" onClick={() => router.push(`/cadastro/?id=${l.id}`)}>
                    <td onClick={(e) => e.stopPropagation()}>
                      <input type="checkbox" disabled={!podeLembrar(l)} checked={marcados.has(l.id)} onChange={(e) => marcar(l.id, e.target.checked)}
                        aria-label={`Marcar ${l.nome}`} title={podeLembrar(l) ? '' : 'Já recebeu um lembrete nas últimas 24 horas'} />
                    </td>
                    <td><Pessoa nome={l.nome} foto={l.foto_url} sub={l.profissoes.join(', ') || l.email || telefone(l.telefone)} /></td>
                    <td>
                      <div className="linha-flex" style={{ gap: 6 }}>
                        {l.pendencias.length ? l.pendencias.slice(0, 4).map((p) => <Selo key={p} tom="laranja">{pendencia[p] ?? p}</Selo>)
                          : <Selo tom="azul">Só falta enviar para análise</Selo>}
                        {l.pendencias.length > 4 ? <Selo>+{l.pendencias.length - 4}</Selo> : null}
                      </div>
                    </td>
                    <td className="fraco">{haQuanto(l.atualizado_em)}</td>
                    <td className="fraco">{l.ultimo_lembrete ? <>{haQuanto(l.ultimo_lembrete)}{l.lembretes > 1 ? ` · ${l.lembretes}×` : ''}</> : 'Nunca'}</td>
                    <td onClick={(e) => e.stopPropagation()} style={{ textAlign: 'right' }}>
                      <button className="botao contorno pequeno" disabled={ocupado || !podeLembrar(l)} onClick={async () => avisar(await lembrar([l.id]))}>
                        <BellRing /> Lembrar
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </section>
  );
}

export default function Cadastros() {
  const router = useRouter();
  const { resumo } = usePainel();
  const [aba, setAba] = useState<Aba>('em_analise');
  const [texto, setTexto] = useState('');
  const [busca, setBusca] = useState('');
  useEffect(() => { const t = setTimeout(() => setBusca(texto), 300); return () => clearTimeout(t); }, [texto]);
  const { dados, erro, carregando, recarregar } = useCarregar(
    () => rpc<Linha[]>('admin_cadastros', { p_status: aba, p_texto: busca || null }), [aba, busca]);

  return (
    <>
      <Cabecalho titulo="Cadastros de profissionais" texto="Confira documento, selfie e antecedentes antes de liberar alguém para atender."
        ajuda={<>
          <strong>Para aprovar:</strong> enviaram tudo e esperam a conferência (o mais antigo no topo). A Política de Verificação promete resposta em até 48 horas úteis.<br />
          <strong>Ajustes pedidos:</strong> a equipe pediu para reenviar algo.<br />
          <strong>Ainda preenchendo:</strong> começaram e pararam no meio. Mande um lembrete dizendo o que falta.<br />
          Abra o cadastro para ver documentos, selfie, preços e certidão antes de aprovar.
        </>} />
      <div className="filtros">
        <Abas<Aba> ativa={aba} mudar={setAba} abas={[
          { id: 'em_analise', rotulo: 'Para aprovar', n: resumo?.cadastros_em_analise },
          { id: 'recusado', rotulo: 'Ajustes pedidos' },
          { id: 'rascunho', rotulo: 'Ainda preenchendo' },
          { id: 'aprovado', rotulo: 'Aprovados' },
          { id: 'suspenso', rotulo: 'Suspensos' },
        ]} />
        <span className="espaco" />
        <div className="busca">
          <Search />
          <input className="entrada" placeholder="Nome, e-mail ou CPF" value={texto} onChange={(e) => setTexto(e.target.value)} aria-label="Buscar cadastro" />
        </div>
      </div>
      {(() => { const tabela = (
      <section className="cartao">
        <div className="corpo sem-espaco">
          {erro ? <div style={{ padding: 16 }}><ErroCaixa erro={erro} tentar={recarregar} /></div> : carregando && !dados ? <Carregando /> : !dados?.length ? (
            <Vazio icone={<BadgeCheck size={24} />} titulo={aba === 'em_analise' ? 'Nenhum cadastro esperando' : 'Nada por aqui'}
              texto={aba === 'em_analise' ? 'Quando um profissional enviar o cadastro, ele aparece aqui.' : undefined} />
          ) : (
            <div className="tabela-rolagem">
              <table className="tabela">
                <thead>
                  <tr><th>Profissional</th><th>Profissões</th><th>Região</th><th>Documentos</th><th>{aba === 'em_analise' ? 'Prazo (48h úteis)' : 'Atualizado'}</th><th>Situação</th></tr>
                </thead>
                <tbody>
                  {dados.map((l) => (
                    <tr key={l.id} className="clicavel" onClick={() => router.push(`/cadastro/?id=${l.id}`)}>
                      <td><Pessoa nome={l.nome} foto={l.foto_url} sub={l.email || telefone(l.telefone)} /></td>
                      <td>
                        <div className="linha-flex" style={{ gap: 6 }}>
                          {l.profissoes.length ? l.profissoes.map((p) => <Selo key={p}>{p}</Selo>) : <span className="fraco">—</span>}
                        </div>
                      </td>
                      <td>{l.regiao ?? <span className="fraco">—</span>}</td>
                      <td>
                        {Number(l.documentos_recusados) ? <Selo tom="vermelho" icone={<AlertTriangle />}>{l.documentos_recusados} para reenviar</Selo> :
                          Number(l.documentos_pendentes) ? <Selo tom="laranja">{l.documentos_pendentes} para conferir</Selo> : <Selo tom="verde">Conferidos</Selo>}
                      </td>
                      <td className="fraco">{aba === 'em_analise' ? <div><SeloPrazo enviado={l.enviado_em ?? l.atualizado_em} />
                        <div className="texto-fraco" style={{ marginTop: 4 }}>Enviado {haQuanto(l.enviado_em ?? l.atualizado_em)}</div></div> : haQuanto(l.atualizado_em)}</td>
                      <td><SeloStatus mapa={statusCadastro} valor={l.status} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </section>);
        return aba === 'rascunho' || aba === 'recusado' ? <Incompletos status={aba} busca={busca} alternativa={tabela} /> : tabela; })()}
    </>
  );
}
