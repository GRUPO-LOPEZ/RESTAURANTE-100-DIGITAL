# Módulo 3 «Precios y Carta»: rentabilidad (pedido de Soy, 2026-11-23)

Nueve prompts, en orden, **un PR cada uno**. El documento de Soy está completo en `docs/fases/fase-4-precios-y-carta.md`, y la API de TapTapChef en `docs/fases/fase-4-taptapchef-api.md`: hay que leer los dos enteros antes del Prompt 0. Soy lo llama **Módulo Precios y Carta** y con él cierra la órbita **Rentabilidad** (Recetario y costos → Compras y facturas → Precios y Carta). En la hoja de ruta es la **Fase 4**. Sus «fases» internas pasan a llamarse **etapas 4.1 a 4.4**, para no confundirlas con las del proyecto.

**Donde el documento de Soy y este archivo digan cosas distintas, manda este archivo.** El documento se escribió sin ver el repositorio: usa nombres `pc_` en castellano, campos que ya existen con otro nombre y una fase de IA que el proyecto deja para la Fase 5. Acá está cómo se adapta, con las decisiones que Soy ya tomó.

## Decisiones de Soy (2026-11-23)

1. **Una sola entrada «Precios y Carta» en el menú lateral, con pestañas adentro** (como dice su documento, sección 11). Cada pestaña igual cumple los 15 criterios de `design.md`.
2. **TapTapChef tiene API** y es la fuente de ventas. Ver «TapTapChef: qué dice la API y qué cambia».
3. **El precio de carta lo fija la marca, y un local puede tener el suyo** (por ejemplo, un shopping más caro). Es la misma herencia que los precios de compra (`costing.price_records`: grupo → marca → local).
4. **Propone el Director de Marca o el Controller; aprueba Dirección General**, que tiene que ser otra persona que quien propuso. La base lo valida.
5. **No se crea el rol «encargada de salón»:** todo lo que el documento le da a la encargada (mapeos faltantes, fugas por descuento, platos a empujar) lo hace el **Gerente** del local (`restaurant_manager`).
6. **Avisos e informes por mail y por los avisos del sistema.** WhatsApp automático, después (la API de WhatsApp Business se paga por mensaje y necesita un número dado de alta).

## Mejoras aprobadas por Soy (2026-11-23)

1. **Repreciación en planilla.** En la pestaña Platos, el precio sugerido al lado del actual; el precio se edita en la celda, un contador junta los cambios y «Enviar a aprobación» los manda juntos, con motivo (el patrón de la matriz de permisos, ADR-0039). Dirección General aprueba el lote o plato por plato.
2. **Aviso al dar conforme una factura.** Si una factura conforme sube un costo, Dirección recibe en el momento «estos N platos perdieron margen», con el precio sugerido de cada uno. Se engancha al evento `cost.changed` que ya existe; un solo aviso por factura, no uno por plato.
3. **Prueba para Soy en staging,** como en las Fases 2 y 3: platos, precios y un mes de ventas inventadas en Demo Pastas, con su guía de recorrido. Las ventas inventadas entran **por el mismo adaptador de TapTapChef** (archivos JSON con la estructura real y datos ficticios), así la prueba también prueba la integración.
4. **«Precio y margen» en la ficha de receta** de tipo plato, con enlace a su ficha en Precios y Carta.
5. **Carta para imprimir:** PDF con la versión de la carta y quién la aprobó (criterio 14). **Soy pide sumar en todo el proceso el nombre de fantasía y la descripción del plato**, que son los que se usan para armar el menú: el nombre de fantasía es el que figura en TapTapChef y en la carta; el nombre de la receta es el técnico de cocina y no se muestra al cliente.
6. **Planilla de políticas en el boceto:** Soy completa food cost máximo, contribución mínima y deriva máxima por rubro de menú, y marca los platos emblema de cada marca. Con eso se cargan las políticas iniciales sin inventar valores.

Al leer la API de TapTapChef, Soy aprobó cuatro más (están en la sección de TapTapChef):

7. **CM por cubierto desde la etapa 4.2**, con los `comensales` de cada ticket (punto 7).
8. **Control de cada turno** contra el informe de cierre de TapTapChef (punto 8).
9. **Aviso si cambia el nombre en TapTapChef** y deja de coincidir con el nombre de fantasía de la carta (punto 10).
10. **Comisión real por medio de pago** calculada con `cobros`, después de la 4.2 (punto 11).

El boceto aprobado está en `docs/prompts/2026-11-23-boceto-precios-y-carta/`.

## Lo que ya existe y se reutiliza (no se duplica nada)

