# Banco de dados

A migração `0001_foundation.sql` cria papéis, perfis, configurações e auditoria. Perfis são vinculados ao identificador estável entregue pelo Sites. Configurações são JSON versionável com autor e data; toda escrita gera auditoria.

As próximas migrações adicionarão entidades por fase. Migrações aplicadas são imutáveis e novas mudanças devem ser anexadas em arquivos numerados.

`0002_catalog.sql` adiciona fornecedores, categorias, produtos, variações, imagens, saldos e movimentos de abertura. Valores monetários são inteiros em centavos. SKU e código de barras são únicos. O saldo reservado nunca pode superar o físico.

`0003_purchasing_inventory.sql` adiciona pedidos, itens, pagamentos e recebimentos. Estados comercial, financeiro e logístico são independentes. A chave de idempotência do recebimento é única; itens avariados são registrados, mas não aumentam o saldo físico.

`0004_deepen_purchasing.sql` cria uma projeção de compras sem multiplicação de joins. Triggers impedem pagamento acumulado acima do pedido e recebimento acima do pendente; a entrada aceita, o ledger e o status logístico são atualizados atomicamente.
