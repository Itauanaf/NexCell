# Testes

Na Fase 1 são validados o artefato Worker, a presença do manifesto e as restrições da migração. Após publicação, verificar: acesso privado autenticado, `/api/session`, leitura e gravação de configurações, rejeição de requisição sem identidade e responsividade em 390, 768 e 1440 px.

Os cenários transacionais de compras, estoque, vendas, financeiro e calculadora entram junto aos respectivos módulos.

## Fase 2

- As migrations 0001 e 0002 foram executadas juntas em SQLite em memória.
- Foram inseridos perfil, fornecedor, produto, SKU e saldo de 20 unidades.
- A restrição bloqueou reserva de 21 unidades sobre saldo físico de 20.
- O Worker e o JavaScript embarcado foram compilados sem erro.
- CRUD hospedado, R2 e responsividade visual ainda dependem da publicação segura no Sites.
