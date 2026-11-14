# Estado del proyecto

_Última actualización: 2026-11-13. Soy aprobó la Fase 1 (ADR-0019). Joaco aprobó el plan de la Fase 2 (ADR-0020). Staging funciona. Fusionados: 2.1 A y 2.1 B (PR #19 y #20), configuración del catálogo (#21) y la base de recetas (#22). **Llegaron las respuestas de Soy a las decisiones de la Fase 2 (ADR-0024).** Fusionado el rediseño completo (PR #52). Fusionado Rubros (PR #53), el arreglo del CI más la sincronización al abrir (PR #54) y la matriz de permisos (PR #56). Fusionado medidas, mermas y rendimientos (PR #57) y los prompts de las fichas únicas (PR #58). Fusionado códigos automáticos y listados por rubro (PR #59) y la ficha única de receta (PR #60). Fusionada la ficha única de materia prima (PR #61, ADR-0043): están los 3 prompts de fichas únicas. Fusionados los prompts del Inicio (PR #63) y rubro con precios y producto de compra (PR #64, ADR-0044). Fusionados los prompts de las fichas sin scroll (PR #66) y el Inicio sin scroll (PR #65, ADR-0045). Siguen las fichas sin scroll. **Llegó el documento de Soy del Módulo 2 «Facturas» (Fase 3, compras), con sus 7 prompts (2026-11-14).**_

## Después de las fichas: Módulo 2 «Facturas», compras (pedido de Soy, 2026-11-14)

- **Documento de Soy:** `docs/fases/fase-3-facturas.md` (completo, tal como llegó). Soy lo llama Módulo 2: Facturas; en la hoja de ruta es la Fase 3 (compras).
- **Prompts:** `docs/prompts/2026-11-14-facturas-modulo-2.md`, siete en orden, un PR cada uno: 0) plan de la Fase 3 (solo docs, `docs/fases/fase-3-plan.md`); 1) proveedores, ficha completa; 2) artículos de proveedor, cola de mapeo y listas de precios; 3) orden de compra; 4) recepción y stock; 5) facturas, control de 3 vías y costos; 6) pagos, cuenta corriente y tablero de compras.
- **Qué se reutiliza** (no se duplica): `catalog.suppliers` (proveedor), `catalog.purchase_products` (artículo de proveedor, el envase es el factor), `costing.price_records` con origen `invoice` (costos; `resolve_prices` es la vista de costos vigentes), `workflow.*` (aprobación de OC), `core.notifications` (alarmas), `catalog.code_series` (numeración RAG-0001), Storage con el patrón de `recipe-media`. Esquemas nuevos: `purchasing` e `inventory` (solo `stock_movements`).
- **Tres decisiones más de Soy (2026-11-14), ya respondidas** y escritas en el archivo de prompts: 1) la factura conforme es la aprobación del precio; una variación grande entra igual y avisa a Dirección (cambia el paso bloqueante del ADR-0029 para los precios de factura); 2) el conforme a mano lo da otra persona distinta de quien cargó la factura, validado por la base; 3) una OC que requiere aprobación la aprueba Compras, nunca quien la pidió.
- **Facturas reales de Soy (2026-11-14):** dos PDF con 33 comprobantes de unos 30 proveedores reales de los tres locales. **No se commitean** (CUIT, precios y firmas reales; el repo es público): Joaco los recibe aparte. El archivo de prompts resume, sin nombres ni importes, lo que cambian: seis clases de papel (factura A, factura/remito, remito R, remito harinero, comprobante X, nota manuscrita), facturación por peso, dos bonificaciones por línea, impuestos internos y percepciones, fletes, artículos que no son comida, un local que recibe a nombre de otro, CAE/CAI/CAEA y una factura con datos de emisor de ejemplo. Cada prompt tiene su sección «FACTURAS REALES».
- **Cuatro preguntas nuevas para Soy**, con recomendación: 4) impuestos internos y percepciones en el costo; 5) fletes y servicios; 6) lo que no es comida (limpieza, descartables, reventa); 7) pago en efectivo al recibir.
- **Carga real:** los proveedores reales se cargan en producción desde la ficha (o con una importación desde planilla, a decidir en el plan del Prompt 1), nunca por el seed.
- **Orden:** primero terminar las fichas sin scroll; después el Prompt 0 y los seis PRs en orden.
- **Sin verificar desde la máquina de Soy:** el formato (`npm run format:check`) de estos archivos de docs.

## Antes: Inicio sin scroll (rama `feat/inicio-sin-scroll`, ADR-0045, PR #65 fusionado)

- **Qué se hizo** (pedido de Soy, `docs/prompts/2026-11-13-inicio-sin-scroll.md`; boceto aprobado):
  - el Inicio entra entero en 1440 × 900, 1600 × 900 y 1920 × 1080, sin scroll (en 1440 termina en 889 px);
  - encabezado «Hola, {nombre} · {local}» con la línea de datos; solo «Ver qué falta corregir» (sin «+ Nueva receta»);
  - aviso «Requiere atención» en una franja de 44 px (suma las revisiones y el recálculo);
  - 4 KPIs compactos; tres tarjetas: confiabilidad (5 filas), cada local (hasta 5) y tareas;
  - un solo ranking con botones (`aria-pressed`, formulario GET `?ranking=`) y 6 accesos con su número del momento;
  - Usuarios, Roles e Historial salen del Inicio; la Cocinera sigue con el Inicio simple;
  - celular: aviso, KPIs de a 2, «Para decidir» y locales, sin ranking ni accesos grandes.
  - Lista para Soy: `docs/modulos/10-inicio-sin-scroll-lista-de-cambios.md`.
- **Regla única de lo que falta** (decisión de Soy): `missingState` en `lib/metrics.ts`. Más de la mitad = Crítico; la mitad o menos = Atención. La usan el Inicio, Calidad (la lista de indicadores antes era siempre amarilla) y los accesos.
- **Sin cambios en la base.** Se borró `components/reliability-chart.tsx` (Recharts), que ya no usaba nadie.
- **Pruebas:** Vitest nueva `home-shortcuts.test.ts` (10); Playwright `inicio.spec.ts` reescrita (7 por proyecto, con axe); el ingreso de las pruebas ahora espera el h1 «Hola, …» en lugar de «Inicio» (10 lugares, misma exigencia).
- **Mi cuenta** suma «Tus roles» (los roles salieron del Inicio y no se veían en ningún otro lado).
- **Revisores (2026-11-13):** seguridad apta (3 menores, corregido «Este local» en Tareas); diseño aprobable con cambios: corregidos los 2 medios (rol ARIA del formulario del ranking y la fila del medio que no ocupaba el alto en 1920) y casi todos los menores. La excepción de 28 y 32 px en este panel la aprobó Joaco y quedó en `design.md` (ADR-0045).
- **Aprendido:**
  - En una corrida completa, las pruebas anteriores cambian los números del seed y crean recetas para todo el grupo (llegan a cualquier local nuevo). Las pruebas del Inicio controlan la regla con los números de la pantalla, no números fijos.
  - `lf-main` con `flex-1` ignora su alto: para que una pantalla ocupe la ventana hace falta `min-h-dvh` y `flex-none`.
  - El 1440 × 900 de la prueba es la ventana entera; en un monitor real quedan unos 790 px útiles y ahí la página hace scroll (no encima nada).
- **Corridas (2026-11-13, base recién recreada):**
  - formato, lint, tipos, Vitest 375 de 375 y pgTAP 2534 de 2534 (incluida la `100`, que antes había fallado por velocidad con la máquina cargada);
  - Playwright, primera corrida completa: 8 fallas, todas de pruebas de este cambio con números fijos o del rol en el Inicio. Se cambiaron para que controlen la regla y para buscar el rol en Mi cuenta;
  - segunda corrida completa: 267 en verde, 15 salteadas y 2 fallas. (1) Con datos reales (importaciones y 26 recetas) el Inicio medía 923 px en 1440 × 900: se ajustaron la línea de importación (un renglón), la separación interna de las tarjetas y la línea de datos, y la prueba ahora controla también las 4 listas del ranking. (2) `recetas` «las fotos van con la versión»: «Salir» no navegó; no la toca este cambio y pasó al repetirla;
  - después del ajuste, `inicio` + `recetas` sobre la base que dejó la corrida completa: 20 en verde y 2 salteadas. **No se repitió la corrida completa entera después de ese último ajuste:** la confirma GitHub Actions en el PR.
- **Capturas** (seed limpio, antes del último ajuste de 2 px): 1440, 1600, 1920 y celular.
- **PR #65 abierto (2026-11-13).** Se fusiona con GitHub Actions en verde.

## Próximo: fichas sin scroll (pedido de Soy, 2026-11-13)

- **Prompts:** `docs/prompts/2026-11-13-fichas-sin-scroll.md`, dos en orden: 1) ficha de materia prima (rama `feat/ficha-materia-prima-sin-scroll`); 2) ficha de receta (rama `feat/ficha-receta-sin-scroll`). Boceto aprobado de la materia prima en `docs/prompts/2026-11-13-boceto-fichas-sin-scroll/`.
- **Qué pide:** las dos fichas entran en 1440 × 900 sin scroll de página, con el mismo patrón que el Inicio. En la receta, la planilla de ingredientes es la única parte con scroll propio. Los alérgenos pasan a un botón por alérgeno que cambia de estado con cada clic.
- **Orden:** primero el Inicio (reutilizan su regla de estado), después Prompt 1 y después Prompt 2.
- **Bocetos aprobados de las dos fichas** en `docs/prompts/2026-11-13-boceto-fichas-sin-scroll/` (materia prima y receta).
- **Sin verificar desde la máquina de Soy:** el formato (`npm run format:check`) de estos archivos de docs.

## Antes: rubro con precios y edición de productos de compra (rama `feat/rubro-y-producto-de-compra`, PR #64 fusionado)

- **Qué se hizo** (ADR-0044, decisiones de Joaco del 2026-11-13):
  - Compras cambia el rubro de una materia prima con precios desde la ficha, con motivo y auditoría. La unidad de recetas sigue fija.
  - Cada producto de compra tiene «Editar» en la computadora. Con precios, el envase y el contenido no cambian (lo hace cumplir la base, por cualquier camino); lo demás sí.
  - «Ya no se compran (N)»: los productos desactivados se ven debajo de la tabla y se pueden volver a activar.
  - «Proponer precio» sigue en el celular.
  - Lista para Soy: `docs/modulos/09-rubro-con-precios-y-producto-de-compra-lista-de-cambios.md`.
- **Base** (`20261130120000_rubro_y_producto.sql`): `guard_priced_ingredient` redefinida (solo la unidad), `category_locked_by_prices` borrada, trigger nuevo `guard_priced_product`, `ingredient_sheet_state` con `priced_products` y `price_record_defaults` con `for share` (la carrera entre cambiar el envase y cargar el primer precio).
- **Pruebas:** pgTAP nueva `310_rubro_y_producto` (29) y ajustadas `211`, `250` y `300`, sin borrar ninguna; Vitest nueva `purchase-product.test.ts`; Playwright `ficha-materia-prima.spec.ts` ampliada.
- **Revisores (2026-11-13):** base sin graves ni medios, seguridad apta y diseño aprobable. Lo corregido y lo que queda está en el ADR-0044.
- **Corrida (2026-11-13):**
  - suite completa (con la versión previa a las correcciones de los revisores): Playwright 265 en verde y 15 salteadas; pgTAP con 1 falla de rendimiento en `100_features` (bandeja de aprobaciones, 842 ms con la máquina cargada; no la toca este cambio);
  - con la versión final, sobre la base recién recreada: pgTAP completo en verde (incluida la `100`), formato, lint, tipos, Vitest 365 de 365, y `ficha-materia-prima` + `codigos` 14 en verde y 4 salteadas.
- **PR #64 fusionado (2026-11-13).** Las pruebas del PR fallaron por la máquina de GitHub (el puerto 54324 de Mailpit ya estaba ocupado al levantar Supabase), no por el código: las migraciones se aplicaron bien. Se fusionó sin esperar el resultado; la corrida sobre `main` es la que vale. **Conviene esperar el verde antes de fusionar.**

## Antes: ficha única de materia prima (rama `feat/ficha-unica-materia-prima`, PR #61 fusionado)

- **Qué se hizo** (ADR-0043, Prompt 3 de Soy): las 6 pestañas de la materia prima pasan a una sola ficha con índice, con la misma forma que la receta.
  - Se editan donde se ven, con una barra que guarda todo junto con un motivo: datos generales, otros nombres, congelada, conversiones y alérgenos.
  - Las altas y las propuestas van en un panel al costado: producto, proveedor, merma o rendimiento, ensayo y precio.
  - En el celular, la ficha es de consulta.
  - Lista para Soy: `docs/modulos/08-ficha-unica-materia-prima-lista-de-cambios.md`.
- **Base** (`20261129120000_ingredient_sheet.sql`): `catalog.save_ingredient_sheet` (guardado en lote), `catalog.ingredient_sheet_state` (sello, precios y rubro trabado), `catalog.category_locked_by_prices` (la regla del rubro, que comparte con el trigger, redefinido) y `costing.ingredient_product_prices` (la tabla de productos con su precio).
- **Pruebas:** pgTAP nueva `300_ingredient_sheet` (49) y `050` ajustada; Vitest nueva `ingredient-sheet.test.ts`; Playwright nueva `ficha-materia-prima.spec.ts` y ajustadas `materias-primas`, `mermas`, `rendimientos` y `precios`.
- **Revisores (2026-11-12):** seguridad apta, base sin graves (3 medios corregidos) y diseño aprobable con cambios (los medios y casi todos los menores corregidos). Lo que queda está en el ADR-0043, «Lo que queda».
- **Para decidir con Soy:** hoy ningún rol puede cambiar el rubro de una materia prima con precios (hacen falta `catalog.manage` y `prices.configure` juntos). Y «Proponer precio» sigue en el celular.
- **Aprendido:** no recrear la base (`db:reset`) mientras corre Playwright, y no lanzar revisores que corran pruebas en paralelo a una corrida propia: se pisan y la corrida no sirve.
- **Retomado el 2026-11-13:**
  - La falla era la prevista: Compras no tiene `yields.record`, así que no ve «Proponer merma o rendimiento» (es lo correcto: lo decide la base). La prueba ahora controla que Compras no vea el botón y la merma la propone la Chef en la misma ficha.
  - Arreglado en el camino:
    - la ficha ya no se rearma al guardar (se perdían cambios hechos enseguida);
    - un pedido para dejar de comprarla congelada muestra lo vigente;
    - un solo aviso de guardado y la etiqueta del motivo;
    - la marca ✓ de los botones segmentados salía en todas las opciones (también en otras pantallas que usan `SegmentedField`): ahora solo en la elegida;
    - los alérgenos entran en una línea a 1440.
  - Las capturas de la ficha se toman como Compras (con la barra), en 1440, 1600 y 1920.
  - **Corrida completa (2026-11-13):**
    - formato, lint y tipos: en verde;
    - pgTAP sobre la base recién recreada: 2503 de 2503 (52 archivos);
    - Playwright: 263 en verde, 15 salteadas y 2 fallas, en `codigos.spec` (celular y computadora). Buscaba «código · rubro» juntos y el encabezado nuevo los separa. Ahora controla el código, el rubro y que la unidad quedó en gramos: 11 en verde y 1 salteada.
  - Capturas mirando la pantalla real: 1440, 1600, 1920 y celular, en `test-results/ficha-materia-prima-*`.
- **PR #61 fusionado (2026-11-13):** GitHub Actions en verde y publicado en staging.
- **Decisiones de Joaco (2026-11-13), sobre lo que quedaba:**
  - el rubro de una materia prima con precios **se tiene que poder cambiar** (falta definir quién);
  - «Proponer precio» **sigue disponible en el celular**;
  - **se arma la pantalla** para editar un producto de compra.
  - Las tres van en una rama nueva, con su plan.
- **Revisión de consumo de la nube (2026-11-13):**
  - Se paga **USD 40 por mes, todo en Vercel**: plan Pro con 2 lugares en el equipo. Se gastaron USD 0,77 de los USD 20 de crédito.
  - GitHub es gratis: el repo es público, y los ~3.350 minutos de pruebas de noviembre no se cobran.
  - Supabase es gratis y está lejos de los límites: la base va por 48 MB de 500.
  - Lo que puede decidir el dueño:
    - pasar la clave de publicación de GitHub Actions a una del dueño y después sacar a Joaco del equipo de Vercel (de USD 40 a USD 20);
    - activar la verificación en dos pasos en Vercel;
    - decidir si el repo sigue público (privado, los minutos de pruebas costarían);
    - el staging de Supabase gratis se pausa solo si pasa alrededor de una semana sin uso.

## Ficha única de receta (rama `feat/ficha-unica-receta`, PR #60 fusionado)

