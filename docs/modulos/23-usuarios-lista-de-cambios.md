# Usuarios en una pantalla (lista de cambios para Soy)

Segunda entrega de las correcciones del Módulo 1. Con esta se cierra tu **Tanda 1**. Detalle técnico en ADR-0062. Capturas en `docs/capturas/usuarios/`.

## La ficha de una persona, entera a la vista

- **Arriba:** nombre, correo, puesto y estado. A la derecha, **Suspender** y **Desactivar** (o levantar la suspensión, pedir la reactivación, liberar el bloqueo), cada uno con su motivo.
- **4 indicadores:**
  - último ingreso y si tiene doble verificación;
  - roles y dónde los usa;
  - cambios en 30 días, con «Ver historial»;
  - accesos rechazados en 7 días.
- **Datos y cuenta:** nombre, apellido, puesto y área se editan ahí mismo. Antes el puesto y el área no se podían cargar. El Superadministrador se los puede cargar a cualquiera, también a Dirección y al Controller, menos a sí mismo y a otro Superadministrador.
- **Roles y dónde los usa:** «Quitar» en cada uno y **«Dar otro rol»** en la misma tarjeta.
- **Lo último que hizo:** los 5 últimos cambios y «Ver los últimos 20».
- **Todo se guarda junto** con la barra de abajo: contador, motivo obligatorio, Descartar y Guardar cambios.
- Un rol que aprueba cosas sigue quedando **pendiente** hasta que otra persona lo apruebe.

## Cerrar todas las sesiones (nuevo)

Si alguien pierde el celular, quien lo administra puede **cerrarle todas las sesiones** con un motivo, sin suspenderlo: la persona vuelve a entrar con su contraseña. Queda registrado y a la persona **le llega un aviso** con quién fue.

## Invitar en un modal corto (tu decisión 6)

Nombre, apellido, correo, rol, dónde trabaja y motivo. El resto se completa en su ficha. Se abre desde el tablero y desde la lista.

## Tablero y lista, sin scroll

- El tablero muestra todo junto: indicadores, accesos por día, personas por local y por rol, y los últimos cambios críticos.
- La lista ocupa la pantalla y se desplaza adentro, con el estado siempre a la vista.

## El Historial dice qué cambió

Muchos cambios decían «Dato del sistema» (recetas, compras, precios, razones sociales). Ahora dicen «Receta», «Orden de compra», «Factura», «Precio»…

## Qué no cambió

- Los permisos y las aprobaciones de los roles son los mismos.
- Nadie se da roles a sí mismo, ni le cambia el nombre a quien tiene más permisos. Si otro te cambia el nombre, te llega un aviso.
- Cada uno cambia su propio nombre, contraseña y sesiones en Mi cuenta.
- En el celular, la ficha es de consulta, salvo lo urgente: suspender, desactivar y cerrar sesiones.
