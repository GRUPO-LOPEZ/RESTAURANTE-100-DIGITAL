# Correcciones del Módulo 1 (pedido de Soy, desde el 2026-11-22)

Soy está recorriendo el sistema en staging y junta las correcciones en tandas. **Se mandan todas juntas** y se aplican todas. Cada tanda trae su boceto validado y su prompt. Hasta que lleguen todas, no se arranca un módulo nuevo.

| Tanda | Qué toca                                                                                      | Boceto                                | Estado                        |
| ----- | --------------------------------------------------------------------------------------------- | ------------------------------------- | ----------------------------- |
| 1     | Panel de control (estructura del grupo, marcas, locales, razones sociales, áreas) y Usuarios | `2026-11-22-boceto-panel-y-usuarios/` | Validada por Soy (2026-11-22) |

---

## Tanda 1: Panel de control y Usuarios, cada cosa en una pantalla

### Lo que pidió Soy

- El Panel de control, en todas sus partes, tiene que cargarse como las fichas de receta y de materia prima: **todos los datos en una sola pantalla**, no en pantallas sucesivas, con los formatos de carga ya validados en otros menús. Más fácil e intuitivo.
- **Marca:** el código se arma solo, con un número correlativo y el nombre. Ejemplo: Ragú → 1-RAGU, la segunda marca → 2-PADELLA.
- **Local nuevo:** el nombre se arma solo con la marca y la zona (Ragú Leloir, Ragú Belgrano). El código, con la marca y un número correlativo.
- **Dirección, localidad, teléfono y fecha de apertura** dejan de ser opcionales. Con las direcciones se arma **un mapa** en el Panel con todos los restaurantes.
- **Razón social:** una ficha completa con todos los datos que hoy tiene ARCA.
- **Las áreas**, en la misma pantalla del local.
- **Usuarios:** simplificar la carga, con poco o nada de scroll.

### Decisiones de Soy sobre las propuestas (2026-11-22)

1. **Código de marca con dos cifras:** `01-RAGU`, `02-PADELLA`, `03-NONNOS`. El número es correlativo y lo pone el sistema. Así la marca 10 no se ordena antes que la 2.
2. **Código de local corto y fijo, `RAGU-001`, con la zona solo en el nombre** («Ragú Leloir»). Soy había pedido «RAGU 001 LELOIR» como código y aceptó la propuesta: el código no cambia nunca (lo usan el historial y las órdenes de compra) y la zona sí puede cambiar si el local se muda. Además, el número de cada OC empieza con el código del local.
3. **Mapa con herramientas gratis:** OpenStreetMap para el mapa y Georef (el servicio de normalización de direcciones del gobierno argentino) para encontrar la dirección. Sin claves ni costo. Google Maps queda descartado por ahora. Es una tecnología nueva: justificala por escrito en el ADR, como pide CLAUDE.md.
4. **Razón social cargada a mano**, con el PDF de la constancia de inscripción de ARCA adjunto. Autocompletar desde ARCA con el CUIT queda para cuando esté el certificado digital (el mismo que va a pedir la factura electrónica).
5. **Obligatorios sin trabar lo existente:** los locales que ya existen y no tienen esos datos no se traban; muestran «Falta teléfono» (o el dato que sea) hasta completarlos. **Un local no puede pasar a «Abierto» si le falta un obligatorio** (lo valida la base).
6. **Invitar a una persona en un modal corto:** nombre, mail, rol y dónde trabaja. El resto se completa en su ficha.

---

### Prompt (copiar en Claude Code)

