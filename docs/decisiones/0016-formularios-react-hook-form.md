# ADR-0016 — Formularios con React Hook Form y un esquema compartido

- **Fecha:** 2026-10-22
- **Estado:** aceptada. Joaco eligió sumar React Hook Form (respuesta 6 de ADR-0015) y aprobó el plan.

## Contexto

`design.md` pide "formularios con React Hook Form + Zod, con el mismo esquema en el navegador y en el servidor". Hasta ahora los formularios usaban `useActionState` y validaban con Zod solo en el servidor:

- no había errores por campo;
- no se validaba nada antes de enviar;
- cada acción tenía su propio esquema, con mensajes distintos para lo mismo.

## Decisión

- **Esquemas compartidos** en `lib/forms/schemas.ts`, uno por formulario: motivo, dar un rol, invitar, decidir, ingresar, código, recuperar, contraseña nueva, mis datos, cambiar la contraseña, borrador y corrección de ensayo.
  - Los usa el navegador antes de enviar.
  - Los usa la acción de servidor, que vuelve a validar porque nunca se confía en la pantalla.
  - Los ids ocultos los valida cada acción.
- **`useServerForm` y `ServerForm`** en `components/ui/form.tsx`:
  - React Hook Form valida con el esquema;
  - si todo está bien, llama a la acción de servidor con **todos** los campos del formulario, también los ocultos y el botón que se apretó;
  - la respuesta de la base sigue pasando por `useActionState`.
- **Campos `FormInput`, `FormSelect` y `FormTextarea`:**
  - se registran solos dentro de un `ServerForm`;
  - muestran el error debajo, con `aria-invalid` y `aria-describedby`;
  - funcionan igual dentro de páginas de servidor. Por eso `ActionForm` sigue recibiendo los campos como hijos y solo suma `schema`.
- **Errores por campo desde el servidor:** las acciones devuelven `fieldErrors` en `ActionState` y el formulario los muestra igual. Por ejemplo, "para rechazar, escribí el motivo".
- **El adaptador de Zod es propio** (`lib/forms/resolver.ts`, unas 15 líneas), en lugar de `@hookform/resolvers`.
  - La versión actual de `@hookform/resolvers` (6.0) declara dependencias opcionales (`effect@4`) que chocan con las del proyecto: `npm install` falla.
  - Forzarla con `--legacy-peer-deps` deja un árbol de dependencias roto.
  - El adaptador propio tiene pruebas en `tests/unit/form-schemas.test.ts`.
- **Dependencia nueva:** solo `react-hook-form`, que ya está en el stack aprobado.
- **El selector de local queda como está:** es un único `select` sin nada que validar.

## Consecuencias

- Los errores aparecen campo por campo, antes de enviar, en español. Se mueve el foco al primer campo con error.
- Después de una respuesta correcta, el formulario vuelve a sus valores iniciales: los que trae la página ya actualizada.
- Un formulario nuevo necesita su esquema en `lib/forms/schemas.ts`, y la acción tiene que validar con ese mismo esquema.
