# ADR-0021 — Rendimientos: ensayos, estándar aprobado y quién lo aprueba (etapa 2.1 B)

- **Fecha:** 2026-10-29
- **Estado:** aceptada por Joaco.
- **Base:** documento de Soy, sección 9; plan de la sesión en `C:\Users\julym\.claude\plans\silly-cuddling-ocean.md`.

## Contexto

El costo de una receta depende de cuánto rinde cada materia prima según el proceso: la papa pelada, la carne desgrasada, la pasta hervida. El documento de Soy pide:

- un **estándar aprobado** por ingrediente y proceso (decisión 5: el motor usa siempre el aprobado);
- **ensayos** que se registran en las cocinas, y que **nunca cambian el estándar solos** (prueba 25);
- **100 % sin merma** solo si alguien lo declara explícitamente;
- **nunca un rendimiento universal ni supuesto.**

## Decisión de Joaco (2026-10-29)

- **El estándar vale para todo el grupo:** la papa pelada rinde lo mismo en todas las marcas. El documento no distingue marcas.
- **Propone** cualquier persona con `yields.record` en algún lugar del grupo: el Chef de una marca o el Jefe de Cocina de un local.
- **Aprueba** un Chef Ejecutivo **de todo el grupo** (`yields.approve` de grupo), nunca quien lo propuso. Como un cambio afecta a todas las marcas, lo decide alguien con alcance en todas.
- **En los datos de prueba** se suma `chefgrupo@ejemplo.test` (Chef Ejecutivo de todo el grupo).

## Cómo quedó

- **Tablas nuevas en `catalog`:**
  - `yield_processes`;
  - `ingredient_yield_profiles`: el estándar. Es inmutable y su estado solo pasa de propuesto a aprobado y de aprobado a reemplazado;
  - `ingredient_yield_tests`: los ensayos, solo de inserción.
- **El estándar:**
  - hay uno solo vigente por ingrediente, proceso, corte y proveedor;
  - el de un proveedor manda sobre el general;
  - el limpio va de 0 a 1 y el factor de cocción, entre 0 y 10;
  - 100 % con factor 1 solo si está "declarado sin merma".
- **Aprobación:** tipo nuevo `catalog.approve_yield_profile`, que aplica `catalog.apply_yield_profile`. La solicitud es de alcance grupo, así que `workflow.decision_blocker` exige `yields.approve` para todo el grupo, sin cambios en esa regla.
- **Para el motor (2.3):** `catalog.standard_yield` devuelve el estándar aprobado o `undefined` (RENDIMIENTO NO DEFINIDO). Nunca supone 100 %.
- **Para la ficha:** `catalog.yield_summary` muestra el estándar, el promedio de los ensayos, la diferencia y si hay propuestas en revisión. Corre con permisos propios para poder contar las propuestas pendientes, que un Jefe de Cocina no puede ver, y controla él mismo que la sesión vea el catálogo del grupo. Solo informa la cantidad, nunca el contenido.

## Cambio de seguridad

**`workflow.check_apply_function`** solo aceptaba funciones `apply_*` de `core` y `org`. Ahora acepta también `catalog`, con la misma firma obligatoria: `(uuid) returns void`, nombre `apply_*`. La prueba `150` controla que siga rechazando otros esquemas y otros nombres.

## Lo que queda para después

- **Fotos de los ensayos:** se suman en 2.2, cuando exista el bucket de Storage de recetas.
- **Pantalla de procesos:** por ahora los carga el seed y se crean por función (`catalog.create_yield_process`, que pide `yields.approve` de grupo). La pantalla llega con la configuración.
- **Propuestas rechazadas o retiradas:** el perfil queda como `draft` sin uso. No se muestra en la ficha (solo se cuentan las pendientes) y el motor nunca lo usa.

## Revisiones (2026-10-29)