- **Plato (producto comercial)** = una receta de tipo `dish` (`recipes.recipe_type`) **más** un registro nuevo de carta que le agrega lo comercial: nombre de fantasía, descripción, estado comercial, etiquetas. La receta sigue siendo del Recetario. **No se crea `pc_platos` con nombre, alérgenos y sin TACC propios:** los alérgenos y el sin TACC salen de la receta publicada (criterio 11: lo que el sistema ya sabe no se vuelve a pedir).
- **Categorías** = los rubros de menú que ya existen (`recipes.recipe_categories`, clase `menu`: PL-ENT Entradas, PL-PAS Pastas, PL-RIS Risottos y arroces…). No se crean categorías nuevas.
- **En qué local se vende un plato** = la asignación de recetas que ya existe (`recipes.recipe_assignments`). Un plato sin receta asignada al local no puede estar en la carta de ese local.
- **Costo del plato** = `costing.recipe_cost_current` (costo vigente por receta y local, por porción) y su historia en `costing.recipe_cost_snapshots`. **No se crea `pc_costos_snapshot`.** El «costo al fijar el precio» se guarda en el precio como referencia a la foto (`recipe_cost_snapshots`) y su valor.
- **Costo de reposición** = ya es así: el costo usa el último precio aprobado o de factura conforme (ADR-0029, ADR-0058).
- **Confiabilidad del costo** = `verified` < `estimated` < `stale` < `incomplete` (ADR-0032). El `DATO_INSUFICIENTE` del documento es `incomplete` (o el costo vacío): el margen y el food cost quedan vacíos con el motivo, nunca en $ 0 ni en 0 % (`components/ui/metric.tsx`, «Métricas confiables» de `design.md`). Con `stale`, el número se muestra en «Atención».
- **IVA** = depende de la razón social del local (`org.legal_entities.vat_condition`, ADR-0029). Responsable inscripto: precio neto sin IVA contra costo sin IVA. Monotributo o exento: el precio de carta es el que cobra (no hay IVA que restar) y el costo va con IVA, como ya lo da el motor. **Nunca se mezclan bases.** Un local sin razón social da `missing_legal_entity`, como hoy.
- **Aprobaciones** = `workflow.approval_workflows` / `approval_requests` / `approval_decisions`, con `approver_role_codes` y `excluded_approvers` (ADR-0008, ADR-0013). **No se crean campos `aprobado_por` propios.** El precio entra recién al aplicarse la aprobación (función `apply_*`, como `costing.apply_price`), con `valid_from`: un precio con fecha futura no vale antes (caso 11).
- **Avisos** = `core.notifications` (tipos nuevos del enum) y mail por el patrón de `purchasing.outbound_messages` (canal `email`). Las alarmas del módulo se guardan en una tabla del módulo porque tienen estado (abierta, vista, asignada, pospuesta con motivo, resuelta), pero **se entregan** por los avisos de siempre (la campana) y por mail.
- **Eventos** = `integration.integration_outbox` (`cost.changed`, `price.approved`, `recipe.published`). La deriva y el aviso de la mejora 2 salen de `cost.changed`.
- **Simulador** = amplía los escenarios de costo que ya existen (`costing.cost_scenarios` y `cost_scenario_overrides`, ADR-0032): hoy simulan precio de compra, rendimiento y gramaje; se suman precio de venta, volumen y comisiones. **No se crea un segundo simulador.**
- **Códigos** = `catalog.code_series` (ADR-0041). Código automático y correlativo para platos de carta y cartas (criterio 10).
- **Fotos** = las de la receta (`recipes.recipe_media`). La carta usa la foto principal del plato; no se sube dos veces.
- **Tareas programadas** = `pg_cron`, como el sellado de la auditoría.
- **Importes ocultos** = `core.hide_costs` esconde las columnas con `price` o `amount` en el nombre a quien no ve costos. **Cuidado:** el precio de venta lo ven roles que no ven costos (por ejemplo, Compras no ve márgenes pero el precio de carta no es secreto). El plan define qué columnas se llaman `_price`/`_amount` (las de costo y margen) y cuáles no (el precio de carta).
- **Pantallas** = los tipos A, B y C de `design.md`, «Pantallas de carga sin scroll», `Metric`, `Tile`, `ShortList`, `SegmentedField`, `ToggleField`, `DataTable scroll`, la barra fija con contador y motivo, y el selector global de local.

## Nombres: de `pc_` al sistema

El documento usa `pc_…` en castellano. El proyecto usa esquemas por tema, nombres en inglés, plural, `group_id` / `brand_id` / `restaurant_id` y las columnas de control por trigger (`database.md`). Propuesta (el plan del Prompt 0 la confirma o la corrige):

- **Esquema `menu`** (carta y precios): `menu_items` (plato de carta), `menu_item_tags`, `menu_item_components` (combos y menú ejecutivo), `sales_channels` y `channel_terms` (comisiones, packaging e IIBB por local, con vigencia), `sale_prices` (solo de inserción), `pricing_policies`, `menus`, `menu_versions`, `menu_version_items`, `alerts`, `decisions`, `objectives`, `menu_engineering_results` (la matriz guardada por período).
- **Esquema `sales`** (ventas que llegan del POS): `pos_stores` (qué ID de tienda de TapTapChef es cada local), `pos_sync_requests` (la cola), `pos_raw_payloads` (lo que devolvió la API, tal cual, en `jsonb`; no se expone por la API de Supabase), `pos_shifts` (turnos), `pos_tickets`, `pos_ticket_lines`, `pos_products` (el maestro `productosweb`), `pos_mappings` (ítem de TapTapChef → plato de carta).
- **Datos del local para el CM por cubierto** (costos fijos del mes, cubiertos esperados, utilidad objetivo): en la ficha del local del Panel de control, con historia por mes, no en columnas sueltas de `org.restaurants`.
- **`pc_costos_snapshot`, `pc_sync_log` y las categorías no se crean** (ver arriba). `pc_escenarios` es `costing.cost_scenarios` ampliado.
- Dinero en `numeric(18,4)`; porcentajes en `numeric(9,6)` como fracción (0,30 = 30 %). Estados como enum documentados. Todo con RLS, auditoría y `comment on` en español.
- **Solo de inserción** (caso 13): `sale_prices`, `channel_terms`, `pos_raw_payloads`, `pos_ticket_lines`, `menu_engineering_results`, `decisions` y el historial de `alerts`. Una corrección es un registro nuevo que anula al anterior; un trigger rechaza `update` y `delete`.

