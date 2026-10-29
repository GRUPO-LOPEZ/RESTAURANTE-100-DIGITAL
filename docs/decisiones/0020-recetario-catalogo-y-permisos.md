# ADR-0020 — Recetario: decisiones de Joaco, permisos y catálogo (etapa 2.1 A)

- **Fecha:** 2026-10-28
- **Estado:** aceptada por Joaco.
- **Contexto previo:**
  - Soy aprobó la Fase 1 (ADR-0019);
  - el plan de la Fase 2 está en [docs/fases/fase-2-plan.md](../fases/fase-2-plan.md);
  - el plan de la sesión, en `C:\Users\julym\.claude\plans\silly-cuddling-ocean.md`.

## Decisiones de Joaco (2026-10-28)

1. **Plan de la Fase 2:** aprobado.
2. **N1, el permiso de costos se llama `recipes.view_costs`**, como en el documento de Soy.
   - `core.can_see_costs` (historial) pasa a usarlo.
   - `costing.view_costs`, que usaba la Fase 1, **nunca se había cargado en el catálogo de permisos**: hasta hoy nadie veía costos en el historial (seguro, por denegar por defecto, pero incompleto).
3. **N1b, decimales:** el costo por unidad base (por gramo, mililitro o unidad) se guarda en `numeric(20,8)`. Con 4 decimales se pierde precisión en insumos baratos. Los importes siguen en `numeric(18,4)`. Se aplica cuando lleguen los precios (2.1 C).
4. **N4, esquemas nuevos:** `imports` e `integration` (los pide el documento de Soy). Se crean cuando una etapa los use; la tabla de esquemas de `.claude/rules/database.md` ya los lista.
5. **Precios:** un precio propuesto no entra a `costing.price_records` hasta que se aprueba. La propuesta vive en `workflow.approval_requests`.
6. **Permisos de quien administra personas:** como en la Fase 1, quien da roles o suspende personas recibe los permisos del recetario de los roles que administra. La regla de seguridad dice que nadie da un rol ni suspende a alguien con permisos que él no tiene, y no se cambia.
   - **Gerente:** además, lo del Jefe de Cocina (borradores, revisión, ensayos).
   - **Director de Marca:** además, lo del Chef (aprobar, publicar, asignar, rendimientos, importar).
   - **Superadministrador:** los de Cocinero, Jefe de Cocina, Compras, Auditor y Gerente, para no perder lo que podía en la Fase 1 (suspender gerentes). Toda receta o precio sigue pasando por la aprobación de otra persona.

## Etapa 2.1 en tres partes

Las decisiones de Soy sobre precios (2, 3, 4, 7, N3 y N6) no están todavía. La etapa 2.1 se parte en tres sesiones:

- **2.1 A (esta):** permisos, `site_type` y catálogo, sin precios.
- **2.1 B:** rendimientos con aprobación.
- **2.1 C:** precios, impuestos, política de selección y aprobación de productos de compra.

## Lo que se construyó en 2.1 A

- **`org.restaurants.site_type`:** restaurante, cocina central o unidad productiva. Cambiarlo pide `org.manage` en la marca.
- **Los 19 permisos de la sección 17**, con su reparto. Lo fija la prueba `140_catalog`.
- **`core.visible_group_ids`:** el catálogo es de todo el grupo y lo lee quien tenga `catalog.view` en cualquier nivel. Solo para lectura.
- **Esquema `catalog`, expuesto por la API, con 10 tablas.**
  - Unidades y conversiones universales (globales).
  - Las tablas del grupo:
    - categorías (dos niveles);
    - ingredientes;
    - alias;
    - conversiones propias (densidad y peso por unidad, con fuente y fecha);
    - proveedores;
    - productos de compra (con contenido obligatorio);
    - alérgenos y su estado por ingrediente (sin fila = sin dato).
- **Escritura solo por funciones**, con `catalog.manage` en el grupo y motivo. Los errores de restricción salen en español (`catalog.raise_friendly`).
- **Unidades sin adivinar:** `catalog.convert_quantity` y `catalog.to_base_quantity`. Si falta un dato devuelven `missing_conversion` y la cantidad vacía, nunca 0 (casos 16 y 17 del documento de Soy).
- **Buscador** `catalog.search_components`, por nombre, alias o código, con `pg_trgm`. Las subrecetas se suman en 2.2.

## Diferencias con el plan de la sesión

- **Contenido de un producto en otra dimensión.**
  - El plan decía: "de la misma dimensión que la unidad de uso".
  - Se permite otra dimensión **solo si el ingrediente tiene la conversión cargada**, porque el aceite se compra por kg y se usa en ml.
  - Sin la conversión, la base lo rechaza.
