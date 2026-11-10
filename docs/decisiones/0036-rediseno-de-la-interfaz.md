# ADR-0036: Rediseño de la interfaz (Grupo LF Design System)

- **Fecha:** 2026-11-09
- **Estado:** aceptada. Joaco aprobó el plan.
- **Reemplaza:** la regla «celular primero» (prompt maestro, secciones 3 y 7; ADR-0002 en la paleta).
- **Migraciones:** ninguna. Es un cambio de interfaz.

## Contexto

Joaco pidió un rediseño completo de la interfaz (prompt maestro de rediseño, 2026-11-09): un único sistema de diseño aplicado a todos los módulos actuales y futuros. El recetario va a ser la fuente de datos de otros módulos y de agentes de IA, y cada módulo nuevo tiene que reutilizar la misma interfaz.

Hasta ahora:

- todas las pantallas vivían en una columna de 1024 px con el menú en una fila arriba;
- había selectores de local dentro de varias pantallas;
- algunas métricas mostraban un estado positivo sin datos («0 de 0 · Todas al día»).

## Decisiones

- **Computadora para operar, celular para supervisar.**
  - La carga y la edición se diseñan para 1440, 1600 y 1920 px.
  - El celular tiene su propia disposición de lectura: KPIs, alertas, aprobaciones y fichas.
  - En la computadora, los controles miden de 36 a 40 px; en el celular siguen con 44 px como mínimo.
- **Layout global:**
  - **Barra lateral fija:** 240 px expandida o 68 px contraída. La preferencia se guarda en una cookie del navegador, sin tocar la base (Joaco, 2026-11-09).
  - **Barra superior de 64 px:** ruta, selector global de local, búsqueda, avisos y perfil.
  - **Área fluida:** sin ancho máximo, con márgenes de 32 px (45 px desde 1700 px).
  - **Celular:** debajo de 800 px, una barra inferior con 4 accesos.
- **Paleta nueva** (la del prompt), en los mismos nombres de token. Las pantallas que todavía no se migraron cambian solas y no se rompen.
  - Se suma `none` («Sin datos»).
  - Se conservan `review` y `draft` para los estados de versión (Joaco, 2026-11-09).
  - El tono fuerte 3 de los gráficos pasa de `#D97706` a `#B45309`: sobre el fondo nuevo, el anterior no llegaba a 3:1.
- **Tipografía:** 12 / 14 / 16 / 20 / 28 px, con KPI de 32 px y mínimo de 12 px.
- **Selector de local único y global.**
  - Usa el local activo que ya existía (`core.set_active_restaurant`), así que respeta el alcance de cada persona.
  - Los selectores propios de cada pantalla se sacan módulo por módulo.
- **Búsqueda global** (Joaco, 2026-11-09):
  - busca recetas y materias primas, con las lecturas que ya existen y la sesión de la persona;
  - cada bloque aparece solo si la persona tiene ese menú.
- **Métricas confiables:** un indicador nunca muestra un estado positivo sin datos. Se resuelve en la interfaz, con el componente `Metric`, y con los números que ya trae la base.
- **Cuatro PR por fases** (Joaco, 2026-11-09):
  1. base, componentes y layout;
  2. Inicio, Recetas y Costos;
  3. Materias primas, Reportes y Calidad;
  4. Aprobaciones, Usuarios, Historial, Roles, Mi cuenta y Panel de control.

## Restricciones

El rediseño no modifica la base, la autenticación, los permisos, los alcances, la lógica de negocio, las fórmulas, el versionado, las aprobaciones ni la auditoría. La interfaz muestra solo lo autorizado, y la seguridad real sigue en la base.

## Adenda: PR 2, Inicio, Recetas y Costos (2026-11-09)

- **Orden por columna en Costos:** `costing.restaurant_costs` suma `p_order`, con una lista cerrada de órdenes y sin SQL dinámico (migración `20261123120000_restaurant_costs_order.sql`, autorizada por Joaco). La lista se pagina en la base, así que ordenar en la pantalla ordenaría solo la página visible. Es solo de lectura: no cambian permisos, datos ni fórmulas. Un cambio chico: el orden por nombre ya no separa mayúsculas de minúsculas.
- **Recetas:**
  - el orden (nombre, código y tipo) y las pestañas de estado (Vigentes y Requieren atención) se resuelven en la consulta de PostgREST, con la sesión de la persona, sin tocar la base;
  - la ficha va en 9 pestañas, con la sección en la dirección (`?seccion=`);
  - las acciones y los formularios son los mismos que antes: solo cambia dónde están.
