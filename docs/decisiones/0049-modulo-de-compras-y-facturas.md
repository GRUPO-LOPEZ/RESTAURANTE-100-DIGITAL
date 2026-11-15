# ADR-0049: Módulo de compras y facturas: alcance y reutilización

- **Fecha:** 2026-11-15
- **Estado:** propuesto. Falta la aprobación de Joaco.
- **Pedido:** Soy, `docs/fases/fase-3-facturas.md` y `docs/prompts/2026-11-14-facturas-modulo-2.md` (Prompt 0).
- **Plan:** `docs/fases/fase-3-plan.md`.
- **Sigue a:** ADR-0029 (precios y razones sociales), ADR-0032 (motor de costos), ADR-0041 (códigos automáticos) y ADR-0048 (selector de local).
- **Sin cambios en la base ni en la app:** solo documentos.

## Contexto

Soy pidió el módulo «Administración y Facturas». Es el circuito completo de compras (proveedor → lista de precios → OC → recepción → factura → pago) y **la única fuente de costos de materia prima**. Su documento propone un modelo con nombres propios: `proveedores`, `articulos_proveedor`, `costos_insumo`, la vista `costos_vigentes` y `alarmas`. También pide expresamente **reutilizar** lo que ya existe y no duplicar.

La base ya tiene, con otros nombres, la mitad de ese modelo, construido en las Fases 1 y 2:

- proveedores;
- productos de compra con su envase (el factor de conversión);
- precios solo de inserción con el origen `invoice` reservado;
- la resolución del precio vigente por local;
- la cola de recálculo;
- avisos, aprobaciones, series de códigos y eventos.

## Opciones

1. **Crear las tablas del documento tal cual**, en paralelo a las que ya existen, y sincronizarlas.
2. **Completar lo que ya existe** y agregar solo lo que falta, en dos esquemas nuevos.

## Decisión (propuesta)

Opción 2.

- **No se crean** `articulos_proveedor`, `costos_insumo`, `costos_vigentes` ni `alarmas`. Las equivalencias son:

  | Lo que pide el documento | Lo que ya existe y cumple ese papel                       |
  | ------------------------ | --------------------------------------------------------- |
  | `articulos_proveedor`    | `catalog.purchase_products`                               |
  | `costos_insumo`          | `costing.price_records`                                   |
  | `costos_vigentes`        | `costing.resolve_prices` / `price_rows`                   |
  | `alarmas`                | `core.notifications`, más `reporting.v_purchasing_alerts` |

  La tabla completa está en el plan, punto 1.

- **`catalog.suppliers` se completa** (contacto y datos fiscales). La operativa, el pago y los rubros van en tablas de `purchasing` con su propia RLS: así el cocinero nunca lee cuentas bancarias.
- **Esquemas nuevos:**
  - `purchasing`: todo el circuito;
  - `inventory`: solo `stock_movements`, por ahora.
- **Los precios de factura entran a `costing.price_records`** con `source = 'invoice'` y una referencia a la línea de factura. Pasan por el mismo camino interno que los aprobados, para que el recálculo y el evento `price.approved` sigan iguales. **Los precios de lista nunca son costos:** sirven para controlar facturas.
- **Las alarmas son avisos** (`core.notifications`, con tipos nuevos) **más una vista consolidada** para el tablero. Los avisos que dependen del calendario cuelgan del trabajo diario que ya existe.
- **«Mandar OC» y el comprobante de pago se encolan** en `purchasing.outbound_messages`. Nadie los despacha hasta que se defina el canal real (decisión 9 de Soy).
- **Se construye en 6 PRs**, uno por prompt, cada uno con su plan aprobado.

## Consecuencias

- **El resto del sistema no cambia.** Recetario, Costos y los tableros siguen leyendo `resolve_prices`, y ahora reciben precios de factura sin saber de dónde vienen.
- **ADR-0029 cambia para los precios de factura** (decisión 1 de Soy): la factura conforme es la aprobación del precio. Si la variación supera el % del grupo, el precio entra igual y se avisa a Dirección, sin una segunda solicitud. Los precios sin factura siguen como hoy. El detalle va en el ADR del Prompt 5.
- **La restricción de aprobación de `price_records` se amplía** en el Prompt 5 (solicitud **o** línea de factura). Por eso ese PR lleva `security-auditor` obligatorio.
- **`database.md`** suma `purchasing` (Prompt 1) e `inventory` (Prompt 4) a la tabla de esquemas.
- **Quedan abiertas 10 preguntas** (P1 a P10, plan punto 9). Cada una lleva su recomendación y el prompt que la necesita. **Ningún prompt arranca con una pregunta suya sin responder.**
- **Los comprobantes reales de Soy se miraron fuera del repositorio.** Ni el plan ni este ADR tienen nombres, CUIT ni importes de ellos.
