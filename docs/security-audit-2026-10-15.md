# NexCell ERP — Auditoria de segurança pré-operacional

Data: 15 de outubro de 2026  
Escopo: código em `6706f6d`, produção `https://nexcell-two.vercel.app` e projeto Supabase `vhiagjcluqlnddirmjum`  
Modo: somente leitura; nenhuma correção, migration ou publicação foi realizada durante esta auditoria.

## Resumo executivo

Não foi confirmado acesso anônimo a dados, bypass de autenticação, chave administrativa pública ou alteração financeira/estoque sem autorização. A matriz anônima consultou 35 tabelas/views, 11 APIs internas e o bucket privado sem obter registros. Todas as tabelas públicas comuns possuem RLS, a view financeira usa `security_invoker=true`, o bucket `product-images` é privado e as RPCs negam execução ao papel `anon`.

O sistema ainda **não deve ser liberado para uso operacional**. Há um risco alto no invariante concorrente do último administrador, além de lacunas médias em sessão/logout, cadastro público, grants, superfície `SECURITY DEFINER`, hardening HTTP, autenticação forte e recuperação. O plano de backup ainda descreve D1/R2 e não é aplicável ao Supabase. Os testes autenticados com papéis distintos não foram realizados porque não existe staging nem foram fornecidas contas fictícias; executá-los em produção violaria o escopo seguro.

Classificação: 0 críticos confirmados, 1 alto, 10 médios e 3 baixos/observações.

## Componentes inspecionados

- Vercel adapter e Worker (`api/handler.js`, `worker/index.js`, `worker/supabase-api.js`).
- Autenticação, sessão, logout, convite e autorização por capacidades.
- Oito migrations Supabase, RLS, policies, grants, funções e view financeira.
- Supabase Storage e bucket `product-images`.
- Código frontend, HTML dinâmico, CSP, cache e cabeçalhos.
- Scripts, build, variáveis de ambiente e histórico Git.
- Fluxos críticos de catálogo, compras, estoque, vendas, preço e financeiro.
- Documentação de arquitetura, acesso, testes e backup.

Skills utilizadas: `supabase` 0.1.2 e `code-review`. A revisão comparativa adotou `2ea29f2` como ponto fixo e os commits `b44cd4f`/`6706f6d` como diff.

## Descobertas

### SEC-001 — Alto — Invariante do último administrador é concorrente e dependente do nome

- Local: `supabase/migrations/20261015000800_user_groups_permissions.sql:207-208`.
- Evidência: a função bloqueia somente o perfil-alvo, conta administradores sem serializar a decisão e identifica autoridade por `g.name='Administrador'`.
- Impacto: duas transações concorrentes podem remover/desativar os últimos administradores, causando perda de administração. Usar nome também contradiz o modelo de capacidades e torna o invariante frágil.
- Pré-condições: duas sessões com `users.edit`, `users.disable` e/ou `groups.manage`, executadas simultaneamente.
- Correção recomendada: serializar a operação com advisory lock transacional ou linha sentinela e usar o ID imutável do grupo de sistema ou capacidade administrativa efetiva.
- Regressão: teste concorrente com dois administradores, duas transações e confirmação de que uma delas falha.

### SEC-002 — Médio — Sessão persistida em `localStorage` e logout apenas local

- Local: `worker/index.js:309`.
- Evidência: access/refresh token completos ficam em `localStorage`; “Sair” apenas remove o item e recarrega a página, sem chamar `/auth/v1/logout`.
- Impacto: qualquer XSS na mesma origem pode roubar a sessão; um token já copiado continua válido após o logout local até expirar/revogar.
- Pré-condições: execução de script na origem, extensão maliciosa ou acesso local ao perfil do navegador.
- Correção recomendada: sessão server-side com cookie `HttpOnly`, `Secure`, `SameSite`, ou cliente oficial com rotação adequada; chamar logout do Supabase e documentar escopo global/local. Reduzir a CSP inline.
- Regressão: após logout, refresh token deve falhar e o access token deve obedecer à política documentada.

### SEC-003 — Médio — Cadastro público permanece exposto em ERP interno

