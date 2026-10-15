# Arquitetura

O ERP é um monólito modular executado em Cloudflare Workers. A interface usa rotas HTTP do mesmo domínio; dados estruturados ficam no D1. A identidade é fornecida pelo Sites e toda escrita valida `oai-authenticated-user-id` no servidor.

Nesta fundação, `worker/index.js` é um módulo de entrega profundo: contém renderização, identidade, persistência de perfil e configurações, com uma interface HTTP pequena (`/`, `/api/session`, `/api/settings`). Domínios serão extraídos quando suas regras existirem, preservando locality e evitando módulos vazios.

O primeiro seam real é o catálogo: a interface HTTP de produtos/fornecedores esconde validação, persistência de variações, upload e criação do saldo inicial. A transação de cadastro usa `DB.batch`, mantendo produto, SKUs, saldo e auditoria juntos.

Seams seguintes: compras, estoque operacional, vendas, financeiro, precificação e relatórios. Operações críticas usarão `DB.batch` e chaves idempotentes.

Compras e recebimentos agora formam um fluxo transacional. Criar compra não toca o saldo. Confirmar recebimento valida pendências, registra conferência, atualiza saldo e auditoria em um único `DB.batch`. A chave de idempotência impede processamento duplicado.

Após a revisão da Fase 3, `worker/modules/purchasing.js` tornou-se o módulo deep para projeção, pagamento e recebimento; `worker/modules/inventory.js` concentra as leituras de saldo e ledger. `worker/index.js` permanece como adapter HTTP e entrega da interface. A migration 0004 move invariantes concorrentes para triggers D1.

Na Fase 5, `worker/modules/finance.js` concentra contas, lançamentos, transferências, obrigações e indicadores. Triggers da migration 0006 ligam pagamentos operacionais ao livro financeiro por uma origem única, evitando lançamentos duplicados sem colocar regras monetárias na interface.

Na Fase 6, `worker/modules/pricing.js` é a única fonte das fórmulas de preço. A interface envia entradas brutas e o servidor converte moeda para centavos e percentuais para pontos-base, calcula com arredondamento controlado e revalida o preço antes de persistir no SKU.

Na Fase 7, `worker/modules/reporting.js` concentra projeções somente de leitura para dashboard e relatórios. As consultas derivam faturamento, CMV, despesas, saldos, giro e alertas das tabelas transacionais; a interface apenas apresenta, filtra e exporta os resultados já calculados no servidor.