- **Qué se hizo** (Prompt 2; ADR-0042; lista para Soy en `docs/modulos/07-ficha-unica-receta-lista-de-cambios.md`):
  - **Base** (`20261128120000_recipe_sheet.sql`):
    - `recipes.save_sheet`: datos, rendimiento, líneas y pasos en una transacción con un motivo; crea el borrador si se edita la vigente; con `p_submit` pide la revisión; en un plato con peso de porción calcula las porciones;
    - `costing.preview_sheet_lines`: la grilla con el mismo motor (`recipe_line_costs_internal` acepta `p_memo.lines`); pesos para quien trabaja la receta, costos con `recipes.view_costs`, precio solo con `prices.view`;
    - `catalog.ingredient_unit_options` (medidas que admite cada materia prima);
    - `recipe_versions.target_yield_ratio`, congelado al pedir la revisión de una preparación (para el control de lotes).
  - **Pantalla:** `/recetas/[id]` es una sola ficha con índice de anclas (`?seccion=` redirige), carrusel de fotos, grilla tipo planilla (`components/recipe-sheet/`), rendimiento de plato o preparación, pasos, barra fija con contador, motivo, Descartar, Guardar y Enviar a revisión. Quien revisa decide desde la ficha. En el celular, consulta.
  - Se borraron los editores viejos (`recipe-lines-editor`, `recipe-steps-editor`) y sus acciones.
- **Decisiones de Joaco (2026-11-12):** precio por kg solo con `prices.view`; los platos viejos conservan sus porciones hasta cargar el peso de la porción; el costo de filas sin guardar solo para quien edita o publica; un plato sin gramos se guarda igual y avisa.
- **Pruebas:** pgTAP nueva `290_recipe_sheet` (48) y `050` ajustada; Vitest nueva `recipe-sheet.test.ts` (347 en total); Playwright nueva `ficha-receta.spec.ts` y ajustadas recetas, subrecetas, escalado, respuestas, costos, mermas y calidad. La carga de la ficha se prueba en la computadora; en el celular, la consulta.
- **Revisores (2026-11-12):** base sin graves; seguridad «no apto» por un grave (la grilla dejaba deducir precios) y diseño con 4 graves. Todo lo grave y lo medio, corregido; Joaco decidió el costo de la grilla y las porciones (ADR-0042, decisiones 3 y 4). Los menores que quedan están en el ADR.
- **Corrida completa (2026-11-12):**
  - formato ✅; pgTAP 2.454 en 51 archivos ✅, desde una base recién creada;
  - Playwright: 238 en verde, 10 omitidas a propósito y 26 en rojo;
  - **causa de casi todas:** la página le pasaba una función (`anchor`) a un componente de cliente, y en la versión armada para producción la ficha no cargaba («Functions cannot be passed directly to Client Components»). Ahora pasa un texto (`anchorSuffix`);
  - otras dos se corrigieron en la prueba, sin aflojarlas:
    - `calidad`: el Controller solo lee recetas y la ficha lo manda a la vista de cocina, igual que en `main`. La prueba vieja miraba la dirección intermedia; ahora controla el enlace (`?seccion=fotos`) y la llegada a la cocina;
    - `recetas`: el carrusel buscaba la flecha antes de que se viera la única foto;
  - las 9 specs afectadas se corrieron de nuevo: 82 en verde y 3 en rojo (las dos de arriba). Corregidas, pasaron solas (3 de 3).
  - pgTAP falló en la corrida completa porque corrió sobre la base que dejaron las pruebas de Playwright, sin recrearla. Recreada, pasó todo.
- **Sigue:** el PR. Después, el Prompt 3 (ficha única de materia prima).

## Antes: códigos automáticos y listados por rubro (fusionado, PR #59)

- **Qué se hizo** (Prompt 1 de `docs/prompts/2026-11-12-fichas-unicas-recetas-y-materias-primas.md`; ADR-0041; lista para Soy en `docs/modulos/06-codigos-y-listados-lista-de-cambios.md`):
  - **Base** (`20261127120000_auto_codes.sql`):
    - el código lo arma la base: `PLA-CAF-0001`, `PRE-SAL-0001`, `MPR-CAR-0001` y, en las variantes, `<maestra>-V01`;
    - contador `catalog.code_series` con bloqueo, sin reutilizar números;
    - vista previa sin consumir (`recipes.preview_code`, `catalog.preview_ingredient_code`);
    - las altas ya no reciben código y avisan si salió otro;
    - el código de una materia prima ya no cambia (`catalog.guard_code`).
  - **Pantallas:**
    - alta de receta en el orden de Soy, con Plato | Preparación, el rubro obligatorio y el código en solo lectura;
    - alta de materia prima con todas las unidades (se guarda la base);
    - `/recetas` y `/materias-primas` con tarjetas de rubros que filtran la tabla, y Platos | Preparaciones con su cantidad.
- **Decisiones de Joaco (2026-11-12):**
  - 9999 pasa a 5 dígitos;
  - variantes con -V01;
  - la importación conserva el código del Excel;
  - «Se usa en recetas en» con todas las unidades, guardando g, ml o unidad.
- **Pruebas (2026-11-12):**
  - db reset desde cero y tipos regenerados; lint, tipos y formato;
  - Vitest 322 (nueva `codes.test.ts`);
  - pgTAP 2.406 en 50 archivos (nueva `280_auto_codes`, con 51; ajustadas `050`, `140`, `160`, `170`, `190`, `238` y `250`);
  - Playwright: nueva `codigos.spec.ts` (11 en verde, 1 omitida a propósito), en celular y computadora (1440, 1600 y 1920), con axe;
  - las specs relacionadas dieron 111 en verde y 4 en rojo. Las 4 eran 2 pruebas que buscaban preparaciones en la pestaña Platos, y se ajustaron;
  - Playwright completo (2026-11-12): 261 en verde, 4 omitidas a propósito y 1 caída por tiempo en `roles.spec` (celular), que no toca este cambio; corrida sola, pasaron sus 5 pruebas.
- **Revisores:**
  - base: sin graves; los 2 medios (prueba de auditoría y RLS para anónimo o sin membresía) corregidos;
  - seguridad: apto; 2 de los 3 menores corregidos y el tercero (la numeración del grupo deja intuir cantidades) documentado;
  - diseño: sin graves; los 2 medios (código duplicado en el celular, búsqueda en la pestaña equivocada) y los menores de una línea, corregidos.
- **Quedó** (ADR-0041, «Lo que queda»):
  - las tarjetas no dependen del buscador;
  - «insumos» o «materias primas»: falta unificar el término con Soy;
  - reservar los prefijos PLA, PRE y MPR en la importación.
- **Sigue:** el PR de este Prompt 1. Después, el Prompt 2 (ficha única de receta) y el Prompt 3 (ficha única de materia prima).

## Antes: medidas, mermas y rendimientos (fusionado, PR #57)

- **Qué se hizo** (pedido de Soy; ADR-0040; lista para Soy en `docs/modulos/05-mermas-y-rendimientos-lista-de-cambios.md`):
  - **Base** (`20261126120000_units_and_waste.sql`):
    - unidades con nombre largo y abreviatura, y 10 medidas de recetario;
    - alta y baja de unidades;
    - «se compra congelada» (`requires_thawing`) y el proceso DESCONGELADO, que el motor suma al rendimiento (`catalog.costing_yield` y `catalog.thawing_factor`, también en escenarios);
    - mermas en % con aprobación (`catalog.propose_waste`);
    - merma de cocción informativa (`recipes.cooking_loss`).
  - **Pantallas:**
    - en la ficha de la materia prima, la tarjeta «Mermas y rendimiento neto»: 4 indicadores, interruptor de congelada y propuesta con vista previa;
    - en la ficha de la receta, el rendimiento final, el costo por kg y la merma de cocción;
    - Unidades en la configuración del catálogo;
    - desplegables «Kilogramo (kg)».
  - **Respaldo** de la base local antes de empezar: el archivo `respaldo-antes-mermas-2026-11-11.sql` de la carpeta temporal de la sesión.
- **Decisiones de Joaco (2026-11-11):**
  - mermas sobre el estándar aprobado;
  - nunca suponer;
  - rendimiento final obligatorio;
  - después de las revisiones: dejar de comprar congelada pide aprobación (marcar es directo), y las unidades las crea Compras, con baja para las cargadas a mano que nada usó.
- **El costo de lo cargado no cambia:** las 198 líneas del seed dan igual antes y después de la migración, y 270 lo prueba.
- **Pruebas (2026-11-11):**
  - db reset desde cero; tipos regenerados; lint, tipos y formato;
  - Vitest 306;
  - pgTAP 2.355 en 49 archivos (nueva `270_units_and_waste`, con 68; ajustadas `050` y `140`);
  - Playwright `mermas.spec.ts` (8) en celular y computadora, con axe WCAG 2.2;
  - Playwright completo: 246 pasaron, 3 omitidas y 5 fallaron en la primera vuelta. Cuatro eran pruebas viejas que chocaban con lo nuevo: «Limpieza (%)» ahora coincide con «Merma de limpieza (%)» en `rendimientos.spec`, y la lista de unidades de peso en `subrecetas.spec` tiene nombres largos y 6 opciones. Se ajustó el localizador y la lista esperada, y siguen controlando lo mismo (solo unidades de peso). La quinta, `precios.spec` en computadora, falló por tiempo. Las tres specs se corrieron de nuevo: 26 de 26.
- **Revisores:** seguridad apto; base y diseño sin graves. Los medios están resueltos o documentados en el ADR-0040.
- **Quedó:**
  - las unidades de las recetas siguen en `lib/recipe-format.ts`: una unidad nueva llega a las recetas con una actualización;
  - la foto del costo no guarda el perfil de descongelado aparte;
  - el costo neto de la ficha se muestra con `menus.costs` y la base pide `prices.view`.
- **Aprendido:**
  - una función `security invoker` nueva tiene que probarse con la sesión de un usuario: `recipes.cooking_loss` usaba `recipes.unit_to_base` (interna) y solo andaba como superusuario;
  - en los scripts de Node, `split/join` en vez de `replace`: un `$$` del texto nuevo se convierte en `$`.

## Antes: matriz de permisos (fusionado, PR #56)

- **Qué se hizo** (prompt de Soy «Rediseño Roles y permisos → Matriz de permisos»; ADR-0039; lista para Soy en `docs/modulos/04-matriz-de-permisos-lista-de-cambios.md`):
  - **Base** (`20261125120000_permission_matrix.sql`):
    - nombre corto y orden para los 40 permisos y la tabla `core.permission_modules`;
    - `core.apply_permission_matrix`: guarda un lote todo o nada. Aplica en el momento las quitas y los permisos comunes, y deja pedidas para Dirección las altas de permisos sensibles. Con bloqueos de la matriz y de las asignaciones de roles, sin tocar roles propios, con la separación de funciones y con auditoría y motivo.
  - **Pantalla `/roles`:** matriz con toggles de un clic, contador, motivo, Guardar/Descartar, confirmación de sensibles, celdas «pendiente», tooltip con mouse y teclado, primera columna y encabezado fijos y celular.
  - **CLAUDE.md:** sección «Edición directa» para todo el sistema.
- **Decisiones de Joaco (2026-11-11):**
  - la matriz se aplica directo;
  - después de la revisión de seguridad, «Mixto»: los permisos sensibles los aprueba Dirección. Se implementó con un pedido por permiso (el camino que ya existía). Una sola tarjeta por lote queda para otro PR, si se quiere.
- **Pruebas (2026-11-11):**
  - db reset desde cero; lint, tipos y formato; Vitest 288;
  - pgTAP 2.287 en 48 archivos (nueva `260_permission_matrix`, con 38; ajustadas `040`, `050` y `060`);
  - Playwright `roles.spec.ts` y `admin.spec.ts` (la prueba 12 del Módulo 0 ahora usa la aprobación de un rol) en celular y computadora, con axe y WCAG 2.2;
  - capturas en 1440, 1600, 1920 y celular;
  - la corrida completa de Playwright: 243 en verde y 3 omitidas a propósito, sin fallas (1,1 h).
- **Revisores:**
  - `security-auditor` no apto en la primera versión (permisos sensibles sin aprobación): resuelto con «Mixto», más las carreras, los bloqueos y los menores;
  - `db-reviewer`: grave (`040` y `060` sin nombre en sus permisos de prueba) corregido, más los medios;
  - `ui-reviewer`: sin graves de código; corregidos los medios y casi todos los menores.
- **Quedó:**
  - «Superadministrador» se corta en tres líneas en el encabezado;
  - el código técnico en el tooltip y el rojo para «No lo tiene» (los pidió Soy);
  - la matriz es una sola para todo el sistema (revisar si se suma otro grupo);
  - solo entra quien tiene `permissions.manage`.
- **Aprendido:** `next build` revisa los tipos también de `tests/e2e`. Un archivo de prueba temporal con errores de tipos hace fallar el servidor de Playwright con «webServer was not able to start».
- **Sigue:** el PR de la matriz y después **medidas, mermas y rendimientos** (plan aprobado en `C:\Users\julym\.claude\plans\streamed-giggling-snowflake.md`, PR 2).

## Antes: bajar cambios al abrir (fusionado, PR #54)

- **Qué se hizo (2026-11-11):** hook `SessionStart` (`.claude/hooks/sync-repo.sh`) que, al abrir Claude Code en VS Code, consulta GitHub y baja los cambios nuevos de la rama actual. Nunca pisa trabajo: si hay archivos modificados sin commitear o la rama se separó de la remota, no baja nada y avisa. Sin internet, avisa y sigue.
- **Por qué en `sh` y no en Node:** en la compu donde se armó (`E:\Luciano\...`) no hay Node ni `node_modules`. El hook solo necesita git. **Ojo:** por lo mismo, los otros hooks del proyecto (`guard`, `protect-migrations`, `pre-commit`, `format`) hoy no corren en esa compu, y tampoco `npm run test`.
- **Pruebas:** 5 casos probados a mano con un remoto de mentira (al día, baja cambios, archivos sin commitear, ramas separadas, sin conexión) y salida JSON válida. `tests/hooks/sync-repo.test.ts` cubre lo mismo en Vitest; no se pudo correr acá por falta de Node: corre en GitHub Actions.

## Antes: Rubros del recetario (fusionado, PR #53)

- **Qué se hizo** (pedido de Soy, `instrucciones-rubros-claude-code.md`; ADR-0038; lista para Soy en `docs/modulos/03-rubros-lista-de-cambios.md`):
  - **Base** (`20261124120000_rubros.sql`, solo aditiva): código (`MP-`, `SR-`, `PL-`) e `is_active` en las dos tablas de categorías, `kind` (sub-recetas o menú) en las de recetas, los 46 rubros de Soy por grupo, la vista `recipes.top_categories`, los conteos en una sola consulta agrupada (`recipes.category_overview`) y funciones para dar de alta, renombrar, dar de baja con destino y reactivar.
  - **Reglas en la base:** un plato va en un rubro de menú; una preparación o un componente, en uno de sub-recetas. Un rubro dado de baja no recibe nada nuevo. Una baja con usos exige un destino.
  - **Datos actuales:** `recipes.map_legacy_categories` empareja las categorías vigentes con los rubros de Soy (por equivalencia, por nombre o por la primera palabra) y deja un código propio en el resto. Lo borrado queda como estaba.
  - **Panel `/rubros`** (Base de conocimiento): pestañas, buscador, orden por cantidad o A-Z, resumen (total, activos, dados de baja, sin uso) y tarjetas de 88 px (5 columnas en la computadora, 2 en el celular) con nombre editable en el lugar, contador, % y barra.
  - **Otras pantallas:** el alta y la ficha de receta ofrecen solo los rubros de su clase; las materias primas no ofrecen los dados de baja; en Configuración del catálogo se crean solo subcategorías.
- **Respaldo:** volcado de la base local antes de empezar (carpeta temporal de la sesión).
- **Pruebas (2026-11-11, todas en verde, con las decisiones de Joaco y de Soy):** db reset desde cero; tipos regenerados sin diferencias; lint, tipos y formato; Vitest 280 en 21 archivos; pgTAP 2.249 en 47 archivos (nueva `250_rubros`, con 114); Playwright 233 en celular y computadora, con axe (3 omitidas a propósito), corrida completa sin fallas.
  - Playwright: la corrida completa dio 224 en verde y 7 en rojo. Las 7 volvieron a correr sobre una base limpia: 5 eran por la carga de una corrida de 1,1 h y pasan solas, y la de cuenta fallaba porque el correo local (Mailpit) dejó de responder; pasó después de reiniciarlo.
  - La de «sin scroll» de Rubros fallaba de verdad: dependía de cuántos rubros de compra agregaban otras pruebas. Ahora mide que entren 5 filas (hasta 25 tarjetas) y, si hay 25 o menos, que no haya scroll.
  - Se ajustaron, sin debilitarlas, las pruebas que usaban los datos de prueba viejos: 050, 170, 230 a 242, `configuracion-catalogo` y `design-system`.
