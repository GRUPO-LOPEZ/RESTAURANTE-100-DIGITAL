# ADR-0029 — Precios con historia y aprobación (etapa 2.1 C)

- **Fecha:** 2026-11-02
- **Estado:** aceptada por Joaco (plan aprobado). PR 1 de 2: la base. Las pantallas van en el PR 2.
- **Base:**
  - las respuestas de Soy sobre precios (ADR-0024, sección A, y ADR-0026, sección A);
  - la regla "un precio cuenta recién cuando se aprueba" (ADR-0020);
  - el plan de la Fase 2 (sección 4, casos 1, 2, 16, 17, 20 y 21).

## Contexto

- Sin precios no hay motor de costos (2.3). El esquema `costing` estaba vacío; solo existían los permisos `prices.view`, `prices.propose` y `prices.approve`.
- **Soy achicó la etapa** (ADR-0026): los precios reales van a llegar de un sistema que lee facturas (el agente de Facturas, Fase 5). Por ahora alcanza con guardar precios con historia y aprobación, y una carga manual con valores de prueba.

## Decisiones de Joaco (2026-11-02)

1. **Varios productos con precio** (por ejemplo, mozzarella de dos marcas): vale el **último aprobado** de cualquiera de los productos vigentes de la materia prima, en el nivel que corresponda. La consulta dice de qué producto viene.
2. **Variación grande:** primero aprueba el Controller y **después Dirección General**. El precio entra recién con las dos.
3. **Fletes y otros cargos:** más adelante, con las facturas. Hoy no hay a qué atarlos.
4. **La configuración del grupo** (el % y los días) la cambia **solo Dirección General**.

Después de las revisiones, Joaco decidió además:

5. **La variación se mide contra el costo que se usa hoy** para esa materia prima en ese lugar: con herencia local → marca → grupo, de cualquier presentación, por unidad de uso y mirando con IVA y sin IVA (vale la más grande de las dos). Así no se saltea a Dirección con una presentación nueva, un precio propio de un local que heredaba o un cambio de comprobante.
6. **El primer precio** (sin nada con qué comparar) lo aprueba solo el Controller.
7. **El primer paso lo da solo el Controller**, no Dirección General.
8. **La razón social de un local** la elige solo quien administra todo el grupo (`org.manage` de grupo). Cambiarla cambia si el costo va con o sin IVA, así que el Gerente y el Director de Marca no la tocan.

Y después de la segunda pasada:

9. **El contenido del envase se congela al aprobar.** Cada precio guarda cuántos gramos, mililitros o unidades trae el envase en ese momento, y el costo sale de ahí. Cambiar el contenido de un producto o una conversión no mueve ningún costo: hay que proponer un precio nuevo, que pasa por aprobación.
10. **Un precio no puede empezar antes que el último** del mismo producto y lugar, **ni antes que el precio que vale hoy en ese lugar** (con herencia y de cualquier presentación; `costing.valid_from_floor`). La historia registrada no se reescribe; para corregir el pasado se carga uno nuevo desde esa fecha en adelante.

## Cómo quedó (migración `20261109120000_prices.sql`)

### Razones sociales

- **`org.legal_entities`:** nombre, CUIT (11 números, sin guiones) y condición frente al IVA: responsable inscripto, monotributo o exento. Cada local apunta a una (`org.restaurants.legal_entity_id`), y varios locales pueden compartirla (respuesta 3 de ADR-0026).
- **Altas y cambios** con `org.create_legal_entity`, `org.update_legal_entity` y `org.set_restaurant_legal_entity`. Piden `org.manage` para todo el grupo y un motivo (decisión 8).
- **Las ve** quien ve precios o administra el grupo; la Cocinera, no.
- **Sin razón social, el costo sin IVA queda incompleto** (`missing_legal_entity`): el sistema no supone la condición frente al IVA. El precio con IVA se ve igual.

### Precios

- **`costing.price_records` es solo de inserción.** Un trigger rechaza cualquier cambio o borrado, aun del dueño de la tabla. Corregir un precio es cargar otro.
- **Cada precio vale** para un producto de compra, en el grupo, una marca o un local, desde una fecha (`valid_from`), que no puede ser anterior al último precio del mismo producto y lugar (decisión 10). Entre dos del mismo día, vale el registrado después (`entry_number`).
- **El precio del envase y el IVA:**
  - con factura (IVA discriminado, alícuota 0, 10,5, 21 o 27) o "precio ingresado" (sin factura: el precio es el final);
  - si incluye IVA, y un descuento;
  - **la base calcula** el precio del envase sin IVA y con IVA.
