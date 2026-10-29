const fuso = 'America/Sao_Paulo';

export function dataHora(v?: string | null): string {
  if (!v) return '—';
  return new Date(v).toLocaleString('pt-BR', { timeZone: fuso, day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' });
}

export function data(v?: string | null): string {
  if (!v) return '—';
  const d = /^\d{4}-\d{2}-\d{2}$/.test(v) ? new Date(v + 'T12:00:00') : new Date(v);
  return d.toLocaleDateString('pt-BR', { timeZone: fuso });
}

export function diaCurto(v: string): string {
  return new Date(v + 'T12:00:00').toLocaleDateString('pt-BR', { timeZone: fuso, weekday: 'short', day: '2-digit' }).replace('.', '');
}

/** "há 5 min", "há 2 h", "há 3 dias" */
export function haQuanto(v?: string | null): string {
  if (!v) return '—';
  const s = Math.max(0, (Date.now() - new Date(v).getTime()) / 1000);
  if (s < 60) return 'agora';
  if (s < 3600) return `há ${Math.floor(s / 60)} min`;
  if (s < 86400) return `há ${Math.floor(s / 3600)} h`;
  const d = Math.floor(s / 86400);
  return `há ${d} ${d === 1 ? 'dia' : 'dias'}`;
}

export function moeda(v?: number | string | null): string {
  if (v === null || v === undefined || v === '') return '—';
  return Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
}

export function numero(v?: number | null): string {
  return (v ?? 0).toLocaleString('pt-BR');
}

export function cpf(v?: string | null): string {
  if (!v) return '—';
  return v.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, '$1.$2.$3-$4');
}

export function telefone(v?: string | null): string {
  if (!v) return '—';
  const d = v.replace(/\D/g, '').replace(/^55(?=\d{10,11}$)/, '');
  if (d.length === 11) return d.replace(/^(\d{2})(\d{5})(\d{4})$/, '($1) $2-$3');
  if (d.length === 10) return d.replace(/^(\d{2})(\d{4})(\d{4})$/, '($1) $2-$3');
  return v;
}

export function whatsapp(v?: string | null): string | null {
  if (!v) return null;
  const d = v.replace(/\D/g, '');
  return `https://wa.me/${d.length <= 11 ? '55' + d : d}`;
}

export function idade(nascimento?: string | null): string {
  if (!nascimento) return '—';
  const n = new Date(nascimento + 'T12:00:00');
  const h = new Date();
  let a = h.getFullYear() - n.getFullYear();
  if (h.getMonth() < n.getMonth() || (h.getMonth() === n.getMonth() && h.getDate() < n.getDate())) a--;
  return `${a} anos`;
}

export function iniciais(nome?: string | null): string {
  const p = (nome || '?').trim().split(/\s+/);
  return ((p[0]?.[0] ?? '') + (p.length > 1 ? p[p.length - 1][0] : '')).toUpperCase();
}

export function hojeISO(): string {
  return new Date().toLocaleDateString('en-CA', { timeZone: fuso });
}

export function diasAtrasISO(n: number): string {
  const d = new Date(Date.now() - n * 86400000);
  return d.toLocaleDateString('en-CA', { timeZone: fuso });
}

export type Tom = 'neutro' | 'azul' | 'verde' | 'laranja' | 'vermelho' | 'roxo';

export const statusCadastro: Record<string, { rotulo: string; tom: Tom }> = {
  rascunho: { rotulo: 'Rascunho', tom: 'neutro' },
  em_analise: { rotulo: 'Em análise', tom: 'laranja' },
  aprovado: { rotulo: 'Aprovado', tom: 'verde' },
  recusado: { rotulo: 'Ajustes pedidos', tom: 'vermelho' },
  suspenso: { rotulo: 'Suspenso', tom: 'vermelho' },
};

export const statusPedido: Record<string, { rotulo: string; tom: Tom }> = {
  solicitado: { rotulo: 'Aguardando resposta', tom: 'laranja' },
  aceito: { rotulo: 'Aceito', tom: 'azul' },
  a_caminho: { rotulo: 'A caminho', tom: 'azul' },
  em_atendimento: { rotulo: 'Em atendimento', tom: 'azul' },
  concluido: { rotulo: 'Concluído', tom: 'verde' },
  recusado: { rotulo: 'Recusado', tom: 'neutro' },
  expirado: { rotulo: 'Expirado', tom: 'neutro' },
  cancelado: { rotulo: 'Cancelado', tom: 'vermelho' },
};

export const statusDocumento: Record<string, { rotulo: string; tom: Tom }> = {
  pendente: { rotulo: 'Pendente', tom: 'laranja' },
  aprovado: { rotulo: 'Aprovado', tom: 'verde' },
  recusado: { rotulo: 'Nova foto pedida', tom: 'vermelho' },
};

export const statusReclamacao: Record<string, { rotulo: string; tom: Tom }> = {
  aberta: { rotulo: 'Aberta', tom: 'laranja' },
  em_mediacao: { rotulo: 'Em mediação', tom: 'azul' },
  resolvida: { rotulo: 'Resolvida', tom: 'verde' },
  encerrada: { rotulo: 'Encerrada', tom: 'neutro' },
};

export const statusDenuncia: Record<string, { rotulo: string; tom: Tom }> = {
  aberta: { rotulo: 'Aberta', tom: 'laranja' },
  em_analise: { rotulo: 'Em análise', tom: 'azul' },
  procedente: { rotulo: 'Procedente', tom: 'vermelho' },
  improcedente: { rotulo: 'Improcedente', tom: 'neutro' },
};

export const tipoDocumento: Record<string, string> = {
  documento_frente: 'Documento (frente)',
  documento_verso: 'Documento (verso)',
  selfie_documento: 'Selfie com o documento',
  antecedentes: 'Certidão de antecedentes',
  comprovante_endereco: 'Comprovante de endereço',
};

export const quandoPedido: Record<string, string> = { agora: 'Agora', hoje: 'Hoje', combinado: 'Horário combinado' };

export const pendencia: Record<string, string> = {
  foto: 'Foto de perfil',
  nome: 'Nome',
  nascimento: 'Data de nascimento',
  cpf: 'CPF',
  telefone: 'Telefone',
  endereco: 'Endereço',
  area_atendimento: 'Área de atendimento',
  profissao: 'Profissão',
  especialidades_e_precos: 'Especialidades e preços',
  documento: 'Foto do documento',
  selfie: 'Selfie com o documento',
  antecedentes: 'Certidão de antecedentes',
};

export const nomesAcao: Record<string, string> = {
  aprovar_cadastro: 'Aprovou o cadastro',
  recusar_cadastro: 'Pediu ajustes no cadastro',
  aprovar_documento: 'Aprovou um documento',
  recusar_documento: 'Pediu nova foto',
  aprovar_certificacao: 'Aprovou uma certificação',
  recusar_certificacao: 'Recusou uma certificação',
  suspender: 'Suspendeu a conta',
  reativar: 'Reativou a conta',
  mediar_reclamacao: 'Atualizou uma reclamação',
  atender_emergencia: 'Atendeu uma emergência',
  resolver_denuncia: 'Tratou uma denúncia',
  ocultar_avaliacao: 'Ocultou uma avaliação',
  mostrar_avaliacao: 'Voltou a mostrar uma avaliação',
  enviar_comunicado: 'Enviou um comunicado',
  ajustar_preco: 'Ajustou um preço de referência',
  insert_profissoes: 'Criou uma profissão',
  update_profissoes: 'Alterou uma profissão',
  insert_especialidades: 'Criou uma especialidade',
  update_especialidades: 'Alterou uma especialidade',
  insert_regioes: 'Criou uma região',
  update_regioes: 'Alterou uma região',
  insert_app_config: 'Criou uma configuração',
  update_app_config: 'Alterou uma configuração',
};
