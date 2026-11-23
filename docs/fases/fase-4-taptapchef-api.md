> Documentación pública de la API de TapTapChef, tal como la pasó Soy (2026-11-23). TapTapChef es el sistema de ventas y facturación de los restaurantes. Acá **no** va ninguna clave: la clave privada (`x-api-secret`) la recibe Joaco por un canal privado y vive solo en los secretos de Supabase de producción. Lo que esto cambia en el diseño está en `docs/prompts/2026-11-23-precios-y-carta-modulo-3.md`, sección «TapTapChef: qué dice la API y qué cambia».

# API Pública de TapTapChef

La API permite obtener en formato JSON la información de los restaurantes autorizados, tanto sean **transacciones** (ventas, cobros, tickets, etc) o **maestros** (productos, clientes, etc).

## Endpoint

```text
POST https://function-gethisto-679004960826.southamerica-east1.run.app
```

Todas las consultas se realizan enviando un JSON en el body y una credencial en el header.

## Autenticación

Cada integrador recibe una clave privada que debe enviarse mediante:

```text
x-api-secret: SU_API_SECRET
```

La clave identifica al integrador y determina automáticamente a qué restaurantes puede acceder.

La API valida en cada solicitud:

- que la clave sea válida;
- que el restaurante solicitado esté autorizado para esa clave;
- que se respete el límite de consultas asignado.

La clave debe mantenerse del lado servidor y no debe exponerse en aplicaciones web ni código público.

## Consulta

Ejemplo:

```http
POST https://function-gethisto-679004960826.southamerica-east1.run.app
Content-Type: application/json
x-api-secret: SU_API_SECRET
```

```json
{
  "fecha": "2026-08-10",
  "tienda": "codigo_restaurante",
  "tabla": "tickets"
}
```

Las tablas de historial también pueden consultarse por `turnoid` en lugar de `fecha`.

### Parámetros

| Campo     | Descripción                                      |
| --------- | ------------------------------------------------ |
| `tienda`  | Identificador único del restaurante o sucursal.  |
| `tabla`   | Información que se desea consultar.              |
| `fecha`   | Fecha de consolidación, en formato `YYYY-MM-DD`. |
| `turnoid` | Identificador del turno.                         |

Los campos `tienda` y `tabla` son obligatorios. En las tablas de historial debe enviarse `fecha` o `turnoid`: uno u otro, nunca ambos. El resto de las tablas no acepta estos parámetros.

## Identificación del restaurante

Cada restaurante o sucursal posee un identificador único, denominado **ID de tienda**.

Ejemplo:

```text
codigo_restaurante
```

Este identificador es provisto por TapTapChef y debe enviarse en el parámetro `tienda`.

Una misma credencial puede tener acceso a uno o varios IDs de tienda. La API rechazará automáticamente cualquier intento de consultar un restaurante no autorizado.

## Tablas disponibles

Actualmente pueden consultarse:

| Tabla            | Params             | Información                                                 |
| ---------------- | ------------------ | ----------------------------------------------------------- |
| `turnos`         | `fecha`            | Historial de turnos (incluye informe).                      |
| `tickets`        | `fecha`, `turnoid` | Historial de ventas (sean o no fiscales).                   |
| `ventas`         | `fecha`, `turnoid` | Historial detallado de ventas (sean o no fiscales).         |
| `fiscales`       | `fecha`, `turnoid` | Historial de facturas oficiales (incluye notas de credito). |
| `cobros`         | `fecha`, `turnoid` | Historial de cobranzas (incluye ctacte).                    |
| `cashflow`       | `fecha`, `turnoid` | Historial de movimientos de dinero.                         |
| `clientes`       |                    | Maestro de clientes.                                        |
| `clientessaldos` |                    | Saldos de ctacte de clientes.                               |
| `clientesctacte` | `fecha`, `turnoid` | Historial de ctacte de clientes.                            |
| `productosweb`   |                    | Maestro de productos de la carta digital.                   |

La estructura del JSON retornado depende de la tabla consultada.

## Filtro por fecha en información transaccional

Este filtro aplica cuando se consulta un historial por `fecha` (no por `turnoid`).

En las tablas transaccionales, el parámetro `fecha` **no representa necesariamente la fecha en que ocurrió la operación**, sino la fecha en que esa información fue consolidada en la nube de TapTapChef.

### Ciclo de vida de una transacción

Durante la operación normal, el restaurante registra y almacena sus transacciones localmente.

Al producirse el **cierre de turno**, esa información se sincroniza con la nube y pasa a formar parte del historial consolidado disponible mediante la API.

Por lo tanto, pueden existir diferencias entre:

