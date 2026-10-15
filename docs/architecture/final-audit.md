# Auditoria arquitetural final

## Resultado

O monólito modular é adequado ao porte atual. Regras críticas estão nos módulos de domínio e em triggers D1; `worker/index.js` atua como adapter HTTP e composição da interface. A revisão não encontrou justificativa para trocar de framework ou criar camadas vazias.

## Correções aplicadas

- Ações de catálogo, configuração, preço e financeiro manual agora exigem perfil Administrador no servidor.
- Escritas com cabeçalho `Origin` externo são rejeitadas.
- Respostas recebem políticas de cache, MIME, referência e permissões.
- O zero fixo do menu de estoque foi removido.
- Busca, notificações, atalhos de teclado, skip link, regiões de status e diálogos receberam comportamento ou semântica acessível.
- Índices foram adicionados aos filtros mais usados por dashboard, obrigações e auditoria.

## Decisões preservadas

- D1 guarda invariantes concorrentes de estoque, pagamentos e recebimentos.
- Valores monetários permanecem em centavos; percentuais de precificação usam pontos-base.
- Relatórios são projeções de leitura e não duplicam dados transacionais.
- Autenticação continua delegada ao Sites, usando apenas a identidade injetada pelo ambiente hospedado.

## Recomendações priorizadas

1. **Antes da operação real:** implementar estornos financeiros vinculados a cancelamentos e devoluções. Até lá, esses casos exigem conferência administrativa; não devem ser tratados apenas como uma saída manual.
2. **Após uma versão estável publicada:** extrair os clientes de interface hoje compostos em `worker/index.js` para assets ESM do mesmo domínio. Isso permitirá remover `unsafe-inline` da CSP. Fazer essa mudança junto com testes de navegador, não como refatoração isolada.
3. **Quando o volume crescer:** acompanhar os planos de consulta dos relatórios e criar paginação. Os índices da migration 0007 cobrem os filtros atuais, mas não substituem medição em produção.
4. **Antes de ampliar a equipe:** transformar a matriz Administrador/Operador em permissões nomeadas, mantendo a verificação no servidor.

## Riscos conhecidos

- Não houve validação visual automatizada em navegador nesta sessão; responsividade foi verificada por regras CSS e compilação do documento.
- A migração e os testes foram executados em SQLite compatível, mas ainda precisam ser aplicados ao D1 hospedado.
- A CSP ainda permite estilos e scripts inline por causa do empacotamento atual da interface.
- O fluxo seguro de publicação requer entrada interativa de credencial Git, indisponível neste ambiente.
