# Estado del proyecto

_Última actualización: 2026-10-30. Soy aprobó la Fase 1 (ADR-0019). Joaco aprobó el plan de la Fase 2 (ADR-0020). Staging funciona. Fusionados: 2.1 A y 2.1 B (PR #19 y #20), configuración del catálogo (#21) y la base de recetas (#22). **Llegaron las respuestas de Soy a las decisiones de la Fase 2 (ADR-0024).**_

## Al retomar: etapa 2.2 B, subrecetas y variantes (PR 2 de 2, pantallas, rama `feat/recetario-subrecetas-pantallas`)

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
- **Próximo:**
  - fusionar el PR 2 (rama ya subida);
  - plan de la importación del Excel de Nonnos. Faltan 4 respuestas: qué hacer con los precios del Excel, qué es el rubro "Plato finalizado", si se conservan los códigos y si los otros recetarios tienen el mismo formato;
  - aprobación de recetas en varios pasos (faltan respuestas de Soy).

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