- la fecha y hora en que ocurrió una transacción;
- la fecha y hora en que esa transacción fue subida a la nube.

Además, si el restaurante atraviesa problemas de conectividad, la sincronización puede demorarse aún más.

Por ejemplo:

1. Un ticket se genera en el restaurante el **9 de agosto a las 22:15**.
2. El turno se cierra el **10 de agosto a la 01:00**.
3. En ese momento el restaurante no tiene conexión a Internet.
4. La conexión se restablece el **10 de agosto a las 09:30** y el ticket finalmente se sincroniza.

Ese ticket aparecerá al consultar:

```json
{
  "fecha": "2026-08-10",
  "tienda": "codigo_restaurante",
  "tabla": "tickets"
}
```

aunque la operación haya ocurrido originalmente el día 9.

En el resultado pueden encontrarse ambas referencias temporales:

```json
{
  "tickets": [
    {
      "groupid": "codigo_restaurante",
      "uploaddate": "2026-08-10T09:30:00-03:00",
      "ticketdate": "2026-08-09T22:15:00-03:00",
      "mesaname": "Mesa 4",
      "tiponame": "Salon",
      "total": 24500,
      "comensales": 3,
      "ticketid": "123456",
      "factura": ""
    }
  ]
}
```

En este ejemplo:

- `ticketdate` indica cuándo ocurrió la operación;
- `uploaddate` indica cuándo fue incorporada al historial consolidado.

### Consumo incremental

Esta lógica permite consumir la información de manera incremental.

Un sistema externo puede consultar periódicamente cada fecha de incorporación y obtener las nuevas transacciones que fueron consolidadas durante ese día, incluso si corresponden a operaciones realizadas anteriormente.

Esto evita perder operaciones que hayan sido sincronizadas con demora debido al cierre de turno o a problemas de conectividad.

Las fechas y horas se expresan en formato ISO 8601 utilizando la zona horaria de Argentina (`-03:00`).

## Filtro por turno

Como alternativa a `fecha`, las tablas de historial aceptan el parámetro `turnoid`. Ambos son mutuamente excluyentes: debe enviarse uno u otro, nunca los dos.

Consultar por `turnoid` devuelve las transacciones de ese turno, independientemente de la fecha en que se consolidaron en la nube.

El identificador se obtiene de la tabla `turnos`.

```json
{
  "turnoid": 123456,
  "tienda": "codigo_restaurante",
  "tabla": "tickets"
}
```

## Rate limit

Cada credencial posee un intervalo mínimo entre consultas.

Según la integración, este intervalo puede ser, por ejemplo:

```text
1 consulta cada 10 segundos
```

o:

```text
1 consulta cada 60 segundos
```

El límite se aplica **por credencial**, independientemente del restaurante o tabla consultados.

Por ejemplo, si una credencial posee un límite de 10 segundos, no puede consultar `ventas` y luego inmediatamente `tickets`: deberá respetar el intervalo entre ambas solicitudes.

TapTapChef informará al integrador el rate limit correspondiente junto con sus credenciales.

Si se supera el límite, la API devuelve:

```json
{
  "status": "error",
  "msg": "Ratelimit superado"
}
```

Ese rechazo reinicia el intervalo de espera: el tiempo se cuenta desde la última solicitud, haya sido aceptada o no.

## Respuesta

Una consulta correcta devuelve un objeto JSON correspondiente a la tabla solicitada.

Si no existen registros para la combinación solicitada, la colección correspondiente se devuelve vacía.

## Errores

Ante una solicitud inválida, la API responde con HTTP `400` y un JSON como:

```json
{
  "status": "error",
  "msg": "No autorizado"
}
```

Entre los posibles errores se encuentran:

- parámetros faltantes;
- `fecha` y `turnoid` enviados simultáneamente;
- credencial faltante o inválida;
- restaurante no autorizado;
- tabla inexistente;
- rate limit superado.

## Ejemplo con cURL

```bash
curl -X POST "https://function-gethisto-679004960826.southamerica-east1.run.app" \
  -H "Content-Type: application/json" \
  -H "x-api-secret: SU_API_SECRET" \
  -d '{
    "fecha": "2026-08-10",
    "tienda": "codigo_restaurante",
    "tabla": "tickets"
  }'
```

Por turno:

```bash
curl -X POST "https://function-gethisto-679004960826.southamerica-east1.run.app" \
  -H "Content-Type: application/json" \
  -H "x-api-secret: SU_API_SECRET" \
  -d '{
    "turnoid": 123456,
    "tienda": "codigo_restaurante",
    "tabla": "tickets"
  }'
```
