# ADR 0001 — Worker ESM com D1

**Status:** aceita.

O ambiente atual não oferece Node/npm. Adotamos Worker ESM sem dependências, hospedado em Sites, com D1 e autenticação nativa. A decisão mantém backend real e implantação suportada. Uma migração futura para Vinext pode ocorrer quando o toolchain Node estiver disponível, sem mudar o modelo de domínio.