## Quién es quién (roles de la base)

El documento habla de dirección, gerencia, controller, responsable de costos, compras, chef, encargado de salón y consulta. En la base son estos roles; Joaco lo confirma en el plan:

- **Dirección** = `general_management`: ve todo, **aprueba precios** y publica cartas.
- **Director de Marca** = `brand_director`: ve su marca, **propone precios**, arma cartas y decisiones.
- **Controller** = `controller` (es el «responsable de costos»): ve todo, **propone precios**, configura políticas y canales.
- **Gerente** = `restaurant_manager` (también hace lo de la «encargada»): ve su local con márgenes (hoy ya ve los costos de su local, ADR-0032), resuelve mapeos de TapTapChef, ve fugas por descuento y platos a empujar. Propone una excepción de precio para su local; no aprueba.
- **Chef** = `executive_chef`: ve costo, food cost y contribución por plato (para reingeniería), sin aprobar precios. Recibe las alarmas de food cost.
- **Compras** = `purchasing`: no ve márgenes ni costos de recetas (como hoy). Ve los precios de carta.
- **Consulta** = `auditor`: lee todo, sin cambiar nada.
- **Jefe de Cocina y Cocinera** (`head_chef`, `cook`): nada del módulo.
- `superadmin` y `superadmin_test` como siempre (recordar volver a correr «Crear el superadministrador de prueba» en staging cuando haya permisos nuevos).

Permisos nuevos (código = módulo.acción; el plan cierra la lista y la matriz): `menu.view`, `menu.view_margins`, `menu.manage_items`, `menu.propose_prices`, `menu.approve_prices`, `menu.publish_menus`, `menu.manage_policies`, `menu.manage_alerts`, `menu.manage_decisions`, `menu.simulate`, `sales.view`, `sales.map_items`. `menu.view_margins` exige además `recipes.view_costs` en el local. Todo va en la matriz de permisos (ADR-0039).

## TapTapChef: qué dice la API y qué cambia

Leído en `docs/fases/fase-4-taptapchef-api.md`. Lo que cambia el diseño:

1. **Un solo endpoint, una clave por integrador** (`x-api-secret`) que decide a qué locales se accede. La clave va **solo** en los secretos de Supabase de producción y la usa **solo** una Edge Function. Nunca en el repositorio (es público), ni en el navegador, ni en staging, ni en el chat. Joaco la pide a TapTapChef junto con el rate limit; si TapTapChef necesita la autorización del titular, Soy la da por mail.
2. **Cada local tiene un «ID de tienda».** Va en la ficha del local del Panel de control («ID de tienda en TapTapChef»), cargado por quien tiene `org.manage`. Sin ese ID, el local no sincroniza y su tablero lo dice.
3. **Rate limit por credencial, no por local** (1 consulta cada 10 o 60 s), y **un rechazo reinicia la espera.** Entonces hay **una sola cola para todo el grupo** (`sales.pos_sync_requests`), que manda de a una consulta y respeta el intervalo configurado; nunca se reintenta enseguida. Cuenta de referencia: 4 locales × 3 tablas (`turnos`, `tickets`, `ventas`) × 2 fechas = 24 consultas; a 60 s son 24 minutos por noche. Con más locales escala lineal: el plan lo calcula y avisa desde cuántos locales no entra en la noche.
4. **`fecha` es la fecha en que el dato llegó a la nube, no la de la venta.** Se consume por fecha de llegada (incremental): cada corrida pide **hoy y ayer**, y guarda todo por su id. La fecha de la venta (`ticketdate`) es la que usan los tableros; la de llegada (`uploaddate`) es la que usa la sincronización. Una venta que llega tarde entra igual y recalcula su período.
5. **Idempotente por id externo:** `ticketid` y el id de cada línea (el plan lo confirma con la estructura real). Pedir dos veces la misma fecha no duplica nada (caso 16).
6. **Lo crudo y lo calculado, separados:** cada respuesta se guarda tal cual en `pos_raw_payloads` (con tienda, tabla, fecha pedida, cuándo y cuántos registros); de ahí se normaliza a turnos, tickets y líneas. Si la normalización cambia, se reprocesa desde lo crudo sin volver a pedir.
7. **`tickets` trae `comensales`** → **el CM por cubierto sale de TapTapChef**: `CM_CUBIERTO_BAJO` pasa de la etapa 4.4 a la 4.2. Trae `tiponame` («Salon», …) → el canal; se mapea a `menu.sales_channels` con una tabla de equivalencias (un `tiponame` desconocido es un aviso, no un canal nuevo).
8. **`turnos` trae su informe** → control de cobertura: lo que suman los tickets de un turno se compara con el total del informe. Si no cierra, ese turno se vuelve a pedir por `turnoid` y, si sigue sin cerrar, aviso `DATO_VENCIDO` / «Datos incompletos» en el tablero del local.
9. **`fiscales` trae las notas de crédito** → las anulaciones. Una venta anulada se corrige con un registro nuevo, trazable (caso 12).
10. **`productosweb` es el maestro de la carta digital** → base del mapeo: cada producto de TapTapChef se mapea a un plato de carta. Al mapear, el sistema **sugiere** el plato por nombre; el Gerente confirma con un clic. Y al dar de alta un plato de carta, el **nombre de fantasía** se propone desde el de TapTapChef (decisión 5 de las mejoras). Si después el nombre en TapTapChef cambia, aviso «el nombre en TapTapChef ya no es el de la carta». **La API es solo de lectura:** el sistema nunca cambia precios ni nombres en TapTapChef (documento de Soy, sección 4).
11. **`cobros` trae los medios de pago** → la comisión real por medio de pago se puede calcular en vez de cargarla a mano. Queda para después de la 4.2; hasta entonces se usa la comisión promedio que cargue el Controller.
12. **La estructura de `ventas`, `turnos`, `productosweb`, `fiscales` y `cobros` no está documentada** («depende de la tabla»). Antes de la base de la 4.2, Joaco hace **una consulta de cada tabla** desde su máquina, con la clave de producción, y documenta en el ADR **solo los nombres y tipos de los campos, sin ningún valor**. Las respuestas reales no se guardan en el repositorio ni en el seed. Con esa estructura se arman los JSON inventados para las pruebas y para staging. De ahí sale también la respuesta a las preguntas 1 y 2 del documento de Soy (importe por ítem, descuentos, modificadores, combos).
13. **Errores:** HTTP 400 con `msg`. Cada error queda en el registro de la sincronización con la tienda, la tabla y la fecha; la credencial inválida o el local no autorizado avisan a Dirección y al Controller, no se reintentan solos.
14. **Hora argentina** (`-03:00`) → `timestamptz`. La franja horaria de los tableros se calcula en la zona del local (`org.time_zones`).

