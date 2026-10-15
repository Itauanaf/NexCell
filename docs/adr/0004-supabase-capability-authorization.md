# ADR 0004 — Autorização por capacidades no Supabase

**Status:** aceita para implementação na branch `feature/user-groups-permissions`.

O runtime atual usa Vercel e Supabase Auth/PostgreSQL. Esta decisão sucede as partes do ADR 0001 que descrevem Sites e D1, preservando o princípio de manter o ERP como monólito modular.

Permissões efetivas são calculadas no banco a partir dos grupos ativos associados ao perfil ativo. Nomes de grupo não concedem autoridade diretamente. O servidor resolve o contexto de autorização a cada requisição, aplica negação por padrão e relaciona cada rota a um código de permissão estável. A interface utiliza as mesmas capacidades apenas para navegação e apresentação; backend e RLS continuam sendo a autoridade.

Operações administrativas do Supabase Auth ficam em um adapter exclusivamente server-side com `SUPABASE_SECRET_KEY`. A chave nunca é incorporada ao HTML, ao JavaScript público ou às respostas da API.

Funções privilegiadas mantêm `search_path` fixo, validam `auth.uid()` e permissão, revogam execução de `PUBLIC` e `anon`, e recebem grants mínimos. Tabelas que misturam colunas operacionais e confidenciais não são lidas diretamente por usuários operacionais; projeções seguras retornam somente campos autorizados.

As migrations já aplicadas permanecem imutáveis. A evolução entra em migration nova e mantém o papel legado apenas para compatibilidade durante a transição.
