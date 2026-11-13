# ADR-0044: Rubro con precios editable y edición de productos de compra

- **Fecha:** 2026-11-13
- **Estado:** aceptada por Joaco (decisiones y plan aprobados el 2026-11-13).
- **Sigue a:** ADR-0043 (ficha única de materia prima), «Lo que queda».
- **Cambia:** la regla del rubro con precios de los ADR-0029 y ADR-0038.

## Contexto

Después de la ficha única de materia prima quedaron tres puntos para decidir:

1. **Hoy nadie puede cambiar el rubro de una materia prima con precios.**
   - El trigger `catalog.guard_priced_ingredient` pedía `prices.configure`, porque el rubro decide cuántos días tarda un precio en quedar vencido.
   - Pero la ficha pide `catalog.manage`, y ningún rol tiene los dos permisos.
   - La única salida era dar de baja el rubro (ADR-0038).
2. **«Proponer precio» en el celular.**
3. **Editar un producto de compra:** la función `catalog.update_purchase_product` existía, pero no tenía pantalla.

## Decisiones de Joaco (2026-11-13)

1. **El rubro lo cambia Compras directo** (quien tiene `catalog.manage`), desde la ficha, con motivo y auditoría. Es el mismo criterio que el ADR-0038 ya aceptó para la baja de un rubro.
2. **«Proponer precio» sigue disponible en el celular.** No cambia nada.
3. **Se arma la pantalla para editar un producto.**
   - Con precios cargados, el envase y el contenido quedan fijos: el precio se guarda por envase. Si cambió el envase, se agrega otro producto y el viejo se marca como que ya no se compra.
   - Lo demás se edita: descripción, marca, proveedor, observaciones y si se sigue comprando.

Se descartaron, para el rubro:

- que Compras lo proponga y Dirección lo apruebe;
- que se aplique directo solo si el rubro nuevo vence igual.

Para el producto, se descartó dejar todo editable con motivo.

- **Corrección (revisión de base, 2026-11-13):** al plantear la pregunta se dijo que cambiar el contenido movería los costos de las recetas. No es así: cada precio guarda su contenido (`base_quantity`) y el costo no se mueve (lo prueba la 211).
- El motivo real para dejarlo fijo:
  - los precios siguientes del mismo producto quedarían sobre otro envase y la historia de precios dejaría de ser comparable;
  - una solicitud de precio pendiente quedaría rechazada al aprobarla.
- La decisión se mantiene con este motivo.

## La base: `20261130120000_rubro_y_producto.sql`

- **`catalog.guard_priced_ingredient`, redefinida:** con precios, solo la unidad de recetas queda fija.
  - El trigger se dispara solo cuando cambia la unidad.
  - El rubro lo controla `catalog.manage`, que ya pide `update_ingredient` y la ficha (`save_ingredient_sheet`).
- **`catalog.category_locked_by_prices`:** se borró. Ya no hay rubro trabado.
- **Trigger nuevo `catalog.guard_priced_product`**, en `catalog.purchase_products`:
  - con precios cargados (no borrados), rechaza cambiar el envase (`package_unit_id`, `units_per_package`) o el contenido (`content_per_unit`, `content_unit_id`), con el error 23514;
  - vale por cualquier camino: la ficha, la importación o una llamada directa.
  - La regla está en una sola función interna, `catalog.purchase_product_has_prices_internal`, que la app no puede llamar.
- **`catalog.ingredient_sheet_state`, redefinida:** ya no informa `category_locked`. Ahora informa `priced_products`, los productos con precios, para que la pantalla deshabilite su envase con la misma regla que el trigger.
- **`update_purchase_product`, sin cambios:** pide `catalog.manage` y motivo, y el código y la materia prima no cambian.

## La pantalla

- **Ficha de materia prima (computadora):**
  - el rubro se puede cambiar siempre;
  - la unidad de recetas sigue trabada con precios, con su tooltip.
- **Tabla de productos (computadora, con `catalog.manage`):** cada fila tiene un botón «Editar», con el nombre accesible «Editar «descripción»». Abre un panel con estos campos:
  - descripción, proveedor habitual y marca;
  - envase y contenido, deshabilitados con un tooltip si el producto tiene precios;
  - observaciones;
  - «¿Se sigue comprando?», un interruptor de un clic;
  - motivo.
- **Lo que viaja a la base:** solo lo que cambió (`lib/purchase-product.ts`). Si no cambió nada, avisa «No cambiaste nada.».
- **El aviso al guardar** sale arriba de la ficha (`?aviso=producto`). Si el producto deja de comprarse, sale de la tabla y su panel se cierra con la fila.
- **«Ya no se compran (N)»:** los productos desactivados y sin precio antes no se veían, así que no se podían volver a activar. Ahora quien edita los ve en un desplegable debajo de la tabla, con su «Editar».
- **En el celular,** la ficha sigue siendo de consulta y no tiene «Editar».