## Lo que no entra todavía

- **WhatsApp automático** (decisión 6). Queda la cola de mensajes con el canal listo.
- **Agentes de IA:** los Anexos A y B del documento quedan guardados como documento y se usan recién en la Fase 5 (`agents.md`: antes de eso no se escribe código de agentes). Los informes de esta fase salen con una plantilla fija de números, sin IA.
- **Etapa 4.4:** contratos JSON a Salón, Cocina y Compras; teórico contra real (necesita inventario y producción); afinidad de productos en ticket; predicción de demanda. Se diseñan los contratos en el plan, pero no se construyen.
- **Cambiar precios en TapTapChef** desde el sistema: nunca (la API es de lectura y el documento lo prohíbe).

## Orden

- **Etapa 4.1, sin ventas** (se usa apenas termina, con precios y costos):
  - Prompt 0: plan de la Fase 4 (solo documentos).
  - Prompt 1: base de carta y precios, y el motor de cálculo.
  - Prompt 2: pantallas Platos, ficha del plato y Configuración.
  - Prompt 3: Inicio del módulo, alarmas sin ventas, aviso de la factura e informe semanal.
  - Prompt 4: prueba de la etapa 4.1 para Soy en staging.
- **Etapa 4.2, ventas e ingeniería de menú:**
  - Prompt 5: integración con TapTapChef y mapeo.
  - Prompt 6: matriz de ingeniería de menú, alarmas con ventas e informe mensual (y la prueba de staging con un mes de ventas).
- **Etapa 4.3, decisiones:**
  - Prompt 7: cartas versionadas y carta para imprimir.
  - Prompt 8: simulador, decisiones y objetivos con revisión a 30 días.

Cada prompt deja algo usable y tiene su compuerta: Soy prueba en staging con datos de prueba antes de cargar datos reales. Las pantallas siguen el boceto aprobado en `docs/prompts/2026-11-23-boceto-precios-y-carta/` (aprobado por Soy el 2026-11-23).

**En todos los prompts:** los 15 criterios de Soy de `design.md` (sin scroll de página en 1440 × 900, 1600 × 900, 1715 × 843 y 1920 × 1080; listados con panel izquierdo de 250 px; altas en modal corto; encabezado en una línea; todo en español; nombres sin «…»); probar con un rol que edita y con uno que solo lee; capturas en `docs/capturas/precios-y-carta/`; revisión de `db-reviewer`, `security-auditor` y `ui-reviewer`; lista de cambios para Soy en `docs/modulos/`; `docs/estado.md` al día.

---

## Prompt 0: plan de la Fase 4 (solo documentos)