- **El contenido queda congelado en cada precio** (`base_quantity`, decisión 9): el trigger lo calcula al registrar con el contenido del producto y sus conversiones (`catalog.to_base_quantity`), y el costo por gramo, mililitro o unidad sale de ahí.
  - Cambiar el contenido de un producto, una conversión o desactivar un producto no mueve el **precio por unidad** de un precio ya aprobado. (La cantidad de una línea de receta todavía se convierte con las conversiones de hoy: ver Riesgos.)
  - Entre la propuesta y la aprobación el contenido tampoco puede cambiar: `check_reference` lo compara con el guardado en la solicitud y, si cambió, la aprobación no se aplica.
  - **Una materia prima con precios no cambia su unidad de uso** (trigger `catalog.guard_priced_ingredient`), porque los precios se guardaron en esa unidad. **Su categoría** decide cuándo un precio está desactualizado, así que la cambia solo quien tiene `prices.configure`.
  - Así se cierra lo que dejó abierto ADR-0020 (M3) y también el caso "dos personas a la vez": un precio sin conversión ni siquiera se registra.
  - **El último costo conocido incluye los productos desactivados:** desactivar un producto no deja la materia prima "sin precio" ni la convierte en un "primer precio".
- **Origen:** `manual`, `test_value` (los valores simbólicos de Soy), `excel_import` o `invoice` (reservado para la Fase 5). Hoy solo se proponen los dos primeros.
- **Los importes llevan `price` o `amount` en el nombre.** Así `core.hide_costs` los oculta del historial y de la bandeja a quien no ve costos.

### Aprobación

- **`costing.propose_price`:** pide `prices.propose` en el lugar del precio y un motivo.
  - Valida el producto, el alcance, el proveedor (vigente y activo), la fecha, el precio, el descuento, el IVA y el largo de las observaciones.
  - El contenido del producto se tiene que poder pasar a la unidad de uso; si no, pide cargar primero la conversión.
  - **Calcula la variación** (decisión 5) contra `costing.reference_price`: el precio que vale hoy (o en la fecha del precio, si es futura) para esa materia prima en ese lugar, con herencia y de cualquier presentación, por unidad de uso, con y sin IVA. Guarda la más grande de las dos.
    - Sin referencia, no hay variación: alcanza con el Controller (decisión 6).
  - Crea la solicitud **`costing.approve_price`**, que aprueba **solo el Controller** de todo el grupo (`approver_role_codes`, decisión 7).
  - Hay una sola propuesta pendiente por producto, alcance y fecha.
- **`costing.apply_price`:** si la variación (en más o en menos) supera el % del grupo, **no aplica**. Crea la segunda solicitud, **`costing.approve_price_direction`**:
  - la aprueba alguien con el rol Dirección General de todo el grupo (`approver_role_codes`);
  - quien propuso y quien ya aprobó quedan excluidos (`excluded_approvers`).
  - **El motor de aprobaciones no cambió:** son dos solicitudes seguidas.
- **Antes de pasar a Dirección y antes de registrar**, `costing.check_reference` controla que la referencia siga siendo la que vio quien aprobó. Si no, la aprobación no se aplica y hay que proponer de nuevo.
- **Los precios de una solicitud no salen de la tabla:** `authenticated` ya no lee `workflow.approval_requests.proposed_changes` (como ya pasaba con `previous_values`). El detalle sale solo por `workflow.inbox`, que muestra los importes de un precio solo a quien tiene `prices.view` en ese lugar (`workflow.can_see_amounts`). Así Compras ve lo que propuso, y un Chef o un Jefe de Cocina ven la solicitud, pero no el precio.
- **`workflow.check_apply_function`** acepta ahora también las funciones `apply_*` del esquema `costing`.

### Configuración

- **`costing.price_settings`:** una fila por grupo, con el % de variación (por defecto 15) y los días para marcar un precio desactualizado (por defecto 30). La cambia `costing.update_price_settings`.
- **Los días por categoría** (`catalog.ingredient_categories.stale_price_days`, de la 2.1 A) se cambian con `catalog.set_category_stale_days`.
- **Permiso nuevo `prices.configure`**, solo para Dirección General (decisión 4).

### Qué precio vale y cuánto cuesta una línea

- **`costing.price_rows`** (interna) resuelve, en una sola consulta, el precio de todas las materias primas del grupo para un local:
  - **orden de búsqueda:** local → marca → grupo, marcando si es heredado;
  - **entre productos:** el último aprobado;
  - **el costo que cuenta:** el neto si hay factura y la razón social es responsable inscripta; si no, el bruto;
  - **desactualizado:** según el plazo de la categoría o, si no tiene, el del grupo;
  - **estados:** `ok`, `missing_price` o `missing_legal_entity`. La línea suma `missing_conversion` (la cantidad pedida no se pasa a la unidad de uso) y `missing_yield`.
