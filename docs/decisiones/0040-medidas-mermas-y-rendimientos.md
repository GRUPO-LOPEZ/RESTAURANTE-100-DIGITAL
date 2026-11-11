# ADR-0040: Medidas, mermas y rendimientos

- **Fecha:** 2026-11-11
- **Estado:** aceptada por Joaco (plan aprobado el 2026-11-11).
- **Pedido:** Soy, «Medidas, mermas y rendimientos».

## Contexto

Soy pidió tres cosas:

- unidades de recetario (taza, cucharada…) que se elijan por nombre y abreviatura;
- la merma de limpieza y la de descongelado de cada materia prima, para el rendimiento neto y el costo real;
- un rendimiento final en peso terminado para las sub-recetas, para usarlas por peso y costearlas bien.

También pidió hacerlo sin romper nada: una rama aparte, un respaldo, campos nuevos con valores por defecto y ningún cambio de costos sin una migración revisada.

Casi todo ya existía:

- unidades y conversiones;
- peso por unidad y densidad;
- rendimientos por proceso con estándar aprobado (ADR-0021);
- la cantidad de compra, limpia o cocida en cada línea;
- el uso de sub-recetas por cantidad terminada (ADR-0025 y ADR-0032).

## Decisiones de Joaco (2026-11-11)

1. **Las mermas van sobre el estándar aprobado.** La pantalla las pide en %. Por dentro se proponen como estándares de los procesos LIMPIEZA y DESCONGELADO, y las aprueba un Chef de todo el grupo distinto de quien las propone.
2. **Nunca suponer.** Sin dato no hay merma de 0 % ni densidad 1: se muestra «—» y el motivo, y el costo queda incompleto. Una merma de 0 % vale solo si alguien marca «No tiene merma».
3. **El rendimiento final de la sub-receta es obligatorio**, con unidad libre. Ya lo exigía la base para pedir la revisión (`recipes.request_review`), y la ficha ahora lo destaca.
4. **Después de las revisiones:**
   - **dejar de comprar congelada pide aprobación.** Desmarcarla baja el costo, así que queda como solicitud (`catalog.change_requires_thawing`) que aprueba un Chef de todo el grupo, nunca quien la pidió. Marcarla sigue siendo directo, porque solo puede dejar el costo incompleto o subirlo;
   - **las unidades las sigue creando Compras**, porque hoy hay un solo grupo. Se suma «Dar de baja» para una unidad cargada a mano que nada usó, así un error se corrige. Antes de sumar un segundo grupo, se revisa quién las crea.

## Cómo quedó

### Base (`20261126120000_units_and_waste.sql`)

- **Unidades:**
  - `long_name` y `abbreviation`, obligatorias y cargadas para todas;
  - 10 medidas nuevas, cada una con su factor a la base: mg, lb, oz, cc, taza (240 ml), cucharada (15 ml), cucharadita (5 ml), onza líquida (29,57 ml), pizca (0,5 g) y porción (1 unidad);
  - `catalog.create_unit` suma otras. Las unidades son de todo el sistema, como antes: las crea quien tiene `catalog.manage` en un grupo, con motivo y auditoría;
  - `catalog.archive_unit` da de baja una unidad cargada a mano que nada usa ni usó. Para saber si se usa, `catalog.unit_in_use` revisa las claves foráneas que apuntan a las unidades, también las de las fotos de costos. Las unidades base y las del sistema nunca se dan de baja;
  - «Atado» sigue siendo un envase, para no romper lo cargado.
- **Descongelado:**
  - `catalog.ingredients.requires_thawing` («se compra congelada»), en falso por defecto;
  - `catalog.set_requires_thawing`, con `catalog.manage` y motivo. Marcar se aplica en el momento. Desmarcar crea la solicitud `catalog.change_requires_thawing` (la aplica `catalog.apply_requires_thawing`). Cualquier cambio anota el recálculo de las recetas que usan esa materia prima;
  - los procesos LIMPIEZA y DESCONGELADO se crean en los grupos que ya existen. El seed los trae.
