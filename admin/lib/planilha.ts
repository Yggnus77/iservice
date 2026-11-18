// Planilha para abrir no Excel: CSV com ponto e vírgula e acentos (BOM UTF-8),
// do jeito que o Excel em português abre com dois cliques, já separado em colunas.

export type Celula = string | number | boolean | null | undefined;

function celula(v: Celula): string {
  if (v === null || v === undefined) return '';
  if (typeof v === 'boolean') return v ? 'Sim' : 'Não';
  if (typeof v === 'number') return Number.isFinite(v) ? String(v).replace('.', ',') : '';
  const t = String(v);
  // Evita que o Excel trate um texto como fórmula (=, +, -, @).
  const seguro = /^[=+\-@]/.test(t) ? `'${t}` : t;
  return /[";\n\r]/.test(seguro) ? `"${seguro.replace(/"/g, '""')}"` : seguro;
}

export function baixarPlanilha(nome: string, linhas: Celula[][]) {
  const texto = '﻿' + linhas.map((l) => l.map(celula).join(';')).join('\r\n');
  const blob = new Blob([texto], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = nome.endsWith('.csv') ? nome : `${nome}.csv`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/** Data e hora de Brasília em texto (para a planilha). */
export function dataHoraPlanilha(v?: string | null): string {
  if (!v) return '';
  return new Date(v).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}

export function dataPlanilha(v?: string | null): string {
  if (!v) return '';
  return new Date(/^\d{4}-\d{2}-\d{2}$/.test(v) ? v + 'T12:00:00' : v).toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo' });
}