- **Revisores:** security-auditor apto (4 menores, corregidos); db-reviewer (1 grave en el mapeo de datos viejos y 3 medios, corregidos); ui-reviewer (1 grave y 5 medios, corregidos, y casi todos los menores).
- **Quedó para después:** `catalog.create_category` sin madre todavía crea rubros (la pantalla ya no la usa; la importación sí); la importación no avisa por fila si nombra un rubro dado de baja; los selectores dicen «Categoría» y no muestran el código.
- **Decisiones de Joaco (2026-11-10), ya aplicadas y probadas:**
  - **Materias primas con precio:** al dar de baja un rubro de compra, las pasa Compras o Dirección, cada uno por su cuenta. La baja marca el rubro como inactivo antes del pase, y `catalog.guard_priced_ingredient` acepta el cambio de `catalog.manage` solo si la materia prima sale de un rubro dado de baja. Fuera de una baja, sigue la regla de ADR-0029. Los rubros de compra los administran `catalog.manage` o `prices.configure`.
  - **Permiso propio** `recipes.manage_categories` para los rubros de sub-recetas y menú. Arranca en los roles que tenían `recipes.draft`, y Soy se lo puede dar a otro rol desde Roles.
  - Pruebas: 14 más en `250_rubros` (109 en total) y una de pantalla para Dirección. `140_catalog` cuenta el permiso nuevo (22 del recetario).
  - Revisión de seguridad de estos cambios: apta, sin graves. Corregido: las funciones de antes (`recipes.rename_category` y `archive_category`) ya no esquivan el permiso nuevo, gracias al trigger `recipes.guard_top_category`. Agregadas las pruebas que faltaban.
- **Decisión de Joaco (2026-11-10):** se acepta que Compras pueda dar de baja un rubro de compra y reactivarlo, aunque así cambie cuándo vencen los precios del rubro sin Dirección. Queda auditado.
- **Equivalencias de nombres (aprobadas por Soy, 2026-11-11), cargadas y probadas.** A partir de las 7 categorías de staging, que Joaco sacó con una consulta de solo lectura: Carne → MP-CAR Carnes y aves, QUESOS → MP-LAC Lácteos y quesos, Verdura → MP-VER Verduras y hortalizas, CARNES (su receta es un plato) → PL-CAR Principales de carne y PESCADOS → PL-PES Principales de pescado. PASTAS y POSTRES se emparejan solas.
  - Por decisión de Soy, las emparejadas toman también el nombre de su lista, salvo que otro rubro del grupo ya se llame así.
  - `250_rubros` (114 pruebas) simula staging y comprueba que quedan exactamente los 46 rubros de Soy.
  - Antes de producción: correr la misma consulta allá. Las categorías que staging no tenga quedarían con código propio.
- **Sigue:** PR a `main`. Después, la lista de cambios a Soy antes de producción.

## Antes: rediseño de la interfaz, PR 4 de 4 (fusionado, PR #52)

- **Qué se hizo** (ADR-0036, adenda del PR 4; sin cambios en la base). Con este PR **termina el rediseño**: todas las pantallas usan el sistema nuevo.
  - **Usuarios:** tablero con 4 tarjetas confiables (cada una lleva a sus registros; «Sin permiso» y «Sin comparación» cuando corresponde), tablas por local y por rol, y cambios críticos con «Ver todos» al Historial. Lista de personas con filtros que se aplican solos, pestañas de estado, tabla y paginación con cursor. Ficha en pestañas (Datos y cuenta, Roles, Actividad), con el nombre como título y «← Volver a personas» que conserva los filtros. Invitar con ancho limitado.
  - **Historial:** filtros que se aplican solos (fechas, persona, módulo, marca y registro), tabla y paginación con cursor («Más antiguos»), exportar en la tarjeta.
  - **Aprobaciones** sin pestañas (pendientes, avisos y resueltas en la misma página, para que el aviso de una decisión se vea en la tarjeta resuelta), con «Marcar avisos como leídos» arriba. **Roles:** el rol se elige con un filtro que se aplica solo. **Mi cuenta** en pestañas (Mis datos, Contraseña y doble verificación, Sesiones) con aviso de cambios sin guardar. **Panel de control** en grilla, con aviso si no hay nada para administrar.
  - **Pendientes de los PR anteriores, cerrados:** «Salir» del celular dentro de «Menú»; el título de las fichas de receta y de materia prima es el nombre del registro; Importaciones con la tabla y la paginación nuevas; un único «← Volver» (`components/back-link.tsx`) en todas las pantallas; se borraron `FiltersPanel` y `UsersTable`.
  - **Arreglado de paso:** la barra inferior del celular tapaba el final del menú; las tablas anchas con scroll no se podían recorrer con teclado (axe).
- **Decisiones de Joaco (2026-11-10):** el local de Usuarios e Historial es el de arriba, y «Todos mis locales» muestra todo el alcance (la Marca aparece como filtro solo en ese caso); paginación con cursor con el estilo nuevo, sin total ni número de página y sin ordenar columnas (el orden lo fija la base).
- **Pruebas (2026-11-10, todas en verde):** db reset desde cero; lint, tipos y formato; Vitest 265; pgTAP 2.133 en 46 archivos; Playwright 217 de 217 en celular y computadora, con axe. Pruebas nuevas: cursor, pestañas y local de arriba en Personas; pestañas de la ficha y «Volver a personas»; cursor y local en Historial; «Salir» dentro de «Menú» en el celular. Capturas en 1440, 1600, 1920, tablet y celular.
- **Revisores:** security-auditor apto, sin graves ni medios; los 4 menores corregidos (el título y los botones del encabezado repiten el control de permisos; un local fuera del alcance se dice; un cursor a medias vuelve al principio; Mi cuenta confirma la sesión antes de leer). ui-reviewer: los 5 medios corregidos (tarjetas que decían «Operando» con 0, tarjetas sin enlace, título de la ficha de persona, enlace al Historial que forzaba «todos», «la otra sesión» en singular) y casi todos los menores.
- **Quedó para después (menores):** una parada de teclado de más en las tablas que no se desplazan (el precio de cumplir axe en las que sí); el selector de persona del Historial lista hasta 100 (falta un buscador); los cambios críticos se ven como tarjetas en el tablero y como tabla en el Historial; la fila de 4 tarjetas aprieta entre 800 y 1200 px (también en Inicio y Calidad); en el celular, la pestaña «Sesiones» de Mi cuenta queda cortada en el borde (la misma pista de «hay más pestañas» que falta en Recetas).
- **Decisión de Joaco (2026-11-10): TanStack Table sale del stack.** Ya no la usaba ninguna pantalla (la tabla común ordena y pagina en el servidor). Se quitó la dependencia y se actualizaron CLAUDE.md y ADR-0036.
- **Sigue:** volver a la Fase 2 (pendientes de «Antes: aviso de rendimiento»).

## Antes: rediseño, PR 3 de 4 (fusionado, PR #51)

- **Qué se hizo** (ADR-0036, adenda del PR 3; sin cambios en la base):
  - **Materias primas:** lista con filtros que se aplican solos, pestañas de estado, orden por nombre o código y 15 por página; alta en un modal (el mismo formulario de `/materias-primas/nueva`); ficha en 6 pestañas (`?seccion=`) con «← Volver» que conserva los filtros.
  - **Reportes:** sin selector de local propio (usa el de arriba y, con «Todos mis locales», pide uno); período y búsqueda de receta que se aplican solos; paginación común; exportaciones en tabla. La tabla del reporte sigue propia por la impresión (encabezado repetido en cada hoja).
  - **Calidad:** panel con «Requiere atención», 4 tarjetas con `Metric` (las mismas de Inicio, ahora en `components/quality-board.tsx`), barras de avance y comparación entre locales en tabla; la lista de un indicador con tabla, paginación y «Ir» directo a la pestaña donde se corrige.
  - El aviso de rendimiento desviado abre la ficha en «Rendimientos» (`lib/notices.ts`).
- **Pruebas (2026-11-10, todas en verde):** db reset desde cero; lint, tipos y formato; Vitest 262; pgTAP 2.133 en 46 archivos; Playwright 210 de 210 en celular y computadora, con axe. Pruebas nuevas: orden, paginación y pestañas de Materias primas; pestañas de la ficha y volver con filtros; foco del modal; Reportes y Calidad con el local de arriba (también cambiándolo con un reporte o una lista abiertos). Capturas en 1440, 1600, 1920, tablet y celular.
- **Revisores:** security-auditor apto, sin graves ni medios. ui-reviewer: 1 grave (cambiar el local arriba con un reporte o una lista de Calidad abiertos daba «no encontrado») y 4 medios (foco al cerrar el modal, nombre de los enlaces de Calidad, la comparación que tumbaba la pantalla, filtros sin JavaScript), todos corregidos y probados, más varios menores.
- **Quedó para después (menores de la revisión):** la fila de 4 tarjetas aprieta entre 800 y 1200 px (también en Inicio); una pista de que hay más pestañas en el celular (también en Recetas); el aviso de alérgenos sin validar armado a mano; si fallan las «Últimas exportaciones», la tarjeta desaparece sin aviso; quien propone precios sin `catalogManage` ve vacío el desplegable de proveedor (ya pasaba antes).
- **Para Joaco:** Reportes y Calidad pasan de 50 a 15 filas por página, como el resto (se puede elegir 10, 25 o 50).
- **Siguió:** PR 4, Aprobaciones, Usuarios, Historial, Roles, Mi cuenta y Panel de control.

## Antes: superadministrador de prueba sin MFA (TEMPORAL; fusionado, PR #49)

- **Qué se hizo** (ADR-0037, pedido de Joaco del 2026-11-10): un rol `superadmin_test` con los permisos del Superadministrador y sin doble verificación, y la persona `superadmin.prueba@ejemplo.test`. Va en un script aparte, `supabase/dev/test-superadmin.sql`, no en migraciones ni en el seed: la regla de MFA no cambia para nadie más.
- **Cómo se usa:** en local, `npm run db:test-admin` después de cada `npm run db:reset`, con la contraseña local del seed. En staging, Actions → «Publicar en staging» → «Crear el superadministrador de prueba», con el secreto `STAGING_TEST_ADMIN_PASSWORD`, que tiene que crear Joaco.
- **Probado:** en local el script corre dos veces sin duplicar nada y deja la auditoría; en el navegador entra sin código y ve Usuarios, Roles y permisos e Historial; el Superadministrador de siempre sigue pidiendo el código.
- **Ojo:** con el script corrido, `040` y `050` fallan en local (11 roles). Antes de las pruebas, `npm run db:reset`.
- **Revisión de seguridad:** apto, sin graves. Corregido: la contraseña viaja solo en una consulta con hash de costo 10; el script corre solo si el único grupo es el ficticio; la auditoría lleva el número de corrida; una prueba de Vitest vigila que no aparezca en otro flujo, en migraciones ni en el seed.
- **Mientras exista (ADR-0037):** no cargar un segundo Superadministrador en staging (el de prueba lo podría suspender sin Dirección) y no aprobar pedidos de «Superadministrador de prueba» para otras personas.
- **Pendiente:** **quitarlo antes de la Fase de producción**: el script, la opción de Actions y el secreto; en staging, quitarle el rol, desactivar la cuenta y dar de baja los permisos del rol y el rol (desactivar solo no alcanza).
- **Sigue:** PR 3 del rediseño, Materias primas, Reportes y Calidad.

## Antes: rediseño, PR 2 de 4 (fusionado, PR #48)

- **Qué se hizo** (ADR-0036, adenda del PR 2):
  - **Inicio** como panel: aviso «Requiere atención», 4 KPIs, comparación entre locales y tareas pendientes.
  - **Costos** como listado: KPIs confiables («Sin recetas con costo calculado»), pestañas por confiabilidad, tabla ordenable en la base (`p_order`, migración autorizada) y paginación.
  - **Recetas:** listado con filtros, pestañas y orden; alta en un modal; ficha en 9 pestañas con barra Guardar / Cancelar fija y aviso de cambios sin guardar.
  - **Sin selectores de local propios** en Inicio, Costos y Escenarios.
- **Decisiones de Joaco (2026-11-09):** un solo PR; la migración del orden; «Crítico» gana; la ficha por pestañas.
- **Pruebas (2026-11-10):** db reset desde cero; lint, tipos y build; Vitest 258; pgTAP 2.133 en 46 archivos (245_cost_order con 25). Playwright en la corrida completa: 196 de 198. Las 2 que fallaron se corrigieron y pasan solas, con la base recreada (18 de 18): `materias-primas.spec` contaba también la búsqueda global de la barra superior (ahora mira solo el contenido) y `admin.spec` en celular, donde el ingreso con doble verificación terminó en el Inicio una vez (intermitente; ya se había visto en costos). Capturas en 1440, 1600, 1920, tablet y celular.
- **Revisores:** db-reviewer, security-auditor y ui-reviewer sin graves. Corregido: la prueba del orden ahora puede fallar de verdad (25 aserciones, las 12 combinaciones); la pestaña Costos sin versión; volver sin perder filtros; la barra fija arriba de la barra inferior del celular; el aviso de cambios sin guardar en los formularios de la ficha; nombres, «—» cuando falta un dato, página máxima 1.000.
- **Arreglado de paso:** `234_cost_screens` fallaba entre las 21 y las 24 de la Argentina (usaba la fecha UTC). Ahora usa `recipes.today()`.
- **Quedó para después:** el título de la ficha dice «Receta» y no el nombre (el nombre está en el encabezado de la tarjeta); la lista de Importaciones todavía sin la tabla nueva (va con el PR 4).

## Antes: rediseño, PR 1 de 4 (fusionado, PR #47)

- **Qué se hizo** (ADR-0036, prompt de rediseño de Joaco del 2026-11-09): paleta y tipografía nuevas; layout global (barra lateral fija de 240/68 px que se recuerda en una cookie, barra superior con ruta, selector global de local, búsqueda, avisos y perfil, área fluida, barra inferior en el celular); biblioteca de componentes (tabla con orden y paginación en el servidor, filtros que se aplican solos, paginación de 15, pestañas, barra de avance, modal, panel lateral, confirmación, estados, métrica confiable); búsqueda global en /buscar. Reglas actualizadas: design.md y CLAUDE.md («computadora para operar, celular para supervisar»).
- **Decisiones de Joaco (2026-11-09):** 4 PR por fases; la barra se recuerda en el navegador; se conservan «En revisión» y «Borrador»; la búsqueda trae recetas y materias primas.
- **Pruebas (2026-11-09, todas en verde):** db reset desde cero; lint, tipos y build; Vitest 257 (contraste de la paleta, navegación, listados, métricas y enlaces internos); pgTAP 2.108 en 45 archivos; Playwright 194 en celular y computadora, con axe (layout.spec nuevo: barra lateral en 1440, 1600 y 1920 px, sin desborde en 800 y 1024 px, barra inferior, selector global y búsqueda). Se actualizaron pruebas por cambios buscados: diseno.spec (paleta nueva y 40 px en la computadora), el helper del menú (botón «Menú» visible). Capturas en 1440, 1600, 1920, tablet y celular.
- **Revisores:** security-auditor apto, sin graves ni medios (menores corregidos: enlaces solo internos y cookie Secure en https). ui-reviewer sin graves; los 8 medios corregidos (foco en la barra oscura, activo del celular no solo por color, barra superior sin desborde entre 800 y 1280 px, un solo h1 con acciones, comparación en la métrica, contraste del texto de ejemplo, campo en /buscar, anuncio de la paginación) y casi todos los menores.
- **Mientras no se migren los módulos:** las tablas viejas van dentro de un contenedor con scroll propio (con la barra lateral el contenido es más angosto que la ventana). Se reemplazan por DataTable en los PR 2 a 4.
- **Quedó para después:** «Salir» del celular dentro de «Menú» (cambia cómo cierran sesión todas las pruebas; va con Mi cuenta); el salto inicial cuando la barra está contraída; un borde más marcado para los campos. **Para Joaco:** si un dato vencido además es «Crítico», hoy gana «Desactualizado» (como dice la tabla de design.md).
- **Sigue:** PR 2, Inicio, Recetas y Costos.

## Antes: aviso de rendimiento (fusionado, PR #46)

- **Qué se hizo** (ADR-0035): si un ensayo de rendimiento se desvía del estándar que usa el costo más que un umbral (10 % de fábrica), llega un aviso en /aprobaciones a quien tiene `yields.alerts` en ese local: Chef, Controller, Director de marca y Dirección General. El umbral se cambia en /configuracion/precios. La ficha de la materia prima marca cuando el promedio de los ensayos pasa el umbral.
- **Decisiones de Joaco (2026-11-09):** umbral de 10 %; permiso nuevo; lo cambia quien tiene `prices.configure`; también lo tienen el Director y Dirección (nadie da un permiso que no tiene); se compara contra el estándar del costo.
- **Pruebas (2026-11-09):** db reset desde cero; lint y tipos; Vitest 238; pgTAP 2.108 en 45 archivos (244_yield_alerts con 40), con una salvedad: en la corrida completa, la prueba de rendimiento 175 dio 475 ms en «la Cocinera cuenta sus recetas» (tope 300 ms); la rama no toca recetas, antes había pasado y corrida sola pasó 3 de 3. Playwright 184 de 184 en celular y computadora, con axe. Capturas del aviso, la ficha y la configuración.
- **Revisores:** db-reviewer, security-auditor y ui-reviewer sin graves. Corregidos: el estándar del costo, las pruebas de corte y de proveedor, que cambiar el umbral no pise el resto (`costing.update_yield_alert`), `catalog.view` para recibir el aviso, el texto del aviso en palabras de cocina y la etiqueta en celulares angostos.
- **Para Joaco:** el Controller figura como «nunca gramajes», pero puede leer los gramos de los ensayos desde la 2.1 B. Si eso no va, se cierra en un PR aparte.
- **Falta después:** `recipes.approve_costs`, huecos de recetas, aprobación en varios pasos (Chef → Compras → Gerente, con su plan), las compuertas con datos reales y el informe de cierre para Soy.