- **`costing.resolve_price`** (una materia prima) y **`costing.resolve_prices`** (todas, para listas y tableros) piden `prices.view` en el local.
- **`costing.ingredient_line_cost`:**
  - pasa la cantidad a la unidad de uso;
  - aplica el rendimiento estándar si va limpia o cocida (`catalog.standard_yield`; sin estándar, `missing_yield`);
  - multiplica por el costo que cuenta. **Nunca da $ 0.**
  - Es la función que va a usar el motor de la 2.3, a través de las versiones internas.

### Quién ve qué

- **Un precio de local** lo ve quien tiene `prices.view` en ese local (por un rol de local, de marca o de grupo).
- **Uno de marca,** quien lo tiene en la marca o en alguno de sus locales.
- **Uno de grupo,** quien lo tiene en cualquier lugar del grupo.
- Así **el Gerente** ve los precios que usa su local, también los heredados, pero no los de otra marca. **El Chef y el Cocinero** no ven ninguno.
- **El Gerente** recibe `prices.view` y `recipes.view_costs` en su local (respuesta 7 de Soy, ADR-0024). Las pruebas que decían "hasta que Soy responda N2" se actualizaron.

### Datos de prueba

- Dos razones sociales ficticias: una responsable inscripta, para los locales de Pastas y Parrilla, y una monotributista, para el Café.
- Precios simbólicos (`test_value`) para 20 materias primas, incluidos:
  - uno de marca (la mozzarella de Demo Pastas);
  - uno viejo (desactualizado);
  - uno sin factura.

## Pruebas

- **`210_prices`:**
  - estructura y tipos de aprobación;
  - razones sociales (permisos, CUIT, auditoría);
  - configuración (solo Dirección);
  - neto y bruto;
  - solo inserción;
  - qué precio ve cada rol;
  - importes ocultos en el historial.
- **`211_prices_flow`:**
  - casos 1, 2, 16, 17, 20 y 21;
  - monotributo, local sin razón social, varios productos, falta precio y desactualizado;
  - quién consulta;
  - el flujo completo: Compras propone, el Controller aprueba, una suba y una baja grandes pasan a Dirección, el % configurable y la carrera entre proponer y aprobar.
- **`212_prices_performance`:** los precios de 500 materias primas con 5.000 precios cargados, por debajo de 300 ms.
- **Snapshots actualizados a propósito:** `000` (acceso al esquema `costing`), `030`, `050` y `140`.

## Revisiones (PR 1)

- **Primera pasada:** `db-reviewer` y `security-auditor` encontraron los mismos dos graves. Los dos quedaron resueltos y con prueba:
  - **Los precios propuestos se filtraban** al Chef y al Jefe de Cocina por la tabla de solicitudes y por la bandeja. Se cerró la columna `proposed_changes`, y la bandeja exige `prices.view` para los importes de un precio.
  - **El paso de Dirección se salteaba** con una presentación nueva, un precio de local que heredaba o un cambio de comprobante. Ahora la variación se mide contra el costo que se usa hoy (decisión 5).
- **Medios resueltos:**
  - el Gerente cambiaba la razón social de su local, y con eso el IVA del costo (decisión 8);
  - el primer paso lo podía dar Dirección (decisión 7);
  - faltaban pruebas: el rechazo de Dirección, el cambio del precio entre los dos pasos, una propuesta de local y la auditoría de la configuración, de un precio aprobado y de la razón social de un local.
- **Menores resueltos:**
  - un precio sin aprobación solo puede ser un valor de prueba (`check`);
  - el largo de las observaciones y el proveedor activo se validan al proponer;
  - `entity_table` es el producto de compra;
  - la Cocinera ya no ve las razones sociales;
  - la línea controla que la materia prima sea del grupo del local.
- **Aceptados y documentados:**
  - **El costo de una fecha pasada usa la razón social de hoy** (medio M4 de base). La foto de costo de la 2.3 tiene que guardar la condición frente al IVA que usó, como el resto de los valores.
  - **La solicitud de Dirección queda a nombre del Controller.** El motor de aprobaciones usa a la persona que la crea, así que solo el Controller la puede retirar. Si el grupo tiene una sola persona de Dirección y ella tuviera algo que ver, la solicitud quedaría sin quien la decida. Con el primer paso solo del Controller (decisión 7), el caso ya no se da.
  - **"El último aprobado"** se ordena por la fecha desde la que vale y después por el orden de registro, no por la hora de aprobación.
  - **El CUIT** se valida como 11 números, sin el dígito verificador: los datos de prueba son ficticios y no lo cumplen.
  - **`ingredient_line_cost` pide `prices.view`**. Para la 2.3, el motor va a usar las versiones internas, y el Chef verá costos de receta sin ver precios.

