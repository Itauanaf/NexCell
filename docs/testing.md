# Testes

Na Fase 1 são validados o artefato Worker, a presença do manifesto e as restrições da migração. Após publicação, verificar: acesso privado autenticado, `/api/session`, leitura e gravação de configurações, rejeição de requisição sem identidade e responsividade em 390, 768 e 1440 px.

Os cenários transacionais de compras, estoque, vendas, financeiro e calculadora entram junto aos respectivos módulos.

## Fase 2

- As migrations 0001 e 0002 foram executadas juntas em SQLite em memória.
- Foram inseridos perfil, fornecedor, produto, SKU e saldo de 20 unidades.
- A restrição bloqueou reserva de 21 unidades sobre saldo físico de 20.
- O Worker e o JavaScript embarcado foram compilados sem erro.
- CRUD hospedado, R2 e responsividade visual ainda dependem da publicação segura no Sites.

## Fase 3

- As três migrations foram executadas juntas em SQLite em memória.
- Uma compra de 20 unidades manteve o estoque físico em zero.
- O recebimento parcial de 15 unidades resultou em físico 15 e pendência 5.
- A chave idempotente repetida foi rejeitada pela restrição do banco.
- Worker e JavaScript embarcado da Fase 3 foram compilados sem erro.

## Correções arquiteturais da Fase 3

- Dois pagamentos de R$ 50,00 em uma compra com dois itens resultaram em R$ 100,00, sem multiplicação pelo número de itens.
- Um pagamento que ultrapassaria o total foi bloqueado pelo trigger.
- O recebimento de 15 unidades gerou saldo e movimento com `physical_after=15`.
- Uma entrada de 6 unidades sobre pendência 5 foi bloqueada pelo trigger.
- Os módulos ESM de compras e estoque e o JavaScript da interface passaram na validação sintática.
