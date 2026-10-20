# Sistema Operativo Gastronómico — Grupo LF

Apps, agentes y tableros para que cada restaurante de Grupo LF recolecte sus datos y los convierta en tableros de control.

- Reglas del proyecto: [docs/prompt-maestro.md](docs/prompt-maestro.md) y [CLAUDE.md](CLAUDE.md)
- Estado actual: [docs/estado.md](docs/estado.md)
- Decisiones de arquitectura: [docs/decisiones/](docs/decisiones/)

## Requisitos

- Node.js 24 LTS y npm
- Docker Desktop (con WSL 2 en Windows), prendido
- Git

La CLI de Supabase viene como dependencia del proyecto: no hace falta instalarla aparte. Se usa con `npx supabase ...`.

## Primeros pasos

```bash
npm install
npx playwright install chromium   # una sola vez
npm run db:start                  # levanta Supabase local (Docker)
npm run db:reset                  # aplica migraciones y seed desde cero
npm run dev                       # http://localhost:3000
```

## Comandos

| Comando | Qué hace |
|---|---|
| `npm run dev` | App en modo desarrollo |
| `npm run lint` | Revisa el código con ESLint |
| `npm run typecheck` | Revisa los tipos de TypeScript |
| `npm run format` | Formatea el código con Prettier |
| `npm run test:unit` | Pruebas de lógica (Vitest) |
| `npm run test:db` | Pruebas de base de datos (pgTAP) |
| `npm run test:e2e` | Pruebas de flujos y accesibilidad (Playwright + axe) |
| `npm run test` | Todo lo anterior, en orden |
| `npm run db:start` / `db:stop` | Prende / apaga Supabase local |
| `npm run db:reset` | Recrea la base local desde las migraciones |
| `npm run db:types` | Regenera `lib/database.types.ts` desde la base |

## Ambientes

Claude Code y Joaco trabajan solo en **desarrollo** (Supabase local con datos ficticios). Prueba y producción solo se tocan desde GitHub Actions. Ver [.claude/rules/security.md](.claude/rules/security.md).
