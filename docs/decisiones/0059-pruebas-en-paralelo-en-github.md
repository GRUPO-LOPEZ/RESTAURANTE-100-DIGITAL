# ADR-0059: Pruebas en paralelo en GitHub Actions

- **Fecha:** 2026-11-18
- **Estado:** pedido y aprobado por Joaco el 2026-11-18.

## Problema

El flujo «Pruebas» corría todo en una sola máquina y en fila: lint, formato, tipos, Vitest, pgTAP y las 350 pruebas de Playwright, que van de a una porque comparten la base. Ya tardaba unas 2 horas y pasó el tope de 90 minutos: GitHub cortó la corrida del PR #86 cuando iban 240 pruebas de pantalla, todas en verde.

## Decisión

El flujo sigue llamándose «Pruebas» (`deploy-staging.yml` espera que termine en verde), pero corre en paralelo:

- **Revisiones** (lint, formato, tipos y Vitest): sin base, avisan en minutos.
- **Base de datos (pgTAP):** con su propia Supabase local.
- **Playwright en 4 tandas** (`--shard=1/4` … `4/4`):
  - cada tanda en su máquina, con su propia Supabase local recién creada y su build;
  - si una falla, las otras siguen (`fail-fast: false`), así se ven todas las fallas de una vez.
- **Reporte:** junta los 4 reportes de las tandas en uno solo (`playwright merge-reports`). Se guarda 14 días.
- **Cachés:** el navegador de Playwright y lo compilado de Next se guardan entre corridas.

## Por qué

- La espera baja de unas 2 horas a unos 40 minutos.
  - Lo que no baja es lo que cada máquina tarda en levantar la base y compilar.
- No cambia ninguna prueba.
- Como el repo es público, los minutos de Actions no se cobran.

## Opciones descartadas

- **Subir el tope a 150 minutos:** destrababa el PR, pero la espera seguía creciendo con cada módulo.
- **Varios procesos de Playwright en una misma máquina:** las pruebas comparten la base y la modifican, así que se pisarían. Aislarlas es mucho trabajo para lo que se gana.

## Riesgos

- **Una prueba que dependía de otra:** si una prueba dependía de lo que dejó otra que ahora corre en otra tanda, falla. Es una dependencia escondida que hay que arreglar, no un motivo para volver atrás.
- **El tope:** cada tanda tiene 60 minutos. Si una crece mucho, se pasa a 5 tandas.

## Lo que sigue

- **Medir la espera del código de doble verificación:** hay 121 ingresos con doble verificación en las pruebas, y cada uno puede esperar hasta 30 segundos un código nuevo. Si pesa, se ingresa una vez por rol y se reusa la sesión.