```text
Leé CLAUDE.md, docs/estado.md, docs/prompt-maestro.md (secciones 5, 6 y 11), .claude/rules/ (los 4),
docs/fases/fase-3-plan.md (es el modelo), docs/fases/fase-4-precios-y-carta.md (el documento de Soy,
completo), docs/fases/fase-4-taptapchef-api.md (la API de TapTapChef) y
docs/prompts/2026-11-23-precios-y-carta-modulo-3.md (este archivo: decisiones de Soy, lo que se
reutiliza y cómo se adapta). Leé también las migraciones de recetas (recipe_type, recipe_categories,
recipe_assignments, recipe_media), costos (recipe_cost_current, recipe_cost_snapshots,
cost_scenarios, price_records y su herencia), razones sociales (vat_condition), aprobaciones,
notificaciones, outbound_messages, integration_outbox y la matriz de permisos.
Tarea: escribir el plan de la Fase 4 (Módulo 3 «Precios y Carta») en docs/fases/fase-4-plan.md, con
la misma estructura que fase-3-plan.md. Rama: docs/plan-fase-4-precios-y-carta. Solo documentos: no
se toca app/ ni supabase/. Entrá en modo plan y mostrame el índice antes de escribir.

EL PLAN TIENE
1. Resumen para Soy, en simple: qué va a poder hacer cada persona al terminar cada etapa.
2. Auditoría (paso A del documento de Soy): qué se reutiliza, tabla por tabla, y qué papel cumple de
   las tablas pc_ del documento. Decí explícitamente que NO se crean pc_platos con alérgenos
   propios, categorías, pc_costos_snapshot, pc_sync_log ni un segundo simulador.
3. Arquitectura: esquemas menu y sales, flujo de datos (Recetario → costo → precio → venta →
   matriz → decisión), relación con Compras (cost.changed) y dónde vive el motor de cálculo (una
   sola capa de funciones SQL que leen tableros, alarmas, simulador e informes; las cuentas de la
   sección 8 del documento, con el IVA según la razón social de este archivo).
4. Diagrama de entidades (mermaid) con las tablas de hoy en un color y las nuevas en otro.
5. Diccionario inicial: tabla, columnas, tipo, obligatoria, qué guarda. Qué columnas llevan _price
   o _amount (las oculta core.hide_costs) y cuáles no (el precio de carta lo ve quien no ve
   costos). Cuáles son solo de inserción.
6. Permisos y reparto por rol según «Quién es quién». Marcá los sensibles.
7. Pantallas: una entrada «Precios y Carta» en la barra lateral (decí en qué grupo y verificá que
   el menú siga entrando en 1715 × 843 con el superadmin) y sus pestañas, cada una con su tipo
   (A, B o C), la pregunta que responde y qué rol la ve. La pestaña va en la ruta
   (/precios-y-carta/platos), así «← Volver», los enlaces de Calidad y el selector de local
   funcionan como en el resto. Alarmas llegan también a la campana. Celular: lectura, alarmas y
   aprobación de precios con un toque.
8. Reglas exactas con un ejemplo con números cada una: los 6 casos numéricos del documento (sección
   18) más IVA con razón social monotributo, herencia marca → local, precio con fecha futura,
   redondeo (00/50), precio sugerido y conflicto de políticas, deriva, período de gracia, corte de
   popularidad, PERRO_ESTRATEGICO, venta que llega tarde de TapTapChef, venta anulada.
9. TapTapChef: los 14 puntos de este archivo, uno por uno, con la tabla o la función que lo
   resuelve, y la cuenta de cuántas consultas por noche caben con el rate limit.
10. Orden de construcción: los PRs de este archivo, con qué deja usable cada uno y su compuerta.
11. Riesgos (por ejemplo: platos de carta sin receta publicada; recetas «incompletas» que dejan
    platos sin margen; un tiponame nuevo en TapTapChef; dos personas proponiendo precio al mismo
    plato; el rate limit con muchos locales).
12. Decisiones: las de Soy (este archivo) y las preguntas nuevas que encuentres, cada una con tu
    recomendación. Nada se decide en el plan: se pregunta.

ENTREGA
- ADR nuevo (siguiente número libre): «Módulo de precios y carta: alcance y reutilización».
- docs/estado.md: encabezado y una sección «Fase 4: precios y carta» con el orden de los PRs.
- Formato (npm run format), PR chico con resumen en simple. Commit: «docs(carta): plan de la Fase 4,
  módulo de precios y carta».
```

---

## Prompt 1: base de carta y precios, y el motor de cálculo