- **Segunda pasada:** `db-reviewer` y `security-auditor` confirmaron cerrados los graves y medios de la primera. Encontraron otros, resueltos y con prueba:
  - **grave (seguridad):** Compras movía el costo tocando el catálogo, sin aprobación (contenido, conversiones, desactivar productos o armar un "primer precio"). Se resolvió con las decisiones 9 y 10, y la referencia incluye los productos desactivados;
  - **medio:** un precio con fecha hacia atrás cambiaba costos pasados sin Dirección (decisión 10);
  - **medio:** Compras no veía los importes de lo que proponía en la bandeja;
  - **menores:** `check_reference` revisa a la fecha de hoy, la referencia elige el precio antes de calcular, comentarios alineados con la regla nueva, y pruebas del `check` de aprobación y del contenido congelado.
- **Tercera pasada (`security-auditor`):** dos graves y medios más, resueltos y con prueba:
  - **grave:** Compras cambiaba el contenido del producto entre la propuesta y la aprobación, y el Controller aprobaba con números que ya no eran reales. Ahora la solicitud guarda el contenido y la aprobación no se aplica si cambió;
  - **grave:** cambiar la unidad de uso de una materia prima (de unidad a gramos, por ejemplo) multiplicaba los costos. Ahora no cambia si tiene precios;
  - **medio:** un precio propio de local, o de otra presentación, con fecha vieja cambiaba el costo pasado de ese local. Ahora tampoco empieza antes del precio que vale hoy en ese lugar;
  - **menor:** cambiar la categoría escondía el aviso de desactualizado; ahora lo decide Dirección General. Una fecha mínima vencida al aprobar sale como "no se puede aplicar", no como un error crudo.
- **Cuarta pasada (`security-auditor`): apto, sin graves ni medios.** Sus dos menores quedaron resueltos: el precio se registra con el contenido que se aprobó (si cambió en el medio, se rechaza), y la solicitud guarda también la unidad de uso. Se acepta que el mensaje "ya tiene precios" le diga a quien administra el catálogo que existen precios, sin mostrar montos (hoy Compras ve precios igual).

## Riesgos y pendientes

- **Locales sin razón social:** en producción hay que cargarlas antes de mirar costos sin IVA.
- **La primera solicitud queda "aprobada" aunque falte Dirección.** El motor responde "aprobada y aplicada"; la pantalla del PR 2 tiene que aclarar que pasó a Dirección. El motor de varios pasos (Chef, Compras y Salón) llega con su propio plan.
- **Fletes y cargos:** cuando lleguen las facturas o el módulo de compras.
- **La foto de costo de la 2.3** tiene que guardar los valores usados (precio, rendimiento y condición frente al IVA).
- **Las conversiones todavía mueven la cantidad de una línea de receta.** Una línea en ml de una materia prima que se usa en gramos se convierte con la densidad de hoy, que Compras puede cambiar sin aprobación. Antes de la 2.3 hay que congelar la cantidad en la unidad de uso al publicar la versión de la receta (o en la foto de costo), o pasar por aprobación el cambio de una conversión usada en recetas publicadas.
- **Un precio con fecha futura** (hasta un año) fija la fecha mínima de los siguientes del mismo lugar hasta que empieza a valer.
- **El motivo y las observaciones de una solicitud de precio** se ven en la bandeja aunque los importes salgan ocultos, y el motivo va en el aviso. La pantalla del PR 2 tiene que pedir que no se escriban montos ahí.
- **Subas en escalones:** varias propuestas seguidas por debajo del % del grupo, cada una contra la anterior, no llegan a Dirección. Cada una la ve el Controller. Si Soy quiere cubrirlo, se puede medir también contra el precio de hace N días: **pregunta abierta para Joaco y Soy.**
- **El historial y su exportación** ocultan importes con `recipes.view_costs`, no con `prices.view`. Hoy todo rol con `audit.view` o `audit.export` también ve precios; si eso cambia, hay que aplicar la regla de `workflow.can_see_amounts`.
- **El Gerente ve todas las razones sociales del grupo** (nombre, CUIT y condición frente al IVA). Son datos públicos de las sociedades; se acepta así.
