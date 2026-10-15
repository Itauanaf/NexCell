# Glossário de domínio

- **Produto:** cadastro comercial que agrupa variações.
- **Variação / SKU:** item individual comprado, estocado e vendido.
- **Pedido de compra:** compromisso comercial que não altera estoque.
- **Pagamento de compra:** liquidação parcial ou total protegida pelo total do pedido.
- **Recebimento:** conferência idempotente que registra aceitos e avariados.
- **Estoque físico:** unidades aceitas e existentes.
- **Estoque reservado:** unidades comprometidas com vendas.
- **Estoque disponível:** físico menos reservado.
- **Movimentação de estoque:** registro imutável da causa e do saldo resultante.
- **Projeção de compra:** leitura agregada de pedido, itens, recebimentos e pagamentos.
- **Reserva de venda:** compromisso de unidades disponíveis sem reduzir o estoque físico.
- **Expedição:** evento único que consome a reserva e reduz o estoque físico.
- **Devolução conferida:** retorno validado que recompõe o estoque físico, limitado ao que foi expedido.
- **Custo histórico:** custo do SKU congelado no item da venda para preservar a margem original.