- Local: `worker/index.js:309`; `handle_new_user()` em `20261015000800_user_groups_permissions.sql`.
- Evidência: a tela oferece “Criar primeira conta” e chama `/auth/v1/signup`; requisição inválida alcançou a validação do endpoint (`422`), não uma rejeição explícita de signup desabilitado.
- Impacto: criação/spam de contas e superfície desnecessária. Novas contas ficam sem grupos, então nenhum acesso a dados foi demonstrado.
- Pré-condições: acesso público ao domínio.
- Correção recomendada: desabilitar novos cadastros no Supabase Auth e remover o fluxo de signup; manter somente convite administrativo.
- Regressão: POST público válido para signup deve retornar “signups disabled” e não criar `auth.users`/`profiles`.

### SEC-004 — Médio — Policies administrativas chamam helper sem EXECUTE

- Local: migration `00800`, linhas 124-125 e 246.
- Evidência: `private.has_permission_for()` tem EXECUTE revogado de `authenticated`, mas cinco policies o chamam diretamente.
- Impacto: usuários autorizados podem receber `permission denied` em leituras diretas, quebrando o contrato RLS e incentivando contornos inseguros. Não houve vazamento anônimo.
- Pré-condições: leitura direta das tabelas administrativas pela Data API.
- Correção recomendada: policy chamar o wrapper seguro `public.has_permission()` ou adotar desenho que preserve execução mínima sem expor o helper.
- Regressão: contas com/sem `groups.view` devem, respectivamente, ler/receber vazio ou 403 sem erro de execução interna.

### SEC-005 — Médio — Superfície extensa de funções SECURITY DEFINER expostas

- Local: 41 RPCs no schema `public`.
- Evidência: Supabase Security Advisor emitiu 41 alertas `authenticated_security_definer_function_executable`. Todas negam `anon`; a inspeção não encontrou RPC de mutação autenticada sem guarda interna de papel/capacidade.
- Impacto: qualquer falha futura de validação numa RPC pode contornar RLS com privilégios do owner.
- Pré-condições: usuário autenticado e defeito numa guarda/validação.
- Correção recomendada: mover helpers para schema privado, manter apenas comandos necessários como API, preferir invoker quando possível, fixar `search_path=''`, qualificar nomes e conceder EXECUTE individualmente.
- Regressão: advisor sem alertas não justificados; matriz por RPC e capability.

### SEC-006 — Médio — Grants de tabelas são mais amplos que o necessário

- Local: estado remoto do PostgreSQL; origem parcialmente em `20261015000100_nexcell_foundation.sql:402-405` e defaults da plataforma.
- Evidência: `anon` e `authenticated` possuem privilégios amplos, inclusive escrita/DDL auxiliar, em muitas tabelas; RLS bloqueou as leituras anônimas testadas e não há policies amplas.
- Impacto: aumenta o raio de impacto de erro futuro em policy. `TRUNCATE` não é governado por RLS, embora não seja exposto como operação comum pelo PostgREST.
- Pré-condições: caminho de conexão/execução que permita usar esses privilégios ou policy futura defeituosa.
- Correção recomendada: revogar tudo de `anon`; conceder ao `authenticated` apenas SELECT/RPC estritamente necessário e remover writes diretos quando comandos transacionais forem a única via.
- Regressão: inventário automatizado de grants esperado e testes negativos para escrita direta.

### SEC-007 — Médio — Corpo HTTP sem limite antes do processamento

- Local: `api/handler.js:3-11`.
- Evidência: o handler acumula todos os chunks em memória; apenas upload de imagem verifica 4 MB depois de carregar o corpo.
- Impacto: consumo de memória/CPU e custo por requisições grandes; potencial negação de serviço de aplicação.
- Pré-condições: acesso público ao endpoint Vercel.
- Correção recomendada: rejeitar por `Content-Length`, impor limite durante streaming e limites menores para JSON; adicionar rate limiting por identidade/IP para rotas sensíveis.
- Regressão: corpos acima dos limites retornam 413 sem alocação integral.

### SEC-008 — Médio — Mensagens internas do Supabase são refletidas ao cliente