- **Motor:**
  - `catalog.costing_yield` es el rendimiento que usa el costo: el estándar del proceso de la línea por el factor de descongelado (`catalog.thawing_factor`), con 4 decimales. El factor es 1 si la materia prima no se compra congelada;
  - los escenarios también suman el descongelado: un rendimiento simulado se multiplica por el factor, como en el costo real;
  - si la materia prima es congelada y no tiene estándar de descongelado, no devuelve nada y la línea queda **RENDIMIENTO NO DEFINIDO**;
  - las dos funciones del motor (`recipe_line_costs_internal` e `ingredient_line_cost`) cambian una sola línea para usarla;
  - `approved_yield` y `standard_yield` no cambian, porque las usan las propuestas y los avisos de ensayos.
- **Mermas en %:** `catalog.propose_waste` propone la limpieza y el descongelado en una sola transacción, todo o nada.
  - La limpieza conserva el factor de cocción que ya tenía. Si no tenía, va 1 («no se cocina»), igual que en el formulario de estándares. Ese valor viaja en la solicitud y quien aprueba lo ve. El descongelado no usa cocción.
  - 0 % solo si se declara. Se controla después de redondear a 4 decimales.
- **Merma de cocción** (`recipes.cooking_loss`, informativa): peso terminado sobre el peso de las líneas tal como están escritas, en gramos.
  - Solo se calcula si todo se puede pasar a gramos. Si no, se dice qué falta y no se muestra una suma parcial.
  - Respeta lo que ve la persona.

### Pantallas

- **Unidades:**
  - los desplegables de líneas, del rendimiento y de los productos de compra muestran «Kilogramo (kg)», agrupados por tipo;
  - en la configuración del catálogo está la lista con su equivalencia y el alta de una unidad nueva, con el tipo en botones a la vista.
- **Ficha de la materia prima, pestaña Rendimientos:**
  - 4 indicadores: merma de limpieza, de descongelado, rinde neto y costo neto por kg en el local de arriba, calculado por el mismo motor;
  - «¿Se compra congelada?» se cambia con un clic, y se guarda con motivo;
  - «Proponer mermas» trae una vista previa en vivo («Rinde 72,0 % neto · Costo neto $ X por kg»).
- **Ficha de la receta, pestaña Rendimientos:** rendimiento final destacado, costo por kg (o litro, o unidad) y merma de cocción.

## Límites y riesgos

- **El costo de lo cargado no cambia.** Se midió antes y después de la migración, con el seed: las 198 líneas dan igual. También lo prueba `270`, que confirma que, sin congeladas, el motor usa los mismos rendimientos en todas las líneas.
- **Marcar «congelada» no pide aprobación.** Lo hace Compras, con motivo y auditoría. Sin la merma de descongelado aprobada, el costo queda incompleto. Con la merma aprobada, sube. Desmarcar, que lo baja, sí pide aprobación (decisión 4).
- **Un descongelado aprobado para una materia prima no marcada** queda sin efecto hasta que se marca. Marcarla es lo que lo activa, y queda en el historial.
- **La foto del costo** guarda en `cleaning_yield` el rendimiento combinado (limpieza × descongelado), y `yield_profile_id` apunta solo al perfil del proceso. El perfil de descongelado que se usó no queda en la foto: se reconstruye con la marca (auditada) y los estándares vigentes en esa fecha. Si hace falta rastrearlo línea por línea, se suman `thawing_profile_id` y `thawing_yield` a la foto en otro PR (revisión de base, M2).
- **Costo neto en la ficha:** la base pide `prices.view` en el local, y la pantalla lo muestra a quien ve costos (`menus.costs`). Quien tiene uno solo de los dos ve «—» con el motivo, nunca un número que no le corresponde.
- **Las mermas se cargan en la ficha, no en el alta.** El alta de una materia prima sigue siendo corta (regla de diseño: el alta crea el borrador). Las mermas necesitan la aprobación de otra persona.
- **La lista de unidades de las recetas** está en `lib/recipe-format.ts`, además de en la base, porque la usan componentes del navegador. Una unidad creada con `create_unit` aparece en compras y en la configuración, pero no en las líneas de receta hasta sumarla a esa lista. La pantalla de unidades lo dice. Leer las unidades de la receta desde la base queda para otro PR (revisión de diseño, M2).
- **Grupos nuevos:** hoy no hay una función para crear grupos. El que se cargue tiene que crear los procesos LIMPIEZA y DESCONGELADO con esos códigos. Si falta alguno, la ficha lo avisa y no ofrece proponer mermas.
- **Pizca = 0,5 g y porción = 1 unidad** son convenciones del plan aprobado. Si Soy prefiere otras, se cambian con una migración.

