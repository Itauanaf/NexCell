# NexCell ERP

ERP interno para catálogo, compras, estoque, vendas, financeiro, relatórios e gestão granular de acessos.

## Arquitetura

- Frontend e API: Cloudflare Worker compatível com o runtime da Vercel.
- Persistência: PostgreSQL hospedado no Supabase, com migrations, RLS e RPCs transacionais.
- Autenticação: Supabase Auth.
- Imagens de produtos: Supabase Storage.
- Autorização: grupos e permissões efetivas validados no servidor e no banco.

## Desenvolvimento local

Copie `.env.example` para `.env.local` e configure `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `APP_URL` e, apenas no servidor, `SUPABASE_SECRET_KEY`.

```powershell
npm install
npm run dev:supabase
```

Abra `http://localhost:4173`. Contas e grupos devem ser criados pelo fluxo administrativo; nenhum novo cadastro recebe acesso de Administrador automaticamente.

## Build e publicação

```powershell
npm run build
```

O artefato é gerado em `dist`. Na Vercel, use `npm run build` como Build Command e `dist` como Output Directory. Cadastre as mesmas variáveis de ambiente no projeto antes do redeploy.

As migrations ficam em `supabase/migrations`. Revise e aplique-as ao projeto vinculado com a Supabase CLI antes de testar funcionalidades que dependem do esquema novo.

## Validação

Execute `npm test` e os testes específicos definidos em `package.json`. Consulte `docs/access-management.md` para o modelo de grupos, permissões, convites e auditoria.

Para uma visualização estática sem autenticação, abra `preview/index.html` com Live Server. Essa prévia não representa persistência real.
