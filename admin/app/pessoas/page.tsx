'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { Search, Users } from 'lucide-react';
import { Cabecalho } from '@/components/Painel';
import { Abas, Carregando, ErroCaixa, Pessoa, Selo, SeloStatus, Vazio, useCarregar } from '@/components/ui';
import { rpc } from '@/lib/supabase';
import { data, numero, statusCadastro, telefone } from '@/lib/formatos';

type Linha = {
  id: string; nome: string; email: string | null; telefone: string | null; foto_url: string | null; e_cliente: boolean; e_profissional: boolean;
  e_admin: boolean; status_profissional: string | null; suspenso: boolean; exclusao_pendente: boolean; pedidos: number; criado_em: string; total: number;
};
type Filtro = 'todos' | 'clientes' | 'profissionais' | 'suspensos' | 'admins';
const POR_PAGINA = 50;

export default function Pessoas() {
  const router = useRouter();
  const [filtro, setFiltro] = useState<Filtro>('todos');
  const [texto, setTexto] = useState('');
  const [busca, setBusca] = useState('');
  const [pagina, setPagina] = useState(0);
  useEffect(() => { const t = setTimeout(() => { setBusca(texto); setPagina(0); }, 300); return () => clearTimeout(t); }, [texto]);
  const { dados, erro, carregando, recarregar } = useCarregar(
    () => rpc<Linha[]>('admin_usuarios', { p_texto: busca || null, p_filtro: filtro, p_limite: POR_PAGINA, p_pular: pagina * POR_PAGINA }),
    [busca, filtro, pagina]);
  const total = dados?.[0]?.total ?? 0;

  return (
    <>
      <Cabecalho titulo="Pessoas" texto="Clientes e profissionais. Abra a ficha para ver pedidos, denúncias ou suspender uma conta." />
      <div className="filtros">
        <Abas<Filtro> ativa={filtro} mudar={(f) => { setFiltro(f); setPagina(0); }} abas={[
          { id: 'todos', rotulo: 'Todos' }, { id: 'clientes', rotulo: 'Só clientes' }, { id: 'profissionais', rotulo: 'Profissionais' },
          { id: 'suspensos', rotulo: 'Suspensos' }, { id: 'admins', rotulo: 'Equipe' },
        ]} />
        <span className="espaco" />
        <div className="busca"><Search /><input className="entrada" placeholder="Nome, e-mail, CPF ou telefone" value={texto} onChange={(e) => setTexto(e.target.value)} aria-label="Buscar pessoa" /></div>
      </div>
      <section className="cartao">
        <div className="corpo sem-espaco">
          {erro ? <div style={{ padding: 16 }}><ErroCaixa erro={erro} tentar={recarregar} /></div> : carregando && !dados ? <Carregando /> : !dados?.length ? (
            <Vazio icone={<Users size={24} />} titulo="Ninguém encontrado" texto={busca ? 'Tente outro nome, e-mail ou CPF.' : undefined} />
          ) : (
            <div className="tabela-rolagem">
              <table className="tabela">
                <thead><tr><th>Pessoa</th><th>Telefone</th><th>Tipo</th><th className="num">Pedidos</th><th>Desde</th><th>Situação</th></tr></thead>
                <tbody>
                  {dados.map((l) => (
                    <tr key={l.id} className="clicavel" onClick={() => router.push(`/pessoa/?id=${l.id}`)}>
                      <td><Pessoa nome={l.nome} foto={l.foto_url} sub={l.email} /></td>
                      <td>{telefone(l.telefone)}</td>
                      <td>
                        <div className="linha-flex" style={{ gap: 6 }}>
                          {l.e_profissional ? <SeloStatus mapa={statusCadastro} valor={l.status_profissional} /> : <Selo tom="azul">Cliente</Selo>}
                          {l.e_admin ? <Selo tom="roxo">Equipe</Selo> : null}
                        </div>
                      </td>
                      <td className="num">{numero(l.pedidos)}</td>
                      <td className="fraco">{data(l.criado_em)}</td>
                      <td>{l.suspenso ? <Selo tom="vermelho">Suspensa</Selo> : l.exclusao_pendente ? <Selo tom="laranja">Excluindo conta</Selo> : <Selo tom="verde">Ativa</Selo>}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </section>
      {total > POR_PAGINA ? (
        <div className="linha-flex" style={{ marginTop: 14, justifyContent: 'flex-end' }}>
          <span className="texto-fraco">{pagina * POR_PAGINA + 1}–{Math.min(total, (pagina + 1) * POR_PAGINA)} de {numero(total)}</span>
          <button className="botao contorno pequeno" disabled={pagina === 0} onClick={() => setPagina(pagina - 1)}>Anterior</button>
          <button className="botao contorno pequeno" disabled={(pagina + 1) * POR_PAGINA >= total} onClick={() => setPagina(pagina + 1)}>Próxima</button>
        </div>
      ) : null}
    </>
  );
}
