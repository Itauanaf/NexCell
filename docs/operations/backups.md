# Backup e restauração

## Política

- Criar um snapshot/exportação do D1 antes de qualquer migration de produção.
- Manter uma cópia externa criptografada por pelo menos 30 dias.
- Exportar também os objetos do bucket R2 de imagens, preservando as chaves.
- Registrar data, versão implantada, última migration e responsável.
- Testar a restauração trimestralmente em um projeto privado de homologação.

## Restauração testada em homologação

1. Bloquear temporariamente novas escritas no sistema afetado.
2. Criar um D1 vazio de homologação e aplicar as migrations na ordem numérica.
3. Importar a exportação correspondente sem substituir o banco de produção.
4. Restaurar o R2 mantendo exatamente as mesmas chaves de objeto.
5. Conferir contagens de vendas, compras, movimentos, lançamentos e auditoria.
6. Executar os cenários automatizados de estoque, vendas, financeiro, preços e relatórios.
7. Comparar saldos financeiros e físicos com o snapshot de origem.
8. Somente após aprovação, planejar a troca controlada do binding de produção.

Nunca testar uma restauração diretamente sobre o único banco de produção. As credenciais e exportações não devem ser gravadas no repositório.
