# ADR-0025 — Subrecetas y variantes locales (etapa 2.2 B)

- **Fecha:** 2026-10-30
- **Estado:** aceptada por Joaco (plan de la sesión aprobado).
- **Base:** documento de Soy, sección 11; sus respuestas 10 y 11 (ADR-0024); plan de la Fase 2.

## Contexto

- **La 2.2 A dejó las recetas versionadas** (ADR-0023). Faltaban dos cosas del recetario:
  - **subrecetas:** un plato que usa una preparación, como una lasaña que lleva salsa bolognesa;
  - **variantes locales:** la receta de un local hecha a partir de una maestra.
- **Respuesta 10 de Soy:** cuando cambia una preparación, los platos que la usan **cambian solos**, y se avisa al Chef, a la gerencia de Compras y a la gerencia general.
- **Respuesta 11 de Soy:** Pariggi es un proveedor externo como cualquier otro. No hace falta nada especial, y el alcance "cocina central" queda sin usar.

## Decisiones de Joaco (2026-10-30)

1. **Las variantes entran ahora, junto con las subrecetas.** Al publicarse una variante, su local deja de usar la maestra y usa la variante.
2. **Avisos (provisorio hasta la pregunta 5 de Soy):** Compras y Dirección General de todo el grupo, más quienes pueden publicar cada plato afectado (chefs y directores de marca). Nunca a quien aprobó el cambio.

## Cómo quedó (PR 1, base)

- **Migración** `20261104120000_recipes_subrecipes.sql`.
- **Una línea es una materia prima o una preparación, nunca las dos:**
  - `recipe_components.sub_recipe_id`, con clave foránea compuesta `(sub_recipe_id, group_id)`;
  - una preparación se mide en **cantidad terminada** (`finished`), y una materia prima nunca. Lo controla la base con `check`.
- **La línea apunta a la receta, no a una versión:** el plato usa siempre la versión vigente de la preparación (respuesta 10). No hay nada que actualizar en el plato cuando cambia la salsa.
- **Reglas al guardar** (`set_components`). La preparación tiene que:
  - estar activa y tener versión vigente;
  - estar al alcance del plato. Una maestra del grupo la usa cualquiera; una de marca, las recetas de esa marca y de sus locales; una de local, solo las de ese local;
  - usar una unidad de la misma dimensión que su rendimiento (kg, g, l, ml, unidad, docena);
  - no formar un círculo. La búsqueda recorre las versiones vigentes y también las abiertas (caso 10);
  - no pasar de 10 niveles.
- **Defensa en profundidad:** `request_review` y la publicación vuelven a validar todas las líneas con una sola función (`first_invalid_line`). Así se frena una línea copiada de una versión anterior que ya no sirve, o dos borradores que se cruzaron.
- **Una preparación que otra receta usa no se archiva.** El mensaje dice cuáles recetas la usan. `archive_recipe` toma la receta con `for update` y `set_components` la lee con `for share`, el mismo patrón que en el catálogo.
- **Alérgenos** (`version_allergens`): recorren las preparaciones con su versión vigente, hasta 10 niveles. Una materia prima sin dato en cualquier nivel deja el plato "no verificado" (caso 23).
- **Quien ve un plato ve también las preparaciones que usa** (`viewable_recipe_ids`), porque las tiene que cocinar. Solo la versión vigente; los borradores siguen siendo de quien trabaja la receta.
- **Avisos** (`notify_recipe_changed`, tipo `recipe_changed`):
  - al publicarse una versión de una receta que otros platos usan en su vigente, se crea un aviso por persona;
  - por ejemplo: "Cambió «Salsa bolognesa» (v3): la usan 4 recetas";
  - los destinatarios se calculan con `core.user_has_role_for_scope` y `core.user_has_permission_for_scope`, las mismas funciones que los avisos de aprobación. La regla vive en una sola función, fácil de cambiar cuando Soy responda la pregunta 5.
- **Variantes:**
  - `recipes.variant_of_recipe_id` guarda la maestra. Una variante es siempre de un local, de la marca de la maestra o de una maestra del grupo;
  - `create_variant` pide `recipes.approve` en ese local (Chef Ejecutivo, Director de Marca o Dirección). Copia la vigente de la maestra (líneas, pasos, dependencias y fotos) en una v1 en borrador y la asigna al local;
  - una sola variante activa por maestra y local (índice único);
  - al publicarse la variante, la asignación de la maestra en ese local se cierra en la misma transacción;
  - `variant_diff` muestra las diferencias contra la vigente de la maestra, solo para quien trabaja la variante;
  - la maestra de una variante no cambia nunca (trigger).