## Después de las revisiones (2026-11-13)

- **Base:** sin graves ni medios. Se corrigieron:
  - el motivo del envase fijo (ver «Decisiones»);
  - la carrera entre cambiar el envase y registrar el primer precio. `costing.price_record_defaults`, por donde pasa todo precio nuevo, lee el producto con `for share`: el precio espera al cambio de envase y usa el contenido nuevo (o rechaza el aprobado con otro), y un cambio de envase posterior ve el precio.
  - la prueba de `priced_products`, que ahora compara contra el producto esperado del seed y suma un producto borrado.
  - También se aclaró que un precio nunca se borra, y quedó anotado el aviso tardío con una solicitud pendiente.
- **Seguridad: apto,** sin graves ni medios. La misma carrera quedó corregida. La acción controla que el producto sea de la materia prima de la ficha, y queda aceptado que se sepa qué productos tienen precio (sin importes).
- **Diseño: aprobable,** sin graves ni medios. Se corrigieron:
  - con precios, el panel dice a la vista «No se cambia: ya tiene precios», ligado al grupo, y el tooltip queda para el detalle;
  - el nombre del grupo ya no incluye la ayuda;
  - el estilo de «Ya no se compran».
  - El asterisco de los obligatorios queda para otro PR.

## Pruebas

- **pgTAP `310_rubro_y_producto` (29):**
  - Compras cambia el rubro con precios, y queda auditado con su motivo;
  - la unidad sigue fija;
  - Dirección, el Jefe de Cocina y la Cocinera no lo pueden cambiar;
  - con precios, ni el contenido, ni las unidades, ni el envase, ni la unidad del contenido cambian, tampoco por un `update` directo;
  - con precios, lo demás sí se edita y queda auditado;
  - se puede volver a activar un producto;
  - sin precios, todo se edita;
  - un producto borrado no figura entre los de envase fijo, y la materia prima sigue con la unidad fija;
  - la regla es interna;
  - anónimo no puede llamar a nada.
- **Ajustadas a la regla nueva, sin borrar ninguna:**
  - `211`: la categoría con precios ahora la cambia Compras. Se suma que el contenido de un producto con precios no cambia, y las dos pruebas que controlan que el costo queda congelado en cada precio apagan el trigger solo dentro de la prueba, como defensa en profundidad.
  - `250`: Compras pasa la materia prima a otro rubro fuera de una baja y la devuelve.
  - `300`: el rubro con precios se aplica y queda auditado; el estado informa `priced_products`.
- **Vitest `purchase-product.test.ts`:** qué viaja a la base y el esquema `productEdit`.
- **Playwright `ficha-materia-prima.spec.ts`, en la computadora:**
  - se cambia el rubro de la Cebolla (con precios) y se le devuelve;
  - en un producto con precios, el envase está deshabilitado y el tooltip explica por qué, con capturas del panel en 1440, 1600 y 1920;
  - en un producto sin precios, se cambian la descripción y el contenido y se marca que ya no se compra;
  - se vuelve a activar desde «Ya no se compran».
- **Playwright, en el celular:** no aparece «Editar».

## Riesgos y lo que queda

- **Compras puede cambiar cuándo vence un precio,** porque los días de vencimiento dependen del rubro, sin pasar por Dirección. Es la decisión de Joaco. Queda en la auditoría, con quién y por qué.
- **Un producto con precios cargado mal no se corrige.** Hay que agregar otro y marcar el viejo como que ya no se compra. Es a propósito.
- **Una solicitud de precio pendiente no traba el envase en la ficha.** `priced_products` cuenta solo precios ya cargados. Si se cambia el envase de un producto con una solicitud pendiente, la aprobación después se rechaza con «el contenido del producto cambió». El resultado es correcto, pero el aviso llega tarde. Se puede sumar más adelante.
- **Quien edita el catálogo sabe qué productos tienen precio en cualquier local del grupo,** aunque no tenga `prices.view` ahí. Solo ve los ids, sin importes; `has_prices` ya lo mostraba antes con la misma regla. Queda aceptado.
- **Los campos obligatorios de los paneles no muestran el asterisco** (revisión de diseño). Pasa en todos los paneles con `ActionForm`, ya pasaba antes y se arregla en otro PR.
- **`prices.configure`** sigue existiendo para la configuración de precios (días por rubro y umbrales), pero ya no tiene que ver con el rubro de cada materia prima.