```text
Leé docs/estado.md, CLAUDE.md, .claude/rules/design.md (pantallas de carga sin scroll, ADR-0046),
docs/decisiones/0030, 0031, 0036, 0039 y 0051, y el boceto
docs/prompts/2026-11-22-boceto-panel-y-usuarios/ (README y los 5 .dc.html).
Tarea: Panel de control y Usuarios, cada cosa en una sola pantalla, como las fichas de receta y de
materia prima. Rama: feat/panel-y-usuarios-en-una-pantalla. Entrá en modo plan y mostrame el plan
antes de tocar nada. Si el plan queda grande, proponé partirlo en 2 PRs (base y pantallas).

PANTALLAS (ver el boceto; 1440 × 900, 1600 × 900, 1715 × 843 y 1920 × 1080 sin scroll de página)
1. /configuracion: «¿Cómo está armado el grupo?». Reemplaza el menú de tarjetas de hoy por una
   sola pantalla tipo A:
   - 4 indicadores (Metric): Marcas, Locales (cuántos restaurantes y cocinas centrales),
     Razones sociales (constancias al día) y Datos que faltan (locales con obligatorios sin
     cargar, con «Completar»). Sin datos: «Sin …», nunca un estado positivo.
   - Izquierda: marcas con sus locales en una lista agrupada (código, nombre, dirección, tipo y
     estado con palabra). Clic en un local abre su ficha. «Nueva marca» se agrega en la misma
     lista, mostrando el código que va a tener (04-…).
   - Derecha: el mapa con todos los locales (OpenStreetMap) y las razones sociales (nombre, CUIT,
     condición de IVA, cuántos locales); cada una enlaza a su ficha.
   - Abajo, una línea con los otros accesos que hoy tiene el Panel (Configuración de precios,
     Usuarios, Roles y permisos, Configuración del catálogo), según los permisos de cada persona.
   - Botones arriba: «+ Nueva marca» y «+ Nuevo local».
2. Alta de local: modal corto. Marca (botones, no desplegable), Zona o ubicación, Tipo
   (Restaurante · Cocina central · Producción) y Motivo. Muestra «Así va a quedar»: el nombre
   (marca + zona) y el código (RAGU-002). «Crear y completar la ficha» crea el local en
   «En apertura» y abre su ficha.
3. Ficha de local (/configuracion/locales/[id]), tipo B sin scroll:
   - encabezado en una línea: «← Panel de control», nombre, código · marca · tipo, estado con
     palabra; a la derecha «Cerrar el local»;
   - 4 indicadores: Personas que trabajan acá (con «Ver quiénes»), Recetas asignadas, Razón
     social (con «Abrir ficha») y Datos obligatorios (N de 8);
   - tarjetas: «El local» (marca fija, zona, nombre automático, código fijo, tipo y estado como
     botones, fecha de apertura); «Ubicación y contacto» (dirección con búsqueda en Georef y la
     marca «Encontrada», localidad, provincia y CP, teléfono, mini mapa); «Razón social» (a nombre
     de quién factura, CUIT, IVA, desde qué fecha, «Cambiar»); «Áreas» (chips que se renombran
     con un clic, se agregan en la misma tarjeta y se quitan sin borrar: quedan inactivas);
   - barra fija abajo: contador, motivo obligatorio, Descartar y Guardar cambios. Todo se guarda
     en una sola transacción.
4. Ficha de marca: la misma idea, más chica (nombre, código, estado y sus locales). Si entra en
   la pantalla 1 como edición en el lugar, mejor: proponelo en el plan.
5. Ficha de razón social (/configuracion/razones-sociales/[id]), tipo B sin scroll, con los datos
   de la constancia de inscripción de ARCA:
   - Identidad: razón social, CUIT (con dígito verificador), forma jurídica (S.R.L. · S.A. ·
     S.A.S. · Persona), inicio de actividades, nombre de fantasía;
   - Domicilio fiscal: calle y número, localidad y CP, provincia, domicilio fiscal electrónico;
   - Impuestos: IVA (Resp. inscripto · Monotributo · Exento, como hoy), Ganancias, Ingresos
     Brutos (Convenio Multilateral · Local · Exento), número de IIBB, jurisdicción sede,
     empleadora, agente de retención, agente de percepción (toggles de un clic);
   - Actividades de ARCA: código y descripción, una principal y las secundarias;
   - Locales que la usan, con desde qué fecha;
   - la constancia en PDF (Storage, como las fotos de facturas) con su fecha, y el indicador
     «Al día» o «Vencida» (proponé la regla en el plan; por ejemplo, más de 12 meses = Atención).
   El agente de retención se conecta con la columna que quedó preparada en Pagos (P8): solo se
   marca, el cálculo sigue fuera de esta tarea.
6. Usuarios:
   - Ficha de persona (/usuarios/[id]) sin scroll: encabezado con nombre, mail, puesto, marca y
     estado; a la derecha Suspender y Desactivar. 4 indicadores (último ingreso y doble
     verificación, roles, cambios en 30 días con «Ver historial», accesos rechazados en 7 días).
     Tarjetas: Datos y Cuenta (estado como botones, doble verificación, sesiones abiertas con
     «Cerrar todas»); Roles y dónde los usa, con «Dar otro rol» en la misma tarjeta; Lo último
     que hizo (5 y «Ver los N», en un panel lateral). Barra fija con motivo.
   - Invitar: modal corto (nombre, mail, rol, dónde trabaja). Reemplaza la pantalla /usuarios/invitar.
   - Revisá también el tablero y la lista de usuarios con la regla de sin scroll de página.

BASE (antes de cualquier pantalla; migraciones nuevas, RLS, auditoría y pgTAP)
- Marca: número correlativo por grupo, que asigna la base (sin saltos ni repetidos, como
  catalog.code_series), y código «NN-NOMBRE» en mayúsculas, sin tildes ni espacios. Proponé en el
  plan qué parte del nombre va (por ejemplo, la primera palabra: Ragú Bodegón → RAGU) y si se
  puede editar antes de guardar.
- Local: número correlativo por marca y código «MARCA-NNN», fijo. Columna nueva para la zona; el
  nombre se arma con marca + zona (decidí en el plan si se guarda o se calcula, y qué pasa si la
  marca cambia de nombre).
- Los códigos que ya existen NO se cambian solos: las OC ya emitidas, los prefijos de importación
  de recetas y los códigos de recetas y materias primas siguen iguales. En el plan, decime dónde se
  usan hoy el código de marca y el de local, y qué proponés para los que ya existen (en producción
  todavía no hay datos reales; en staging sí hay OC con el código PCE).
- Dirección, localidad, teléfono y fecha de apertura obligatorios para locales nuevos y para pasar
  a «Abierto»; los existentes muestran lo que falta. Latitud y longitud del local (de Georef),
  provincia y código postal.
- Razón social: las columnas de ARCA de arriba, actividades (tabla aparte) y la constancia
  (adjunto con fecha).
- Áreas: alta, cambio de nombre y baja lógica desde la ficha, en el mismo guardado del local.
- Todo con motivo y auditoría, como hoy. Los permisos no cambian (org.manage y los de usuarios).

TECNOLOGÍA NUEVA (justificar en el ADR, aprobación de Joaco)
- Mapa: Leaflet (o la opción más liviana que propongas) con teselas de OpenStreetMap, respetando
  su política de uso y la atribución.
- Georef: https://apis.datos.gob.ar/georef/ desde una función de servidor (sin claves). Si no
  encuentra la dirección, se guarda igual y queda «Sin ubicar en el mapa», sin trabar.
- Nada de Google Maps.

PRUEBAS
- pgTAP: correlativos de marca y de local sin saltos ni repetidos (también con dos altas a la vez),
  obligatorios para pasar a «Abierto», CUIT válido, áreas con baja lógica, auditoría con motivo,
  RLS por rol (quien no tiene org.manage no ve ni cambia nada de esto).
- Vitest: armado del nombre y de los códigos, regla de la constancia.
- Playwright con axe: las pantallas sin scroll de página en los 4 tamaños, con un rol que edita y
  uno que solo lee; alta de local desde el modal hasta la ficha; agregar y quitar un área;
  invitar a una persona desde el modal; dar un rol desde la ficha; celular de consulta con 44 px.
- Las pruebas que se rompan por la nueva disposición se ajustan para controlar lo mismo. No se
  borran ni se aflojan. Corré todo (npm run test).

ENTREGA
db-reviewer, security-auditor y ui-reviewer. Capturas reales en 1440, 1600, 1715 × 843, 1920 y
celular de cada pantalla, como PNG en docs/capturas/panel-y-usuarios/, commiteadas en el PR. ADR
nuevo. Lista de cambios para Soy en docs/modulos/. docs/estado.md. Commit: «feat(panel): estructura
del grupo, local, razón social y persona en una pantalla».
```
