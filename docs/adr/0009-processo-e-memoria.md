# ADR 0009 — Processo e memória: ADRs sim, AgEnFK não

**Status:** aceito em 2026-11-11

- **ADRs em `docs/adr/`** (um arquivo por decisão: contexto, decisão, medição,
  consequências). O `CLAUDE.md` fica curto — ele é carregado inteiro a cada sessão — e
  aponta para cá. A pasta `docs/` abre como vault no Obsidian; o Obsidian é só o leitor.
- **AgEnFK não adotado**: instala servidor local, quadro Kanban, hook global em
  `~/.claude/settings.json` que bloqueia edição sem card, gates de review/test por tarefa e
  telemetria ligada por padrão. Mede tokens, não economiza: cada tarefa ganha chamadas
  extras. Reavaliar só se o projeto passar a ter mais de uma pessoa e precisar de rastreio.
