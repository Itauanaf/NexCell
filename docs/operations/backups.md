# Backup e restauração do Supabase

## Política

- Confirmar a retenção dos backups automáticos e, quando disponível no plano, o PITR do PostgreSQL antes de migrations de produção.
- Gerar um dump lógico consistente antes de alterações críticas e guardar uma cópia externa criptografada por pelo menos 30 dias.
- Exportar separadamente os objetos do Supabase Storage, preservando bucket, chave, metadados e vínculo com `product_images`.
- Registrar a versão implantada, última migration, horário, responsável e localização segura do backup.
- Não gravar senhas, chaves, tokens, dumps ou exportações no repositório.
- Testar a restauração trimestralmente em um projeto Supabase privado de homologação.

## Ensaio de restauração em homologação

1. Criar um projeto isolado de homologação, sem apontar o domínio de produção para ele.
2. Restaurar o dump do PostgreSQL ou o ponto selecionado do PITR no ambiente isolado.
3. Restaurar os objetos do Storage nas mesmas chaves e conferir o bucket privado `product-images`.
4. Recriar usuários de teste no Supabase Auth; dados de `auth.users` não devem ser improvisados por SQL de aplicação.
5. Conferir contagens e relacionamentos de vendas, compras, estoque, finanças, perfis, grupos e auditoria.
6. Executar os testes automatizados e cenários ponta a ponta de compra, venda, pagamento, preço e imagem.
7. Comparar saldos financeiros, físicos e reservados com o backup de origem.
8. Registrar tempo de recuperação, divergências e aprovação antes de planejar qualquer recuperação de produção.

Nunca ensaiar uma restauração sobre o único banco de produção. Durante uma recuperação real, bloquear novas escritas, preservar evidências e validar o ponto restaurado antes de reabrir o ERP.
