# Gestão de usuários, grupos e permissões

## Modelo

O perfil em `profiles` permanece vinculado ao Supabase Auth. Autoridade é calculada pela união das permissões dos grupos ativos associados em `user_groups`. Um usuário inativo não possui permissões efetivas.

Tabelas adicionadas pela migration `20261015000800_user_groups_permissions.sql`:

- `permission_groups`: grupos configuráveis e grupos protegidos do sistema.
- `permissions`: catálogo de códigos estáveis, módulo e sensibilidade.
- `group_permissions`: associação entre grupos e permissões.
- `user_groups`: associação muitos-para-muitos entre usuários e grupos.
- `user_invitations`: estado operacional dos convites enviados pelo servidor.

Os grupos iniciais são Administrador, Vendedor, Estoquista e Expedição. Apenas o grupo Administrador é imutável. Os demais podem ser ajustados pelo administrador.

## Autorização

`worker/modules/authorization.js` é a interface central do servidor. Cada combinação de método e rota declara uma permissão. Rotas não declaradas são negadas. O contexto é obtido por `current_access_context()` em toda nova requisição, portanto desativação ou remoção de grupo não depende da expiração de claims antigas do JWT.

No banco, `private.has_permission_for()` é a fonte canônica usada por RLS e comandos privilegiados. Funções `SECURITY DEFINER` usam nomes qualificados, validam a identidade, têm execução revogada de `PUBLIC` e `anon` e concedida apenas a `authenticated` quando necessário.

Tabelas com custos ou dados financeiros não são expostas a usuários operacionais. Catálogo, estoque, vendas e dashboard operacionais continuam usando projeções RPC que selecionam somente campos autorizados.

## Administração

O administrador pode:

- consultar, pesquisar e filtrar usuários;
- convidar colaboradores pelo Supabase Auth;
- associar múltiplos grupos;
- ativar ou desativar acesso;
- consultar permissões efetivas;
- criar, editar e duplicar grupos;
- selecionar permissões em matriz por módulo;
- consultar auditoria administrativa.

A remoção ou desativação do último administrador ativo é rejeitada dentro da transação do banco.

## Convites

Convites usam `SUPABASE_SECRET_KEY` exclusivamente no runtime do servidor. Configure essa variável na Vercel e nunca a prefixe como variável pública. Configure `APP_URL` com a origem canônica HTTPS; na Vercel, `VERCEL_PROJECT_PRODUCTION_URL` é usado automaticamente como fallback. A mesma URL pública precisa estar cadastrada em Supabase Auth → URL Configuration → Redirect URLs.

O navegador envia somente nome, e-mail e grupos escolhidos. O servidor valida `users.invite`, chama o Auth Admin API e registra associação e auditoria por RPC autenticada.

## Aplicação e testes

A migration não deve ser aplicada ao projeto remoto até a aprovação final. Antes da aplicação:

1. Configure `SUPABASE_SECRET_KEY` somente no ambiente do servidor.
2. Execute a migration em um ambiente Supabase de teste.
3. Rode `npm run test:permissions-schema` e `npm run test:rbac`.
4. Valide com contas de teste Administrador, Vendedor, Estoquista e Expedição.
5. Execute `supabase db lint` e os testes SQL/RLS.

Depois da aprovação, aplique com `supabase db push`, faça novo deploy e valide convite, revogação, último administrador e acesso direto pela Data API.