## Antes: fichas por receta (etapa 2.5; fusionado, PR #45)

- **Qué se hizo** (ADR-0034): ficha técnica y ficha de costeo de una receta, en PDF, Excel y CSV. Con esto están los siete reportes de la sección 18, y queda construido lo que pide Soy para la Fase 2.
- **Pruebas (2026-11-08, todas en verde):** db reset desde cero; lint y tipos; Vitest 235; pgTAP 2.068 en 44 archivos (243_recipe_cards con 32); Playwright 180 en celular y computadora, con axe. Capturas de las dos fichas en celular, computadora y papel.
- **Revisores:** db-reviewer y security-auditor sin graves. Se corrigieron las medias: la base controla que la receta sea del local (`costing.require_report_recipe`), el registro guarda la receta, y las pruebas que no podían fallar ahora pueden. ui-reviewer marcó un grave (la ficha técnica sin alérgenos): corregido, en pantalla, papel, Excel y CSV.
- **Quedó afuera:** la lista compacta de la ficha técnica en celular (hoy son tarjetas, una por ingrediente) y que /reportes muestre la receta en "Últimas exportaciones" (el registro ya la guarda).
- **Falta después:** los agregados chicos (aviso de rendimiento, `recipes.approve_costs`, huecos de recetas, aprobación en varios pasos), las compuertas con datos reales y el informe de cierre para Soy.

## Antes: reportes (etapa 2.5; fusionado, PR #44)

- **Qué se hizo** (ADR-0034): `/reportes`, con cinco reportes en PDF, Excel y CSV: materias primas, rendimientos, dónde se usa, cambios de costo y calidad de datos. Lo que se exporta queda en el registro de seguridad.
- **Pruebas (2026-11-07), `npm run test` completo desde una base recién creada:** lint y tipos ✅ · Vitest 231 de 231 ✅ · pgTAP 2.036 de 2.036 ✅ · Playwright 178 de 178 ✅ · formato ✅.
- **Revisión:** `db-reviewer`, `security-auditor` y `ui-reviewer`. Los graves están corregidos y casi todos los medios también. Las correcciones no volvieron a revisión.
- **Decisiones de Joaco:** el PDF sale de la impresión del navegador; "Cambios de costo" muestra lo que pasó en el período, aunque la receta ya no se use; una versión nueva aparece marcada como "Cambió la receta" (ADR-0034).
- **Queda sin hacer:** medir "Cambios de costo" con años de historia, poner un tope a `log_report`, y la vuelta en texto plano cuando se pierde el permiso con la pantalla abierta.
- **Sin comprobar:** una impresora real, Safari en iPhone (`window.print` después de esperar al registro) y un CSV abierto en un Excel argentino de verdad.
- **Falta después:** las dos fichas por receta (técnica y de costeo), y las compuertas con datos reales y el informe de cierre para Soy.

## Antes: tablero de Inicio (etapa 2.5, PR 2; fusionado, PR #43)

- **Qué se hizo** (ADR-0033): el Inicio responde "¿qué tan completo y confiable está nuestro recetario?", con 6 tarjetas, un gráfico, costos y actividad. El cocinero ve el Inicio de siempre.
- **Pruebas (2026-11-07), `npm run test` completo desde una base recién creada:** lint y tipos ✅ · Vitest 211 de 211 ✅ · pgTAP 1.983 de 1.983 ✅ · Playwright 160 de 164. Las 4 que faltaron (`fase1` y `materias-primas`, en celular y computadora) las rompió el tablero: el saludo había dejado de mostrar los roles, y la prueba encontraba dos paneles de filtros. Corregidas, `fase1`, `materias-primas`, `inicio` y `cuenta` pasaron solas, 44 de 44, sin otra corrida completa.
- **Revisión:** `db-reviewer`, `security-auditor` y `ui-reviewer`. Los graves y los medios están corregidos, salvo los dos selectores de local. Las correcciones no volvieron a revisión.
- **Decidido sin consultar, a confirmar por Joaco:** "Costo por corregir" como nombre, y que una receta que recién tiene costo se muestre como "Ahora tiene costo".
- **Falta después:** `/reportes`, que espera la decisión del PDF. Después, las compuertas con datos reales y el informe de cierre para Soy.

## Antes: calidad de datos (etapa 2.5, PR 1; fusionado, PR #42)

- **Qué se hizo** (ADR-0033): `/calidad`. Once indicadores por local, en dos ejes, y cada uno abre la lista de lo que hay que corregir. Quien ve más de un local los compara.
- **Pruebas (2026-11-06), `npm run test` completo desde una base recién creada:** lint y tipos ✅ · Vitest 209 de 209 ✅ · pgTAP 1.950 de 1.950 ✅ · Playwright 156 de 156 ✅ · formato ✅. Después cambiaron dos textos de pantalla, y `calidad` volvió a pasar sola.
- **Revisión:** `db-reviewer`, `security-auditor` y `ui-reviewer`. Los graves están corregidos y los medios también, salvo los que siguen. Las correcciones no volvieron a revisión.
- **Decisiones de Joaco:** se cuentan todas las recetas, aunque la persona no las vea, y cuentan también las sin publicar de la marca y del grupo (ADR-0033).
- **Queda sin hacer:** "Reintentar" en `app/error.tsx` usa `reset()`, que en Next 16 no vuelve a traer los datos: pasa en toda la app. La tarea de la noche no avisa si falla. La comparación muestra 20 locales como máximo.
- **Sin comprobar:** la tarea de la noche disparándose a su hora, un celular físico y los estados de carga y error en pantalla.
- **A confirmar con Joaco:** las excepciones a las reglas de tableros de ADR-0033.
- **A validar con el Controller:** las definiciones de ADR-0033 (costo completo, unidad normalizada, posible duplicado).
- **Falta después:** PR 2, el tablero de Inicio. Después, `/reportes`, que espera la decisión del PDF.

## Antes: retiro del documento de ensayo (fusionado, PR #41)

- **Qué se hizo** (ADR-0023): se retiró `core.test_documents` y `/ensayo`. Las pruebas 2, 3 y 7 de la Fase 1 pasan sobre recetas reales en `238_fase1_recetas_reales`. La auditoría vieja queda.
- **Pruebas (2026-11-05), `npm run test` completo desde una base recién creada:** lint y tipos ✅ · Vitest 201 de 201 ✅ · pgTAP 1.898 de 1.898 ✅ · Playwright 142 de 142 ✅ · formato ✅.
- **Revisión:** `db-reviewer`, `security-auditor` y `ui-reviewer`. El grave (una prueba que no podía fallar, también en `170` y `190`) y los medios están corregidos. Sus correcciones no volvieron a revisión.
- **Además:** el Inicio suma "Recetas": en el celular, el cocinero la tenía solo detrás del menú. La exportación del historial ya tiene prueba de que tapa los costos.
- **Antes de aplicar en producción:** contar las solicitudes pendientes. Las de asignar un rol van a fallar con "los permisos del rol cambiaron" y hay que pedirlas de nuevo; las de cambiar `test_documents.*`, rechazarlas. Falla cerrado.
- **GitHub Actions:** la primera corrida del PR se cortó con 80 pruebas de Playwright en verde y ninguna fallada. El trabajo tenía un límite de 45 minutos: se subió a 90. Si sigue creciendo, repartir Playwright en varios trabajos.
- **Queda sin hacer:** `formatMoney` de `lib/data.ts` quedó sin uso.
- **Falta después:** la etapa 2.5 (Inicio, `/calidad` y `/reportes`, que espera la decisión sobre el PDF) y la compuerta 2.3 con el Controller.

## Antes: escenarios (etapa 2.3, PR 3C; fusionado, PR #40)

- **Qué se hizo** (ADR-0032): `/costos/escenarios`. Se simula un precio (también de otro proveedor), un rendimiento o un gramaje en un local, y se ve cuánto cambia cada receta. Nunca toca lo oficial. Con esto se cierra el contenido de la etapa 2.3.
- **Pruebas (2026-11-04), `npm run test` completo desde una base recién creada:** lint y tipos ✅ · Vitest 202 de 202 ✅ · pgTAP 1.883 de 1.883 ✅ · Playwright 141 de 142. La que faltó (`escenarios`, celular) la rompió la prueba nueva de anchos, que no volvía al tamaño original. Corregida, `escenarios` pasó sola, 6 de 6 en celular y computadora, sin otra corrida completa.
- **Revisión:** `db-reviewer`, `security-auditor` y `ui-reviewer`. Sus graves y medios están corregidos, salvo los que siguen.
- **A confirmar con Joaco:** si un precio simulado puede completar una receta incompleta (hoy sí, con la etiqueta "Simulado"). Y lo que ya estaba: las excepciones a las reglas de tableros, la excepción a la auditoría, el aviso de costo sin porcentaje y la planilla DEMO.
- **Queda sin hacer:** los desplegables de materias primas y recetas no tienen búsqueda, y la lista de escenarios corta en 200, con aviso. Con un precio todavía en la cola, la diferencia puede ser engañosa hasta que se procese.
- **Sin comprobar:** un celular físico, un escenario archivado en pantalla, la paginación real (más de 50 recetas) y la etiqueta "No se aplica". Dos cargas a la vez tampoco se probaron.

## Antes: escalado (etapa 2.3, PR 3B; fusionado, PR #39)

- **Qué se hizo** (ADR-0032): `/recetas/[id]/escalar`, con factor, cantidades, líneas para ajustar a mano, aviso de más tandas, costo proyectado e impresión. El editor de pasos pide equipo y capacidad.
- **Pruebas (2026-11-04), `npm run test` completo desde una base recién creada:** lint y tipos ✅ · Vitest 191 de 191 ✅ · pgTAP 1.780 de 1.780 ✅ · Playwright 136 de 136 ✅ · formato ✅. Después hubo ajustes chicos: pasaron Vitest (192), `236` (48) y Playwright de `escalado` y `recetas`, sin otra corrida completa.
- **Falta:** una impresión en una impresora real, para ver los cortes de página.
- **Falta en esta etapa:** PR 3C (escenarios), con su plan. Después, retirar `core.test_documents`.
- **A confirmar con Joaco:** las excepciones a las reglas de tableros, la excepción a la auditoría, el aviso de costo sin porcentaje y la planilla DEMO.

## Antes: costos al día (etapa 2.3, PR 3A; fusionado, PR #38)

- **Qué se hizo** (ADR-0032): tarea diaria, foto de fin de mes, cierre de recálculos fallidos, aviso con impacto de costo e `integration_outbox`.
- **Pruebas (2026-11-04), `npm run test` completo desde una base recién creada:** lint y tipos ✅ · Vitest 184 de 184 ✅ · pgTAP 1.734 de 1.734 ✅ · Playwright 130 de 130 ✅ · formato ✅. Después se ajustó una prueba de `235`, que pasó sola.
- **Al retomar (Joaco):** abrir el PR de `feat/costos-al-dia` contra `main` y mirar GitHub Actions. Después, armar el plan del PR 3B.
- **Sin comprobar:** las dos tareas programadas disparándose a su hora. `ui-reviewer` no revisó este PR.
- **Falta en esta etapa:** PR 3B (escalado) y PR 3C (escenarios), cada uno con su plan. Después, retirar `core.test_documents`.
- **A confirmar con Joaco:** las excepciones a las reglas de tableros, la excepción a la auditoría en las fotos y la cola, y la planilla DEMO.

## Antes: pantallas de costos (etapa 2.3, PR 2 de 3; fusionado, PR #37)

- **Qué se hizo** (ADR-0032, sección PR 2): `/costos`, el detalle de una receta, el impacto de un precio, y el costo en la lista y la ficha de recetas.
- **Pruebas (2026-11-04), desde una base recién creada:** lint y tipos ✅ · Vitest 183 de 183 ✅ · pgTAP 1.684 de 1.684 ✅ · Playwright 126 de 128 en la corrida completa. Las 2 que faltaron (Chef, celular y computadora) esperaban un texto viejo; corregido, `costos` pasó sola en los dos proyectos. Sin otra corrida completa después.
- **Cambios contra lo anotado:** `core.test_documents` se retira en un PR aparte, y el aviso con impacto de costo pasa al PR 3.
- **A confirmar con Joaco:** las excepciones a las reglas de tableros (ADR-0032), la excepción a la auditoría en las fotos y la cola, y la planilla DEMO.
- **Falta:** PR 3 (escalado, escenarios, tarea diaria, fin de mes, `integration_outbox`, aviso con impacto), PR de retiro de `core.test_documents`, reintentar o descartar recálculos fallidos.

## Antes: motor de costos (etapa 2.3, PR 1 de 3; fusionado, PR #36)

- **Qué se hizo** (ADR-0032): cada receta tiene costo en cada local, con y sin IVA, por porción y con su confiabilidad.
  - **Cantidades congeladas al publicar:** una densidad nueva ya no mueve una receta publicada.
  - **Fotos históricas** que no cambian, y **cola de recálculo** cada minuto: aprobar un precio tarda milisegundos.
  - **Variantes:** un plato usa la variante de su local.
- **Decisiones de Joaco:** ver ADR-0032 (qué ve el Chef, qué ve Compras, cola y bajas de precio).
- **Falta en esta etapa:**
  - **PR 2:** pantallas (costos en la receta, `/costos`, impacto de un precio), mostrar los errores de la cola y retirar `core.test_documents`.
  - **PR 3:** escalado, escenarios, tarea diaria (precios con fecha futura y "desactualizado") y `integration_outbox`.
- **Compuerta 2.3:** Joaco y el Controller validan [docs/guias/costos-demo.md](guias/costos-demo.md).
- **Pruebas (2026-11-03), desde una base recién creada:** lint y tipos ✅ · Vitest 174 de 174 ✅ · pgTAP 1.642 de 1.642 ✅ · formato ✅ · Playwright 117 de 118 en la corrida completa. La que faltó (`admin`, celular) falló en la primera carga del servidor y pasó sola, en celular y computadora.
- **Producción:** Joaco lo ve después.
- **Al retomar (Joaco):**
  1. abrir el PR de `feat/costos-motor` contra `main` y mirar GitHub Actions (hay que confirmar Playwright completo);
  2. confirmar la excepción a la auditoría en las fotos y la cola (aprobada solo para el costo vigente);
  3. validar la planilla de costos DEMO con el Controller;
  4. después de fusionar, armar el plan del PR 2 (pantallas).
- **Sin causa encontrada:** una vez falló el reset de la base al iniciar el contenedor, y después anduvo cuatro veces seguidas.

## Antes: pantallas de precios (fusionado, PR #35)

- **Qué se hizo** (ADR-0029, sección "PR 2"):
  - **ficha de materia prima:** tarjeta "Precios" (solo con `prices.view`) con el costo en el local, los precios vigentes, el historial y "Proponer precio";
  - **aprobaciones:** resumen propio de los precios, con la variación contra hoy y contra hace N días; la tarjeta dice cuándo pasó a Dirección General;
  - **Panel de control → Precios:** el %, los días hacia atrás y los de desactualizado, y los días por categoría (Dirección General);
  - **subas en escalones** (respuesta 8 de Soy): migración `20261111120000_prices_lookback.sql`.
- **Revisiones:** `security-auditor` apto; `db-reviewer` y `ui-reviewer` sin graves, medios resueltos.
- **Pruebas (2026-11-03), `npm run test` completo desde una base recién creada:** lint y tipos ✅ · Vitest 174 de 174 ✅ · pgTAP 1.487 de 1.487 ✅ · Playwright 118 de 118 ✅ · formato ✅.
- **Confirmado por Joaco:** una baja grande también pasa a Dirección.

## Antes: panel de control de la estructura (rama `feat/panel-estructura`)

- **Qué se hizo** (ADR-0031): el "Panel de control" (`/configuracion`), que pidió Soy para cargar los datos reales.
  - **marcas** (alta, nombre, código y estado);
  - **locales** (alta con tipo y razón social en un paso, datos, tipo y estado);
  - **áreas** de cada local;
  - **razones sociales** (CUIT con o sin guiones, condición frente al IVA, qué locales usa cada una y cuáles no tienen).
- **Quién puede:** se carga con Superadministrador (decisión de Joaco). No cambió ningún permiso: la Directora maneja su marca, el Gerente los datos y áreas de su local, y la razón social la elige solo quien administra el grupo.
- **Base:** migración `20261110120000_org_panel.sql`. `create_restaurant` acepta tipo y razón social, y arregla un error de la Fase 1: una fecha de apertura vacía rompía el alta.
- **Revisiones:**
  - `security-auditor`: apto;
  - `db-reviewer`: sin graves, sus 2 medios resueltos;
  - `ui-reviewer`: su grave (un aviso falso de "sin razón social") resuelto.
- **Pruebas (2026-11-03), `npm run test` completo desde una base recién creada:** lint y tipos ✅ · Vitest 167 de 167 ✅ · pgTAP 1.466 de 1.466 ✅ · Playwright 110 de 110 ✅ · formato ✅.
  - La prueba `admin` («Dirección ve los 4 locales») ahora busca los 4 locales del seed por nombre y no por cantidad: el panel crea locales en la misma base. La del Gerente sigue exacta.
  - Ojo: `npm run test` corre pgTAP sobre la base que dejó la corrida anterior de Playwright. Antes de correrlo, `npm run db:reset`.