- Local: `worker/supabase-api.js:29-30,342`.
- Evidência: mensagens de PostgREST/Auth/Storage são promovidas a `Error.message` e devolvidas em JSON.
- Impacto: enumeração de schema, constraints e estados internos para usuários autenticados.
- Pré-condições: sessão válida e entrada que provoque erro.
- Correção recomendada: mapear erros conhecidos para códigos públicos; registrar detalhes somente no servidor com correlação.
- Regressão: entradas malformadas retornam erro genérico/código estável, sem nomes de tabelas, funções ou constraints.

### SEC-009 — Médio — Controles fortes de Auth incompletos

- Local: configuração remota do Supabase Auth.
- Evidência: advisor `auth_leaked_password_protection`; não há fluxo ou política de MFA para administradores no código/documentação.
- Impacto: maior risco de tomada de conta por senha reutilizada/phishing.
- Pré-condições: credencial comprometida.
- Correção recomendada: habilitar proteção contra senha vazada, MFA obrigatório para administradores, CAPTCHA/rate limits adequados e política de senha.
- Regressão: senha conhecida como vazada rejeitada; operação administrativa sensível exige AAL2.

### SEC-010 — Médio — Adaptador Vercel não entrega a secret ao módulo de convites

- Local: `api/handler.js:29-32` e `worker/modules/user-administration.js:1-11`.
- Evidência: o handler passa URL e publishable key, mas omite `SUPABASE_SECRET_KEY`; o módulo retorna 503 sem ela.
- Impacto: convite/compensação administrativa indisponíveis; pode induzir procedimentos manuais inseguros.
- Pré-condições: tentativa de convidar usuário em produção.
- Correção recomendada: encaminhar a variável somente no runtime server-side, validar presença no startup/deploy e nunca incluí-la no HTML.
- Regressão: convite fictício em staging funciona; `/api/config`, HTML e build público continuam sem valor privilegiado.

### SEC-011 — Médio — Backup e restauração não correspondem ao runtime atual

- Local: `docs/operations/backups.md:5-18`.
- Evidência: procedimento ainda usa D1/R2, enquanto produção usa PostgreSQL/Supabase Storage.
- Impacto: ausência de recuperação testada para dados financeiros, estoque, Auth e objetos antes do início operacional.
- Pré-condições: corrupção, exclusão ou migration defeituosa.
- Correção recomendada: política Supabase/Postgres, PITR conforme plano, dumps criptografados, export do Storage, recuperação de Auth e teste trimestral em projeto isolado.
- Regressão: restauração de snapshot fictício com reconciliação de saldos e contagens.

### SEC-012 — Baixo — Upload valida MIME declarado, não assinatura do arquivo

- Local: `worker/supabase-api.js:172-179`.
- Evidência: tipo aceito e tamanho são verificados, mas o conteúdo não é decodificado/validado.
- Impacto: armazenamento de bytes não-imagem com extensão permitida; impacto reduzido pelo bucket privado e URL assinada.
- Correção recomendada: validar magic bytes/decodificar imagem no servidor, remover metadados e manter `Content-Disposition`/`nosniff` adequados.
- Regressão: arquivo HTML/SVG renomeado para JPG deve ser rejeitado.

### SEC-013 — Baixo — CSP ainda permite scripts inline

- Local: `worker/index.js:345`; cabeçalho confirmado em produção.
- Evidência: `script-src 'self' 'unsafe-inline'` e `style-src ... 'unsafe-inline'`.
- Impacto: reduz proteção contra XSS e agrava o risco do token em `localStorage`.
- Correção recomendada: extrair scripts/estilos para assets e usar nonce/hash; manter `frame-ancestors` conforme necessidade real.
- Regressão: CSP sem `unsafe-inline`, testes de navegador e nenhuma violação no console.

### OBS-014 — Informações positivas e observações

