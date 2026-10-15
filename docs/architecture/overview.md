# Arquitetura

O ERP é um monólito modular executado em Cloudflare Workers. A interface usa rotas HTTP do mesmo domínio; dados estruturados ficam no D1. A identidade é fornecida pelo Sites e toda escrita valida `oai-authenticated-user-id` no servidor.

Nesta fundação, `worker/index.js` é um módulo de entrega profundo: contém renderização, identidade, persistência de perfil e configurações, com uma interface HTTP pequena (`/`, `/api/session`, `/api/settings`). Domínios serão extraídos quando suas regras existirem, preservando locality e evitando módulos vazios.

O primeiro seam real é o catálogo: a interface HTTP de produtos/fornecedores esconde validação, persistência de variações, upload e criação do saldo inicial. A transação de cadastro usa `DB.batch`, mantendo produto, SKUs, saldo e auditoria juntos.

Seams seguintes: compras, estoque operacional, vendas, financeiro, precificação e relatórios. Operações críticas usarão `DB.batch` e chaves idempotentes.