```text
Leé docs/fases/fase-4-plan.md y su ADR. Rama: feat/carta-base. Base primero: no hay pantallas en
este PR. Modo plan antes de empezar.

HACÉ
1. Esquema menu con: menu_items (receta de tipo dish, rubro de menú, código automático, nombre de
   fantasía, descripción de carta, estado comercial, fecha de alta, estación de cocina de una lista
   del catálogo), menu_item_tags (emblema, tractor, contribución, complementario, entrada,
   estacional, experimental, candidato a retiro; con motivo, quién y desde cuándo),
   menu_item_components (combos y menú ejecutivo como suma ponderada), sales_channels y
   channel_terms (IIBB, comisión de medio de pago, comisión del canal y packaging por local, con
   vigencia; solo de inserción), pricing_policies (jerarquía producto > rubro > carta > local >
   marca > grupo) y sale_prices (solo de inserción; marca con excepción por local; canal; precio de
   carta; alícuota de IVA del plato, 21 % por defecto y 10,5 % si aplica; foto del costo al fijar;
   vigente desde; solicitud de aprobación).
2. Datos del local para el CM por cubierto (costos fijos, cubiertos esperados, utilidad objetivo),
   por mes, en el alcance de org.manage.
3. Aprobación del precio por workflow: proponen brand_director y controller (y el gerente, solo
   excepción de su local); aprueba general_management, nunca quien propuso. Un lote de precios es
   una sola solicitud con una línea por plato, que se aprueba entera o plato por plato. El precio
   entra al aplicarse y vale desde su fecha.
4. El motor, en funciones SQL que solo leen: precio neto según la razón social, costos variables,
   MC1, MC2, food cost, markup (sin alarma), deriva, precio sugerido por cada método y el
   recomendado con su conflicto. Sin costo confiable devuelven vacío con el motivo, nunca 0.
5. Permisos y reparto por rol del plan, en la matriz de permisos. RLS en todas las tablas,
   auditoría, comment on en español, índices, y el seed con platos de carta y precios inventados
   para las recetas de prueba.

PRUEBAS
- pgTAP: RLS por rol y alcance, auditoría, solo de inserción (update y delete fallan: caso 13), la
  aprobación por otra persona y el rechazo sin permiso en la base (caso 14), precio con fecha futura
  (caso 11), mismo plato en dos locales con precios y márgenes distintos (caso 8), plato sin receta
  publicada sin margen (caso 9), un insumo que sube cambia el margen y no toca lo histórico (caso 7).
- Vitest y pgTAP con los casos numéricos 1, 2 y 6 del documento de Soy y los ejemplos del plan
  (monotributo, redondeo, conflicto de políticas).
- explain analyze de la lectura de márgenes de un local con 80 platos: menos de 300 ms.

ENTREGA: ADR, lista de cambios para Soy en docs/modulos/, estado.md, revisiones de db-reviewer y
security-auditor, PR con resumen en simple. Commit: «feat(carta): platos de carta, precios con
aprobación y motor de márgenes».
```

---

## Prompt 2: pantallas Platos, ficha del plato y Configuración

```text
Leé el plan, el ADR del Prompt 1 y el boceto aprobado en docs/prompts/2026-11-23-boceto-precios-y-carta/.
Rama: feat/carta-pantallas. Modo plan antes de empezar.

HACÉ
1. Entrada «Precios y Carta» en la barra lateral, con la barra de pestañas (Inicio, Platos, Cartas,
   Matriz, Alarmas, Simulador, Decisiones, Configuración). Las pestañas que todavía no tienen
   contenido no se muestran.
2. Pestaña Platos (tipo C, una pantalla): panel izquierdo de 250 px con los rubros de menú (ícono,
   nombre y cantidad); tabla con nombre de fantasía, precio de carta, costo, contribución, food
   cost, deriva y estado con palabra; precio sugerido al lado del actual. Repreciación en planilla
   (mejora 1): el precio se edita en la celda, la celda cambiada lleva borde punteado, contador,
   motivo y «Enviar a aprobación» en la barra fija de abajo. Quien no ve márgenes ve la tabla sin
   esas columnas.
3. «+ Nuevo plato» arriba a la derecha: modal corto (receta de tipo plato, nombre de fantasía
   propuesto desde el nombre de la receta, rubro tomado de la receta, precio) que crea el plato y
   abre su ficha. Lo que se pidió en el modal no se vuelve a pedir.
4. Ficha del plato (tipo B, sin scroll): encabezado en una línea (← Volver, nombre de fantasía,
   código · rubro · receta y versión, estado); 4 indicadores (precio neto, costo por porción,
   contribución neta, food cost); tarjetas: precio por canal (MC1 y MC2 de cada canal), carta
   (nombre de fantasía y descripción, editables donde se ven), historia de precios y costo al
   fijar, etiquetas. Cuadrante: «Sin ventas todavía» hasta la etapa 4.2.
5. Pestaña Configuración: canales y sus condiciones por local, políticas por rubro (la planilla del
   boceto, mejora 6) y redondeo. Datos del local para el CM por cubierto en el Panel de control.
6. «Precio y margen» en la ficha de receta de tipo plato (mejora 4), como dice el boceto, con
   enlace a la ficha del plato. Si no entra sin sacar algo, se avisa y se decide.

PRUEBAS: Playwright con axe: repreciar 3 platos y aprobarlos como Dirección (otra persona); el
gerente sin permiso no ve «Enviar a aprobación»; Compras no ve márgenes; sin scroll en los 4
tamaños con un rol que edita y con uno que lee, con 15 platos en un rubro; celular de consulta.

ENTREGA: capturas en docs/capturas/precios-y-carta/, revisiones (ui-reviewer incluido), lista de
cambios para Soy, estado.md, PR. Commit: «feat(carta): platos, ficha del plato y repreciación en planilla».
```

---

## Prompt 3: Inicio del módulo, alarmas sin ventas, aviso de la factura e informe semanal