- **Las fotos copiadas a una variante** siguen siendo los mismos archivos de la maestra. Se leen porque están registrados en una versión que la persona ve (`visible_media_paths`). Las fotos nuevas de la variante van en su propia carpeta.
- **Lectura:** `recipe_usage` (dónde se usa una receta) y `search_subrecipes` (buscador de preparaciones a su alcance, desde 3 letras). Las dos corren con los permisos de quien pregunta (RLS).
- **Seed:**
  - la Lasaña usa la Salsa bolognesa y la Salsa blanca;
  - los Ravioles suman la bolognesa;
  - Demo Pastas Norte tiene una variante publicada de los Ñoquis, y ya no usa la maestra.

## Casos del documento

- **10:** C no puede usar A si A usa B y B usa C. Se frena al guardar y también al pedir la revisión.
- **23:** una materia prima sin dato en la subreceta deja el plato "no verificado".
- **26 (reescrito según la respuesta 10):** al publicar la v2 de la salsa, el plato no necesita versión nueva, ya la usa y se avisa a quien corresponde.

## Pruebas

- `190_subrecipes.test.sql` (78): estructura, ciclos, alcance, unidades, profundidad, casos 23 y 26, avisos, archivo y variantes.
- `195_subrecipes_performance.test.sql`: con 2.000 platos y 200 preparaciones en cadenas de 10 niveles, cada lectura responde en menos de 300 ms.
- **Se actualizaron a propósito:**
  - `050`: las cuatro funciones nuevas;
  - `170`: ahora hay 20 recetas vigentes, y la prueba "deja de verla" usa una receta que ningún plato usa. La Salsa blanca la sigue viendo la cocina, porque la usa la Lasaña.

## Revisiones

- **`security-auditor`: apto, sin graves.** Los 3 medios están resueltos:
  - **Para usar una preparación, quien edita la tiene que ver.** El mensaje de error no la nombra si no la ve.
  - **El límite de niveles mira hacia arriba y hacia abajo** (es el mismo hallazgo que el grave de la revisión de base).
  - **`variant_diff` pide ver también la maestra.** Elegí la opción que deniega por defecto: el Jefe de Cocina de un local que ya usa la variante no ve más la fórmula de la maestra. Las diferencias las ve el Chef de la marca. **Joaco puede cambiarlo.**
- **Menores de seguridad:**
  - la ficha de cocina nombra la maestra solo a quien la ve;
  - el aviso ya no cuenta los platos de todo el grupo;
  - `first_invalid_line` vuelve a controlar el alcance;
  - `create_variant` bloquea la maestra recién después de controlar el permiso.
- **`db-reviewer`: 1 grave (reproducido) y 4 medios, todos resueltos:**
  - **G1, el grave:** el límite de 10 niveles solo se medía hacia abajo. Alargando una cadena desde abajo, un plato con harina en el nivel 17 decía "sin gluten verificado".
    - Ahora `sub_height` mide los niveles de encima, y el límite se controla al guardar, al pedir la revisión y al publicar.
    - Además, `version_allergens` marca "no verificado" si el árbol queda cortado.
    - La `190` prueba los dos casos.
  - **M1:** guardar líneas con preparaciones y publicar toman un bloqueo por grupo (`lock_sub_graph`). Así dos cambios simultáneos no forman un círculo.
  - **M2:** una preparación no puede publicar un rendimiento con otro tipo de unidad (de kilos a unidades, por ejemplo) mientras otra receta la use.
  - **M3:** los avisos preguntan el permiso por alcance, no por plato. La `195` mide una preparación que usan 100 platos.
  - **M4:** una maestra no se vuelve a asignar a un local que usa una variante suya publicada.
- **Menores de base:**
  - comentarios en español al día;
  - índice de la clave foránea sin filtro;
  - el buscador trata `%` y `_` como texto común;
  - una preparación no acepta base de compra ni rendimiento de materia prima;
  - una materia prima inactiva se rechaza también al guardar;
  - más pruebas: auditoría, que la cocina no vea borradores de una preparación, y el rechazo al publicar.

## Para que decida Joaco

- **¿Un plato se puede usar como preparación de otro?** Por ejemplo, un combo. Hoy la base lo permite.
- **`variant_diff`:** ¿lo ve también el Jefe de Cocina del local de la variante, aunque ya no vea la maestra? Hoy no.

## Riesgos

- **Si se archiva la maestra de una variante,** la variante sigue y deja de mostrar diferencias (no hay contra qué comparar).
- **Las fotos copiadas a una variante** siguen en la carpeta de la maestra. `media_recipe_id(storage_path)` puede devolver la maestra, así que nunca se usa para autorizar algo sobre una fila de `recipe_media`.

- **"Cambian solos"** significa que un cambio en una preparación llega a todos los platos sin aprobar cada uno. Es lo que pidió Soy; quedan el aviso y la historia.
- **Si se archiva una variante,** la maestra no vuelve sola a su local: hay que asignarla de nuevo.
- **Los avisos son provisorios** hasta la pregunta 5.
