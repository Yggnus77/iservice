# Site oficial do iService

Site estático (HTML + CSS + um pouco de JS), sem build. Abra `index.html` no navegador para ver.

## Onde editar

- **Contatos, CNPJ e links das lojas:** `assets/js/site.js`, no topo (`CONTATO` e `LOJAS`). Campo vazio aparece como "em breve".
- **Textos:** direto em `index.html`, `termos.html`, `privacidade.html` e `excluir-conta.html`.
- **Cores e estilo:** `assets/css/site.css` (variáveis no `:root`).

## Publicar no domínio (GitHub Pages)

1. Copie o conteúdo desta pasta para a raiz do ramo `gh-pages` (mantendo as pastas `cliente/` e `profissional/` dos apps web).
2. Crie um arquivo `CNAME` com o domínio, por exemplo `www.seudominio.com.br`.
3. No registro do domínio (Registro.br ou outro), crie os registros DNS:
   - `www` → CNAME → `yggnus77.github.io`
   - domínio sem www (`@`) → A → `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153`
4. Em Settings → Pages do repositório, preencha o domínio em *Custom domain* e marque *Enforce HTTPS* quando liberar.

Com domínio próprio, os apps web passam a ficar em `/cliente/` e `/profissional/`: recompile com `--base-href /cliente/` e `--base-href /profissional/` e troque o link "Quero me cadastrar" em `index.html`.
