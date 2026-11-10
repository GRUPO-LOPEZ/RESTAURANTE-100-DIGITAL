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
