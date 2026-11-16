# ADR-0050: Ficha completa de proveedor

- **Fecha:** 2026-11-15
- **Estado:** plan aprobado por Joaco el 2026-11-15.
- **Pedido:** Prompt 1 de `docs/prompts/2026-11-14-facturas-modulo-2.md` (Etapa 0 del documento de Soy).
- **Sigue a:** ADR-0049 (alcance del módulo), ADR-0039 (edición directa), ADR-0045 y ADR-0046 (pantallas sin scroll).
- **Migración:** `20261202120000_suppliers.sql`.

## Decisiones de Joaco (2026-11-15)

- **P1. Importación de los proveedores reales desde planilla:** sí, en un PR aparte, justo después de este.
- **P10. Pago con código electrónico:** es un medio de pago más (`electronic_code`).
- **P2 a P9:** valen las recomendaciones del plan de la Fase 3. Se aplican en el prompt que usa cada una.

## Base

- **`catalog.suppliers` se completa, no se reemplaza.**
  - Suma: nombre de fantasía, condición frente al IVA, domicilio, localidad, teléfono, WhatsApp, correo, contacto de ventas y contacto de pagos.
  - **CUIT:** 11 números con dígito verificador (`core.valid_cuit`; 11 → 0 y 10 → 9). El check es `not valid`: los CUIT de antes, con guiones, no se tocan hasta que alguien edita ese proveedor. Las funciones lo normalizan al guardar.
  - **Lectura:** ahora también lo lee quien tiene `purchasing.view_suppliers` (el cocinero). Esta tabla no tiene datos sensibles.
- **Esquema `purchasing`**, con cinco tablas:
  - `supplier_terms`: operativa, canal de la OC, cómo factura, frecuencia de la lista y si la OC requiere aprobación;
  - `supplier_payment_terms`: condición de pago, días y pedido mínimo;
  - `supplier_payment_accounts`: medios y cuentas;
  - `supplier_categories`: rubros que provee;
  - `supplier_customer_numbers`: nuestro número de cliente por local.
- **El pago va en tablas propias porque la RLS es por fila.** Lo leen `purchasing.manage_suppliers` (Compras y Dirección) o `purchasing.view_payment_terms` (Controller y Dirección). El cocinero, el gerente y los chefs no.
- **Un solo camino de escritura:**
  - `purchasing.create_supplier` crea el proveedor con código automático (PROV-0001);
  - `purchasing.save_supplier_sheet` guarda la ficha en una transacción, con motivo y sello;
  - `purchasing.set_supplier_active` lo desactiva o lo reactiva.

  `catalog.create_supplier` y `update_supplier` pasan a pedir `purchasing.manage_suppliers`. El alta corta de la ficha de materia prima ahora usa el código automático.

- **El listado es una función** (`purchasing.supplier_list`, `security invoker`): cada uno ve lo que su RLS le deja, y la condición de pago le llega vacía a quien no la ve.

### Desvío del plan: el superadmin recibe los permisos de proveedores

El plan decía que el superadmin no recibía permisos de compras. La regla G2 de la Fase 1 dice que nadie administra a alguien con un permiso que no tiene. Sin estos permisos, el superadmin dejaba de poder suspender a Compras ni a nadie con `purchasing.view_suppliers`, y la prueba `080_accounts` falló. Se siguió el mismo criterio que en la Fase 2 (allá recibió `catalog.manage`, `prices.propose` y otros): recibe `view_suppliers` y `manage_suppliers`, y no recibe `view_payment_terms`. Con `manage_suppliers` lee las cuentas bancarias. Queda anotado para la revisión de seguridad.

## Pantallas

- **`/proveedores` (tipo C):**
  - búsqueda (nombre, código o CUIT, con o sin guiones), rubro y canal, que se aplican solos;
  - pestañas Activos / Inactivos;
  - tabla con proveedor, CUIT, rubros, días de entrega, canal, pago (solo para quien lo ve) y estado;
  - 15 filas por página;
  - «+ Nuevo proveedor» en un modal corto (razón social, CUIT opcional y motivo) que lleva a la ficha.
- **`/proveedores/[id]` (tipo B, sin scroll en 1440 × 900):**
  - encabezado en una línea con «Desactivar» o «Reactivar»;
  - 4 indicadores en «Sin datos» con su motivo (se llenan en los prompts 2, 3, 5 y 6);
  - tres columnas, 4 : 6 : 4: Identificación y contacto; Operativa; Pago y Rubros;
  - barra fija con contador, motivo, Descartar y Guardar cambios.
- **Para que entre con Compras (la vista más cargada)** se aplicaron las excepciones de ADR-0045 y ADR-0046, sin bajar de los mínimos:
  - botones de días y de «Cómo factura» de 28 px (grillas de estados, como los alérgenos);
  - opciones segmentadas de 32 px (`Segmented compact`);
  - etiquetas en línea, a la izquierda (`Segmented inline`);
  - números de cliente al lado del título de Operativa;
  - cuentas resumidas en una línea, con «Editar» en un panel que trabaja sobre el mismo borrador;
  - la aprobación de la OC dentro de Operativa;
  - nombres de opción más cortos: «Sistema propio», «Remito y factura», «Contacto de pagos».
- **Medido con `next start`**, sin scroll en 1440 × 900, 1600 × 900 y 1920 × 1080, con Compras (edita) y con la cocinera (solo lee; la lectura no es más alta). En 1440 la grilla termina justo en el máximo: si en Linux mide de más, lo marca Playwright en Actions.
- **Barra lateral:** «Proveedores» en Base de conocimiento (ícono `Truck`).

## Pruebas

