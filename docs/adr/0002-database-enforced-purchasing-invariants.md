# ADR 0002 — Invariantes de compras protegidas no banco

**Status:** aceita.

Pagamentos e recebimentos deixam de depender de sequências “ler, validar, gravar” no adaptador HTTP. Triggers atômicos protegem limite de pagamento, quantidade pendente e aplicação do recebimento ao estoque. A view `purchase_order_summary` agrega itens e pagamentos separadamente para impedir multiplicação de valores.

O módulo de compras oferece comandos pequenos; D1 preserva as invariantes mesmo com chamadas concorrentes ou novos adapters.