- **«Crítico» gana sobre «Desactualizado»** cuando un dato vencido además es crítico (Joaco, 2026-11-09).
- **El selector de local único:** Inicio, Costos y Escenarios ya no tienen el suyo. Con «Todos mis locales», la pantalla pide elegir uno y ofrece los enlaces.
- **Cambios sin guardar:** los editores de ingredientes y pasos llevan una barra Guardar / Cancelar fija abajo. El aviso de cambios sin guardar también salta al cambiar de pestaña. `ActionForm` lo ofrece con `warnUnsaved`, y por ahora lo usan los dos formularios de la ficha.
- **Volver sin perder filtros:** las fichas de costo y de receta vuelven a la lista con sus filtros y su página (`?volver=`). Solo se acepta la lista del mismo módulo.
- **Una prueba arreglada por la causa:** `234_cost_screens` usaba `current_date` (UTC) y el motor usa la fecha de la Argentina. Entre las 21 y las 24 fallaba sin que nada estuviera mal. Ahora usa `recipes.today()`.

## Adenda: PR 3, Materias primas, Reportes y Calidad (2026-11-10)

Sin migraciones ni cambios de permisos, fórmulas o aprobaciones: todo se resuelve en la interfaz y en las lecturas que ya existían, con la sesión de la persona.

- **Materias primas (listado tipo C):**
  - barra de filtros que se aplica sola (buscar y categoría), con etiquetas para quitar cada filtro;
  - pestañas de estado (Todas · Activas · Desactivadas) sobre el filtro que ya existía;
  - tabla ordenable por nombre y por código, con el orden en la consulta de PostgREST (`getIngredients`), así ordena todas las materias primas y no solo la página;
  - paginación de 15 filas (10, 25, 50);
  - «Nueva materia prima» se abre en un modal corto, con el mismo formulario que `/materias-primas/nueva`, que sigue como página para quien entra sin JavaScript o abre el enlace en otra pestaña. El modal (`CreateModal`) es el mismo de «Nueva receta».
- **Ficha de materia prima:** 6 pestañas con la sección en la dirección (`?seccion=`): Datos generales · Precios y compra · Rendimientos · Conversiones · Alérgenos · Dónde se usa. El encabezado (nombre, código, categoría y estado) queda siempre a la vista. Cada pestaña consulta solo lo que muestra. «← Volver» regresa a la lista con sus filtros, y solo acepta la lista de materias primas.
- **Los enlaces llevan a la pestaña donde se corrige:**
  - el «Ir» de cada registro en Calidad abre la ficha en su pestaña (por ejemplo, una receta sin foto abre «Fotos»; una materia prima sin precio, «Precios y compra»);
  - el aviso de rendimiento desviado abre «Rendimientos». El enlace lo guarda la base sin pestaña, y la interfaz se la agrega al leerlo (`lib/notices.ts`), con la misma regla de solo rutas internas.
- **Reportes:** sin selector de local propio; usa el de la barra de arriba y, con «Todos mis locales», pide uno. El período y la búsqueda de receta se aplican solos. Las «Últimas exportaciones» van en tabla.
  - **La tabla del reporte no pasa a `DataTable`:** al imprimir repite en cada hoja de qué reporte, local y fecha es, algo que la tabla común no hace. Se queda con su componente, con el mismo corte a celular (800 px) y la paginación común. Imprimir sigue trayendo todas las filas.
