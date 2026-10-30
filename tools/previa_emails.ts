// Gera a prévia de todos os e-mails e os modelos do Supabase Auth.
//   node --experimental-strip-types tools/previa_emails.ts [pasta-da-previa]
// Escreve supabase/templates/*.html (para colar em Authentication > Emails)
// e, na pasta indicada (padrão: build/previa-emails), um arquivo por e-mail.
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { type App, gerar, MODELOS_AUTH, montar } from "../supabase/functions/enviar-email/modelos.ts";

const pasta = process.argv[2] ?? "build/previa-emails";
mkdirSync(pasta, { recursive: true });
mkdirSync("supabase/templates", { recursive: true });

const exemplos: { tipo: string; app: App; nome: string; titulo?: string; corpo?: string; dados?: Record<string, unknown>; rotulo: string }[] = [
  { rotulo: "Boas-vindas (cliente)", tipo: "boas_vindas", app: "cliente", nome: "Mariana Souza" },
  { rotulo: "Boas-vindas (profissional)", tipo: "boas_vindas", app: "profissional", nome: "Carlos Pereira" },
  { rotulo: "Cadastro recebido", tipo: "cadastro_recebido", app: "profissional", nome: "Carlos Pereira",
    dados: { profissoes: "Eletricista, Técnico de ar-condicionado", enviado_em: "2026-10-30T15:00:00Z" } },
  { rotulo: "Cadastro aprovado", tipo: "cadastro_aprovado", app: "profissional", nome: "Carlos Pereira" },
  { rotulo: "Cadastro precisa de ajuste", tipo: "cadastro_recusado", app: "profissional", nome: "Carlos Pereira",
    corpo: "A certificação NR-10 enviada está vencida. Envie o certificado atualizado." },
  { rotulo: "Documento recusado", tipo: "documento_recusado", app: "profissional", nome: "Carlos Pereira",
    corpo: "Precisamos que você envie de novo a selfie com o documento. A foto ficou escura e o rosto não aparece por inteiro." },
  { rotulo: "Reclamação recebida (profissional)", tipo: "reclamacao_recebida", app: "profissional", nome: "Carlos Pereira",
    dados: { codigo: "7F3A2C", servico: "Eletricista", data_pedido: "2026-10-28T13:20:00Z", motivo: "Serviço não resolveu o problema", autor_nome: "Mariana" } },
  { rotulo: "Reclamação aberta (quem reclamou)", tipo: "reclamacao_aberta", app: "cliente", nome: "Mariana Souza",
    dados: { protocolo: "G-00012", codigo: "7F3A2C", servico: "Eletricista", motivo: "Serviço não resolveu o problema" } },
  { rotulo: "Garantia: em mediação", tipo: "garantia", app: "profissional", nome: "Carlos Pereira",
    titulo: "Garantia iService: estamos mediando",
    corpo: "Conversamos com a cliente. Ela pediu um retorno para revisar a tomada da cozinha, sem custo. Você consegue ir até sexta?",
    dados: { status: "em_mediacao", protocolo: "G-00012", codigo: "7F3A2C", servico: "Eletricista" } },
  { rotulo: "Garantia: resolvida", tipo: "garantia", app: "cliente", nome: "Mariana Souza",
    titulo: "Garantia iService: reclamação resolvida",
    corpo: "O profissional voltou, revisou a instalação e o problema foi resolvido. Obrigado pela paciência!",
    dados: { status: "resolvida", protocolo: "G-00012", codigo: "7F3A2C", servico: "Eletricista" } },
  { rotulo: "Conta suspensa", tipo: "conta_suspensa", app: "profissional", nome: "Carlos Pereira",
    corpo: "Recebemos três reclamações de não comparecimento em menos de uma semana." },
  { rotulo: "Conta reativada", tipo: "conta_reativada", app: "profissional", nome: "Carlos Pereira" },
  { rotulo: "Exclusão de conta", tipo: "exclusao_conta", app: "cliente", nome: "Mariana Souza", dados: { dias: 30 } },
];

const lista: { rotulo: string; arquivo: string; assunto: string }[] = [];
for (const e of exemplos) {
  const email = gerar(e.tipo, { nome: e.nome, app: e.app, titulo: e.titulo ?? "", corpo: e.corpo ?? "", dados: e.dados ?? {} });
  if (!email) throw new Error(`Sem modelo: ${e.tipo}`);
  const arquivo = `${lista.length + 1}-${e.tipo}-${e.app}.html`;
  writeFileSync(join(pasta, arquivo), email.html);
  lista.push({ rotulo: e.rotulo, arquivo, assunto: email.assunto });
}
for (const m of Object.values(MODELOS_AUTH)) {
  const html = montar(m.conteudo);
  writeFileSync(join("supabase/templates", m.arquivo), html);
  writeFileSync(join(pasta, `auth-${m.arquivo}`), html);
  lista.push({ rotulo: `${m.rotulo} (Supabase: ${m.nome})`, arquivo: `auth-${m.arquivo}`, assunto: m.conteudo.assunto });
}
writeFileSync(join(pasta, "lista.json"), JSON.stringify(lista, null, 2));
console.log(`${lista.length} e-mails em ${pasta}`);
