# ADR-0026 — Segundas respuestas de Soy (Fase 2)

- **Fecha:** 2026-10-30
- **Estado:** respuestas de Soy, recibidas por Joaco. Lo marcado "a confirmar" es nuestra interpretación técnica: Joaco la confirma con Soy antes de construirlo.
- **Base:** las 13 preguntas de seguimiento de ADR-0024, ordenadas por urgencia.

## Respuestas y qué cambia

### A. Precios (etapa 2.1 C)

1. **Varias marcas o presentaciones de una misma mercadería:**
   - Los precios de los insumos **van a venir de otro sistema**, que lee las facturas de los proveedores.
   - Mientras tanto, se usan **valores simbólicos**.
   - Lo que sí hace falta es el alta, baja y modificación de productos y materias primas: ya existe (etapas 2.1 A y B).
   - **Qué cambia:** la 2.1 C se achica.
     - **Queda:** guardar precios con su historia y su aprobación, y una carga manual con valores de prueba.
     - **Sale de la 2.1 C:** la carga de facturas y la elección de un producto "preferido". La lectura de facturas es el agente de Facturas de la Fase 5 (`.claude/rules/agents.md`), y tendrá que entrar por el mismo flujo de aprobación.
   - **A confirmar:** con dos productos con precio, ¿qué toma el costo mientras tanto? Proponemos el último precio aprobado de cualquiera de los productos de esa materia prima, mostrando de cuál viene.

2. **Fletes y otros cargos:** se ven en un **reporte aparte, por proveedor, para analizarlos a fin de mes**. No suben el costo de cada producto. Confirma lo que entendimos en ADR-0024.

3. **Local nuevo que comparte razón social:** alcanza con elegir la razón social existente al crear el local.

4. **Porcentaje que también aprueba Dirección:** se mide contra el precio anterior de ese mismo producto, tanto si sube como si baja.

### B. Recetas

5. **A quién se avisa cuando cambia una preparación:** a quienes corresponda **de todos los restaurantes que usan ese producto o receta**.
   - **Qué cambia (ya aplicado, migración `20261105120000_recipe_change_notices.sql`):** se avisa a:
     - quien puede publicar cada plato afectado (el Chef);
     - Compras, Dirección General y Gerencia de cada local que usa alguno de esos platos (asignación vigente). Una persona de grupo los cubre a todos; una de marca, a los locales de su marca; una de local, al suyo.
   - **Deja de recibirlo:** quien es de Compras o Dirección en un alcance donde ningún local usa esos platos.

6. **Rendimientos:** el desvío que dispara la alerta se **configura en un panel de control**. Por ejemplo, por encima de la inflación (IPC).
   - **Qué cambia:** el umbral va en la configuración del grupo, junto con el porcentaje de precios (pregunta 4). No va fijo en el código.
   - **A confirmar:** ¿el umbral es un porcentaje fijo que se carga y se actualiza a mano (por ejemplo, el IPC del mes), o hay que traer el IPC de una fuente oficial? Proponemos cargarlo a mano.
   - **A confirmar:** ¿a quién se avisa (Chef, Controller)?

7. **Alérgenos:** el externo que firma **entra al sistema con su propio usuario** y con permisos para hacer eso. Soy le puede dar más o menos permisos.
   - **Qué cambia:**
     - un rol nuevo, "Auditor externo de alérgenos", con el permiso de firmar alérgenos y nada más;
     - MFA obligatorio, porque firma algo sensible;
     - se asigna como cualquier rol, por invitación y con aprobación;
     - la firma queda en la auditoría con su usuario.

8. **Quién aprueba una receta:** **varias personas: Chef, Compras y Salón**. Más adelante Soy quiere poder **agregar o sacar responsables** de la aprobación.
   - **Qué cambia:** hoy una receta la aprueba una sola persona con `recipes.publish`, distinta de quien pidió la revisión. Pasa a ser una **aprobación de varios pasos configurable**: cada paso con su rol, y todos tienen que aprobar.
   - **Es un cambio del motor de aprobaciones de la Fase 1** (`workflow`) y pide su propio plan. Antes hay que responder:
     - ¿"Salón" es un rol nuevo (Jefe de Salón o Maître) o lo aprueba la Gerencia del local?
     - ¿Las tres aprobaciones son necesarias para todas las recetas, o solo para los platos? Una salsa interna no pasa por el salón.
     - ¿Una misma persona puede cubrir dos pasos? Proponemos que no.
   - **Responde también a la pregunta pendiente de Joaco (ADR-0023):** quien escribió la receta no aprueba su propio paso.

9. **Traspaso de local:** sus recetas propias **pasan al local nuevo**. Responde la otra pregunta pendiente de Joaco (ADR-0023). Se suma al traspaso de la Fase 1 (`org.request_transfer`), con una migración nueva.

### C. Para validar

10. **Quién valida qué:**
    - precios e impuestos: Compras y Soy;
    - cargar una receta completa sin ayuda: el Chef;
    - **todas las recetas** (no 20) las aprueban el Chef y la "administración maestra".
    - **Qué cambia:** la compuerta de la Fase 2 ("el Controller valida el costo de 20 recetas reales") se reescribe. Pasa a ser: el Chef y la administración aprueban los costos de las recetas cargadas.
    - **A confirmar:**
      - ¿"administración maestra" es el Superadministrador o Dirección General?
      - Faltan los nombres de las personas y cuándo pueden.

11. **Excel del recetario actual:** viene adjunto en el mail (el de Nonnos, con una solapa que explica cómo se usa).
    - Soy quiere **cargar desde ahí** el de Nonnos y los de los otros restaurantes.
    - Después, todo se carga por pantallas ordenadas, con desplegables, como un sistema de carga de recetas.
    - **Referencia de diseño:** conceptos del Culinary Institute of America, de la Escuela Hotelera de Lausana y de sistemas como CALCMENU.
    - **Qué cambia:** la importación de Excel (esquema `imports`, ADR-0020) se usa también para recetas.
    - **Falta:** **el archivo no llegó a este chat.** Joaco tiene que dejarlo en la carpeta del proyecto (fuera del repositorio si tiene datos reales) para analizar su estructura.

12. **Las 20 recetas reales:** no se pasan aparte. Se cargan **con la ficha de recetas del programa, con desplegables**, en una solapa propia de carga de recetas, como la de insumos. Es lo que ya construye la 2.2: la lista, la ficha y los editores con buscador.

### D. Para después

13. **Marcas:** Trattoria Padella, Ragú Bodegón y Casa Nonnos, por ahora.
    - Va a haber más locales de estas tres marcas, y cada uno puede o no tener su propia razón social (ver pregunta 3).
    - Sobre otros negocios del grupo (vinos, consultoría) no respondió: queda abierto.
    - **No cambia nada del modelo:** grupo → marca → local ya lo cubre. Las marcas reales se cargan en staging y producción, nunca en el seed.

## Lo que queda abierto

- **Joaco (ADR-0025):** ¿un plato se puede usar como preparación de otro? ¿El Jefe de Cocina ve las diferencias de la variante de su local?
- **Soy:**
  - qué precio toma el costo mientras no exista el sistema de facturas (1);
  - el umbral de rendimiento y a quién se avisa (6);
  - "Salón" y los pasos de la aprobación de recetas (8);
  - quién es la "administración maestra" (10);
  - otros negocios del grupo (13).
- **El Excel de Nonnos.**
