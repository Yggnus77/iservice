# iService

Serviços imediatos perto de você. O cliente escolhe a profissão, vê os profissionais mais bem avaliados da região e faz o pedido direto para um deles.

## Estrutura

| Pasta | O que é |
|---|---|
| `apps/cliente` | App do Cliente (Flutter, azul) |
| `apps/profissional` | App do Profissional (Flutter, laranja) |
| `packages/iservice_core` | Base comum: tema, componentes, dados, cadastro, chat e notificações |
| `supabase/migrations` | Banco (Postgres + PostGIS): tabelas, regras, segurança e catálogo |
| `supabase/tests` | Testes das regras de negócio |
| `tools` | Scripts (gerar catálogo, testar o banco) |

## Rodar

```bash
cp config/exemplo.json config/dev.json   # preencha com a URL e a chave publicável do Supabase
flutter pub get
cd apps/cliente && flutter run --dart-define-from-file=../../config/dev.json
cd apps/profissional && flutter run --dart-define-from-file=../../config/dev.json
```

## Banco

As migrações em `supabase/migrations` são a fonte da verdade. Para testar as regras localmente com um Postgres do Supabase em `localhost:54329`:

```bash
bash tools/testar_banco.sh
```

No projeto na nuvem as migrações foram aplicadas pelo painel/MCP com os nomes `schema`, `funcoes`, `seguranca` e `catalogo`, por isso o histórico remoto não tem os mesmos carimbos de data dos arquivos.

## Regras principais

- Pedido direcionado: vai só para o profissional escolhido, que tem 10 minutos para aceitar. Recusa ou falta de resposta encerra o pedido.
- Só "Agora" (com taxa de urgência) ou "Hoje"; outro dia apenas com horário combinado, até 7 dias.
- Quem está em atendimento some das buscas.
- Ranking pela qualidade (nota, serviços, confiabilidade, distância); novos entram em rodízio.
- O profissional define o preço; o app mostra a faixa da região.
- Planos VIP e Premium prontos no código, desligados (`cobranca_ativa = false`).
