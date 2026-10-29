'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { AlertTriangle, BadgeCheck, Search, ShieldAlert } from 'lucide-react';
import { Cabecalho, usePainel } from '@/components/Painel';
import { Abas, Carregando, ErroCaixa, Pessoa, Selo, SeloStatus, Vazio, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { haQuanto, statusCadastro, telefone } from '@/lib/formatos';

type Linha = {
  id: string; nome: string; email: string; telefone: string; foto_url: string; status: string; motivo_status: string | null;
  profissoes: string[]; exige_antecedentes: boolean; regiao: string | null; documentos_pendentes: number; documentos_recusados: number;
  criado_em: string; atualizado_em: string; suspenso: boolean;
};

type Aba = 'em_analise' | 'recusado' | 'rascunho' | 'aprovado' | 'suspenso';

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
      <Cabecalho titulo="Cadastros de profissionais" texto="Confira documento, selfie e antecedentes antes de liberar alguém para atender." />
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
      <section className="cartao">
        <div className="corpo sem-espaco">
          {erro ? <div style={{ padding: 16 }}><ErroCaixa erro={erro} tentar={recarregar} /></div> : carregando && !dados ? <Carregando /> : !dados?.length ? (
            <Vazio icone={<BadgeCheck size={24} />} titulo={aba === 'em_analise' ? 'Nenhum cadastro esperando' : 'Nada por aqui'}
              texto={aba === 'em_analise' ? 'Quando um profissional enviar o cadastro, ele aparece aqui.' : undefined} />
          ) : (
            <div className="tabela-rolagem">
              <table className="tabela">
                <thead>
                  <tr><th>Profissional</th><th>Profissões</th><th>Região</th><th>Documentos</th><th>{aba === 'em_analise' ? 'Na fila' : 'Atualizado'}</th><th>Situação</th></tr>
                </thead>
                <tbody>
                  {dados.map((l) => (
                    <tr key={l.id} className="clicavel" onClick={() => router.push(`/cadastro/?id=${l.id}`)}>
                      <td><Pessoa nome={l.nome} foto={l.foto_url} sub={l.email || telefone(l.telefone)} /></td>
                      <td>
                        <div className="linha-flex" style={{ gap: 6 }}>
                          {l.profissoes.length ? l.profissoes.map((p) => <Selo key={p}>{p}</Selo>) : <span className="fraco">—</span>}
                          {l.exige_antecedentes ? <Selo tom="roxo" icone={<ShieldAlert />}>Antecedentes</Selo> : null}
                        </div>
                      </td>
                      <td>{l.regiao ?? <span className="fraco">—</span>}</td>
                      <td>
                        {Number(l.documentos_recusados) ? <Selo tom="vermelho" icone={<AlertTriangle />}>{l.documentos_recusados} para reenviar</Selo> :
                          Number(l.documentos_pendentes) ? <Selo tom="laranja">{l.documentos_pendentes} para conferir</Selo> : <Selo tom="verde">Conferidos</Selo>}
                      </td>
                      <td className="fraco">{haQuanto(l.atualizado_em)}</td>
                      <td><SeloStatus mapa={statusCadastro} valor={l.status} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </section>
    </>
  );
}