- **pgTAP `320_suppliers` (59).** Cubre:
  - estructura, comentarios y auditoría;
  - CUIT (casos 1 y 2 del plan);
  - RLS por rol: la cocinera no ve el pago, el Controller lo ve y no edita, otro grupo no ve nada;
  - el guardado todo o nada, con motivo y sello;
  - las validaciones (casos 3 y 4);
  - el código automático, desactivar y el camino viejo cerrado;
  - el listado.
- **Ajustadas, sin aflojar:**
  - `000`, `040` y `050`: el módulo nuevo en sus listas, como se hizo con `catalog` y `costing`;
  - `catalog-schemas.test.ts`: el CUIT ahora exige el dígito verificador, más estricto;
  - `design-system.test.ts`: el ítem nuevo de la barra.
- **Vitest `supplier-schemas.test.ts`:** CUIT, días, borrador y esquema de la ficha.
- **Playwright `proveedores.spec.ts`, con axe:**
  - listado con filtro, pestañas y pago según el rol;
  - alta y edición con un clic por dato;
  - sin scroll en tres tamaños con los dos roles;
  - celular de consulta con 44 px.

## Después de las revisiones (2026-11-15)

Las tres revisiones (`db-reviewer`, `security-auditor` y `ui-reviewer`) encontraron un hallazgo grave en común. Se corrigió, junto con los medios.

### Decisiones de Joaco

- **El pago lo ve solo quien tiene el permiso para todo el grupo.** Las políticas usan `core.permitted_group_ids`, la misma regla que para editar. Un Controller o un Compras de un solo local o de una marca no ve las cuentas.
- **Cada alta, cambio o baja de una cuenta de pago avisa** a quien ve el pago para todo el grupo (Controller y Dirección), con lo de antes y lo de ahora (`supplier_account_changed`). Es el control del fraude de cambio de CBU hasta que los pagos pidan aprobación (Prompt 6).
- **El superadmin ve el pago (aceptado y documentado).** Por la regla G2 tiene `manage_suppliers`, y con eso lee las cuentas. Tiene doble verificación obligatoria. Hay una prueba que lo controla.
- **El Historial oculta el pago** a quien no lo ve: `core.hide_payment` en `core.audit_history` y `core.audit_export`, como ya se hacía con los costos.

### Base

- **Grave (base y seguridad):** el Historial mostraba CBU, alias y CUIT de los titulares al Auditor y al Director de Marca, que no ven el pago. Queda «[oculto]», con su prueba.
- **Números de cliente por local:** cada uno ve los de los locales que ve (`permitted_restaurant_ids`).
- **El CUIT se controla con un trigger, solo cuando se carga o se cambia.** Un check se evalúa en cada update y trababa desactivar o renombrar un proveedor viejo con el CUIT mal cargado. Los de antes que son válidos sin guiones se normalizan en la migración; los que siguen inválidos los avisa la ficha. Se borró el check viejo de «números y guiones».
- **Otros ajustes:**
  - el pedido mínimo en `numeric(14,4)`, con moneda;
  - índice completo en las cuentas;
  - la búsqueda sin comodines (`strpos`);
  - mensajes en español para un dato obligatorio vacío, una hora o un número fuera de rango;
  - los números de cliente solo en locales vigentes.
- **pgTAP `320`: 77 pruebas** (antes 59). Suma:
  - la matriz rol por permiso de compras;
  - el Auditor y el Director de Marca sin pago;
  - el superadmin con pago;
  - el Historial oculto y entero;
  - el aviso de la cuenta nueva;
  - los números de cliente por local;
  - quitar una cuenta y guardar rubros;
  - los rechazos por el camino viejo;
  - el proveedor viejo con el CUIT mal.

### Pantalla

- **Grave (diseño):** el día elegido se distinguía solo por color. Los días y «Cómo factura» usan el mismo estilo de elegido que las opciones segmentadas (azul con borde), y el día elegido va además en negrita y subrayado.
- **Los días van con dos letras** (Lu Ma Mi Ju Vi Sá Do): «M» no distinguía martes de miércoles. El nombre completo lo lee el lector de pantalla.
- **«Pedidos por» en la lista** son botones con `aria-pressed`, como la confiabilidad de Costos.
- **Las cuentas se editan en un solo panel** (lista o cuenta), y al cerrarlo el foco vuelve a «Editar». Lo mismo con los números de cliente.
- **Otros ajustes:**
  - columnas 4,5 : 6 : 3,5, para que los nombres no se corten;
  - las observaciones pasan a la tercera columna, así la cocinera no ve un hueco;
  - la lectura de Identificación en dos columnas;
  - indicadores con estado «Sin datos»;
  - «Órdenes de compra abiertas»;
  - teclado numérico y números tabulares donde corresponde;
  - el «Volver» del alta en el encabezado.

### Pantalla real de Soy: 1715 × 843 (pedido del 2026-11-15)

- **Se prueba también en 1715 × 843.** Es la pantalla de Soy: 1920 × 1080 con 112 % de escala, menos Windows y Chrome.
- **La página no se mueve:** si una tarjeta no entra, se desplaza adentro, como la tabla de Costos. Cada eslabón lleva `min-h-0`, base `0px`, `relative` y `overflow-y-auto`.
- **Medido:** sin scroll de página en 1440 × 900, 1600 × 900, 1715 × 843 y 1920 × 1080, con Compras y con la cocinera. En 1715 × 843 Identificación se desplaza adentro.
- **Lo que no cambia:** ni la letra ni los controles bajan de los mínimos.
- **Queda para un PR aparte:** las pantallas que ya existían (Inicio, fichas y Costos) y el texto de `design.md`, con su ADR.

### Respuestas de Soy (2026-11-15)

- P3, P4, P5, P6, P8 y P9 aceptadas como recomendaba el plan (PR #73).
- El lote (P9) tiene que poder seguirse desde Calidad: se tiene en cuenta en el Prompt 4.
