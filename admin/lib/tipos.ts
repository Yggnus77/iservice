export type Documento = {
  id: number; tipo: string; arquivo_path: string; status: string; observacao: string | null; criado_em: string; revisado_em: string | null;
};

export type Certificacao = {
  id: number; nome: string; instituicao: string | null; profissao_id: string | null; arquivo_path: string | null; status: string; criado_em: string;
};

export type FichaProfissional = {
  status: string; motivo_status: string | null; verificado: boolean; disponivel: boolean; bio: string | null; anos_experiencia: number | null;
  area_raio_km: number; area_lat: number | null; area_lng: number | null; regiao: string | null; plano: string;
  nota_media: number; total_avaliacoes: number; servicos_concluidos: number; pedidos_recebidos: number; pedidos_aceitos: number;
  pedidos_perdidos: number; cancelados_pelo_profissional: number; aprovado_em: string | null; criado_em: string; atualizado_em: string;
  pendencias: string[];
  profissoes: { id: string; nome: string; principal: boolean; exige_antecedentes: boolean; especialidades: { id: number; nome: string; preco: number | null; aprovada: boolean }[] }[];
  documentos: Documento[];
  certificacoes: Certificacao[];
  portfolio: { id: number; descricao: string | null; antes_path: string | null; depois_path: string }[];
};

export type Ficha = {
  perfil: {
    id: string; nome: string; email: string | null; telefone: string | null; cpf: string | null; nascimento: string | null; foto_url: string | null;
    telefone_verificado: boolean; e_cliente: boolean; e_profissional: boolean; e_admin: boolean; criado_em: string;
    suspenso_em: string | null; motivo_suspensao: string | null; exclusao_solicitada_em: string | null; codigo_indicacao: string | null;
  };
  enderecos: { id: number; rotulo: string; logradouro: string; bloco: string | null; numero: string | null; complemento: string | null; cidade: string; uf: string; cep: string | null; regiao: string | null; principal: boolean }[];
  profissional: FichaProfissional | null;
  pedidos: { id: string; codigo: string; status: string; criado_em: string; profissao: string; papel: string; outra_parte: string; valor: number | null }[];
  denuncias_recebidas: { id: number; motivo: string; status: string; criada_em: string }[];
  reclamacoes: { id: number; motivo: string; status: string; criada_em: string }[];
  acoes: { acao: string; dados: Record<string, unknown>; criada_em: string; admin: string | null }[];
};

export function enderecoTexto(e: Ficha['enderecos'][number]): string {
  return [e.logradouro, e.bloco && `Bloco ${e.bloco}`, e.numero, e.complemento, e.regiao || e.cidade, e.uf].filter(Boolean).join(', ');
}
