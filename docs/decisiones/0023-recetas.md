# ADR-0023 — Recetas versionadas (etapa 2.2 A)

- **Fecha:** 2026-10-29
- **Estado:** aceptada por Joaco (plan de la sesión aprobado).
- **Base:** documento de Soy, secciones 3, 11, 13, 14 y 17; plan de la Fase 2 (`docs/fases/fase-2-plan.md`).

## Contexto

- **La Fase 2 cierra** cuando el Controller valida el costo de 20 recetas reales. Para eso primero tienen que existir las recetas: la 2.2 es la etapa que las construye.
- **La 2.2 se parte en dos:**
  - **2.2 A (esta):** recetas con componentes, procedimiento y tiempos, versiones, aprobación, vista de cocina, alérgenos y asignación a locales.
  - **2.2 B:** subrecetas, variantes, cocina central y Pariggi. Dependen de las decisiones 1 y 6 de Soy; con ellas van los casos 10, 23 y 26.
- **La 2.2 A va en tres PR:** (1) base, (2) pantallas, (3) fotos y retiro del documento de ensayo de la Fase 1.

## Decisiones de Joaco (2026-10-29)

1. **Aprobar = publicar.** Se pide la revisión y quien tiene `recipes.publish` en el alcance de la receta la aprueba en `/aprobaciones`. Queda vigente en el acto y la anterior pasa a archivada. Quien pidió la revisión nunca la aprueba (`workflow.decision_blocker`).
2. **Alcances de la 2.2 A:** maestra del grupo, de marca y de local. Variante y cocina central llegan en la 2.2 B.

## Cómo quedó (PR 1, base)

- **Migración** `20261101120000_recipes.sql`, con siete tablas en `recipes`:
  - `recipe_categories`;
  - `recipes`, la identidad. El código y el alcance no cambian nunca;
  - `recipe_versions`, la fórmula. Usa el trigger de versiones de la Fase 1: nace en borrador, desde aprobada no cambia y no se borra. Hay una sola vigente y una sola abierta (borrador o en revisión) por receta;
  - `recipe_components`, `recipe_steps` y `recipe_step_dependencies`: solo cambian en un borrador y nunca se borran físicamente. Al guardar, las líneas anteriores quedan con borrado lógico;
  - `recipe_assignments`, qué receta usa cada local, sin copiarla.
- **Sin valores económicos en `recipes`:** los costos van en `costing` (2.3). Una prueba recorre el esquema y falla si aparece una columna de costo o precio (caso 24).
- **Quién ve qué (RLS):**
  - la versión vigente la ve quien tiene `recipes.view` en el alcance de la receta. Las maestras del grupo también las ve quien ve toda una marca del grupo, para poder asignarlas. Y cualquier receta la ve quien tiene `recipes.view` en un local al que está asignada;
  - una receta sin versión vigente no se ve, ni siquiera su nombre, salvo para quien la trabaja;
  - los borradores, las revisiones y la historia los ve quien trabaja la receta en su alcance (`recipes.draft`, `review` o `publish`);
  - las asignaciones, solo las de los locales que la persona ve;
  - las políticas usan conjuntos (`viewable_recipe_ids`, `workable_recipe_ids`, `visible_version_ids`), armados con `core.permitted_*_ids`, que se calculan una vez por consulta. Las escrituras preguntan por un solo lugar con `recipes.allowed`, que usa `core.has_permission*`. La lógica de permisos no se duplica.
- **Versiones, líneas, pasos y dependencias llevan la marca y el local de su receta** (los copia un trigger). Así la auditoría queda con el alcance de la receta: quien audita un local ve los cambios de la fórmula de sus recetas.
- **Las escrituras devuelven `{"result": ...}`, como las de la Fase 1.** Un rechazo por permiso pasa por `core.deny` y queda en el registro de seguridad (caso 11). Si cortaran con un error, el registro se desharía con la transacción.
- **Una cantidad tiene que poder pasarse a la unidad de la materia prima** (`catalog.to_base_quantity`). Si no, el motor de costos no podría calcularla; el mensaje dice qué conversión falta.
- **Rechazos y retiros:** una versión en revisión cuya solicitud se rechazó o se retiró vuelve sola a borrador la próxima vez que alguien la toca. Solo quien pidió la revisión la retira (regla de `workflow.cancel_request`).
- **Lectura:**
  - `critical_path`: el tiempo total es el camino crítico entre pasos que se esperan (caso 22: 90 minutos);
  - `version_allergens`: por alérgeno, el peor estado entre las materias primas. Si alguna no tiene dato, "no verificado";
  - `version_diff`: las diferencias contra la versión anterior, que también viajan en la solicitud de aprobación;
  - `kitchen_card`: la ficha de cocina, sin ningún valor económico;
  - `catalog.ingredient_usage`: "dónde se usa" una materia prima.