- **Fuera de esta versión:** archivar y restaurar, y el traspaso de un local.
- **Respondido por Joaco (2026-11-03):** el Gerente puede cambiar el código de su local, y los locales cerrados siguen apareciendo en «Personas por local». Queda como está.
- **Después:** con producción creada (plan Pro), Joaco y Soy cargan juntos los datos reales desde el panel.

## Antes: terceras respuestas de Soy (ADR-0030)

- **Registradas en ADR-0030.** Lo que cambia el plan:
  - **plan pago de Supabase: sí.** Joaco crea el proyecto de producción con la cuenta de Soy;
  - **datos reales:** Soy pide un **panel de control** para dar de alta marcas, locales y razones sociales; cuando esté, los cargan juntos (en producción, nunca en desarrollo);
  - **"administración maestra":** un permiso que se asigna desde el panel de roles, no un rol fijo;
  - **aprobación de recetas en varios pasos:** el "Salón" es el Gerente del local; el orden es Chef → Compras → Gerente;
  - **aviso de rendimiento:** umbral cargado a mano y aviso al Chef y al Controller;
  - **precios:** confirma la comparación contra el costo de hoy; pide además comparar contra el precio de hace 30 días (subas en escalones) y que el % lo cambie "el administrador";
  - **otros negocios:** no por ahora.
- **Próximo, en este orden:**
  1. **panel de control de la estructura del grupo** (marcas, locales y razones sociales): es lo que frena la carga real;
  2. **2.1 C, PR 2:** pantallas de precios, configuración y subas en escalones;
  3. **producción**, con la carga de datos reales junto a Soy y la compuerta 2.4;
  4. **2.3, motor de costos;** después, la aprobación en varios pasos, con su plan.
- **A confirmar con Soy:**
  - ¿"el administrador" del % es Dirección General o el Superadministrador?
  - ¿el permiso de "administración maestra" nace asignado a algún rol?
  - en una receta que usan varios locales, ¿aprueba un Gerente por local?

## Antes: etapa 2.1 C, precios (PR 1 de 2, base; fusionado, PR #32)

