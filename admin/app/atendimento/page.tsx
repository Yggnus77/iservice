'use client';

import { useEffect, useState } from 'react';
import { Clock, Headset, Save, Siren } from 'lucide-react';
import { Cabecalho, usePainel } from '@/components/Painel';
import { Carregando, ErroCaixa, Interruptor, Selo, useAcao, useCarregar } from '@/components/ui';
import { GRAVIDADES } from '@/components/Prazo';
import { rpc } from '@/lib/supabase';

type Horario = { dias: number[]; inicio: string; fim: string };
type Plantonista = { email: string; nome: string; papel: string; plantao: boolean; ativo: boolean };
type Atendimento = { horario: Horario; agora_aberto: boolean; pode_editar: boolean; pode_plantao: boolean; plantao: Plantonista[] };
type Canal = { canal: string; total: number; sem_resposta: number; no_prazo_pct: number | null; mediana_minutos: number | null };
type Indicadores = {
  dias: number; total: number; sem_resposta: number; no_prazo_pct: number | null; mediana_minutos: number | null;
  canais: Canal[]; gravidades: { gravidade: number; total: number; no_prazo_pct: number | null }[];
};

const DIAS = ['', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
const DIAS_LONGOS = ['', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];
const CANAIS: Record<string, string> = { emergencia: 'Emergências', denuncia: 'Denúncias', garantia: 'Garantia', email: 'E-mails' };
const CARGOS: Record<string, string> = { dono: 'Dono', gerente: 'Gerente', responsavel: 'Responsável de setor', suporte: 'Suporte' };

const hora = (h: string) => (h.endsWith(':00') ? `${Number(h.slice(0, 2))}h` : h.replace(':', 'h'));
function textoHorario(h: Horario) {
  const d = [...h.dias].sort((a, b) => a - b);
  const seguidos = d.length > 1 && d.every((x, i) => i === 0 || x === d[i - 1] + 1);
  const quando = d.length === 7 ? 'Todos os dias' : seguidos ? `De ${DIAS_LONGOS[d[0]]} a ${DIAS_LONGOS[d[d.length - 1]]}` : d.map((x) => DIAS_LONGOS[x]).join(', ');
  return `${quando}, das ${hora(h.inicio)} às ${hora(h.fim)}`;
}

function tempo(min: number | null) {
  if (min == null) return '—';
  if (min < 60) return `${min} min`;
  const h = min / 60;
  return h < 48 ? `${h.toFixed(h < 10 ? 1 : 0).replace('.', ',')} h` : `${Math.round(h / 24)} dias`;
}

function HorarioCartao({ a, salvo }: { a: Atendimento; salvo: () => void }) {
  const [dias, setDias] = useState<number[]>(a.horario.dias);
  const [inicio, setInicio] = useState(a.horario.inicio);
  const [fim, setFim] = useState(a.horario.fim);
  const { executar, ocupado } = useAcao();
  useEffect(() => { setDias(a.horario.dias); setInicio(a.horario.inicio); setFim(a.horario.fim); }, [a.horario]);
  const mudou = dias.join() !== a.horario.dias.join() || inicio !== a.horario.inicio || fim !== a.horario.fim;

  return (
    <section className="cartao">
      <div className="titulo">
        <div><h2>Horário de atendimento</h2><p>{textoHorario(a.horario)} (Brasília). Emergências: plantão 24 horas.</p></div>
        {a.agora_aberto ? <Selo tom="verde" icone={<Clock />}>Aberto agora</Selo> : <Selo tom="neutro" icone={<Clock />}>Fora do horário</Selo>}
      </div>
      <div className="corpo" style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div className="campo">
          <span className="rotulo">Dias</span>
          <div className="linha-flex" style={{ gap: 6 }}>
            {[1, 2, 3, 4, 5, 6, 7].map((d) => (
              <button key={d} type="button" disabled={!a.pode_editar} aria-pressed={dias.includes(d)}
                className={`botao pequeno ${dias.includes(d) ? 'primario' : 'contorno'}`}
                onClick={() => setDias((l) => (l.includes(d) ? l.filter((x) => x !== d) : [...l, d].sort((x, y) => x - y)))}>{DIAS[d]}</button>
            ))}
          </div>
        </div>
        <div className="grade g2">
          <div className="campo"><label htmlFor="h-ini">Abre às</label><input id="h-ini" className="entrada" type="time" step={900} disabled={!a.pode_editar} value={inicio} onChange={(e) => setInicio(e.target.value)} /></div>
          <div className="campo"><label htmlFor="h-fim">Fecha às</label><input id="h-fim" className="entrada" type="time" step={900} disabled={!a.pode_editar} value={fim} onChange={(e) => setFim(e.target.value)} /></div>
        </div>
        <p className="texto-suave" style={{ margin: 0 }}>
          Fora desse horário, quem manda e-mail recebe uma resposta automática dizendo quando voltamos. O app e o site mostram este horário na Central de Ajuda.
          Os prazos de resposta só contam dentro do horário, menos as emergências.
        </p>
        {a.pode_editar ? (
          <div className="linha-flex">
            <span className="espaco" />
            <button className="botao primario" disabled={!mudou || ocupado || !dias.length}
              onClick={async () => { if (await executar(() => rpc('admin_salvar_horario', { p_dias: dias, p_inicio: inicio, p_fim: fim }), 'Horário salvo.')) salvo(); }}>
              <Save /> Salvar horário
            </button>
          </div>
        ) : <span className="texto-fraco">Só quem tem acesso às Configurações muda o horário.</span>}
      </div>
    </section>
  );
}

function PlantaoCartao({ a, salvo }: { a: Atendimento; salvo: () => void }) {
  const { executar, ocupado } = useAcao();
  const algum = a.plantao.some((p) => p.plantao && p.ativo);
  return (
    <section className="cartao">
      <div className="titulo">
        <div><h2>Plantão de emergência</h2><p>Quando alguém aperta o botão de emergência, o dono e quem está de plantão recebem notificação no celular e e-mail na hora.</p></div>
        <Siren size={20} />
      </div>
      <div className="corpo sem-espaco">
        {!algum ? <div className="alerta-faixa laranja" style={{ margin: 16 }}><div><strong>Ninguém de plantão</strong>Enquanto isso, todos que atendem emergências recebem o alerta.</div></div> : null}
        <table className="tabela">
          <thead><tr><th>Pessoa</th><th>Cargo</th><th>De plantão</th></tr></thead>
          <tbody>
            {a.plantao.map((p) => (
              <tr key={p.email}>
                <td><strong>{p.nome}</strong><div className="fraco">{p.email}{p.ativo ? '' : ' · ainda não entrou'}</div></td>
                <td>{CARGOS[p.papel] ?? p.papel}{p.papel === 'dono' ? <div className="fraco">recebe sempre</div> : null}</td>
                <td>
                  <Interruptor ligado={p.plantao} desativado={!a.pode_plantao || ocupado} rotulo={`Plantão de ${p.nome}`}
                    mudar={async (v) => { if (await executar(() => rpc('admin_definir_plantao', { p_email: p.email, p_plantao: v }), v ? `${p.nome} está de plantão.` : `${p.nome} saiu do plantão.`)) salvo(); }} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

function Regras() {
  return (
    <section className="cartao">
      <div className="titulo"><div><h2>Gravidade e prazos</h2><p>Cada atendimento ganha uma gravidade sugerida pelo texto. Corrija na própria conversa quando precisar.</p></div></div>
      <div className="corpo sem-espaco">
        <table className="tabela">
          <thead><tr><th>Gravidade</th><th>Exemplos</th><th>Primeira resposta</th><th>Quem decide</th></tr></thead>
          <tbody>
            <tr><td><Selo tom={GRAVIDADES[1].tom}>1. Crítica</Selo></td><td>Emergência, violência, assédio, furto, acidente, criança ou idoso em risco</td><td>{GRAVIDADES[1].prazo}</td><td>Plantonista e dono</td></tr>
            <tr><td><Selo tom={GRAVIDADES[2].tom}>2. Alta</Selo></td><td>Não apareceu, dano no imóvel, briga, pagamento por fora, cobrança indevida</td><td>{GRAVIDADES[2].prazo}</td><td>Gerente</td></tr>
            <tr><td><Selo tom={GRAVIDADES[3].tom}>3. Média</Selo></td><td>Garantia, serviço mal feito, cadastro e documentos, avaliação</td><td>{GRAVIDADES[3].prazo}</td><td>Responsável de setor</td></tr>
            <tr><td><Selo tom={GRAVIDADES[4].tom}>4. Baixa</Selo></td><td>Dúvidas, sugestões, troca de dados</td><td>{GRAVIDADES[4].prazo}</td><td>Suporte</td></tr>
          </tbody>
        </table>
        <div style={{ padding: 16 }}>
          <strong>Gravidade 1, passo a passo</strong>
          <ol style={{ margin: '8px 0 0', paddingLeft: 20, display: 'flex', flexDirection: 'column', gap: 4 }}>
            <li>Ligue para quem acionou em até 15 minutos. Com risco à vida ou crime acontecendo, oriente a ligar 190 (ou 192) e fique na linha.</li>
            <li>Suspenda a outra parte na ficha da pessoa, como medida preventiva, até apurar.</li>
            <li>Guarde as provas: pedido, conversa, local e horários. Nada é apagado enquanto a apuração estiver aberta.</li>
            <li>Avise o dono por telefone.</li>
            <li>Em até 48 horas, decida: reativar, advertir ou banir, e registre o motivo.</li>
            <li>Polícia ou Justiça: dados de cadastro só para autoridade com poder legal de pedir; conversas e registros de acesso só com ordem judicial. Registre todo pedido.</li>
          </ol>
        </div>
      </div>
    </section>
  );
}

function IndicadoresCartao() {
  const [dias, setDias] = useState(30);
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Indicadores>('admin_indicadores_suporte', { p_dias: dias }), [dias]);
  return (
    <section className="cartao">
      <div className="titulo">
        <div><h2>Como estamos respondendo</h2><p>Tempo até a primeira resposta e quanto ficou dentro do prazo.</p></div>
        <select className="entrada" style={{ width: 'auto' }} value={dias} onChange={(e) => setDias(Number(e.target.value))} aria-label="Período">
          <option value={7}>7 dias</option><option value={30}>30 dias</option><option value={90}>90 dias</option>
        </select>
      </div>
      <div className="corpo sem-espaco">
        {erro ? <div style={{ padding: 16 }}><ErroCaixa erro={erro} tentar={recarregar} /></div> : carregando && !dados ? <Carregando /> : !dados?.total ? (
          <p className="texto-suave" style={{ padding: 16, margin: 0 }}>Nenhum atendimento no período.</p>
        ) : (
          <table className="tabela">
            <thead><tr><th>Canal</th><th className="num">Atendimentos</th><th className="num">Sem resposta</th><th className="num">Tempo típico</th><th className="num">No prazo</th></tr></thead>
            <tbody>
              {dados.canais.map((c) => (
                <tr key={c.canal}>
                  <td>{CANAIS[c.canal] ?? c.canal}</td>
                  <td className="num">{c.total}</td>
                  <td className="num">{c.sem_resposta}</td>
                  <td className="num">{tempo(c.mediana_minutos)}</td>
                  <td className="num"><Selo tom={c.no_prazo_pct == null ? 'neutro' : c.no_prazo_pct >= 90 ? 'verde' : c.no_prazo_pct >= 70 ? 'laranja' : 'vermelho'}>{c.no_prazo_pct ?? '—'}%</Selo></td>
                </tr>
              ))}
              <tr>
                <td><strong>Total</strong></td><td className="num"><strong>{dados.total}</strong></td><td className="num"><strong>{dados.sem_resposta}</strong></td>
                <td className="num"><strong>{tempo(dados.mediana_minutos)}</strong></td><td className="num"><strong>{dados.no_prazo_pct ?? '—'}%</strong></td>
              </tr>
            </tbody>
          </table>
        )}
      </div>
    </section>
  );
}

export default function PaginaAtendimento() {
  const { pode } = usePainel();
  const { dados, erro, carregando, recarregar } = useCarregar(() => rpc<Atendimento>('admin_atendimento'), []);
  return (
    <>
      <Cabecalho titulo="Horário, plantão e prazos" texto="Quando o suporte atende, quem recebe os alertas de emergência e em quanto tempo cada caso precisa de resposta."
        ajuda={<>A meta é responder dentro do prazo em pelo menos 90% dos atendimentos. Os selos de prazo aparecem nos E-mails, na Garantia e nas Denúncias, e as filas mostram primeiro o que vence antes.</>} />
      {erro ? <ErroCaixa erro={erro} tentar={recarregar} /> : carregando && !dados ? <Carregando /> : dados ? (
        <div className="pilha">
          <div className="grade g2">
            <HorarioCartao a={dados} salvo={recarregar} />
            <PlantaoCartao a={dados} salvo={recarregar} />
          </div>
          {pode('relatorios') ? <IndicadoresCartao /> : null}
          <Regras />
        </div>
      ) : <section className="cartao"><div className="corpo"><Headset /> Sem dados.</div></section>}
    </>
  );
}
