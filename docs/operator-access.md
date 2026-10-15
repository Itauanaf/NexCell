# Controle de acesso do Operador

O controle binário descrito originalmente neste documento é preservado por compatibilidade. A evolução para múltiplos grupos e permissões efetivas está documentada em `docs/access-management.md`; o navegador não decide nem altera sua própria autoridade.

## Camadas de proteção

- Interface: o Administrador conserva o menu original. O Operador recebe somente Dashboard, Vendas, Pedidos para separação, Envios, Produtos, Estoque e Meu perfil.
- API: toda requisição autenticada resolve o perfil no servidor. Operadores passam por uma lista explícita de rotas permitidas; qualquer outra rota retorna HTTP 403.
- Banco: a migration `20261015000600_operator_rbac.sql` remove leitura ampla, limita tabelas sensíveis ao administrador e expõe RPCs operacionais com colunas selecionadas.

As RPCs do Operador nunca retornam custo, custo histórico, fornecedor, margem, lucro, contas a pagar/receber ou saldos. A criação de venda usa o preço cadastrado no banco e rejeita desconto ou substituição de preço. Cancelamentos e devoluções permanecem administrativos.

## Fluxos permitidos

- Consultar catálogo e disponibilidade.
- Criar venda com preço validado pelo servidor.
- Consultar pedidos e itens sem custo histórico.
- Registrar recebimento dentro do saldo pendente.
- Separar pedido e registrar expedição.

## Validação

Execute `npm run test:rbac` para validar a filtragem da API, o bloqueio das rotas administrativas, o acesso administrativo preservado e o bloqueio de usuário anônimo. As políticas reais devem ser aplicadas com `supabase db push` antes do teste manual com contas reais.