- Nenhuma chave privilegiada, JWT privado, URL de banco ou private key foi encontrada no worktree ou histórico Git. `.env.local` está ignorado.
- Produção não contém marcador de secret/service role; `/api/config` publica somente URL e publishable key, comportamento esperado.
- Root possui `private, no-store`, HSTS, `nosniff`, `no-referrer`, Permissions Policy e CSP.
- O bucket `product-images` é privado, 4 MB, JPEG/PNG/WebP; listagem anônima retornou zero objetos.
- Não existem dependências npm de runtime declaradas. `npm audit` não pôde rodar por ausência de lockfile (`ENOLOCK`); não foi criado lockfile para manter o modo somente leitura.

## Matriz de testes

| Grupo | Resultado | Evidência/limitação |
|---|---|---|
| A — anônimo | Aprovado no escopo testado | 35 tabelas/views sem linhas; 11 APIs retornaram 401; RPC anônima bloqueada |
| B — usuários distintos | Não executado | Sem staging/contas fictícias; não testar papéis em produção |
| C — parâmetros/IDOR | Parcial | Default deny e guardas revisados; sem contas para teste dinâmico |
| D — financeiro | Parcial | Testes unitários passaram e validações transacionais revisadas; sem teste remoto autenticado |
| E — estoque | Parcial | Testes de vendas/estoque passaram; sem mutação remota |
| F — Storage | Parcial aprovado | Bucket/policies/metadados e listagem anônima; upload cruzado não testado |
| G — sessão | Parcial/reprovado | JWT expirado é validado pelo Supabase; logout não revoga sessão no servidor |
| H — malformadas | Parcial | Anônimo bloqueado antes do parsing; mensagens autenticadas ainda refletem detalhes internos |

Testes automatizados aprovados: vendas, financeiro, pricing, relatórios, limites de segurança, RBAC simulado, schema de permissões, adapter Vercel, limite anônimo Supabase e build.

## Revisão code-review em dois eixos

### Standards

- Hard: policies RLS administrativas chamam helper sem EXECUTE.
- Hard: proteção de administrador usa nome de grupo, contrariando ADR 0004.
- Hard: proteção do último administrador é suscetível a corrida.
- Smell: fluxo de convite/reenvio duplicado e reenvio confia em e-mail/nome enviados pelo cliente.
- Smell: políticas HTTP são triples posicionais em vez de objetos nomeados.

Total: 3 violações hard e 2 smells. Pior item: invariante concorrente do último administrador.

### Spec

A revisão do diff registrou ausência histórica de relatório, testes reais de papéis, matriz completa, auditoria de Storage/dependências/segredos e MFA. Esta auditoria atual cobre parte dessas lacunas. O apontamento de “correções antes do relatório” é apenas uma observação processual do diff: os commits auditados antecedem a especificação atual e não foram produzidos durante esta auditoria.

## Plano de correção priorizado

1. **P0 antes de operar:** corrigir e testar concorrência do último administrador; criar staging e matriz autenticada completa.
2. **P0 operacional:** substituir plano de backup por Supabase/Postgres/Storage e provar restauração.
3. **P1:** desabilitar signup público; corrigir logout/sessão e definir MFA AAL2 para administradores.
4. **P1:** reduzir grants e superfície `SECURITY DEFINER`; corrigir helper das policies; executar advisors novamente.
5. **P1:** encaminhar secret no adapter exclusivamente server-side e validar convite em staging.
6. **P2:** limites de corpo/rate limiting, erros públicos sanitizados, validação real de imagens e CSP sem inline.

## Critério de liberação

Resultado atual: **não aprovado para dados comerciais/financeiros reais**. Reavaliar após correção dos itens P0/P1, testes com Administrador/Vendedor/Estoquista/Expedição em staging, advisor revisado, backup restaurado e regressão completa. Esta conclusão não representa garantia absoluta; monitoramento, rotação de credenciais, revisão de logs e auditorias recorrentes continuam necessários.

## Referências oficiais consultadas

- Supabase changelog: https://supabase.com/changelog.md
- Product Security: https://supabase.com/docs/guides/security/product-security
- Securing the Data API: https://supabase.com/docs/guides/api/securing-your-api
- MFA: https://supabase.com/docs/guides/auth/auth-mfa
- Storage access control: https://supabase.com/docs/guides/storage/security/access-control