- **Estado:** fusionado (PR #32).
- **Qué se hizo:** migración `20261109120000_prices.sql`. Detalle en ADR-0029.
  - **razones sociales** (`org.legal_entities`) y la de cada local: deciden si el costo va con o sin IVA;
  - **precios solo de inserción y solo aprobados** (`costing.price_records`), con neto y bruto calculados por la base y el contenido del envase congelado al aprobar;
  - **aprobación:** Compras propone, aprueba el Controller y, si la variación contra el costo que se usa hoy supera el % del grupo (15 por defecto), también Dirección General;
  - **configuración del grupo** (% y días de desactualizado), solo Dirección General (`prices.configure`);
  - **qué precio vale** en un local (local → marca → grupo, el último aprobado) y el costo de una línea: `costing.resolve_price`, `resolve_prices` e `ingredient_line_cost`, nunca $ 0;
  - **el Gerente** ve los precios y costos de su local (respuesta 7 de Soy).
- **Decisiones de Joaco (2026-11-02):** 10, en ADR-0029. Entre otras:
  - el último aprobado entre varias presentaciones;
  - Controller y después Dirección;
  - la variación contra el costo que se usa hoy;
  - el contenido congelado al aprobar;
  - ninguna fecha anterior al precio que vale hoy;
  - la razón social de un local la elige solo quien administra el grupo;
  - los fletes quedan para después.
- **Revisiones:**
  - `db-reviewer`: dos pasadas; los graves y medios quedaron resueltos o aceptados por escrito;
  - `security-auditor`: cuatro pasadas; la última, **apto**, sin graves ni medios. Todos los caminos que encontraron para mover un costo sin aprobación quedaron cerrados y con prueba.
- **Pruebas nuevas:** `210`, `211` y `212` (500 materias primas por debajo de 300 ms). Snapshots actualizados a propósito: `000`, `030`, `050` y `140`.
- **Pruebas (2026-11-02), `npm run test` completo desde una base recién creada:** lint y tipos ✅ · Vitest 148 de 148 ✅ · pgTAP 1.442 de 1.442 ✅ · Playwright 98 de 98 ✅ · formato ✅.
- **Preguntas para Soy:** se le pasaron a Joaco el 2026-11-02 (plan de Supabase, datos reales del grupo, "administración maestra", pasos de aprobación y Salón, aviso de rendimiento, variación de precio y subas en escalones, otros negocios, compras excepcionales).
- **Pendiente:**
  - el PR 2, con las pantallas: precios en la ficha, proponer, la bandeja y la configuración. Tiene que pedir que no se escriban montos en el motivo;
  - **pregunta abierta para Joaco y Soy:** ¿se miden las subas en escalones (varias por debajo del %) contra el precio de hace N días?
  - **para la 2.3:** congelar la cantidad de las líneas de receta en la unidad de uso, porque hoy una densidad nueva la cambia sin aprobación.

## Antes: etapa 2.4, importar el recetario de Excel (PR 2 de 2, lector y pantallas; fusionado, PR #31)

- **Sale de la rama del PR 1** (`feat/importar-recetario`), que **ya está fusionada (PR #28)**: el PR 2 va contra `main`.
- **Estado:** fusionado (PR #31).
- **Pruebas (2026-11-02), `npm run test` completo desde una base recién creada:** lint y tipos ✅ · Vitest 161 de 161 ✅ · pgTAP 1.316 de 1.316 ✅ · Playwright 102 de 102 ✅ (con axe, en celular y computadora).
  - En la corrida anterior falló `materias-primas.spec.ts:22`: la importación de prueba creaba "MUZZA DEMO" y la búsqueda "muzz" encontraba 2. Se arregló en la causa: el Excel DEMO usa nombres que ninguna otra prueba busca ("QUESO TYBO XLS", "ZAPALLO XLS", etc.).
- **Pantallas:** miradas en capturas de celular y computadora (subir, vista previa y lista).
- **El arreglo del sellado ya está fusionado (PR #29):** esta rama trae `main` con ese cambio. Con las dos migraciones juntas, desde una base recién creada: pgTAP 1.330 de 1.330 ✅.
- **Qué se hizo** (detalle en ADR-0027, "Cómo quedó (PR 2)"):
  - **lector del Excel** en el servidor con ExcelJS 4.4.0 (`lib/imports/recipe-book.ts`), con topes contra archivos enormes;
  - **el navegador sube el Excel directo al bucket** (Vercel no acepta más de 4,5 MB por pedido) y una acción de servidor lo lee con la sesión de quien lo subió;
  - **pantallas:** `/recetas/importar` (lista), `/nueva` (subir) y `/[id]` (vista previa, confirmar materias primas o recetas, validar, cancelar, recetas creadas, problemas y su CSV). Botón "Importaciones" en Recetas;
  - **migración `20261108120000_imports_upload_checks.sql`:**
    - lee su archivo quien lo subió, mientras importe en la marca;
    - se sube solo a nombre propio;
    - la importación se registra solo sobre un archivo propio;
    - una carga cortada no se valida (`expected_rows`).
- **Excel real de Nonnos:** comprobado **solo leyéndolo**, con una prueba temporal borrada; nunca entró en la base. 161 materias primas, 65 preparaciones, 135 platos y 602 líneas, iguales al análisis inicial. Se lee en unos 15 s.
- **Revisiones:**
  - `ui-reviewer`: sin graves, 5 medios resueltos;
  - `security-auditor`: apto, sin graves. 2 de sus 3 medios resueltos;
  - `db-reviewer`: 1 grave (una prueba) resuelto; la segunda pasada, sin graves ni medios.
- **Pendiente para decidir con Joaco antes de producción:** los **archivos huérfanos** del bucket (medio 2 de seguridad). Un Excel que se subió pero no se importó queda guardado y nadie lo puede borrar. Propuesta: una limpieza programada en el servidor y una regla de cuántos días se guardan.
- **Pendiente para la próxima migración de importaciones:** que `parsed` acepte solo valores simples (menor 4 de seguridad).
- **Después del PR 2, la compuerta 2.4 (en producción):** Joaco y el Chef cargan el Excel real de Nonnos y verifican que no haya duplicados. El Excel real nunca entra en desarrollo.

## Antes: arreglo del sellado de la auditoría (fusionado, PR #29)

- **Qué pasaba:** el sellado de la auditoría y del registro de seguridad salteaba eventos nuevos en el medio de la secuencia. Eso dejaba huecos, y la verificación daba "alterado" sin que nadie hubiera tocado nada: una falsa alarma. Detalle en ADR-0028.
- **Qué se hizo:** migración `20261107120000_audit_seal_contiguous.sql`.
  - el sellado toma solo el tramo continuo de la secuencia;
  - un evento con fecha futura se rechaza, porque frenaría el sellado.
- **Pruebas:** nueva `025` (14 casos). Contra el código anterior fallan 10.
- **Revisiones:** `security-auditor` apto; `db-reviewer` sin graves. Sus menores están resueltos y el medio está documentado.
- **Pendiente antes de las importaciones grandes:** acotar la duración de las transacciones a menos que el margen del sellado (ADR-0028).

## Antes: etapa 2.4, importar el recetario de Excel (PR 1 de 2, base; fusionado, PR #28)

- **Qué se hizo:** migración `20261106120000_imports.sql`. Detalle en ADR-0027.
  - zona intermedia con vista previa, sin tocar nada oficial;
  - confirmación en dos pasos: Compras confirma las materias primas y la cocina las recetas, que quedan en borrador;
  - sin duplicados (caso 8);
  - las reglas del recetario: alcance, unidades, círculos y niveles;
  - precios aparte, solo para quien ve precios.
- **Decisiones de Joaco (2026-10-31):**
  - precios del Excel como prueba;
  - "Plato finalizado" son los platos de la carta;
  - se conservan los códigos con el prefijo de la marca;
  - un importador para las tres marcas;
  - ExcelJS en el servidor;
  - dos pasos;
  - el Chef no ve precios;
  - se acepta el riesgo de la carga de filas.
- **Revisiones:**
  - `security-auditor`: apto en la segunda pasada;
  - `db-reviewer`: 3 graves en total (2 en la primera pasada y 1 en la segunda), todos reproducidos, resueltos y con prueba.
- **Pruebas (2026-10-31):** pgTAP 1.306 de 1.306 ✅ (nuevas `200`, `201` y `205`) · lint, tipos y Vitest 145 ✅ · Playwright 88 de 88 ✅.
- **Datos reales:** el Excel de Nonnos sigue fuera del repositorio y nunca se carga en desarrollo. Se carga en producción con el PR 2.
- **Encontrado al fusionar (problema de la Fase 1, va en un PR aparte):** el sellado del registro de seguridad (`audit.seal_security_events`, que corre a los 7 minutos de cada hora) toma los eventos de más de 10 minutos aunque queden huecos en la secuencia. Si un evento con número más bajo es más nuevo, el sello deja un hueco y `verify_security_seals` lo marca inválido: una falsa alarma de registro alterado. Pasó en local al reiniciar la base a las 16:06 (la prueba `060` falla si el sellado corre dentro de los 10 minutos posteriores a un `db reset`). En producción puede pasar con transacciones cruzadas. **Arreglo:** sellar solo el tramo continuo de la secuencia, y revisar `audit.seal_events`, que podría tener la misma forma.
- **Próximo:** PR 2 de la importación:
  - lector con ExcelJS;
  - Excel ficticio de prueba;
  - pantallas de vista previa y confirmación;
  - CSV de errores escapado.

## Antes: etapa 2.2 B, subrecetas y variantes (PR 2 de 2, pantallas; fusionado, PR #27)

- **Ya fusionados:** el PR 1 (base, #25) y los avisos de la respuesta 5 de Soy (#26).
- **Qué se hizo:** sin migraciones nuevas (solo un aviso DEMO en el seed). Detalle en ADR-0025 (PR 2).
  - el buscador del editor trae materias primas y preparaciones;
  - en la ficha: "Recetas que la usan como preparación", variantes de local con el formulario para crear una, y las diferencias con la maestra;
  - la vista de cocina enlaza cada preparación con su ficha;
  - la lista tiene el filtro "Variantes de local";
  - "Aprobaciones" tiene la sección "Avisos de recetas".
- **Revisiones:**
  - `ui-reviewer`: sin graves; 5 medios resueltos;
  - `security-auditor`: apto, sin graves ni medios.
- **Pantallas:** miradas en capturas de celular y computadora.
- **Pruebas (2026-10-30):**
  - **antes de las correcciones de las revisiones, `npm run test` completo:** lint y tipos ✅ · Vitest 147 de 147 ✅ · pgTAP 1.209 de 1.209 ✅ · Playwright 98 de 98 ✅;
  - **después de las correcciones:** lint, tipos y Vitest de líneas ✅, y Playwright de recetas y subrecetas 18 de 18 ✅;
  - **corrida final (2026-10-31), con todas las correcciones:** lint y tipos ✅ · Vitest 148 de 148 ✅ · pgTAP 1.209 de 1.209 ✅ · Playwright 98 de 98 ✅.
  - Ojo: si Playwright falla en masa en el ingreso con "name resolution failed", el contenedor de Edge Functions quedó apagado (`docker start supabase_edge_runtime_grupo-lf`). Pasó el 2026-10-31.
- **Excel de Nonnos:** está en `C:\Users\julym\Downloads\proyecto Lucho\recetarios\`, fuera del repositorio. Análisis hecho: 294 insumos, 65 pre-elaborados y 66 platos.

## Antes: segundas respuestas de Soy (ADR-0026)

- **Registradas en ADR-0026.** Lo que cambia el plan:
  - **precios (2.1 C):** vienen de un sistema futuro de lectura de facturas; mientras tanto, valores simbólicos. La 2.1 C se achica a guardar precios con historia y aprobación;
  - **avisos de recetas:** a los locales que usan el plato. Ya aplicado en la rama de subrecetas;
  - **aprobación de recetas en varios pasos** (Chef, Compras y Salón, configurable): cambia el motor de aprobaciones y necesita su propio plan;
  - **alérgenos:** un rol nuevo, "Auditor externo de alérgenos", con su usuario;
  - **traspaso de local:** las recetas propias pasan al local nuevo;
  - **compuerta de la Fase 2:** todas las recetas las aprueban el Chef y la administración, no 20;
  - **Excel del recetario de Nonnos:** se importa. **El archivo no llegó al chat**: hay que dejarlo en la carpeta del proyecto.
- **Abierto con Soy:** precio mientras no haya facturas, umbral de rendimiento, "Salón" y pasos de aprobación, quién es la "administración maestra", otros negocios.

## Antes: etapa 2.2 B, subrecetas y variantes (PR 1 de 2, base, rama `feat/recetario-subrecetas`)

- **Qué se hizo (PR 1, base):** migración `20261104120000_recipes_subrecipes.sql`. Detalle en ADR-0025.
  - una línea de receta puede ser una preparación (subreceta), que usa siempre su versión vigente ("cambian solos", respuesta 10 de Soy);
  - sin círculos (caso 10), hasta 10 niveles, al alcance del plato y con una unidad como la de su rendimiento;
  - los alérgenos bajan por las preparaciones (caso 23);
  - al publicarse una preparación que otros usan, se avisa al Chef de cada plato y a Compras, Dirección y Gerencia de los locales que lo usan (caso 26, respuesta 5 de Soy, ADR-0026);
  - variantes locales: las crea el Chef Ejecutivo; al publicarse, el local deja de usar la maestra;
  - el editor de componentes ya guarda bien las líneas de preparación (las pantallas nuevas van en el PR 2).
- **Revisiones:**
  - `security-auditor`: apto, con 3 medios resueltos;
  - `db-reviewer`: 1 grave (el límite de niveles solo miraba hacia abajo, y un plato con harina en el nivel 17 decía "sin gluten verificado") y 4 medios, todos resueltos. Detalle en ADR-0025.
- **Pruebas (2026-10-30, después de las revisiones):** lint y tipos ✅ · Vitest 145 de 145 ✅ · pgTAP 1.209 de 1.209 ✅ (la nueva `190` tiene 79 y la `195` mide el volumen) · Playwright 88 de 88 ✅.
- **Para que decida Joaco (ADR-0025):**
  - ¿un plato se puede usar como preparación de otro (por ejemplo, un combo)?
  - ¿las diferencias de una variante las ve también el Jefe de Cocina del local, aunque ya no vea la maestra?
- **Próximo:** PR 2 (pantallas: buscador de preparaciones, "Dónde se usa", crear variante y sus diferencias, avisos en `/aprobaciones`).

## Antes: etapa 2.2 A, recetas (PR 3 de 3, fotos; fusionado, PR #24)

- **La rama sale de `feat/recetario-pantallas`:** fusionar en orden `docs/respuestas-soy`, `feat/recetario-pantallas` y este.
- **Qué se hizo:** fotos de las recetas en Supabase Storage (bucket privado `recipe-media`). Son parte de la versión: se agregan en un borrador, pasan por la revisión y la cocina ve las de la vigente. Detalle en ADR-0023 (PR 3).
- **Revisiones:** `security-auditor` apto (3 medios resueltos); `ui-reviewer` sin graves (4 medios resueltos).
- **Pruebas (2026-10-30, `npm run test` completo):** lint y tipos ✅ · Vitest 141 de 141 ✅ · pgTAP 1.128 de 1.128 ✅ (la nueva `180` tiene 31) · Playwright 88 de 88 ✅.
- **Cambio de plan:** el retiro del documento de ensayo de la Fase 1 pasa a la 2.3 (ADR-0023).
- **Con esto termina la 2.2 A.** Para la compuerta de la 2.2 falta que un Chef cargue una receta completa sin ayuda en staging (antes: categorías y materias primas cargadas allá).

## Antes: etapa 2.2 A, recetas (PR 2 de 3, pantallas, rama `feat/recetario-pantallas`)

- **La rama sale de `docs/respuestas-soy`:** fusionar primero ese PR y después este.
- **Qué se hizo:** lista, alta, ficha por bloques con editores de componentes y pasos, vista de cocina, la bandeja con el resumen de la versión, "Dónde se usa" en materias primas y categorías de recetas en la configuración. Detalle en ADR-0023 (PR 2).
- **Revisiones:** `security-auditor` apto; `ui-reviewer` con 2 graves y 8 medios, todos resueltos.
- **Pruebas (2026-10-30, `npm run test` completo):** lint y tipos ✅ · Vitest 141 de 141 ✅ · pgTAP 1.097 de 1.097 ✅ · Playwright 86 de 86 ✅ (la nueva `recetas.spec` recorre alta, edición, "salir y volver", revisión, aprobación y vista de cocina).
- **Pantallas:** miradas en capturas de celular y computadora.
- **Para el Chef en staging (compuerta de la 2.2):** primero, categorías y materias primas cargadas en staging.
- **Próximo:** PR 3 (fotos y retiro del documento de ensayo de la Fase 1).

## Antes: respuestas de Soy (ADR-0024)

- **Respondidas:** orden de precios (con aviso de dónde se hereda), IVA (costo sin IVA recuperable, mostrar con y sin IVA, precio "ingresado" sin factura, razón social por local, fletes aparte), quién aprueba precios (Dirección con un porcentaje configurable), plazo de precio viejo, rendimiento aprobado con alertas de desvío, el Gerente ve costos de su local, Superadmin con permisos del recetario, Compras de grupo, subrecetas que cambian solas con avisos, Pariggi como proveedor externo, alérgenos firmados por un externo, quiénes validan.
- **Sin respuesta:** con qué producto se costea si hay varios (4) y el Excel del recetario actual (14). Las 20 recetas reales (15) y la lista de marcas y locales (16), las pasa después.
- **A confirmar con Soy:** los puntos marcados en ADR-0024 (fletes, razón social compartida, cómo se mide la variación de precio, umbral de alerta de rendimiento, a quién avisar por una subreceta, cómo firma el externo de alérgenos, quién valida qué).
- **Siguen pendientes de Joaco (ADR-0023):** si quien redactó un borrador puede aprobarlo, y si en un traspaso de local pasan sus recetas.
- **Staging:** crear las categorías reales en Materias primas → Configuración, con un usuario de Compras o Superadministrador.

## Antes: etapa 2.2 A, recetas (PR 1 de 3, base; fusionado, PR #22)

- **Qué se hizo (PR 1, solo base):**
  - migración `20261101120000_recipes.sql`: siete tablas en `recipes` (categorías, recetas, versiones, líneas, pasos, dependencias y asignaciones);
  - versiones con aprobación: aprobar = publicar, y quien pidió la revisión no aprueba;
  - ficha de cocina sin valores económicos, camino crítico, alérgenos propagados y diferencias entre versiones;
  - seed con 20 recetas DEMO; el esquema `recipes` se expone por la API y entra en los tipos y el diccionario.
  - Detalle, revisiones y decisiones en ADR-0023.
- **Revisiones:**
  - `security-auditor`: apto, con sus 3 medios resueltos;
  - `db-reviewer`: 2 graves (rendimiento de las políticas y del camino crítico) y 6 medios, todos resueltos. Las políticas pasaron de 2,7 segundos a menos de 35 ms con 2.000 recetas (prueba `175`).
- **Pruebas (2026-10-29, `npm run test` completo):** lint y tipos ✅ · Vitest 141 de 141 ✅ · pgTAP 1.094 de 1.094 ✅ (la `170` tiene 97 y la `175` mide el volumen) · Playwright 80 de 80 ✅.
- **Pendiente de Joaco (ADR-0023):**
  - ¿quien redactó el borrador puede aprobarlo si la revisión la pidió otra persona?
  - en un traspaso de local, ¿pasan sus recetas y asignaciones?
- **Próximo de la 2.2 A:** PR 2 (pantallas: lista, editor, vista de cocina, bandeja) y PR 3 (fotos y retiro del documento de ensayo de la Fase 1).

## Antes: configuración del catálogo (fusionado, PR #21)

- **Por qué:** en staging no se podía cargar ninguna materia prima. Cada una necesita una categoría, las categorías solo las cargaba el seed (que no corre en staging) y no había cómo crearlas. Lo detectó Joaco.
- **Qué se hizo:**
  - migración `20261031120000_catalog_settings.sql`: crear, renombrar y dar de baja categorías (`catalog.manage` de grupo) y procesos de rendimiento (`yields.approve` de grupo). Nada en uso se da de baja;
  - pantalla `/materias-primas/configuracion`, con enlace desde la lista de materias primas;
  - el alta de materia prima sin categorías lleva a la configuración;
  - una baja y una carga al mismo tiempo ya no se cruzan (trigger con `for share`, probado a mano con dos sesiones).
  - Detalle en ADR-0022.
- **Pruebas (2026-10-29, `npm run test` completo, después de las revisiones):**
  - lint y tipos ✅;
  - Vitest 141 de 141 ✅;
  - pgTAP 995 de 995 ✅ (la nueva `160` tiene 44);
  - Playwright 80 de 80 ✅ (celular y computadora, con axe).
- **Pantalla:** mirada en capturas de celular y computadora.
- **Revisiones:** `security-auditor` apto; `db-reviewer` y `ui-reviewer` sin graves. Todo lo medio y lo menor que valía la pena, resuelto (ADR-0022).
- **Arreglo de paso en la 2.1 B:** la prueba `150` usaba la fecha UTC y fallaba después de las 21 h de la Argentina. Ahora usa la fecha de la Argentina, como la base.
- **Pendiente de Joaco:**
  1. abrir el PR y fusionarlo con "Pruebas" en verde;
  2. en staging, entrar con alguien que tenga `catalog.manage` de grupo (Superadministrador o Compras de grupo) y crear las categorías reales en Materias primas → Configuración;
  3. recién ahí se pueden cargar materias primas en staging.
- **Próximas etapas:** 2.2 A (recetas sin subrecetas ni Pariggi; no depende de Soy), 2.2 B y 2.1 C (necesitan respuestas de Soy).

## Antes: etapa 2.1 B terminada (fusionada, PR #20)

- **Qué se hizo:**
  - migración `20261030120000_catalog_yields.sql`: procesos, estándar de rendimiento con aprobación y ensayos (solo de inserción);
  - sección "Rendimientos" en la ficha de la materia prima: registrar un ensayo y proponer un estándar;
  - la aprobación usa la bandeja `/aprobaciones`, que ahora muestra "80,0 %" y "se expande ×2,5";
  - seed: persona nueva `chefgrupo@ejemplo.test` (Chef Ejecutivo de todo el grupo), 5 procesos, 2 estándares y 2 ensayos DEMO.
  - Detalle y decisiones de Joaco en ADR-0021.
- **Pruebas (2026-10-29):**
  - lint y tipos ✅;
  - Vitest 137 de 137 ✅;
  - pgTAP 951 de 951 ✅ (la nueva `150` tiene 61);
  - Playwright 70 de 72 en la corrida completa; las 2 que fallaron eran de `rendimientos.spec` por un selector ambiguo de la prueba (no de la app). Se corrigió y esa prueba pasó 4 de 4. **Falta una corrida completa final**, que corre igual en GitHub Actions al abrir el PR.
- **Revisiones:** `security-auditor`, `db-reviewer` y `ui-reviewer` sin graves; sus medios resueltos (ADR-0021).
- **Aviso:** la prueba de rendimiento de la Fase 1 (`110`, A10) una vez dio 311 ms (límite 300) con la máquina cargada; repetida, pasó 3 de 3. No se tocó. Si se repite, revisar.
- **Pendiente de Joaco:** abrir el PR y fusionarlo con "Pruebas" en verde. Staging publica solo la migración nueva.
- **Próximas etapas:** 2.2 (recetas; necesita las decisiones 1 y 6 de Soy) y 2.1 C (precios; necesita las respuestas de Soy sobre precios).

## Antes: etapa 2.1 A terminada (fusionada, PR #19)

- **Qué se hizo:**
  - migraciones `20261028120000_recipes_permissions.sql`, `20261028120100_catalog.sql` y `20261029120000_catalog_review_fixes.sql`;
  - pantallas `/materias-primas`, `/nueva` y `/[id]`;
  - seed con 50 materias primas DEMO;
  - diccionario `docs/modulos/02-recetario-diccionario.md`.
  - Detalle en ADR-0020.
- **Pruebas (2026-10-29, `npm run test` completo):**
  - lint y tipos ✅;
  - Vitest 126 de 126 ✅;
  - pgTAP 889 de 889 ✅;
  - Playwright 68 de 68 ✅.
- **Revisiones:**
  - `security-auditor`: apto, sin graves;
  - `db-reviewer`, segunda revisión: sin graves, con sus dos medios resueltos;
  - `ui-reviewer`: sin graves, con sus medios resueltos.
  - Lo que queda para más adelante está en ADR-0020 (sección Revisiones) y en el plan.
- **Arreglo que toca la Fase 1:** el selector de local usaba un id fijo. Como Next guarda ocultas las pantallas anteriores, quedaba repetido; ahora usa `useId`. La prueba de Playwright de Materias primas controla que no haya ids repetidos.
- **Pendiente de Joaco:** abrir el PR y fusionarlo con "Pruebas" en verde. Staging publica solo la migración nueva.
- **Próxima etapa:** 2.1 B (rendimientos). No depende de Soy.
- **Pendiente de Soy** (la lista detallada se le pasó a Joaco el 2026-10-29):
  - precios: orden por local, IVA, quién aprueba y aumento grande, plazo, producto preferido;
  - rendimiento aprobado;
  - qué ve el Gerente (N2) y los permisos del Superadministrador;
  - Compras por marca;
  - subrecetas y Pariggi;
  - quién valida los alérgenos;
  - quiénes validan cada etapa;
  - el Excel del recetario actual y las 20 recetas reales;
  - la lista de marcas y locales;
  - el plan Pro de Supabase para producción.
- **Supabase local:** después de cambiar `api.schemas`, hay que reiniciarlo (`npx supabase stop` y `start`).

## Staging (funciona desde el 2026-10-28)

- **La primera publicación completa salió en verde** el 2026-10-28, después del PR #17:
  - base, funciones y configuración en el Supabase de staging;
  - la app en `https://restaurante-100-digital.vercel.app`.
- **De ahora en más se publica sola:** con cada push a `main` y "Pruebas" en verde. Las personas de prueba se cargan solo a mano, una vez, con la casilla.
- **Pendiente de Joaco:**
  - confirmar que las personas de prueba se cargaron y que se puede entrar;
  - activar la doble verificación en las 7 cuentas con MFA (`superadmin`, `direccion`, `direccion2`, `director`, `gerente`, `gerente2` y `controller`), con `STAGING_DEMO_ADMIN_PASSWORD`;
  - si el ingreso falla, revisar que `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` no tenga un salto de línea al final en Vercel;
  - proteger `main` en GitHub, ahora que tiene el permiso: que nada entre sin PR ni con "Pruebas" en rojo. Está postergado desde la Fase 0.
- **A verificar en staging** (ADR-0018 y ADR-0014):
  - que `config push` haya aceptado `email_sent = 2`;
  - el límite por IP del ingreso, mandando `x-client-ip` y `x-forwarded-for` falsos.
- **Supabase está en el plan gratis:** pausa el proyecto tras unos 7 días sin uso. Se reactiva con "Restore project", sin perder datos.
- **Errores corregidos en la primera publicación, en orden** (además del PR #12, el espacio faltante en los comandos de Supabase):
  1. **Error del flujo (PR #15, fusionado).** La app recibía el proyecto como salida de la parte de la base, pero GitHub vacía las salidas que coinciden con un secreto (`STAGING_PROJECT_REF`). Ahora la app lo lee de `config.toml`, y el error muestra la URL encontrada.
  2. **Error de Vercel (corregido por Joaco).** `NEXT_PUBLIC_SUPABASE_URL` tenía un salto de línea al final. Joaco lo reescribió a mano. **Falta confirmar** que la publishable key no tenga el mismo problema: el flujo no lo controla en esa variable.
  3. **Error del flujo (PR #16, fusionado).** La lista de variables permitidas no aceptaba `VERCEL` (con valor `"1"`), una variable que agrega Vercel. La prueba nueva fija qué variables pasan y cuáles no.
  4. **Error del flujo (PR #17, fusionado).** `vercel inspect` no lee `VERCEL_ORG_ID`. Sin `--scope`, busca en la cuenta personal del dueño del token, y el token solo alcanza al equipo de Soy. Ahora lleva `--scope "$VERCEL_ORG_ID"`.

## Al retomar: Fase 2 (recetario)

- **Documento de Soy:** [docs/fases/fase-2-recetario.md](fases/fase-2-recetario.md). Está completo; el diagrama de la sección 5 y la tabla de la sección 20 se pasaron desde capturas.
- **Plan:** [docs/fases/fase-2-plan.md](fases/fase-2-plan.md). Aprobado por Joaco el 2026-10-28, con N1, N4 y la regla de que un precio cuenta recién cuando se aprueba (ADR-0020).
- **Decisiones de Soy:** las 8 de la sección 22, más N2, N3, N5, N6 y el "aumento grande". Joaco las ve con Soy más adelante.
  - Sin la decisión 3 (IVA) y la N6 (qué producto de compra usa el motor), la etapa 2.1 puede construir el catálogo, pero no cerrar los precios.
- **Plantilla de Excel v0 (borrador):** [docs/plantillas/plantilla-recetario-v0.xlsx](plantillas/plantilla-recetario-v0.xlsx). Se ajusta cuando llegue el Excel actual del recetario, que hay que pedirle a Soy.
- **Ya confirmado (2026-10-28):**
  - `grupo-lf-staging` está en la organización de Soy;
  - Vercel tiene plan Pro;
  - Supabase sigue en el plan gratis: alcanza para staging; para producción hace falta el plan Pro.
- **Demo local:**
  - para levantarla hace falta `.env.local`, copiado de `.env.example`;
  - si el ingreso da "name resolution failed", falta el contenedor de Edge Functions: `npx supabase stop` y después `npx supabase start`.

## Historia: staging bloqueado por el ambiente de GitHub (resuelto el 2026-10-28)

La causa era la primera de las dos: Joaco no tenía permiso de administrador.

- **Qué pasa:**
  - "Publicar en staging" frena en el primer control: "STAGING_PROJECT_REF no coincide con [remotes.staging]". Pasó dos veces, la segunda después de que Joaco volvió a cargar el secreto.
  - El código está bien: el mismo `awk`, corrido sobre `main`, da exactamente `tdbciscmemfdwjttgurj`. Entonces, el secreto le llega al flujo vacío o distinto.
  - El control funcionó como se esperaba: no se tocó nada en Supabase ni en Vercel.
- **Causa probable:**
  - Joaco abre `https://github.com/GRUPO-LOPEZ/RESTAURANTE-100-DIGITAL/settings/environments` y le da "página no encontrada". Eso pasa por una de dos razones:
    1. **Joaco no es Admin del repositorio** (sin la pestaña Settings, GitHub responde 404). Soy le da el rol Admin en **Settings → Collaborators and teams**, o carga él los secretos.
    2. **El plan gratis de GitHub no tiene ambientes en repositorios privados** (hacen falta Pro, Team o Enterprise). Si es esto, decide Soy:
       - **A (recomendada):** pasar la organización a GitHub Team. Producción va a necesitar ambientes con aprobación de todos modos.
       - **B:** usar secretos del repositorio. Eso afloja la seguridad, porque cualquier rama las alcanza, y obliga a cambiar el flujo y el ADR-0018.
  - **Falta que Joaco diga** si ve la pestaña Settings del repositorio, para saber cuál de las dos es.
- **Cuando se destrabe:**
  - crear el ambiente `staging` (con la regla de rama `main`) y sus 9 secretos (`docs/guias/staging.md`, sección 3);
  - correr **Actions → Publicar en staging → Run workflow** con "Cargar las personas y datos de prueba";
  - activar la doble verificación en las 7 cuentas con MFA.
  - Si el error persiste con el ambiente bien armado, agregar al control un mensaje que diga si el secreto llega vacío o con otro largo, sin mostrar el valor.
- **Ojo:**
  - `https://restaurante-100-digital.vercel.app/ingresar` ya muestra la pantalla de ingreso, pero **no la publicó nuestro flujo**. Es casi seguro de cuando el proyecto de Vercel estuvo conectado al repositorio, antes de desconectarlo.
  - No sirve como prueba de que staging funciona.
- **PR #12** corrigió un espacio que faltaba en los 4 comandos de la CLI de Supabase del flujo (`supabaselink`). La prueba de Vitest ahora exige el comando completo.
- **Sin instalar en esta compu:** GitHub CLI (`gh`). Por eso Claude Code no puede ver las corridas de Actions del repositorio privado. Para instalarlo: `winget install GitHub.cli` y `gh auth login`.

## Antes (2026-10-27): staging listo para PR

Plan aprobado: `C:\Users\julym\.claude\plans\silly-cuddling-ocean.md`. Decisión: ADR-0018. Guía para Joaco: `docs/guias/staging.md`.

- **Proyecto de Supabase:** `grupo-lf-staging`, Reference ID `tdbciscmemfdwjttgurj`. **Falta que Joaco confirme** que está en la organización de Soy.
- **Decisiones de Joaco:**
  - **2026-10-26:**
    - personas de prueba con un script propio de staging;
    - sin servicio de correo propio por ahora;
    - la app la publica GitHub Actions en Vercel.
  - **2026-10-27:**
    - CLI de Vercel como devDependency exacta (63.1.2);
    - dos contraseñas de demo;
    - el token personal de Supabase se acepta hasta antes de producción.
- **Hecho y probado en local:**
  - `[remotes.staging]` en `config.toml` (la CLI lo acepta);
  - el flujo `deploy-staging.yml`, en dos jobs, con las claves paso por paso;
  - `supabase/staging/demo-data.sql`: carga 12 personas, una segunda corrida no cambia nada, aborta con otros datos y sin contraseña no arranca. Con las contraseñas: el cocinero entra solo con la suya y Dirección con la de los roles con doble verificación. La auditoría guarda el número de corrida.
- **Pruebas (2026-10-27):**
  - formato, lint y tipos ✅;
  - Vitest 115 de 115 ✅;
  - pgTAP 785 de 785 ✅;
  - Playwright 60 de 60 ✅.
- **Revisiones:**
  - **`security-auditor`:**
    - primera revisión: NO APTO, con 1 grave y 5 medios;
    - segunda revisión: **apto**, con un medio nuevo (N1, el token de Vercel durante el armado de la app);
    - N1 y los menores fáciles están corregidos; lo que queda está aceptado con motivo en el ADR.
  - **`db-reviewer`:** sin graves; sus medios están corregidos.
- **`npm audit`:**
  - sobre lo que se publica (`--omit=dev`): 0 vulnerabilidades;
  - completo: unas 30 altas y 1 crítica, todas de la CLI de Vercel; aceptado en el ADR.
- **Bloqueantes para producción (ADR-0018):**
  - mover staging a una organización de Supabase y a un equipo de Vercel aparte, con tokens de cuentas técnicas;
  - fijar las acciones de GitHub por SHA;
  - revisar `npm ci --ignore-scripts`.
- **A verificar en la primera corrida de staging:**
  - que `db push` funcione sobre Supabase alojado;
  - que `config push` acepte `email_sent = 2`;
  - que `vercel build` funcione sin token;
  - el límite por IP del ingreso, mandando `x-client-ip` y `x-forwarded-for` falsos.
- **Pendientes de Joaco:**
  - ~~abrir el PR de `chore/staging`~~ (fusionado, PR #11);
  - el PR `docs/estado-fase-1-en-main` sigue sin abrir (es solo documentación; se puede cerrar sin fusionar, porque este estado lo reemplaza);
  - seguir la guía: Vercel a nombre de Soy y los secretos en el ambiente `staging` de GitHub.

## Las 6 preguntas pendientes (terminadas en local, 2026-10-23)

Decisiones en ADR-0017. Migración `20261023120000_old_questions.sql`, pruebas `130_old_questions.test.sql`.

1. Quitarle el rol a otro superadmin lo aprueba Dirección. También suspender o dar de baja su cuenta (Joaco, 2026-10-23, por la revisión de base).
2. Un local o una marca cerrados o borrados dejan de dar permisos; los roles de marca y de grupo siguen viendo su historia.
3. A alguien de Dirección lo da de baja o lo reactiva el superadmin u otra persona de Dirección, con la aprobación de otra persona de Dirección. Si no hay quién apruebe, se rechaza de entrada.
4. Un rol sensible lo aprueba Dirección o el Director de Marca de ese lugar, y el Director solo si tiene todos los permisos del rol (Joaco, 2026-10-23). El Controller y la Chef ya no lo aprueban.
5. La reactivación ya funcionaba así; hay prueba.
6. El bloqueo a propósito de una cuenta pasa a "antes de producción", con dispositivo de confianza.

**Rendimiento:**

- El tablero de usuarios bajó de 213–668 ms a 55–123 ms.
- El historial filtrado, de 147–374 ms a 129–205 ms.
- Cómo: índices por tabla en la auditoría, planes con los valores reales y costos calculados una vez por consulta.

**Revisiones:**

- `db-reviewer`: un hallazgo grave (suspender o dar de baja a otro superadmin al instante) y medios; todos corregidos o decididos por Joaco.
- `security-auditor`: sin graves. Medios corregidos: varios grupos y persona borrada.
- `ui-reviewer`: sin graves. Medios corregidos: la ficha recibe de la base si una acción va con aprobación, con aviso destacado y botón "Pedir…"; la prueba de pantalla limpia pedidos viejos antes de empezar.

**Decidido por Joaco (2026-10-23):** el rol Director de Marca solo se da para una marca (`20261023150000_brand_director_scope.sql`).

**Verificación completa (2026-10-23, `npm run test` desde una base nueva, sin nada más corriendo, con todos los cambios):**

| Prueba                                                                   | Resultado     |
| ------------------------------------------------------------------------ | ------------- |
| Formato, lint y tipos                                                    | ✅            |
| Lógica y configuración (Vitest)                                          | ✅ 95 de 95   |
| Base de datos (pgTAP), con A10                                           | ✅ 781 de 781 |
| Pantallas en celular y computadora, con accesibilidad (Playwright + axe) | ✅ 60 de 60   |

## Alineación de la Fase 1 con el documento de Soy (terminada en local)

Plan aprobado: `C:\Users\julym\.claude\plans\dapper-dazzling-haven.md`. Decisiones y diferencias que quedan: ADR-0015. Informe para Soy: `docs/fases/fase-1-cierre.md`.

**Qué se hizo:**

- **Base de datos.** Cuatro migraciones nuevas:
  - `20261021180000_phase_doc_enums.sql`
  - `20261021180100_align_with_phase_doc.sql`
  - `20261021190000_phase_doc_features.sql`
  - `20261021200000_phase_doc_screens.sql`

  Contenido:
  - nombres y columnas de las secciones 4 a 7;
  - estados activo, suspendido y desactivado;
  - membresías con lugar y fechas;
  - permisos nuevos;
  - avisos dentro de la app;
  - tabla de ensayo;
  - historial con filtros y exportación;
  - tablero de control;
  - sesiones cerradas que dejan de operar en el momento.

- **Pantallas:**
  - recuperar la contraseña;
  - "recordar sesión";
  - mi cuenta;
  - selector de local;
  - tablero de usuarios y lista con filtros;
  - ficha;
  - roles y permisos;
  - bandeja con el antes y el después;
  - historial con filtros y CSV;
  - ensayo;
  - menú y filtros plegables en el celular.
- **Revisiones:**
  - `db-reviewer` y `security-auditor`, en los tres pasos de base;
  - `ui-reviewer`, en las pantallas.

  Graves y medios corregidos. Lo que queda abierto está en ADR-0015.

- **Ajuste de configuración local:** el límite de ingresos de Auth subió de 30 a 300 cada 5 minutos, **solo en `supabase/config.toml`** (local y CI), porque la suite de pantallas ingresa muchas veces desde la misma IP. Staging y producción conservan el suyo.
- **Diccionario de datos:** se regenera con `npm run db:dictionary` (script nuevo, `scripts/data-dictionary.mjs`).

**Respuestas de Joaco a las 9 preguntas (2026-10-22), ya implementadas** (detalle en ADR-0015 y ADR-0016):

1. La Chef **no** publica lo que ella misma mandó a revisión: lo publica otra persona. La base lo rechaza y la pantalla no le ofrece el botón.
2. El último acceso, el primer ingreso, quién invitó y los motivos de suspensión o baja los ve solo quien administra a la persona: permiso nuevo `users.view_admin_details` (Superadmin, Dirección, Director de Marca y Gerente), sobre **todos** sus roles.
   - La tabla de personas ya no entrega esas columnas por la API (hallazgo grave de seguridad, corregido).
   - La bandeja oculta el motivo de una baja a quien no administra ni decide.
   - El historial los sigue mostrando a quien tiene `audit.view`, porque es para auditar (decisión de Joaco).
3. Los permisos de ensayo sumados quedan aprobados.
4. Los gráficos usan tonos fuertes (`chart-strong-*`, 3:1 o más sobre el fondo); los pasteles quedan para fondos.
5. Todos los KPI del tablero se comparan con hace 7 días, con la fecha a la vista.
6. React Hook Form en todos los formularios: errores debajo de cada campo antes de enviar, con el mismo esquema que el servidor (`lib/forms/schemas.ts`). El adaptador de Zod es propio, porque `@hookform/resolvers` choca con las dependencias del proyecto (ADR-0016).
7. "Recordar mi sesión" viene sin marcar.
8. Exportación sin límite de frecuencia; queda el tope por archivo.
9. El lugar donde trabaja una persona limita sus roles. La base no deja terminar una membresía que cubre un rol, y el traspaso de un local lleva la membresía al local nuevo.

**También se corrigió:**

- el encabezado del celular;
- "Grupo Grupo Demo";
- en `docs/modulos/00-identidad.md`, la tabla de roles copiada de Soy, que una edición anterior había pisado por error.

**Revisiones:**

- `db-reviewer`: sin graves. Medios corregidos: un bloqueo entre transacciones en las membresías, el criterio de "administra" y pruebas más precisas.
- `security-auditor`: 1 grave (las columnas de la tabla de personas) y 4 medios, corregidos. El del historial quedó como excepción decidida por Joaco.
- `ui-reviewer`: 1 grave corregido. Sin JavaScript, el formulario se enviaba por la dirección; ahora va siempre por POST y hay una prueba que lo controla. También se corrigieron los medios:
  - el foco y el aviso para lectores de pantalla;
  - la invitación con el mismo esquema;
  - la leyenda del gráfico;
  - los mensajes en inglés.

**Verificación completa (2026-10-22, `npm run test` desde una base nueva, sin nada más corriendo en paralelo):**

| Prueba                                                                   | Resultado     |
| ------------------------------------------------------------------------ | ------------- |
| Formato, lint y tipos                                                    | ✅            |
| Lógica y configuración (Vitest)                                          | ✅ 95 de 95   |
| Base de datos (pgTAP), con A10 por debajo de 300 ms                      | ✅ 736 de 736 |
| Pantallas en celular y computadora, con accesibilidad (Playwright + axe) | ✅ 58 de 58   |

Además se miró la pantalla real: el tablero en computadora y celular, el error por campo y la ficha vista por el auditor.

**Notas para trabajar en local:**

- **Las pruebas de pantalla no se corren dos veces a la vez.** Comparten los usuarios de prueba: una corrida en paralelo bloquea cuentas y cierra sesiones de la otra, y aparecen fallas que no son del código (pasó el 2026-10-22).
- **Antes de una demo, correr `npm run db:reset`:** las pruebas automáticas dejan datos en la base local.
- **Para abrir la app en local hace falta `.env.local`,** copiado de `.env.example`, que tiene los valores públicos de desarrollo local.
- **En una base recién cargada, "Cuentas activas" dice "+20 contra el …":** la comparación usa la historia de la auditoría, y las personas de prueba se crean al cargar la base.

**Para la Fase 2:** llevar la regla "quien manda a revisión no publica" al trigger de versiones de las recetas reales (revisión de seguridad, m5).

**Lo que falta, fuera del código:**

- subir la rama y ver GitHub Actions en verde;
- proyectos de Supabase de desarrollo en la nube y de staging, a nombre de Soy, más Vercel;
- la demo de la compuerta sobre staging;
- proteger `main`.

## Resumen para Soy: la Fase 1 está construida

**Qué se hizo:** el sistema ya tiene la base de todo lo que viene. Sabe **quién es cada persona, qué puede hacer y dónde**, y **registra cada cambio para siempre**.

- **Ingreso:**
  - Se entra solo por invitación, con correo y contraseña.
  - Los roles de los niveles 1 a 4 y Controller además usan una **app de doble verificación** en el celular.
  - **Cinco intentos fallidos bloquean la cuenta 10 minutos.** Un administrador la puede liberar antes.
- **Permisos por lugar:**
  - Cada persona ve y hace solo lo de su grupo, su marca o su local.
  - El cocinero no ve costos.
  - Nadie se puede dar permisos a sí mismo.
  - Los roles que aprueban cosas los tiene que aprobar otra persona.
  - El Superadministrador puede **pedir** cualquier rol, pero lo aprueba Dirección General.
- **Aprobaciones:** hay una bandeja para aprobar o rechazar cambios. Nadie aprueba lo que pidió, y quien bloquea una cuenta no puede reactivarla.
- **Cuentas:** desactivar una cuenta la saca al instante y cierra todas sus sesiones. Para reactivarla hace falta la aprobación de otra persona.
- **Historial:** se ve quién cambió qué, cuándo y por qué. Es inalterable y está sellado cada hora.
- **Pantallas:**
  - ingreso;
  - doble verificación;
  - inicio;
  - **tablero de usuarios** ("¿Quién tiene acceso y dónde?");
  - ficha de cada persona;
  - invitar;
  - aprobaciones;
  - historial.

  Todas están en español, pensadas primero para el celular y con los colores pastel.

**Cómo está probado (en la computadora de desarrollo, 2026-10-21):**

| Prueba                                                                   | Resultado                                                   |
| ------------------------------------------------------------------------ | ----------------------------------------------------------- |
| Base de datos (pgTAP)                                                    | ✅ 520 de 520                                               |
| Lógica y configuración (Vitest)                                          | ✅ 73 de 73                                                 |
| Pantallas en celular y computadora, con accesibilidad (Playwright + axe) | ✅ 28 de 28                                                 |
| Lint, formato, tipos y compilación                                       | ✅                                                          |
| Las **13 pruebas obligatorias y las 10 adicionales** del Módulo Maestro  | ✅ todas, en local (mapa en `docs/modulos/00-identidad.md`) |

**Revisiones:** cada paso pasó por los revisores de base de datos, seguridad y diseño, varias veces. Los graves que encontraron se corrigieron.

- **Seguridad:** en la primera ronda de M6 y M7 encontró dos huecos graves en cómo el Superadministrador daba y quitaba roles. Están cerrados.
- **Base:** encontró consultas que con mucho volumen tardaban segundos. Ahora tardan milisegundos.
- **Diseño:** pidió una pantalla de error, una página de "no encontrada" en español y un historial en lenguaje simple. Las tres están hechas.

**Qué falta para cerrar la Fase 1:**

1. Subir las ramas a GitHub y ver las pruebas en verde allá (es requisito). Necesita la confirmación de Joaco.
2. Que usted recorra la **checklist de validación** (sección 14 del prompt maestro) con los usuarios de prueba.
3. Las decisiones que están abajo.

## Preguntas para Joaco (respondidas el 2026-10-22: ver ADR-0017)

1. ¿Un superadmin le puede quitar el rol a otro superadmin sin aprobación, siempre que quede uno? Hoy sí.
2. ¿Un local cerrado o borrado deja de dar permisos a quienes tenían rol ahí? Hoy no.
3. Nadie puede desactivar a una persona de Dirección General, ni cambiar los permisos de ese rol, salvo con una migración documentada. ¿Está bien?
4. Controller puede aprobar que se le dé a alguien un rol que aprueba cosas (ADR-0008). ¿Se mantiene?
5. ¿Quién aprueba una reactivación? Hoy, otra persona con permiso sobre esa cuenta. ¿Tiene que ser alguien de igual o mayor alcance que quien la desactivó?
6. Ante el bloqueo a propósito de una cuenta (alguien falla 5 veces cada 10 minutos), ¿dejamos entrar igual a quien pone la contraseña y el código de doble verificación correctos?
7. El tablero de usuarios muestra el **estado actual**, sin comparar con un período anterior. ¿Lo aceptamos como excepción a la regla de tableros?

Riesgos técnicos antes de producción: ADR-0014, sección "Riesgos que quedan".

## Dónde está cada cosa

| Paso                                                | Rama / commit                                |
| --------------------------------------------------- | -------------------------------------------- |
| M5: permisos y lectura por la API                   | `feat/fase-1-permisos` · `2d49eaa`           |
| M6 y M7: roles, aprobaciones, registro de seguridad | `feat/fase-1-roles-aprobaciones` · `607ebd4` |
| M8 y M9, pantallas, Edge Functions, CI              | `feat/fase-1-cuentas-pantallas`              |

Las ramas están apiladas una sobre la otra y **todavía no están en GitHub**.

**Notas técnicas:**

- `.env.example` tiene la clave pública (publishable) de Supabase local. La CI verifica que coincida con la suya.
- Supabase local prende las Edge Functions (`auth-login` e `invite-user`), el hook de ingreso y la doble verificación TOTP.
- Playwright recrea la base antes de correr.
- Usuarios de prueba: `<rol>@ejemplo.test` con la contraseña `Demo-Local-2026!`. Los roles con doble verificación usan el secreto TOTP ficticio `JBSWY3DPEHPK3PXP`.

## Resumen para Soy: personas, roles y permisos (M4)

**Qué se hizo:** la base ya conoce a las personas y qué puede hacer cada una.

- Están cargados **los 10 roles de su Módulo Maestro** y los permisos de esta fase. Cada rol tiene su lista de permisos (la matriz que aprobó Joaco está en `docs/modulos/00-identidad.md`).
- **Llevan doble verificación (MFA):** Superadministrador, Dirección General, Director de Marca, Gerente y Controller. A esos roles nadie les puede sacar el MFA.
- Cada persona tiene un rol **en un lugar**: todo el grupo, una marca o un local. La base no deja dar un local que no es de esa marca, ni dar un rol a alguien que no es del grupo o que tiene la cuenta bloqueada.
- **Nada se borra:** sacar un rol deja quién lo sacó, cuándo y por qué. Una persona no se borra, se bloquea.
- Para probar hay **una persona inventada por rol**, un gerente de dos locales y una cuenta técnica para los agentes del futuro. Ya se puede entrar con ellas en la computadora de desarrollo.
- Todo sigue **cerrado**: ninguna pantalla puede leer estos datos hasta que existan las reglas de acceso (M5).

**Cómo está probado:** 285 pruebas de base de datos en verde. Pasó por los revisores de base de datos y de seguridad: ninguno encontró problemas graves, y los puntos que se podían arreglar ahora ya se arreglaron. El resto quedó anotado como requisito de M5, M6 y M8.

**Preguntas para usted:**

- ~~**P15:** ¿cómo se pasa un local a otra marca?~~ Resuelta por Joaco: se crea el local nuevo y se cierra el viejo, que conserva su historia. Si hiciera falta, se puede cambiar más adelante (ADR-0007).
- ~~**P16:** las 10 pruebas adicionales.~~ Recibidas; la 6 (alcance incoherente) ya pasa.
- ~~**P5:** cómo se registran los ingresos.~~ Resuelta por Joaco (ADR-0010). El ingreso pasa por una función nuestra que anota y cuenta los intentos, y una cuenta bloqueada no recibe sesión. Funciona con el plan gratis o Pro.
- ~~**P18:** duración del bloqueo.~~ Resuelta por Joaco: dura 10 minutos y se libera solo. Un administrador puede liberarlo antes, y eso queda registrado.
- ~~**P17:** operación rechazada.~~ Resuelta por Joaco: quedan registradas las aprobaciones rechazadas y los intentos sin permiso en las funciones importantes (ADR-0009).
- ~~**P7:** ¿qué cambios necesitan aprobación?~~ Resuelta por Joaco (ADR-0008). Piden aprobación de otra persona:
  - dar roles que aprueban;
  - dar el rol Superadministrador;
  - cambiar los permisos de los roles;
  - pasar un local a otra marca;
  - reactivar una cuenta.

  Bloquear una cuenta es inmediato.

**Estado:** rama `feat/fase-1-identidad` (sale de `feat/fase-1-organizacion`). Es un **adelanto**: no se suma a `main` sin su aprobación.

| Prueba                                        | Resultado                                         |
| --------------------------------------------- | ------------------------------------------------- |
| pgTAP (`000` a `040`)                         | ✅ 285 de 285                                     |
| `npx supabase db reset` (con el seed)         | ✅                                                |
| Ingreso local con una persona del seed (Auth) | ✅ entra; contraseña mala y alta libre rechazadas |

Revisiones de M4:

- **`db-reviewer`:** sin hallazgos graves. Corregidos en la misma migración:
  - asignación duplicada;
  - carrera entre dar un rol y sacar la membresía;
  - reglas entre tablas (permisos y roles borrados, cuentas bloqueadas);
  - vigencias que se extendían;
  - pruebas faltantes;
  - el ingreso local apagado por `config.toml`.

  Anotados: el traspaso (P15), la sincronización del correo (M8) y SSO.

- **`security-auditor`:** apto. Corregidos:
  - los códigos de permisos y roles, que se podían renombrar (era una vía para darse más permisos);
  - el MFA de los roles del catálogo, que se podía bajar;
  - la guarda del seed, ahora más fuerte.

  Pasaron a requisitos de M5, M6 y M8: separación de funciones (cuentas títere, superadmin que edita la matriz), reglas sobre a quién se puede bloquear, comparación por permisos y no por nivel, y la configuración de Auth en los paneles remotos.

## Resumen para Soy: estructura del grupo (M3)

**Qué se hizo:** la base ya conoce cómo está armado el grupo: **grupo → marcas → restaurantes → áreas** (cocina, salón, depósito). Para probar hay datos inventados: "Grupo Demo", 3 marcas y 4 locales.

- Un local **no puede quedar en una marca de otro grupo**, ni un área en un local de otro grupo: la base lo rechaza.
- Por decisión de Joaco:
  - **no se puede borrar algo que todavía tiene cosas vigentes adentro** (una marca con locales abiertos, por ejemplo);
  - **un local no se puede mover a otra marca con una edición común**. Va a haber un trámite que pide motivo y queda en el historial.
- Cada alta, cambio o borrado queda en el historial, **con el local, la marca y el grupo correctos**, aunque alguien intente cargar datos engañosos.
- Todo sigue **cerrado**: ninguna pantalla puede leer estos datos hasta que existan los permisos (ADR-0005).

**Cómo está probado:** 207 pruebas de base de datos en verde, revisadas por los revisores de base de datos y de seguridad (sin hallazgos graves; lo que encontraron está corregido).

**Preguntas para usted:** P13 (¿se puede editar algo borrado?), P14 (¿alcanzan los estados "operando" y "cerrado"?) y P10 (¿qué datos lleva cada local: dirección, CUIT…?).

**Estado:** rama `feat/fase-1-organizacion` (sale de `feat/fase-1-base-auditoria`). Es un **adelanto**: no se suma a `main` sin su aprobación.

| Prueba                                | Resultado     |
| ------------------------------------- | ------------- |
| Lint, formato y tipos                 | ✅            |
| Vitest                                | ✅ 63 de 63   |
| pgTAP (`000`, `010`, `020`, `030`)    | ✅ 207 de 207 |
| Playwright + axe                      | ✅ 10 de 10   |
| `npx supabase db reset` (con el seed) | ✅            |

Revisiones de M3: `db-reviewer` sin graves (2 medias que eran reglas de negocio, ya decididas por Joaco, y 5 menores corregidas). `security-auditor` apto (3 medias latentes: alcance falsificable en la auditoría, ya corregido; riesgos del ADR-0005, ya documentados; permisos por defecto en `public`, ya cortados; y 4 menores corregidas).

## Adelanto de la Fase 1: base común y auditoría (M1 y M2)

**Qué se hizo:** se construyó el **historial inalterable** del sistema, la parte de la Fase 1 que no depende de su documento:

- Cada cambio que se haga en cualquier tabla va a quedar registrado: **quién, cuándo, qué había antes, qué quedó y por qué**.
- **Nadie puede borrar ni cambiar ese historial**, ni siquiera un administrador. Y si alguien con la contraseña máxima de la base lo intentara, unos **sellos** (huellas digitales encadenadas) lo detectan. Hay una prueba que simula ese ataque.
- Las contraseñas, tokens y claves **nunca** quedan en el historial, aunque vengan escondidos dentro de otros datos.
- Los datos de "quién creó o cambió esto" los pone siempre la base, nunca la aplicación, así que no se pueden falsear.

**Cómo está probado:** 156 pruebas de base de datos en verde, revisadas por los revisores de base de datos y de seguridad (sin hallazgos graves; todo lo que encontraron ya está corregido).

**Qué falta:** su Módulo Maestro de Usuarios, para los roles, permisos y las 13 pruebas. Y una pregunta nueva (P13): ¿se puede editar algo que ya está borrado, o hay que restaurarlo primero?

**Estado:** rama `feat/fase-1-base-auditoria`. Es un **adelanto**: no se suma a `main` hasta que usted apruebe la Fase 0 y este avance.

### Pruebas de esta tarea (local, 2026-10-20)

| Prueba                               | Resultado     |
| ------------------------------------ | ------------- |
| Lint, formato y tipos                | ✅            |
| Vitest                               | ✅ 63 de 63   |
| pgTAP (`000`, `010`, `020`)          | ✅ 156 de 156 |
| Playwright + axe                     | ✅ 10 de 10   |
| `npx supabase db reset` (desde cero) | ✅            |

Revisiones: `db-reviewer` sin graves (4 medias y 6 menores, corregidas o anotadas), `security-auditor` apto (4 medias y 8 menores, corregidas o anotadas en ADR-0006). Dos errores reales los encontraron las propias pruebas antes de commitear: los permisos por defecto por esquema no cerraban nada, y `postgres` sin herencia no podía conectar el trigger de auditoría.

### Pendientes de la Fase 1 que salen de esta tarea

- Tarea programada que selle la auditoría cada hora, y exportación externa con la última huella (ADR-0006).
- `audit.authentication_security_events` (diseño en ADR-0009 y ADR-0010).
- La lectura de la auditoría tiene que ocultar costos a quien no tenga `costing.view_costs` (ADR-0006).
- P13 (resuelta): un registro borrado no se edita, primero se restaura. Se implementa junto con M5.

## Fase 0 (mergeada en `main`, PR #1)

**Qué se hizo:** se preparó el "taller" donde se va a construir el sistema. Todavía no hay pantallas para los restaurantes; eso es a propósito. Quedó listo:

- **Las reglas del proyecto adentro del código.** Claude las lee solo en cada sesión: principios, base de datos, seguridad, diseño y agentes.
- **Candados automáticos.** Claude no puede leer claves, no puede tocar producción, no puede forzar cambios en GitHub ni editar cambios de base de datos ya guardados. Cada candado tiene su prueba.
- **La base de datos local**, ordenada en 12 temas (identidad, organización, auditoría, recetas, costos, etc.), todavía vacía y **cerrada por defecto**: nadie entra a nada hasta que se le dé permiso explícito.
- **El estilo visual:** colores pastel, letra Inter, botones grandes para el celular. Está controlado por pruebas automáticas: si alguien usa un color fuera de la paleta o con poco contraste, la prueba falla.
- **Pruebas automáticas que corren en cada cambio** (en GitHub, una vez que se suba).
- **El plan detallado de la Fase 1** (usuarios, permisos e historial), ya revisado por los revisores de base de datos y de seguridad.

**Qué falta para arrancar la Fase 1:** el documento del Módulo Maestro de Usuarios (roles, niveles, permisos y las 13 pruebas). Sin eso no se puede cerrar la Fase 1.

**Riesgos:** ninguno grave en lo construido. Los riesgos de diseño que encontraron los revisores ya están corregidos en el plan de la Fase 1.

## Hecho

Rama `chore/fase-0-entorno`, mergeada en `main` con el PR #1. Falta confirmar si GitHub Actions dio verde en ese PR.

| Paso del prompt de arranque                   | Estado  | Dónde                                                                                  |
| --------------------------------------------- | ------- | -------------------------------------------------------------------------------------- |
| 1. Estructura del repositorio (sección 4)     | ✅      | raíz del repo (ADR-0001)                                                               |
| 2. `CLAUDE.md` y `.claude/rules/`             | ✅      | `CLAUDE.md`, `.claude/rules/{database,security,design,agents}.md`                      |
| 3. Permisos y hooks                           | ✅      | `.claude/settings.json`, `.claude/hooks/` (guardián, migraciones, formato, pre-commit) |
| 4. Subagentes revisores y skills              | ✅      | `.claude/agents/`, `.claude/skills/{nueva-tabla,nuevo-modulo}`                         |
| 5. Next.js + TS strict + Tailwind + shadcn/ui | ✅      | Next 16.4, Tailwind 4 (ADR-0002), tokens en `app/globals.css`                          |
| 6. Supabase local, pgTAP, Playwright, CI      | ✅ / ⚠️ | Todo corre en local. **CI escrito, sin verificar en GitHub** (falta subir la rama).    |
| 7. Plan de la Fase 1                          | ✅      | `docs/fases/fase-1-plan.md`                                                            |

### Pruebas (corridas en local el 2026-10-20, resultado literal)

| Prueba                                          | Resultado                         |
| ----------------------------------------------- | --------------------------------- |
| `npm run lint`                                  | ✅ sin errores ni advertencias    |
| `npm run format:check`                          | ✅                                |
| `npm run typecheck`                             | ✅                                |
| Vitest (hooks + contraste de la paleta)         | ✅ 63 de 63                       |
| `npx supabase db reset`                         | ✅ aplica la migración desde cero |
| pgTAP (`npx supabase test db`)                  | ✅ 60 de 60                       |
| Playwright + axe (celular Pixel 7 y escritorio) | ✅ 10 de 10                       |
| `npm audit --omit=dev`                          | ✅ 0 vulnerabilidades             |

### Revisiones de los subagentes

- **ui-reviewer:** aprobado con cambios. Corregidos: contraste del hover del botón, `link` sin 44 px, pruebas del botón (tamaño y foco), tamaños, pesos y radios fuera de la escala, pares de contraste nuevos y aviso sobre componentes nuevos de shadcn en `design.md`.
- **db-reviewer:** Fase 0 sin hallazgos graves. Prueba de humo ampliada (12 esquemas × 3 roles). Sus 2 graves y 9 medios del diseño de la Fase 1, corregidos en el plan y en la skill `nueva-tabla`.
- **security-auditor:** Fase 0 apta. Corregidos los 9 hallazgos del guardián y los permisos (17 ataques nuevos en las pruebas), `format.mjs` sin shell, `shadcn` movido a dependencias de desarrollo y control de migraciones inmutables en CI. Sus 2 graves de diseño de la Fase 1 (escalada en asignación de roles y suplantación de cuentas técnicas), corregidos en el plan.

### Control de reglas (paso 2)

Se compararon 110 reglas clave del prompt maestro contra `CLAUDE.md` + `.claude/rules/` + `settings.json`. Faltaban 2, que ya se agregaron: "Joaco accede como miembro" y la nota pendiente sobre marcas, locales y otros negocios.

## Falta

_Actualizado el 2026-10-20._

**Hecho fuera de la Fase 1:** conector MCP de Supabase solo contra la base local, en solo lectura (ADR-0011, rama `chore/mcp-supabase-local`). Pendiente: el MCP de GitHub.

1. **Construir M5, M6 y M8** y las pantallas de ingreso, "sin acceso" y usuarios. No dependen de nadie.
2. **M7 (aprobaciones)**: P7 y P17 ya están resueltas (ADR-0008 y ADR-0009).
3. Preguntas de la Fase 1: **todas resueltas**. P10, P13 y P14 se implementan junto con M5. Para producción falta la lista real de marcas y locales.
4. **Subir las 3 ramas de adelanto** (M1–M2, M3, M4) como PRs y verificar GitHub Actions en verde. Necesita la confirmación de Joaco para el `git push`.
5. **Supabase remoto:**
   - Soy ya creó la organización y Joaco es administrador.
   - Faltan los proyectos `grupo-lf-staging` y `grupo-lf-prod` (región São Paulo), los ajustes de Auth en el panel, y el flujo de GitHub Actions con sus secretos. Lo hace Joaco desde el panel, nunca Claude Code.
   - Pendiente también una guía escrita para Soy.
6. Vercel, respaldos y exportación semanal del historial (Soy).
7. **Proteger `main` en GitHub: postergado por decisión de Joaco (2026-10-20).** Mientras tanto se sigue la regla igual, por costumbre:
   - nada entra a `main` sin un PR aprobado por Soy;
   - Claude Code nunca hace push a `main`;
   - el push forzado está bloqueado por el guardián.

   Se retoma antes de pasar a producción.

8. Texto completo del Módulo Maestro y tabla de fases (sección 12) de Soy.

## Bloqueado

- **Fase 1:** necesita el Módulo Maestro de Usuarios de Soy (`docs/modulos/00-identidad.md` está vacío, con un aviso de pendiente).
- **Tabla de fases** (sección 12 del prompt maestro): no llegó completa.

## Riesgos y avisos conocidos

- `npm audit` completo (con desarrollo) marca 5 vulnerabilidades altas de `braces`, en el linter de Next (`eslint-config-next`). No afecta lo que llega al usuario. El "arreglo" automático baja el linter a una versión vieja; se espera el arreglo de Next y lo trae Dependabot.
- npm 11 avisa que `unrs-resolver` tiene un script de instalación no aprobado. ESLint funciona sin ese script.
- El guardián de Claude Code es una ayuda, no la única barrera. La defensa real es que **en esta máquina nunca haya claves ni tokens de staging o producción**, y que nunca se haga `supabase link`.
- Docker tiene unos 3,9 GB de RAM; Supabase local usa alrededor de 1,1 GB. Si se pone lento, ver ADR-0001.

## Prueba de restauración mensual

Todavía no aplica: no hay producción.