## Pruebas

- **pgTAP `270_units_and_waste` (68):**
  - unidades y factores, y quién crea unidades;
  - que el costo de lo cargado no cambia;
  - congelada sin estándar → no definido; con estándar, 1.000 / (0,8 × 0,9);
  - el descongelado no se cuenta dos veces;
  - recálculo y auditoría;
  - mermas: todo o nada, 0 % declarado, se conserva la cocción;
  - merma de cocción, con y sin densidad, con la sesión de un usuario y sobre una versión que no se ve;
  - el descongelado en el motor de recetas y en un escenario;
  - que quien propone no aprueba lo propio y que el Cocinero no ve el costo neto;
  - desmarcar: queda pendiente, no se pide dos veces y lo aprueba otra persona;
  - dar de baja unidades: sin permiso, en uso, base, del sistema, y la que sí se puede, con auditoría.

  Además se ajustaron `050` (inventario) y `140` (la lista exacta de las 24 unidades de las migraciones).

- **Vitest `waste.test.ts`:** rendimiento neto, vista previa, unidades y esquemas.
- **Playwright `mermas.spec.ts`:**
  - congelada con un clic, y desmarcar queda pendiente;
  - propuesta con vista previa;
  - unidades, unidad nueva y su baja;
  - rendimiento final y merma de cocción;
  - axe con WCAG 2.2, en celular y computadora.

## Revisiones (2026-11-11)

- **`security-auditor`: apto, sin graves.** Los medios se resolvieron así:
  - desmarcar «congelada» pide aprobación (decisión 4);
  - las unidades mal cargadas se pueden dar de baja (decisión 4).

  De los menores, se sumaron las pruebas que faltaban. La diferencia de permisos del costo neto quedó documentada.

- **`db-reviewer`: sin graves.** Se corrigieron:
  - los escenarios sin descongelado;
  - que 140 dependiera de lo que dejan las pruebas de pantalla;
  - los comentarios del motor y de `units.name`;
  - el redondeo de la vista previa;
  - el 0 % redondeado;
  - el aviso por procesos con nombre ocupado;
  - las pruebas del motor de recetas.

  Quedaron documentados: la foto del costo sin el perfil de descongelado y la cocción 1 de LIMPIEZA.

- **`ui-reviewer`: sin graves.** Se corrigieron:
  - el estado del costo según su confiabilidad (vencido, heredado o con estimaciones);
  - las explicaciones en tooltip (`components/ui/info-tip.tsx`);
  - el nombre fijo del interruptor, con la palabra al lado;
  - «No aplica» repetido y la merma de cocción en «20,0 %»;
  - «Costo» sin unidad;
  - el aviso de procesos faltantes (sin formulario);
  - el motivo cuando falta el precio;
  - el estado vacío por tipo de unidad;
  - la marca en la opción elegida;
  - los tokens de alto.

  Quedan:
  - las unidades de las recetas fijas en el código (documentado);
  - el borde de 2 px del interruptor, igual que la matriz;
  - los obligatorios sin marca, como en el resto del sistema.
