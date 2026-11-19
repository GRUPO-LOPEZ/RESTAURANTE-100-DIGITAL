# Prueba de la Fase 2 para Soy: materias primas, recetas y costos

Una trattoria inventada dentro de **Demo Pastas**, en staging, para ver el circuito completo funcionando: Compras carga las materias primas y sus precios, la Controller los aprueba, la Chef arma las recetas, la Directora de marca las publica y el sistema calcula los costos solo.

**Todo es inventado**: proveedores «(ficticios)» con CUIT de prueba, precios simbólicos (`test_value`) y recetas armadas para la prueba. Nada sale de los restaurantes reales.

## Qué se carga

| Qué                 | Cantidad | Detalle                                                                                                                                                                   |
| ------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Proveedores         | 3        | Verdulería La Huerta, Frigorífico El Corral y Distribuidora Trattoria (todos ficticios)                                                                                   |
| Materias primas     | 28       | Verduras, hierbas, carnes, quesos, harinas, aceite, conservas, vino y especias. Código automático por rubro                                                               |
| Productos de compra | 28       | Uno por materia prima, con su envase (cajón, horma, bidón, maple…)                                                                                                        |
| Precios aprobados   | 54       | El del grupo y uno propio de Demo Pastas Centro, de 27 productos. Los propone Compras y los aprueba la Controller                                                         |
| Preparaciones       | 4        | Salsa pomodoro, Ragú de osobuco, Masa al huevo y Fondo de verduras                                                                                                        |
| Platos              | 9        | Tagliatelle al ragú, Fettuccine al pomodoro, Carbonara, Alfredo, Ñoquis de espinaca, Risotto alla milanese, Pollo al romero, Lasaña de berenjenas y Peceto al vino blanco |

Las 13 recetas quedan publicadas y asignadas a los dos locales de Demo Pastas. Si esos locales no tienen razón social (en staging no la carga `demo-data.sql`), la Superadministradora de prueba les asigna una ficticia, «Demo Pastas S.R.L. (ficticia)», responsable inscripta: sin ella el sistema no sabe si el costo va con o sin IVA y deja las recetas incompletas.

**Dos casos a propósito**, para ver que el sistema avisa en vez de inventar un número:

- **Ñoquis de espinaca con manteca y salvia: desactualizado.** El precio de la salvia es viejo: de hace 60 días, o del doble del plazo de vencimiento si el grupo tiene uno más largo.
- **Risotto alla milanese: incompleto.** El azafrán no tiene precio: el costo queda vacío, nunca en $ 0.

Además, **Demo Pastas Centro** tiene sus propios precios (costo «Completo y verificado») y **Demo Pastas Norte** usa los del grupo (dice «Con estimaciones»).

## Cómo se carga (Joaco)

1. Que staging esté activo: el plan gratis de Supabase lo pausa después de una semana sin uso.
2. GitHub → Actions → **Publicar en staging** → Run workflow, desde `main`, con **«Cargar materias primas, precios y recetas de prueba»** tildada.
3. El paso termina con una tabla: cada receta, su local, su estado y su costo. Tiene que coincidir con la de abajo.

Es todo o nada: si algo falla, no queda nada a medias. Antes de confirmar, el script controla que haya 28 materias primas, 54 precios y 13 recetas publicadas, y que cada costo tenga el estado esperado; si no, deshace todo. Si ya se cargó, no hace nada. Si en staging ya hay una materia prima, un proveedor o una receta con el mismo nombre, frena y dice cuál, sin tocar nada.

## Recorrido para Soy (10 minutos)

En la dirección de staging, con los usuarios de prueba (las contraseñas las tiene Joaco).

1. **Materias primas** (`compras@ejemplo.test`, Pablo de Compras): buscar «Queso parmesano». Se ve el código que le puso el sistema, el rubro, el producto (horma de 4 kg), el proveedor y el precio de $ 128.000 con IVA.
2. **Historial del precio** (`controller@ejemplo.test`, Camila): en la misma ficha, el precio dice quién lo propuso y quién lo aprobó.
3. **Ficha de receta** (`chef@ejemplo.test`, Carla): abrir «Tagliatelle carbonara». Se ven las líneas, la Masa al huevo como preparación, los pasos, la versión 1 publicada y quién la aprobó.
4. **Costos**, con el local **Demo Pastas Centro** elegido arriba: 7 platos «Completo y verificado», los Ñoquis desactualizados y el Risotto incompleto. Abrir la carbonara para ver de dónde sale cada peso.
5. Cambiar arriba a **Demo Pastas Norte**: los mismos números, pero «Con estimaciones», porque Norte usa el precio del grupo.
6. **En el celular**: el Inicio y la ficha de la carbonara.

## Las cuentas a mano

Precios con IVA. Costo por gramo = precio del envase / contenido.

