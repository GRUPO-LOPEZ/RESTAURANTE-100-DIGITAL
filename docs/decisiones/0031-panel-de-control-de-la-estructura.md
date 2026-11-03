# ADR-0031 — Panel de control de la estructura del grupo

- **Fecha:** 2026-11-03
- **Estado:** aceptada por Joaco (plan aprobado).
- **Base:** la respuesta 2 de Soy (ADR-0030): "que Claude construya un panel de control para que se pueda hacer desde un panel de control; así desde allí se van dando de alta. Cuando esté hecho, lo hacemos juntos."

## Contexto

- **Para cargar los datos reales** (marcas, locales y razones sociales) solo existían las funciones de la base: marcas, locales y áreas desde la Fase 1, y razones sociales desde la 2.1 C. No había ninguna pantalla.
- **Sin esos datos** no se puede usar el sistema con datos reales: falta la razón social de cada local, y por eso su costo sin IVA queda incompleto. Tampoco se puede hacer la compuerta 2.4, que pide el Excel real de Nonnos.

## Decisiones de Joaco (2026-11-03)

1. **Se carga con una cuenta de Superadministrador.** No cambia ningún permiso: el panel muestra lo que cada persona ya puede hacer.
2. **Entran:** marcas, locales, razones sociales y **las áreas de cada local**.
3. **Quedan para después:**
   - **archivar y restaurar** (la base ya lo permite con `org.set_deleted`);
   - **el traspaso de un local a otra marca**, porque falta que las recetas propias pasen con el local (ADR-0026).

## Cómo quedó

### Pantallas (`/configuracion`, "Panel de control" en el menú)

- **Inicio del panel:**
  - responde "¿qué puedo administrar?" con una tarjeta por cosa;
  - avisa cuántos locales no tienen razón social;
  - enlaza a Usuarios, Roles y permisos y Configuración del catálogo, que ya existían.
- **Marcas** (`/configuracion/marcas`): la lista, con su código, su estado y cuántos locales tiene cada una; y "Nueva marca".
- **Una marca** (`/configuracion/marcas/[id]`): editarla, sus locales y "Nuevo local". El local nuevo lleva su tipo y, para quien administra el grupo, su razón social en el mismo paso.
- **Un local** (`/configuracion/locales/[id]`): sus datos, su razón social (si no tiene, avisa que su costo sin IVA queda incompleto) y sus áreas, con alta y cambio de nombre.
- **Razones sociales** (`/configuracion/razones-sociales`):
  - nombre, CUIT (se escribe con o sin guiones) y condición frente al IVA;
  - qué locales usa cada una;
  - qué locales todavía no tienen.

### Quién puede qué

Son las reglas de la base, que no cambiaron. La pantalla solo oculta lo que la persona no puede hacer.

| Qué                                                         | Permiso                                                |
| ----------------------------------------------------------- | ------------------------------------------------------ |
| Marca nueva, código y estado de una marca                   | `org.manage` de todo el grupo                          |
| Razones sociales, y la razón social de un local             | `org.manage` de todo el grupo (decisión 8 de ADR-0029) |
| Nombre de una marca, local nuevo, tipo y estado de un local | `org.manage` de la marca                               |
| Datos de un local y sus áreas                               | `org.manage` del local                                 |

Con el seed, esto queda así:

- **el Superadministrador** hace todo;
- **la Directora de Marca** maneja su marca y sus locales, sin razón social;
- **el Gerente** edita los datos y las áreas de su local, pero no lo cierra ni le cambia el tipo.

### Base (migración `20261110120000_org_panel.sql`)

- **`org.create_restaurant` acepta en `p_details`** el tipo (`site_type`) y la razón social (`legal_entity_id`).
  - La razón social pide además `org.manage` de todo el grupo, y que sea del grupo y esté vigente.
  - Elegirla al crear el local era lo que pedía Soy (ADR-0024, respuesta 2 b).
- **Un error de la Fase 1, corregido:** una fecha de apertura vacía rompía el alta de un local, porque se convertía un texto vacío a fecha. Nadie lo había visto porque no había pantallas.
- **`org.restaurants.legal_name` y `tax_id` quedan como datos viejos:** los reemplaza la razón social (`legal_entity_id`). El panel no los muestra ni los edita, y las columnas no se borran.

## Pruebas

- **pgTAP `220_org_panel`:**
  - el alta con tipo y razón social en un paso;
  - la Directora sin razón social, y con razón social se le rechaza sin crear nada;
  - una razón social de otro grupo o dada de baja se rechaza;
  - una fecha vacía no rompe el alta;
  - la Cocinera no crea locales;
  - la auditoría guarda el motivo.
- **Vitest `org-schemas`:** CUIT con o sin guiones, códigos, teléfono y tipo, y motivo obligatorio.
- **Playwright `panel-estructura`**, en celular y computadora, con axe:
  - el Superadministrador crea una razón social, una marca, un local con su razón social y un área;
  - la Directora crea un local sin ver la razón social;
  - el Gerente edita su local sin poder cerrarlo;
  - la Cocinera no ve el panel.

## Revisiones

- **`security-auditor`: apto**, sin graves ni medios. De sus menores quedaron resueltos:
  - un rechazo de permiso que no sea el propio de la base ("No tenés permiso para …") ya no se muestra tal cual, ni un error crudo de Postgres con nombres internos;
  - una fecha que no existe se rechaza en el formulario.
- **`db-reviewer`:** sin graves. Sus dos medios quedaron resueltos: un tipo o una razón social mal escritos, enviados directo a la base, reciben un mensaje en español; y la prueba `220` cubre el tipo por defecto, esos datos y el Gerente.
- **`ui-reviewer`:** su grave quedó resuelto. Si alguien que administra un local no pudiera ver las razones sociales, la pantalla le diría "tiene su razón social cargada" y no un aviso falso de que no tiene. Hoy no pasa, porque todos los roles con `org.manage` ven precios, pero la pantalla no depende de eso. Además: la fecha de apertura se ve en formato argentino, el estado vacío de las áreas es como el resto, el enlace del aviso tiene altura táctil y el CUIT se puede escribir con guiones desde el celular.
- **Aceptado y anotado:**
  - **Las listas no están paginadas:** marcas, locales, áreas y razones sociales del grupo son decenas, no miles. Si el grupo crece mucho, se paginan.
  - **El título de la marca y del local** está en la tarjeta, no en el encabezado de la página.
  - **`org.update_restaurant`** todavía convierte una fecha con solo espacios con el criterio viejo. La pantalla nunca la manda así (Zod recorta).
  - **`legal_name` y `tax_id` viejos** se siguen aceptando si alguien llama a la función directo. Se sacan en una migración futura.
  - **Respondido por Joaco (2026-11-03):** el Gerente **sí** puede cambiar el código de su local, y los locales cerrados **siguen apareciendo** en «Personas por local» (`/usuarios`). Queda como está.

## Riesgos y pendientes

- **Los datos reales se cargan en producción,** que todavía no existe: Joaco la crea con el plan Pro (ADR-0030). En desarrollo, solo datos ficticios.
- **Cargar mal una marca o un local:** mientras no esté "archivar", se corrige editando el nombre o el código.
- **Hoy hay un solo grupo:** las altas usan el grupo de la persona. Con más grupos, el panel va a tener que elegir el grupo.
