# ADR-0030 — Terceras respuestas de Soy

- **Fecha:** 2026-11-03
- **Estado:**
  - respuestas de Soy, recibidas por Joaco;
  - lo marcado "a confirmar" es nuestra interpretación técnica: Joaco la confirma con Soy antes de construirlo.
- **Base:** las 9 preguntas que se le mandaron el 2026-11-02 (plan del servidor, datos reales, aprobaciones, rendimiento, precios y otros negocios).

## Respuestas y qué cambia

### A. Producción

1. **Plan pago del servidor:** **sí.** Soy autoriza pasar Supabase al plan Pro para producción.
   - **Qué cambia:** se destraba crear el proyecto de producción, que es la última de las tres bases (desarrollo, staging y producción; `.claude/rules/security.md`).
   - **Quién lo hace:** Joaco, con la cuenta de Soy.
   - **Después del alta:** se publican las migraciones solo por GitHub Actions y con la aprobación de Soy. Claude Code nunca se conecta a producción.

2. **Los datos reales del grupo** (marcas, locales y razones sociales): **que Claude construya un panel de control para darlos de alta desde ahí; cuando esté hecho, los cargan juntos.**
   - **Qué cambia:** hace falta un **panel de control de la estructura del grupo**. Hoy la base ya tiene las funciones (crear y editar marcas, locales y áreas, desde la Fase 1, y razones sociales, desde la 2.1 C), pero no hay pantallas.
   - **Va en:**
     - marcas: alta, edición, cierre;
     - locales: alta, edición, cierre, razón social y tipo;
     - razones sociales: alta, edición y condición frente al IVA.
   - **Se carga en producción, no en desarrollo:** los datos reales nunca entran a la base de desarrollo.
   - **Consecuencia:** el panel pasa a ser lo próximo a construir, porque frena la carga real y la compuerta 2.4 (el Excel real de Nonnos).

### B. Aprobaciones

3. **La "administración maestra":** **las personas y usuarios que se carguen desde un panel de control, con sus permisos.**
   - **Lectura:** no es un rol fijo, sino un permiso que se asigna a quien corresponda desde el panel de roles, que ya existe en la Fase 1 (`/roles`, con aprobación de los cambios en la matriz).
   - **Qué cambia:** la aprobación final de los costos de las recetas (compuerta de la Fase 2) pide un permiso propio (por ejemplo, `recipes.approve_costs`), que Soy reparte desde el panel.
   - **A confirmar:** ¿ese permiso nace asignado a algún rol (Dirección General), o vacío para que Soy lo asigne?

4. **Aprobación de recetas en varios pasos:**
   - **el "Salón" es el Gerente del local;**
   - **el orden es:** primero el Chef, después Compras y al final el Gerente del local. Es lo que propusimos.
   - **Qué cambia:** el motor de aprobaciones necesita pasos encadenados con un rol por paso. Hoy tiene un solo paso; la 2.1 C ya encadena dos solicitudes para los precios, sin cambiar el motor (ADR-0029).
   - Necesita su propio plan, que decida:
     - si se generaliza ese encadenado;
     - qué pasa con una receta de marca o de grupo, que usan varios locales: ¿aprueba un Gerente por local, o alcanza con uno?
   - **A confirmar:** eso último.

### C. Rendimientos

5. **El aviso de rendimiento:**
   - **el umbral se carga a mano** (por ejemplo, con la inflación del mes);
   - **se avisa al Chef y al Controller.**
   - **Qué cambia:**
     - el umbral va en la configuración del grupo, junto con el de precios;
     - el aviso, en `core.notifications`, para el Chef y el Controller del alcance del ensayo.
   - Se suma a la etapa 2.3 o 2.5.

### D. Precios (confirmación de ADR-0029)

6. **El porcentaje que hace aprobar también a Dirección:** **sí, y que lo pueda cambiar el administrador.**
   - **Ya está:** el % vive en la configuración del grupo (`costing.price_settings`) y lo cambia quien tiene `prices.configure`.
   - **Hoy** ese permiso lo tiene Dirección General (decisión 4 de ADR-0029). Desde el panel de roles se le puede dar a otro rol, con la aprobación que ya pide un cambio de la matriz.
   - **A confirmar:** ¿"el administrador" es Dirección General, como está hoy, o el Superadministrador?
   - La pantalla para cambiarlo va en el PR 2 de la 2.1 C.

7. **Comparar contra el costo que el local usa hoy:** **sí.** Confirma la decisión 5 de ADR-0029. No cambia nada.

8. **Subas en escalones:** **sí, comparar también contra el precio de hace 30 días.**
   - **Qué cambia:** la variación se mide contra dos referencias:
     - el costo que se usa hoy;
     - el que valía hace 30 días;
   - vale la más grande. Así varias subas chicas seguidas llegan a Dirección cuando en total superan el %.
   - **Propuesta:** que los 30 días sean configurables en `costing.price_settings`, igual que el %.
   - **Va en:** una migración nueva de precios, con pgTAP, junto con las pantallas de la 2.1 C.

### E. Para después

9. **Otros negocios del grupo** (vinos, consultoría): **no por ahora.** El sistema es solo para los restaurantes. Se cierra la pregunta que estaba abierta desde la Fase 1 (`CLAUDE.md`).

10. **Compras excepcionales:** **sin respuesta.** Sigue abierta para la Fase 3 (compras).

## Orden de trabajo que se propone

1. **Panel de control de la estructura del grupo** (respuesta 2): marcas, locales y razones sociales. Frena la carga real.
2. **2.1 C, PR 2:**
   - las pantallas de precios;
   - la configuración del % y de los 30 días;
   - las subas en escalones (respuesta 8).
3. **Producción:** Joaco crea el proyecto con el plan Pro (respuesta 1). Después se cargan juntos los datos reales y se hace la compuerta 2.4.
4. **2.3, motor de costos;** después, la aprobación en varios pasos (respuesta 4), con su plan.

## Lo que queda abierto

- **Soy:**
  - ¿quién es "el administrador" que cambia el %?
  - ¿el permiso de "administración maestra" nace asignado a algún rol?
  - en una receta que usan varios locales, ¿aprueba un Gerente por local?
  - compras excepcionales.
- **Joaco (ADR-0025):** ¿un plato se puede usar como preparación de otro? ¿El Jefe de Cocina ve las diferencias de la variante de su local?
