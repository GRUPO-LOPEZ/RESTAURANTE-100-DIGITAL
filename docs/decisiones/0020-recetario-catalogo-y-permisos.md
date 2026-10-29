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

## Consecuencias

- **Pruebas de la Fase 1 actualizadas a propósito, sin debilitarlas:**
  - `000_smoke`: la API tiene acceso a `catalog`;
  - `040_identity`: la matriz de la Fase 1 se compara sin los módulos del recetario, que fija `140_catalog`;
  - `050_permissions`: la lista exacta de funciones y tablas abiertas suma las del catálogo;
  - `060_roles_workflow`: sus permisos de prueba se llamaban `recipes.*` y ahora existen de verdad; pasan a `test_recipes.*`;
  - `120_answers`: la regla de membresías se prueba con un rol que la Directora de Marca puede dar.
- **El Director de Marca ya no puede dar el rol de Compras para su marca**, porque Compras tiene permisos del catálogo que él no tiene. Compras se da para todo el grupo, desde el Superadministrador. Si hiciera falta Compras por marca, se decide aparte.
- **Supabase local:** al cambiar `api.schemas` hay que reiniciarlo (`npx supabase stop` y `start`). En staging lo aplica `config push`.
- **Rendimiento con 5.000 materias primas:**
  - lista: 28 ms;
  - buscador: entre 88 y 154 ms.

  Los dos están debajo de los 300 ms. Si el catálogo crece mucho, el buscador pasa a usar el operador de similitud con índice.
