'use client';

import type { ReactNode } from 'react';
import { BriefcaseBusiness, Crown, Headset, Megaphone, ShieldUser, UserPlus } from 'lucide-react';
import type { Cargo, Permissao } from './Painel';
import { Interruptor, Selo } from './ui';
import type { Tom } from '@/lib/formatos';

/** Uma permissão, como vem do banco (permissoes_catalogo). */
export type ItemPermissao = { chave: Permissao; grupo: string; nome: string; descricao: string; ordem: number };

/** Os cargos, na ordem em que aparecem. O que cada um acessa vem do banco (tela Cargos). */
export const cargos: { id: Cargo; nome: string; tom: Tom; icone: ReactNode; resumo: string }[] = [
  { id: 'dono', nome: 'Dono', tom: 'azul', icone: <Crown />, resumo: 'Tudo, sempre. Só ele passa a posição de dono, e ninguém mais mexe no acesso dele.' },
  { id: 'gerente', nome: 'Gerente geral', tom: 'roxo', icone: <BriefcaseBusiness />,
    resumo: 'O mesmo acesso do dono, inclusive Configurações, Cargos e Permissões. Gere toda a equipe, menos o dono.' },
  { id: 'responsavel', nome: 'Responsável de setor', tom: 'verde', icone: <ShieldUser />,
    resumo: 'Toda a Operação: e-mails de todos, aprova cadastros, decide a Garantia, resolve denúncias e suspende contas. Vê o próprio time na Equipe.' },
  { id: 'suporte', nome: 'Suporte', tom: 'laranja', icone: <Headset />,
    resumo: 'Atende os próprios e-mails e as emergências, consulta pedidos e pessoas e registra reclamações. CPF e documentos aparecem mascarados.' },
  { id: 'marketing', nome: 'Marketing', tom: 'neutro', icone: <Megaphone />,
    resumo: 'Buscas e mapa, Site e downloads, Avaliações, Comunicados e Captação. Não vê dados pessoais.' },
  { id: 'captacao', nome: 'Captação', tom: 'neutro', icone: <UserPlus />,
    resumo: 'Só a página Captação: funil de cadastros, metas por profissão e quem indicou. Não vê dados pessoais nem manda comunicados.' },
];
export const cargoDe = (id: Cargo) => cargos.find((c) => c.id === id) ?? cargos[3];

export function SeloCargo({ papel }: { papel: Cargo }) {
  const c = cargoDe(papel);
  return <Selo tom={c.tom} icone={c.icone}>{c.nome}</Selo>;
}

/**
 * Chaves de liga e desliga, agrupadas (Operação, Crescimento, Catálogo, Equipe).
 * `marca` mostra uma etiqueta ao lado (por exemplo, "além do cargo").
 * `travada` desliga a chave com um motivo (Início sempre ligado, acesso que você não tem).
 */
export function ListaPermissoes({ catalogo, ligadas, mudar, travada, marca }: {
  catalogo: ItemPermissao[];
  ligadas: Set<string>;
  mudar: (chave: Permissao, ligada: boolean) => void;
  travada?: (p: ItemPermissao) => string | null;
  marca?: (p: ItemPermissao) => ReactNode;
}) {
  const grupos = Array.from(new Set(catalogo.map((p) => p.grupo)));
  return (
    <div className="lista-permissoes">
      {grupos.map((g) => (
        <fieldset key={g}>
          <legend>{g}</legend>
          {catalogo.filter((p) => p.grupo === g).map((p) => {
            const motivo = travada?.(p) ?? null;
            return (
              <div key={p.chave} className={`permissao ${ligadas.has(p.chave) ? 'ligada' : ''}`}>
                <div>
                  <strong>{p.nome}</strong>{marca?.(p)}
                  <small>{motivo ?? p.descricao}</small>
                </div>
                <Interruptor ligado={ligadas.has(p.chave)} desativado={!!motivo} mudar={(v) => mudar(p.chave, v)}
                  rotulo={`${p.nome}: ${ligadas.has(p.chave) ? 'ligado' : 'desligado'}`} />
              </div>
            );
          })}
        </fieldset>
      ))}
    </div>
  );
}