- **`kitchen_card` y `version_allergens` corren con permisos propios:** la Cocinera no ve el catálogo, pero tiene que leer los nombres de los ingredientes y sus alérgenos. Las dos controlan antes que la sesión vea la receta.
- **El esquema `recipes` se expone por la API** (`supabase/config.toml`, `api.schemas`).
- **Seed:** 5 categorías y 20 recetas DEMO (5 maestras, 6 de Demo Pastas, 6 de Demo Parrilla, 2 de Demo Café y 1 de local), con sus pasos y asignaciones. La bolognesa reproduce el caso 22. Todas publicadas salvo el risotto, que queda en borrador.

## Cambio de seguridad

**`workflow.check_apply_function`** aceptaba funciones `apply_*` de `core`, `org` y `catalog`. Ahora acepta también `recipes`, con la misma firma obligatoria: `(uuid) returns void` y nombre `apply_*`. La prueba `170` controla que una función de `recipes` que no es `apply_*` siga rechazada.

## Revisiones (2026-10-29)

**`security-auditor`: apto, sin graves; 3 medios. `db-reviewer`: 2 graves y 6 medios. Todos resueltos en este PR, salvo lo que es decisión de negocio (abajo).**

**Graves (base):**

- **G1, las políticas no escalaban:** llamaban funciones por cada fila. Con 2.000 recetas, la lista de la Cocinera tardaba 2,7 segundos. Ahora usan conjuntos calculados una vez por consulta: la prueba `175` (2.000 recetas y 20.000 líneas) mide 7 a 31 ms en cada lectura.
- **G2, el camino crítico crecía exponencialmente:** la consulta recursiva armaba todos los caminos posibles; con 22 pasos tardaba 3 segundos. Ahora guarda el máximo por paso (pasos × dependencias). La `170` prueba 100 pasos donde cada uno espera a todos los anteriores, en menos de medio segundo.

**Medios:**

- **Nada se escribe antes del control de permiso** (seguridad y base, M1). Una versión rechazada volvía a borrador antes de controlar quién llamaba. Ahora lo hace `recipes.open_draft`, después del permiso.
- **La historia solo para quien trabaja la receta** (seguridad, M2): `version_diff` ya no le muestra la versión anterior a quien solo ve la vigente.
- **La solicitud de aprobación lleva un resumen, no la fórmula** (seguridad, M3). La ve cualquiera con `approvals.view` en el alcance (por ejemplo, Compras o el Auditor). Ahora lleva cuántas líneas se agregan, quitan o cambian; el detalle lo lee quien trabaja la receta.
- **Dos personas editando el mismo borrador** (base, M2): las escrituras aceptan la marca de la última lectura (`p_expected_updated_at`) y rechazan si otra persona lo cambió. Guardar líneas o pasos también marca la versión como cambiada.
- **Las líneas copiadas se vuelven a validar al pedir la revisión** (base, M3): materia prima vigente y activa, unidad convertible y rendimiento estándar vigente.
- **Auditoría con el alcance de la receta** (base, M4; seguridad, m3): descripto arriba.
- **Pruebas que faltaban** (base, M6): RLS de líneas, pasos y asignaciones; categorías; responsable técnico; receta archivada; rechazo, retiro y edición concurrente; revalidación; 100 pasos; volumen. La `170` pasó de 75 a 97 pruebas, y se sumó la `175`.

**Menores resueltos:** una receta sin vigente no muestra su nombre; asignaciones solo de locales propios; no se edita, asigna ni pide revisión de una receta archivada; el responsable técnico tiene que ser del grupo; la versión anterior es de la misma receta; una solicitud nunca queda colgada de un borrador; el orden de las líneas del seed es fijo; quien asigna también tiene que ver la receta.

**Para que decida Joaco:**

1. **Separación de funciones** (base M5, seguridad m6). Hoy la base cumple "aprueba alguien distinto de quien pidió la revisión", como dice `security.md`. Pero quien redactó el borrador puede aprobarlo si la revisión la pidió otra persona: por ejemplo, la Chef escribe, la Directora pide la revisión y la Chef publica. ¿Hay que excluir también a quien editó el borrador?
2. **Traspaso de locales** (base, menor 10). `org.apply_transfer` crea un local nuevo. ¿Las recetas de local y las asignaciones del local viejo pasan al nuevo?

**Para más adelante:** la fecha de "hoy" usa siempre el huso de Buenos Aires, aunque `org.restaurants` tiene `time_zone` (se revisa si se abre un local en otro huso). La descripción del permiso `recipes.review` dice que pedir revisión es parte de `recipes.draft`; hoy todos los roles tienen los dos, y se alinea cuando se toquen los permisos.

## Lo que queda para después

- **2.2 B:** subrecetas (con la regla de ciclos de hasta 10 niveles), variantes, cocina central y Pariggi.
- **Una versión en revisión en el seed**, para ver la bandeja apenas se abre la demo: el seed no puede pedir aprobaciones como una persona. La crean las pruebas de pantalla.
- **Comentarios, etiquetas y ensayos de rendimiento de una receta** (`recipe_comments`, `recipe_tags`, `recipe_yield_tests`): llegan con la pantalla que los usa.

## Consecuencias

- **La prueba `000`** suma `recipes` a los esquemas que usa `authenticated`, y la `050`, sus funciones y tablas, a propósito.
- **El diccionario del recetario** (`docs/modulos/02-recetario-diccionario.md`) pasa a incluir `recipes`.