- **Aprobación de productos de compra.** La sección 14 pide la aprobación del Controller. Se suma en 2.1 C, junto con los precios: hasta entonces, un cambio de producto no mueve ningún costo.
- **Proveedores:** se crean desde la ficha de la materia prima. No hay una pantalla aparte.
- **Validación de la lista de alérgenos:** queda para cuando se responda N5. Mientras tanto, la ficha avisa que la lista no está validada.

## Revisiones (2026-10-28 y 2026-10-29)

**Resuelto:**

- **`security-auditor` (apto, sin graves).**
  - El historial (`core.audit_history`) tenía su propia copia de la regla de costos con `costing.view_costs`. Ahora usa `recipes.view_costs`, con la misma regla de alcance que `can_see_costs`. Hay una prueba de punta a punta en `140`.
  - **El Gerente queda sin `recipes.view_costs` ni `prices.view` hasta que Soy responda N2** (denegar por defecto). Lo de la tabla de arriba era la propuesta.
  - El menú "Nueva materia prima" aparece solo con `catalog.manage` para todo el grupo, igual que lo exige la base.
- **`db-reviewer`.**
  - Los graves G1 y G2 eran de una edición mía que rompía la migración; ya aplica desde cero.
  - **M2:** migración `20261029120000_catalog_review_fixes.sql`. Un producto vigente en otra dimensión no queda sin su conversión: la base frena quitar la densidad o el peso por unidad y cambiar la unidad de uso del ingrediente. Desactivar un producto nunca se frena.
  - En la misma migración:
    - no se usa una categoría ni un proveedor borrados;
    - índices completos en las claves foráneas;
    - el buscador toma `%` y `_` como letras y no ofrece borrados.
- **`ui-reviewer` (sin graves).**
  - `id` propios por pantalla. Next guarda ocultas las páginas anteriores, y una etiqueta podía apuntar a un campo oculto. Lo controla Playwright.
  - Tope de proveedores en el desplegable y aviso de página inexistente.
  - Flecha en las acciones plegables, y textos.

**Queda decidido para más adelante:**

- **2.1 C (precios)**, una vez que existan precios:
  - los cambios de contenido de un producto, de una conversión o de la unidad de uso pasan por aprobación, o el snapshot de costo guarda los valores usados (db-reviewer, M3);
  - `core.hide_costs` pasa a una lista explícita de columnas por tabla (security-auditor, 5).
- **Dos personas a la vez** (segunda revisión de base, m1): si una crea un producto en kg y otra quita el peso por unidad del mismo ingrediente en el mismo instante, las dos pueden pasar. Es raro en la operación real y falla hacia lo seguro (el producto queda como "conversión faltante", nunca a $ 0). Se cierra en 2.1 C bloqueando la fila del ingrediente.
- **Rechazos del catálogo:** se niegan con `org.require` (42501), igual que `org.*`, y no quedan registrados como las operaciones de identidad (`core.deny`). Para el catálogo se acepta así; se revisa si una auditoría lo pide.
- **Sin funciones de escritura para categorías y alérgenos.** Por ahora los carga la migración o el seed. Llegan con la configuración (2.1 C) y con la respuesta a N5.
- **`content_per_unit` sin fuente:** es el dato del envase, que figura en la etiqueta. La fuente se exige en las conversiones y en los precios.
- **`measured_on` es `date`:** es una fecha de calendario, igual que `org.restaurants.opened_on`.
- **Errores que todavía salen genéricos** (campo vacío, número mal escrito en un pedido directo a la base): la app los frena antes con Zod y muestra un mensaje genérico en español.

## Consecuencias

- **Pruebas de la Fase 1 actualizadas a propósito, sin debilitarlas:**
  - `000_smoke`: la API tiene acceso a `catalog`;
  - `040_identity`: la matriz de la Fase 1 se compara sin los módulos del recetario, que fija `140_catalog`;
  - `050_permissions`: la lista exacta de funciones y tablas abiertas suma las del catálogo;
  - `060_roles_workflow`: sus permisos de prueba se llamaban `recipes.*` y ahora existen de verdad; pasan a `test_recipes.*`;
  - `120_answers`: la regla de membresías se prueba con un rol que la Directora de Marca puede dar.
- **Ni el Director de Marca ni el Gerente pueden dar el rol de Compras**, porque Compras tiene permisos del catálogo que ellos no tienen. Compras se da para todo el grupo, desde el Superadministrador. Si hiciera falta Compras por marca o por local, se decide aparte.
- **Supabase local:** al cambiar `api.schemas` hay que reiniciarlo (`npx supabase stop` y `start`). En staging lo aplica `config push`.
- **Rendimiento con 5.000 materias primas:**
  - lista: 28 ms;
  - buscador: entre 88 y 154 ms.

  Los dos están debajo de los 300 ms. Si el catálogo crece mucho, el buscador pasa a usar el operador de similitud con índice.
