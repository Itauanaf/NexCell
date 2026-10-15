# ADR 0003 — Autorização no adapter HTTP

**Status:** aceita.

O Sites autentica a pessoa e injeta sua identidade, mas o ERP continua responsável por autorizar cada escrita. Operadores podem executar o fluxo diário de compras, recebimentos, vendas, pagamentos e expedições. Alterações de catálogo, configurações, preços e lançamentos financeiros manuais exigem Administrador.

A verificação permanece no servidor mesmo quando a interface oculta ou desabilita ações. Requisições mutáveis com origem externa também são rejeitadas. Uma futura matriz de permissões pode substituir a regra binária sem alterar os módulos de domínio.