```text
Rama: feat/carta-inicio-y-alarmas. Modo plan antes de empezar.

HACÉ
1. Tabla menu.alerts con estado (abierta, vista, asignada, pospuesta con motivo, resuelta), una sola
   abierta por plato, local y tipo (sin duplicados), prioridad por impacto en pesos por mes
   estimado, y cada alarma con qué pasó, valor contra objetivo, cuánto cuesta por mes, quién actúa
   y acción sugerida. Entrega por core.notifications (tipos nuevos) y mail. Máximo 5 rojas por
   persona por envío; no se reenvía hasta que el valor cambie más de 2 puntos o pasen 7 días.
2. Alarmas de esta etapa: SIN_RECETA / SIN_PRECIO, DERIVA_COSTO, FOOD_COST_ALTO, CM_BAJO_PISO,
   CANAL_NO_RENTABLE y PRECIO_INCONSISTENTE, cada una con el responsable de «Quién es quién».
3. Aviso al dar conforme una factura (mejora 2): al llegar cost.changed por una factura, un solo
   aviso a Dirección con los platos que pasaron la deriva máxima y el precio sugerido de cada uno,
   con enlace a la pestaña Platos filtrada en esos platos.
4. Pestaña Inicio (tipo A, sin scroll): las 4 preguntas del documento de Soy; 4 indicadores (food
   cost ponderado teórico, % de platos fuera de política, platos con deriva, decisiones
   pendientes); lo que pide atención; comparación entre locales. Los indicadores con ventas
   aparecen en la 4.2 y hasta entonces dicen «Sin ventas todavía», no 0.
5. Pestaña Alarmas (tipo C): panel izquierdo por tipo, tabla priorizada, asignar, posponer con
   motivo y cerrar.
6. Informe semanal por local por mail (C1 del documento, con plantilla fija, sin IA), los lunes,
   con pg_cron. Lleva la fecha de los datos.

PRUEBAS: pgTAP de cada regla de alarma con números, la deduplicación y el tope de 5; el aviso de la
factura (una factura que sube la harina avisa una sola vez con los platos afectados); Playwright
del Inicio y de Alarmas, sin scroll, con axe.

ENTREGA: como siempre. Commit: «feat(carta): inicio de rentabilidad, alarmas y aviso por factura».
```

---

## Prompt 4: prueba de la etapa 4.1 para Soy en staging

```text
Rama: feat/prueba-carta-soy. Igual que supabase/staging/demo-recipes.sql y demo-purchasing.sql.

HACÉ: supabase/staging/demo-menu.sql y la opción «Cargar platos y precios de prueba» de Publicar en
staging. Se apoya en las recetas de prueba de la Fase 2 (Demo Pastas). Carga, con las funciones de
la app y la sesión de cada persona de prueba: canales, políticas por rubro, los platos de carta con
nombre de fantasía y descripción, precios propuestos y aprobados por otra persona, una excepción de
precio en un local, y a propósito: un plato sin precio, uno con food cost alto y uno que pierde
margen al dar conforme una factura de prueba. Guía y recorrido para Soy en
docs/guias/prueba-fase-4-soy.md, con las cuentas a mano de cada número que va a ver.

PRUEBAS: ensayo local con DRY_RUN=1 imitando staging; guardas de «ya cargado»; control final que
deshace todo si un número no coincide con la guía.
Commit: «feat(staging): prueba de precios y carta para Soy».
```

---

## Prompt 5: integración con TapTapChef y mapeo

```text
Antes de la base: hacé una consulta de cada tabla de TapTapChef (turnos, tickets, ventas,
productosweb, fiscales, cobros) desde tu máquina con la clave de producción y documentá en el ADR
SOLO nombres y tipos de los campos, sin ningún valor. No guardes las respuestas en el repositorio.
Confirmá el rate limit de la credencial y el ID de tienda de cada local.
Rama: feat/ventas-taptapchef. Modo plan antes de empezar.

HACÉ
1. Esquema sales con las tablas de este archivo. ID de tienda en la ficha del local del Panel de
   control. Equivalencias tiponame → canal.
2. Adaptador desacoplado: una interfaz «fuente de ventas» y la implementación TapTapChef en una
   Edge Function, con la clave en los secretos. Cambiar de POS = otra implementación, sin tocar el
   módulo.
3. La cola única del grupo que respeta el rate limit (un rechazo reinicia la espera), pide hoy y
   ayer por fecha de llegada, guarda lo crudo, normaliza con idempotencia por id externo y controla
   cada turno contra su informe (si no cierra, lo pide por turnoid). pg_cron cada noche y cada X
   horas durante el día (configurable).
4. Mapeo (pestaña Platos, panel «Sin mapear»): productos de TapTapChef sin plato, con la sugerencia
   por nombre; el Gerente confirma con un clic. Al crear un plato desde un producto de TapTapChef,
   el nombre de fantasía sale de ahí. Aviso si el nombre en TapTapChef cambia.
5. Alarmas MAPEO_FALTANTE (al Gerente) y DATO_VENCIDO (local sin sincronizar más de X horas, a
   Dirección y Controller). Cobertura en el Inicio: % de la venta mapeada y última sincronización.
6. Archivos JSON inventados con la estructura real, para las pruebas y para staging (la fuente
   «archivo» del mismo adaptador). En staging nunca se llama a la API real.

PRUEBAS: Vitest del adaptador con los JSON inventados (rate limit, rechazo, 400, credencial
inválida); pgTAP de idempotencia (la misma fecha dos veces no duplica: caso 16), la venta que llega
tarde, la anulada por nota de crédito (caso 12), el ítem sin mapeo que bloquea su rubro (caso 15) y
RLS.
Commit: «feat(ventas): ventas de TapTapChef, cola con límite de consultas y mapeo de platos».
```

---

## Prompt 6: matriz de ingeniería de menú, alarmas con ventas e informe mensual

