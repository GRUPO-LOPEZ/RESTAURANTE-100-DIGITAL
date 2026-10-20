---
name: nuevo-modulo
description: Receta para construir un módulo completo de Grupo LF (recetario, costos, compras, etc.) siguiendo el método de 6 pasos, de la base a la pantalla y la entrega. Usala al empezar cualquier módulo nuevo.
---

# Construir un módulo nuevo

Un módulo se construye siempre con el mismo ciclo. **Ningún paso se saltea.** El Módulo 0 (identidad, permisos y auditoría) tiene que estar aprobado antes de empezar cualquier otro.

## 1. Explorar

- Leé `docs/estado.md`, el plan de la fase, `docs/modulos/` y las migraciones existentes.
- Listá los conceptos del módulo y con qué tablas existentes se relacionan.

## 2. Planificar (modo plan; Joaco aprueba)

El plan incluye:

- **Objetivo** en una frase que Soy entienda.
- **Tablas** nuevas o cambiadas, por esquema.
- **Permisos** nuevos (`modulo.accion`) y qué roles los reciben. Si no está definido, **preguntá**.
- **Flujos de aprobación** y versiones, si el módulo los tiene.
- **Pantallas:** qué pregunta responde cada una.
- **Pruebas:** pgTAP, Vitest y Playwright.
- **Riesgos y preguntas abiertas.**
- Una rama: `feat/<modulo>-<tarea>`.

## 3. Base primero

- Por cada tabla, la skill `nueva-tabla`.
- Funciones SQL transaccionales para las escrituras críticas (dato + auditoría + recálculo).
- Vistas sin columnas sensibles (por ejemplo, la receta sin precios para cocina).
- Vistas en `reporting` para lo que vayan a leer los tableros.
- `npm run db:reset` y `npm run test:db` en verde antes de pasar a la interfaz.

## 4. Interfaz

- Solo componentes de `components/ui/` y tokens de `app/globals.css`. Reglas en `.claude/rules/design.md`.
- Formularios con React Hook Form + Zod; el mismo esquema valida en el servidor.
- Datos con TanStack Query, listas paginadas, estados de vacío, carga y error.
- Celular primero.

## 5. Verificar

- `npm run test` completo en verde (o el subagente `test-runner`).
- Subagentes `db-reviewer`, `security-auditor` y `ui-reviewer`, sin hallazgos graves abiertos.
- Pantalla real en celular y en computadora, con capturas.
- `explain analyze` de las consultas de tablero (menos de 300 ms).

## 6. Entregar

- PR chico con: resumen en simple para Soy, capturas, pruebas ejecutadas (resultado literal) y riesgos pendientes.
- `docs/modulos/<nn>-<modulo>.md` actualizado (qué hace, tablas, permisos, diccionario de datos).
- ADR en `docs/decisiones/` si hubo una decisión de arquitectura.
- `docs/estado.md` actualizado.
- Checklist de la definición de terminado de `CLAUDE.md`, completa.