### Masa al huevo (rinde 1.400 g)

| Línea                    | Cantidad | Envase             | Por g o unidad | Costo          |
| ------------------------ | -------- | ------------------ | -------------- | -------------- |
| Harina 00 italiana       | 1.000 g  | $ 32.000 por 25 kg | $ 1,28         | $ 1.280,00     |
| Semolín de trigo candeal | 200 g    | $ 9.500 por 5 kg   | $ 1,90         | $ 380,00       |
| Huevo de campo           | 10       | $ 7.800 por 30     | $ 260,00       | $ 2.600,00     |
| Sal gruesa               | 10 g     | $ 3.500 por 5 kg   | $ 0,70         | $ 7,00         |
| **Total**                |          |                    |                | **$ 4.267,00** |

Sin IVA: 4.267 / 1,21 = **$ 3.526,45**. Por gramo terminado: 4.267 / 1.400 = $ 3,0479.

### Tagliatelle carbonara (1 porción)

| Línea                  | Cantidad | De dónde sale      | Costo          |
| ---------------------- | -------- | ------------------ | -------------- |
| Masa al huevo          | 180 g    | $ 3,0479 por gramo | $ 548,61       |
| Panceta ahumada        | 60 g     | $ 18.000 por kg    | $ 1.080,00     |
| Huevo de campo         | 1        | $ 7.800 por 30     | $ 260,00       |
| Queso parmesano        | 25 g     | $ 128.000 por 4 kg | $ 800,00       |
| Pimienta blanca molida | 1 g      | $ 12.000 por 500 g | $ 24,00        |
| **Total**              |          |                    | **$ 2.712,61** |

Sin IVA: **$ 2.241,83**.

## Lo que muestra la corrida (ensayo en la base local, 2026-11-19)

| Receta                             | Centro                | Norte            | Total con IVA | Sin IVA     |
| ---------------------------------- | --------------------- | ---------------- | ------------- | ----------- |
| Salsa pomodoro (2 kg)              | Completo y verificado | Con estimaciones | $ 8.508,50    | $ 7.031,82  |
| Ragú de osobuco (2,5 kg)           | Completo y verificado | Con estimaciones | $ 26.527,00   | $ 21.923,14 |
| Masa al huevo (1,4 kg)             | Completo y verificado | Con estimaciones | $ 4.267,00    | $ 3.526,45  |
| Fondo de verduras (3 l)            | Completo y verificado | Con estimaciones | $ 1.751,00    | $ 1.447,11  |
| Tagliatelle al ragú de osobuco     | Completo y verificado | Con estimaciones | $ 3.466,99    | $ 2.865,28  |
| Fettuccine al pomodoro             | Completo y verificado | Con estimaciones | $ 1.750,38    | $ 1.446,59  |
| Tagliatelle carbonara              | Completo y verificado | Con estimaciones | $ 2.712,61    | $ 2.241,83  |
| Fettuccine Alfredo                 | Completo y verificado | Con estimaciones | $ 2.054,61    | $ 1.698,03  |
| Ñoquis de espinaca (4 porciones)   | Desactualizado        | Desactualizado   | $ 5.677,60    | $ 4.692,23  |
| Risotto alla milanese              | Incompleto            | Incompleto       | —             | —           |
| Pollo al romero con tomates cherry | Completo y verificado | Con estimaciones | $ 3.298,30    | $ 2.725,87  |
| Lasaña de berenjenas               | Completo y verificado | Con estimaciones | $ 3.470,14    | $ 2.867,88  |
| Peceto braseado al vino blanco     | Completo y verificado | Con estimaciones | $ 4.633,10    | $ 3.829,01  |

## Cómo está hecho

El script es `supabase/staging/demo-recipes.sql`. No escribe en las tablas directamente: llama a las mismas funciones que usa la app (`catalog.create_ingredient`, `costing.propose_price`, `workflow.decide_approval`, `recipes.create_recipe`, `recipes.save_sheet`, `recipes.set_assignment`) con la sesión de cada persona de prueba. Así pasa por los permisos, los códigos automáticos, las versiones, las aprobaciones y la auditoría, igual que si lo cargaran a mano. En la historia, cada cambio y cada aprobación llevan el motivo «Prueba de la Fase 2 para Soy (corrida N de GitHub Actions)»: así se distingue de lo que una persona hizo de verdad en la app. El origen queda «manual», porque lo fijan las mismas funciones de la app.

**Solo para el Grupo Demo y con datos inventados.** El script simula la sesión de las personas de prueba (con doble verificación declarada) y el registro de Actions muestra la tabla de costos. Las dos cosas valen solo porque todo es ficticio: este patrón no se usa con personas ni precios reales.

Para probarlo en la base local sin dejar nada: `DRY_RUN=1` hace todo y al final lo deshace.
