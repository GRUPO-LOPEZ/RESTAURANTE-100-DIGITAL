# ADR-0035: Aviso de rendimiento

- **Fecha:** 2026-11-09
- **Estado:** aceptada. Joaco aprobó el plan.
- **Migraciones:** `20261122120000_yield_alerts_kind.sql` y `20261122120100_yield_alerts.sql`.

## Contexto

Soy pidió que se avise cuando las mediciones de rendimiento se desvían del estándar aprobado, para controlar las producciones (ADR-0024 punto 6, ADR-0026 punto 6, ADR-0030 punto 5). Ya había decidido tres cosas:

- el umbral se carga a mano, por ejemplo con la inflación del mes;
- va en la configuración del grupo, junto con la de precios;
- avisa al Chef y al Controller.

## Decisiones

- **Qué se mide:** el desvío relativo de cada ensayo contra **el estándar que usa el costo** (`catalog.approved_yield`, decisión de Joaco del 2026-11-09). Es el de la misma materia prima, proceso y corte, y el del proveedor si tiene uno propio; si no, el general. Así avisa justo cuando el desvío pega en el costo.
  - **Limpieza:** limpio/bruto ÷ estándar − 1.
  - **Cocción:** después/antes ÷ factor − 1.
  - **Ejemplo:** con un estándar de 80 % y un umbral de 10 %, avisa por debajo de 72 % o por encima de 88 %.
  - Avisa si cualquiera de los dos supera el umbral. Justo en el umbral no avisa.
- **Se mide cada ensayo, no el promedio:** es lo que pasó en esa producción. La ficha de la materia prima, en cambio, marca cuándo el promedio de los ensayos pasa el umbral.
- **Sin estándar aprobado, no hay aviso:** no hay contra qué comparar.
- **Umbral de fábrica: 10 %** (Joaco, 2026-11-09).
  - Va en `costing.price_settings.yield_alert_pct`.
  - Lo cambia quien tiene `prices.configure` (hoy Dirección General), en `/configuracion/precios`, con `costing.update_yield_alert`. Esa función cambia solo el umbral: no pisa el porcentaje ni los días de precios que otra persona haya guardado al mismo tiempo. `update_price_settings` también deja como estaba lo que llega vacío.
  - Queda auditado con su motivo.
- **A quién avisa: un permiso nuevo, `yields.alerts`** (Joaco, 2026-11-09).
  - Lo reciben quienes tienen ese permiso y `catalog.view` en el local del ensayo: el aviso nombra la materia prima y sus rendimientos. Quien cargó el ensayo no se avisa a sí mismo.
  - Lo tienen el Chef y el Controller, como pidió Soy.
  - **También lo tienen el Director de marca y Dirección General** (Joaco, 2026-11-09). La base no deja dar un permiso que uno no tiene, y ellos son quienes dan y aprueban los roles de Chef y Controller. Sin el permiso, ya no podían hacerlo, así que ellos también reciben el aviso.
  - Desde el panel de roles se puede cambiar, con la aprobación que ya pide la matriz.
- **El aviso va en la misma transacción que el ensayo** (`catalog.record_yield_test`). Si el aviso falla, el ensayo se guarda igual: el aviso no puede frenar la carga en la cocina.
- **El texto del aviso, en palabras de cocina:** «Limpieza: 50 % contra 80 % del estándar (37,5 % menos). En Demo Pastas Centro, el 09/11/2026. Avisa con un desvío de más de 10 %.»
- **Dónde se ve:** en `/aprobaciones`, con los avisos de recetas y costos, marcado como «Rendimiento desviado». El aviso lleva a la ficha de la materia prima.

## Pruebas

- **pgTAP `244_yield_alerts`:**
  - quién recibe el aviso: por rol, por local y por marca;
  - quien carga el ensayo no se avisa;
  - dentro del umbral, justo en el umbral y sin estándar no hay aviso;
  - cocción;
  - texto del aviso;
  - cambio de umbral, con su auditoría y su rango.
- **Vitest:** el desvío y el formulario.
- **Playwright:** el Jefe de Cocina carga un ensayo, el Chef recibe el aviso y ve la ficha marcada, y Dirección cambia el umbral.

## Riesgos

- Un aviso por ensayo desviado: si el umbral queda bajo, pueden ser muchos. Si molesta, se agrupan por día.
- Un error de tipeo en un ensayo dispara un aviso falso. Es justamente lo que el Chef tiene que mirar.
- Si el aviso falla, el ensayo se guarda y queda solo una advertencia en el registro de la base, sin el detalle del error. No hay una tabla de fallos.
- **Para Joaco (revisión de seguridad):** el Controller figura como «nunca gramajes», pero desde la etapa 2.1 B puede leer los gramos de los ensayos (piden `catalog.view`). El aviso le muestra porcentajes, no gramos. Si «nunca gramajes» incluye los ensayos, se cierra en un PR aparte.