- **Calidad (panel tipo A):** sin selector propio. Lleva el aviso «Requiere atención», 4 tarjetas con `Metric` (lo que falta, nunca «Completo» sin datos), los dos ejes con barras de avance, y «Cómo está cada local» en tabla. El aviso y las tarjetas son los mismos componentes de Inicio (`components/quality-board.tsx`).
- **Paginación de 15 en Reportes y Calidad:** antes eran 50 por página. Ahora siguen la regla común (15, con 10, 25 o 50 a elección).
- **`FiltersPanel`** ya no se usa en estos tres módulos. Queda solo en Historial y Usuarios, que se migran en el PR 4.
- **Cambiar el local arriba con un reporte o una lista de Calidad abiertos** (revisión de diseño del PR 3): el selector saca `?local=` de la dirección, y esas dos pantallas daban «no encontrado». Ahora usan el local activo cuando la dirección no trae uno y, con «Todos mis locales», lo piden. Una ficha de receta que no es del local nuevo vuelve a «¿De qué receta?».
- **`FilterBar`:** sin JavaScript conserva lo demás de la dirección (local, pestaña, orden); al aplicar un filtro saca el aviso de una acción anterior; una fecha escrita con el teclado espera a que se termine de escribir.
- **Modal de alta:** al cerrarse, el foco vuelve al botón que lo abrió (WCAG 2.4.3), y el botón avisa que abre un diálogo. No usa el disparador de Radix: abriría el modal también con Ctrl+clic, que tiene que abrir la página en otra pestaña.
- **`ProgressBar` decorativa** (`decorative`): dentro de un enlace que ya dice el número, se oculta a los lectores de pantalla para que el nombre del enlace no repita todo.

## Adenda: PR 4, administración y cierre del rediseño (2026-11-10)

Sin migraciones ni cambios de permisos o de lógica. Con este PR quedan migradas todas las pantallas.

- **Local en Usuarios e Historial** (decisión de Joaco, 2026-11-10): se saca el filtro de local propio y se usa el selector de arriba. Con «Todos mis locales» se ve todo el alcance de la persona (no pide elegir, como Costos). La Marca queda como filtro de la barra solo cuando arriba está «Todos». Un `?local=` de la dirección se sigue aceptando; si no está en el alcance, la pantalla lo dice.
- **Paginación con cursor** (decisión de Joaco, 2026-11-10): Personas e Historial no tienen total ni páginas (la base trae «los siguientes N»; contar todo el historial es caro). `CursorPagination` tiene el aspecto de `Pagination`: cuántas filas se ven, filas por página, «Volver al principio» y «Siguientes» o «Más antiguos». Sus columnas no se ordenan: el orden lo fija la base.
- **Usuarios:** el tablero con filtros que se aplican solos, KPIs que nunca dan un estado positivo sin datos y que llevan a sus registros, tablas comunes y los 5 últimos cambios críticos con «Ver todos» al Historial (con el mismo período y módulo). La lista de personas con pestañas de estado. La ficha en pestañas (Datos y cuenta · Roles · Actividad), con el nombre como título.
- **Historial** en tabla, con el antes y el después de cada cambio en la última columna.
- **Aprobaciones sin pestañas:** pendientes, avisos y resueltas siguen en una sola página, así el resultado de una decisión se ve en la tarjeta resuelta. «Marcar avisos como leídos» va en el encabezado.
- **Roles:** el rol se aplica al elegirlo. **Mi cuenta** en pestañas (Mis datos · Contraseña y doble verificación · Sesiones). **Panel de control:** los grupos en grilla.
- **Pendientes de los PR anteriores:**
  - «Salir» del celular va dentro de «Menú», con Mi cuenta (design.md). El encabezado pasó a `z-40`: el menú abierto queda por encima de la barra inferior, que antes tapaba su final.
  - El título (h1) de las fichas de receta, materia prima y persona es el nombre del registro; la ruta de arriba conserva el tipo. `AppShell` y `PageHeader` suman la prop `heading`, y cada ficha lee el registro una sola vez por pedido (`cache` de React).
  - Importaciones con `DataTable` y paginación común.
  - Todos los «← Volver» usan `BackLink`.
- **`DataTable`:** cuando la tabla es más ancha que su lugar, la zona con scroll se puede recorrer con el teclado (región con nombre, `tabIndex=0`; axe `scrollable-region-focusable`).
- **Se borran** `FiltersPanel` y la tabla vieja de personas (`users-table`). TanStack Table ya no se usa en ninguna pantalla; la dependencia queda hasta que Joaco decida si sale del stack.
