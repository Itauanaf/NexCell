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

## Fase 4

- As migrations 0001–0005 foram executadas juntas em SQLite em memória.
- Uma venda de 3 unidades sobre físico 15 manteve físico 15, reservou 3 e deixou disponível 12.
- A expedição reduziu o físico para 12, zerou a reserva e uma segunda expedição foi rejeitada.
- O custo histórico permaneceu em R$ 25,00 após o custo atual mudar para R$ 31,00.
- Uma devolução conferida de 2 unidades recompôs o físico; devolver além do saldo vendido foi bloqueado.
- O cancelamento de outra venda liberou toda a reserva sem alterar o físico.
- O Worker, o módulo de vendas e o JavaScript embarcado da Fase 4 passaram na validação sintática.

## Fase 5

- As migrations 0001–0006 foram executadas juntas em SQLite em memória.
- Pagamento parcial de compra reduziu o saldo e atualizou a conta a pagar sem virar despesa de resultado.
- Recebimento parcial de venda aumentou o saldo e atualizou a conta a receber sem duplicar lançamento.
- Faturamento de R$ 150,00, CMV de R$ 75,00 e despesa de R$ 10,00 produziram resultado estimado de R$ 65,00.
- Transferência entre contas preservou o saldo financeiro total.
- Pagamento acima do total foi rejeitado e a conciliação registrou usuário e data.
- Módulos, Worker, preview e JavaScript embarcado passaram na validação sintática.
