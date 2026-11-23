# Contribuir a KiuPop

## Ramas
`main` siempre desplegable y verde. Todo entra por PR.
| Prefijo | Uso |
|---|---|
| `feat/<tema>` | funcionalidad (`feat/store-onboarding`, `feat/catalog`, `feat/ai-assistant`) |
| `fix/<tema>` | corrección |
| `docs/<tema>` | documentación |
| `chore/`, `ci/` | mantenimiento y CI |

## Trabajo en paralelo con Claude Code
Una sesión de agente = un worktree = una rama. Nunca dos agentes escribiendo en el mismo directorio.
```bash
git fetch origin
git worktree add ../kiupop-catalog -b feat/catalog origin/main
cd ../kiupop-catalog && claude
# al terminar y mergear:
git worktree remove ../kiupop-catalog
```
Todos los worktrees comparten el mismo stack Docker (`kiupop`). Si dos personas necesitan bases distintas en la misma máquina, usa otro `.env` con otros puertos y `docker compose -p kiupop-<tema>`.

## Commits
Conventional Commits en inglés o español, en imperativo: `feat(api): add stores module`, `fix(web): handle empty catalog`.
Commits pequeños que compilen. Sin force push a ramas compartidas.

## Pull requests
1. `make lint && make test` (y `make smoke` si tocaste backend o infra).
2. Abre el PR con la plantilla y la evidencia de las pruebas.
3. CI (`Go`, `Flutter`, `Infra`, `Secret scan`) debe estar en verde.
4. Al menos una aprobación. Las rutas sensibles (CODEOWNERS) requieren al lead.
5. Squash merge. Borra la rama.

## Protección de `main` — estado real
La organización `kiuvy-universe` está en el plan **GitHub Free**. En repos **privados** de ese plan, GitHub **no permite** reglas de protección de rama ni rulesets (la API responde 403 «Upgrade to GitHub Pro or make this repository public»). Por lo tanto, hoy:
- CODEOWNERS **solo asigna revisores automáticamente**. No bloquea merges.
- «PR obligatorio», «1 aprobación», «checks requeridos» y «sin force push» son **acuerdos del equipo**, no controles técnicos.
- Cuando la org pase a Team (o si se decide), aplicar el ruleset documentado en `docs/development/main-ruleset.json` con
  `gh api -X POST repos/kiuvy-universe/kiupop/rulesets --input docs/development/main-ruleset.json`.

## Revisión
Quien revisa verifica: aislamiento de Kiuvy, que no haya secretos, el contrato actualizado, las pruebas, los estados de UI (cargando, éxito, error, vacío) y que no se sumen dependencias innecesarias.