**`security-auditor`: apto, sin graves. `db-reviewer`: sin graves. `ui-reviewer`: sin graves.**

**Resuelto en este PR:**

- **Una propuesta vieja ya no pisa a una más nueva** (revisiones de base y de seguridad, M1):
  - hay una sola propuesta pendiente por ingrediente, proceso, corte y proveedor;
  - la propuesta guarda cuál era el estándar vigente, y `apply_yield_profile` no aplica si cambió (o si la materia prima ya no está vigente).
- **La ficha no muestra propuestas rechazadas ni retiradas**, y no usa procesos borrados.
- **Pruebas que faltaban (base, M3; seguridad, m7):**
  - transiciones prohibidas;
  - no nacer aprobado con una persona en la sesión;
  - no borrar un estándar;
  - un rechazo deja el estándar como estaba;
  - auditoría de ensayos y procesos;
  - quién crea procesos;
  - fecha futura.

  La 150 pasó de 43 a 61 pruebas.

- **Un estándar solo nace aprobado sin una persona en la sesión** (seed y migraciones). Antes alcanzaba con el origen del cambio, que es informativo y nunca decide permisos. El borrado del estándar también quedó congelado.
- **El ayudante de permisos pasó a `core`**, como `core.has_permission_in_group_any_scope`, de la familia `has_permission_*`. Una prueba controla que ninguna política RLS lo use.
- **Al registrar un ensayo:**
  - la base pone quién y cuándo lo registró;
  - proceso y proveedor tienen que estar vigentes;
  - la fecha no puede ser futura;
  - los datos mal escritos dan un mensaje en español.
- **Pantalla:**
  - la bandeja y el historial muestran "78,5 %" y "se expande ×2,5", no "0.785";
  - la casilla "No tiene merma" se valida igual que en la base (nueva `FormCheckbox`), con un texto que dice cuándo es obligatoria;
  - el ensayo tiene corte;
  - se aclara que los pesos suman todas las muestras;
  - la diferencia se lee "3,0 puntos menos que el estándar";
  - hay estados vacíos de procesos y de rendimientos.

**Decisiones de Joaco (2026-10-29), a pedido de las revisiones:**

1. **El promedio de los ensayos se pondera por la cantidad de muestras:** "mientras más tienen, más pesan" (base, m10). 77 % con 3 muestras y 74 % con 2 dan 75,8 %, no 75,5 %. Lo prueba la 150.
2. **El Chef Ejecutivo de todo el grupo no necesita doble verificación**, aunque apruebe estándares de todo el grupo (seguridad, nota). El nivel 5 sigue sin exigirla, como dice el Módulo Maestro.

**Para más adelante:**

- **Motor (2.3):** `standard_yield` respeta RLS, así que sin permiso responde `undefined`, igual que "no hay estándar". El motor va a correr con sus propios permisos y un control explícito, y así se distinguen (base, m7).
- **Propuestas rechazadas o retiradas:** se siguen leyendo por la API con `catalog.view`. No son datos de costo; si hiciera falta se filtran en la política (seguridad, m4).
- **Ensayos:** los pesos van siempre en gramos (lo dice el comentario de cada columna) y `tested_on` es una fecha de calendario (`date`), como `opened_on`.
- **Muchas propuestas:** cualquiera con `yields.record` en un local puede proponer para todo el grupo, y cada propuesta avisa a los aprobadores. Lo limita la regla de una pendiente por clave. Si molesta, se revisa.

## Consecuencias

- **La prueba de la Fase 1 que cuenta personas** pasó de 20 a 21 (`050`) y de 12 a 13 (`040`), a propósito.
- **En `140`**, el catálogo pasa a tener 13 tablas, y la regla de columnas de control excluye los ensayos, que son solo de inserción (lo prueba `150`).
- **La bandeja de aprobaciones** muestra el tipo "Rendimiento estándar" con el antes y el después (materia prima, proceso, corte, limpieza y factor).
