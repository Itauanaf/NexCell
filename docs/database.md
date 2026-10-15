# Banco de dados

A migração `0001_foundation.sql` cria papéis, perfis, configurações e auditoria. Perfis são vinculados ao identificador estável entregue pelo Sites. Configurações são JSON versionável com autor e data; toda escrita gera auditoria.

As próximas migrações adicionarão entidades por fase. Migrações aplicadas são imutáveis e novas mudanças devem ser anexadas em arquivos numerados.

`0002_catalog.sql` adiciona fornecedores, categorias, produtos, variações, imagens, saldos e movimentos de abertura. Valores monetários são inteiros em centavos. SKU e código de barras são únicos. O saldo reservado nunca pode superar o físico.