```text
Rama: feat/carta-matriz. Modo plan antes de empezar.

HACÉ
1. Cálculo y guardado por local, rubro, canal y período (menu_engineering_results, solo de
   inserción): Kasavana & Smith con los cortes de la sección 9.1 del documento, Pavesic, Omnes y
   complejidad (insumo exclusivo sale del Recetario). Período de gracia, disponibilidad mínima,
   volumen mínimo (INSUFICIENTE), PERRO_ESTRATEGICO para los emblemas. Nunca se sugiere una baja
   solo por ser Perro. Salón y delivery por separado. El rubro con un ítem sin mapear no genera
   matriz.
2. Pestaña Matriz (sin scroll): burbuja por rubro (tamaño = contribución total), los cortes y la
   metodología a la vista, comparación con el período anterior y el movimiento de cada plato;
   columnas Pavesic, Omnes y complejidad. Local, después marca, después grupo.
3. Indicadores con ventas en el Inicio y en la ficha del plato: ventas netas, contribución total,
   CM por cubierto contra el objetivo (con comensales de TapTapChef), food cost ponderado real,
   precio real promedio contra lista, cuadrante.
4. Alarmas FUGA_DESCUENTO (al Gerente), CAIDA_POPULARIDAD, ENIGMA_BAJA_EXPOSICION, CAMBIO_CUADRANTE
   y CM_CUBIERTO_BAJO.
5. Informe mensual de la matriz por mail (C2, plantilla fija, sin IA).
6. Ampliar demo-menu.sql con un mes de ventas inventadas por el mismo adaptador (fuente archivo),
   pensadas para que haya al menos una Estrella, un Caballo, un Enigma, un Perro y un Perro
   estratégico. Actualizar la guía de Soy.

PRUEBAS: los casos numéricos 3, 4, 5 y 6 del documento de Soy; rendimiento de la matriz de un mes de
un local con 80 platos y 20.000 líneas (menos de 300 ms la lectura); Playwright con axe.
Commit: «feat(carta): matriz de ingeniería de menú y alarmas con ventas».
```

---

## Prompt 7: cartas versionadas y carta para imprimir

```text
Rama: feat/carta-cartas. Modo plan antes de empezar.

HACÉ
1. menus, menu_versions y menu_version_items: carta por local (o por marca con excepción), canal y
   horario; estados borrador, en revisión, aprobada, publicada, archivada; una versión publicada no
   se toca. Altas y bajas con motivo. Publica Dirección General.
2. Pestaña Cartas: versiones, qué cambió contra la anterior y el impacto económico de una carta nueva
   antes de publicarla (contribución esperada con el mix actual). Ficha de evaluación de platos
   nuevos (en prueba) con su período de gracia.
3. Carta para imprimir (mejora 5): PDF con nombre de fantasía, descripción, precio, alérgenos y sin
   TACC (de la receta), con la versión y quién la aprobó al pie (criterio 14).

PRUEBAS: pgTAP de versiones inmutables y aprobación; Playwright del circuito borrador → aprobada →
publicada y del PDF.
Commit: «feat(carta): cartas versionadas y carta para imprimir».
```

---

## Prompt 8: simulador, decisiones y objetivos con revisión a 30 días

```text
Rama: feat/carta-decisiones. Modo plan antes de empezar.

HACÉ
1. Ampliar costing.cost_scenarios con cambio de precio de venta, de volumen, de mix, promoción,
   alta y baja de plato y cambio de comisiones. Actual contra simulado, punto de equilibrio de
   volumen ante un cambio de precio. Elasticidad: hipótesis por rubro cargada por el usuario, con
   pesimista, base y optimista, y el resultado marcado «Simulación».
2. Decisiones (solo de inserción, por workflow): subir o bajar precio, reingeniería, reubicar,
   empujar en salón, baja, alta; con KPI esperado y fecha de revisión a 30 días. Un escenario
   aprobado se convierte en decisión. Propuesta de repreciación (C3, plantilla fija) para Dirección.
3. Objetivos por área (salón, cocina, compras, gerencia) con indicador base, meta, responsable y
   resultado medido a los 30 días (caso 17). Aviso de revisión vencida en el Inicio.
4. Pestañas Simulador y Decisiones. Aprobación con un toque en el celular.

PRUEBAS: pgTAP y Vitest de cada tipo de escenario con números, del pasaje escenario → decisión y de
la comparación objetivo contra resultado; Playwright con axe y sin scroll.
Commit: «feat(carta): simulador, decisiones y objetivos con revisión a 30 días».
```

---

## Preguntas que siguen abiertas

**Para Soy** (antes de conectar datos reales; las de políticas y emblemas van en la planilla del boceto):

1. IIBB de cada local.
2. Comisión promedio de los medios de pago (hasta que salga de `cobros`).
3. Comisiones reales y packaging de PedidosYa, Rappi y delivery propio.
4. Qué canales usa cada local (salón, take away, delivery propio, PedidosYa, Rappi).
5. Redondeo de precios: ¿a $100 («00») o a $50 («50»)?

**Para Joaco** (en el Prompt 0 o el 5):

1. Rate limit de la credencial y el ID de tienda de cada local.
2. Cómo vienen en `ventas` los combos, el menú ejecutivo, los modificadores y los descuentos (preguntas 1 y 2 del documento de Soy).
3. Si TapTapChef distingue «take away» de «delivery» en `tiponame`, y cómo llegan los pedidos de PedidosYa y Rappi.
