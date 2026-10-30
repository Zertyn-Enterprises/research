# AGENTS.md — research

Reglas de este repo para cualquier agente (Claude, Codex, Grok, Kimi, GLM). `CLAUDE.md` es un
symlink a este fichero: no hay un segundo fichero de instrucciones. Las reglas globales y el mapa
de ficheros viven en `~/.agency/rules/core.md`; aquí va solo lo propio de este repo. El estado del
producto va en `CONTEXT.md` y el trabajo en curso en `PLAN.md`, nunca aquí.

## Qué es
Hub público de investigación y notas (IA, LLMs, inferencia local, finetuning, robótica) que además
publica `multi-agent-coding/`: un mismo juego de reglas, un suelo de seguridad y un instalador para
Claude Code, Codex y Grok Build (`README.md`). Licencia MIT.

## Comandos
Copiables tal cual, desde la raíz del repo. Los tests necesitan `jq` y `gitleaks` en el PATH.

| Para | Comando |
|---|---|
| Instalar | no aplica: sin dependencias de paquete |
| Desarrollo | `bash multi-agent-coding/doctor.sh` (solo lectura) · `bash multi-agent-coding/install.sh --dry-run` |
| Tests | `bash multi-agent-coding/tests/run-tests.sh` |
| Lint | el paso "Syntax check every script" de `.github/workflows/multi-agent-coding.yml`: `/bin/bash -n` sobre cada `*.sh` y sobre los ficheros con shebang bash de `tools/` y `githooks/` (`agentsify`, `plan-init`, `pre-commit`…) |
| Tipos | no aplica (bash) |
| Build | no aplica |

## Reglas
Convenciones que un agente no deduce leyendo el código. Cada una lleva su porqué: sin él, la
regla se rompe en el primer caso raro.

- Los scripts del kit funcionan con el bash de serie de macOS (3.2) y de Ubuntu (5) — el kit dice
  soportar ambos y CI comprueba la sintaxis con `/bin/bash` en los dos
  (`.github/workflows/multi-agent-coding.yml`).
- Un test saltado no es un pase: `run-tests.sh` sale con 3 y CI lo trata como no verde.

## Nunca
Lo que aquí no se hace aunque parezca razonable.

- Escribir con `install.sh` sin la confirmación del humano — `multi-agent-coding/AGENT-INSTALL.md`
  es el contrato del agente: diagnosticar, dry-run y preguntar antes de cada escritura (`README.md`).

## Gotchas
Sorpresas verificadas, con fecha. Borra la que deje de ser verdad.

- 2026-10-31 El repo es público en GitHub: todo lo que se commitea aquí es visible.
- 2026-10-31 `tests/test-pre-commit.sh` necesita `gitleaks`; sin él se salta y la suite sale con 3.
- 2026-10-31 CI solo corre con cambios en `multi-agent-coding/**` o en su workflow.

## Dónde mirar
- `multi-agent-coding/README.md` — qué instala el kit y sus flags; los límites, en
  `multi-agent-coding/docs/limitations.md`.
- `multi-agent-coding/tests/` — la suite (`run-tests.sh` y `test-*.sh`).
- `.github/workflows/multi-agent-coding.yml` — la matriz macOS + Ubuntu.
- `CONTEXT.md` — no existe todavía (2026-10-31); cuando exista, estado del producto y decisiones
  abiertas.
