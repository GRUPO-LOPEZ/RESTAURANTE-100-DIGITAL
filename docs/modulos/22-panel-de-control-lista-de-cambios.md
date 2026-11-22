# Panel de control en una pantalla (lista de cambios para Soy)

Primera entrega de las correcciones del Módulo 1 (tu Tanda 1). El Panel, la ficha de cada local y la de cada razón social ahora se cargan como las fichas de receta y de materia prima: todo en una pantalla, sin pantallas sucesivas. Detalle técnico en ADR-0061. Capturas en `docs/capturas/panel-y-usuarios/`. Usuarios llega en la entrega siguiente.

## El Panel: «¿Cómo está armado el grupo?»

- **4 indicadores arriba:**
  - **Marcas:** cuántas, y si están todas activas.
  - **Locales:** cuántos restaurantes y cocinas, y cuántos están en apertura.
  - **Razones sociales:** cuántas, y si sus constancias están al día.
  - **Datos que faltan:** los locales a los que les falta algo obligatorio. «Completar» muestra qué le falta a cada uno.
- **A la izquierda, las marcas con sus locales:** código, nombre, dirección, tipo y estado con palabra. Clic en un local abre su ficha.
  - **«Editar»** en cada marca abre su ficha al costado: nombre, nombre corto, estado y sus locales.
  - **«Nueva marca»** se agrega al final de la misma lista y muestra el código que va a tener (04-…).
- **A la derecha, el mapa con todos los locales** (OpenStreetMap, gratis) y la lista de **razones sociales**. «+ Nueva razón social» abre un modal corto y lleva a su ficha.
- **Abajo, los otros accesos:** Configuración de precios, Usuarios, Roles y permisos y Configuración del catálogo, según lo que pueda hacer cada persona.

## Códigos y nombres que se arman solos (tus decisiones 1 y 2)

- **Marca:** número de dos cifras y nombre corto: `01-RAGU`, `02-PADELLA`. Así la marca 10 no se ordena antes que la 2.
  - Cada marca tiene un **nombre corto** (Ragú, Padella, Nonnos), que arma el código y el nombre de sus locales.
  - Dos marcas no pueden usar la misma palabra.
- **Local:** la palabra de la marca y un número de tres cifras: `RAGU-001`. **No cambia nunca**: lo usan las órdenes de compra y el historial.
- **El nombre del local** es la marca más la zona: «Ragú Leloir». Si el local se muda, cambia la zona y el nombre; el código, no.
- **Lo que ya existe no cambió solo:** las marcas y los locales que ya tenían código lo conservan (por ejemplo, PCE en la prueba). A los locales que no tenían, se les puso el automático.

## Alta de local en un modal corto

- **Qué se pide:** marca (botones), zona, tipo (Restaurante · Cocina central · Producción) y motivo.
- **«Así va a quedar»** muestra el nombre y el código antes de crear.
- **El local nace «En apertura»** y se abre su ficha para completar el resto.

## Ficha del local

- **Arriba:**
  - el nombre, el código, la marca, el tipo y el estado;
  - a la derecha, **«Cerrar el local»** (o «Reabrir»), con motivo.
- **4 indicadores:**
  - personas que trabajan ahí («Ver quiénes»);
  - recetas asignadas («Ver cuáles»);
  - razón social («Abrir ficha»);
  - datos obligatorios (N de 8).
- **El local:** zona, nombre automático, código fijo, tipo y estado como botones (En apertura · Abierto) y fecha de apertura.
- **Ubicación y contacto:**
  - la dirección, con **«Buscar»**, que la encuentra en el servicio de direcciones del gobierno (Georef);
  - localidad, provincia, código postal y teléfono;
  - un mini mapa.
  - Si no la encuentra, se guarda igual y dice «Sin ubicar en el mapa».
- **Razón social:** a nombre de quién factura, su CUIT, su IVA y **desde qué fecha**. Las facturas viejas siguen con la anterior.
- **Áreas:**
  - se agregan en la misma tarjeta;
  - se renombran con un clic;
  - se quitan sin borrar: quedan inactivas, con su historia, y se pueden volver a usar.
- **Todo se guarda junto** con la barra de abajo: contador de cambios, motivo obligatorio, Descartar y Guardar cambios.

## Datos obligatorios (tu decisión 5)

- **Para pasar a «Abierto», un local necesita 7 datos:**
  - marca, zona, tipo y fecha de apertura;
  - dirección, localidad y teléfono.
- Sumé la **zona**, que arma el nombre. La **razón social** no es obligatoria para abrir: sin ella el costo sin IVA queda incompleto, nada más.
- **Los locales que ya estaban abiertos no se traban:** muestran «Falta teléfono» (o lo que sea) hasta completarlo.

## Ficha de la razón social (tu decisión 4)

- **Los datos de la constancia de ARCA, cargados a mano:**
  - **Identidad:** razón social, CUIT (controla que sea válido), forma jurídica, inicio de actividades y nombre de fantasía.
  - **Domicilio fiscal:** calle y número, localidad, código postal, provincia y domicilio fiscal electrónico.
  - **Impuestos:**
    - IVA, Ganancias e Ingresos Brutos como botones, con el número y la jurisdicción sede;
    - empleadora, agente de retención y agente de percepción, con un clic;
    - la retención todavía no se calcula en los pagos: solo queda marcada.
  - **Actividades en ARCA:** una principal y las secundarias.
  - **Los locales que la usan**, con desde qué fecha.
- **«Subir constancia de ARCA»:** el PDF y su fecha de emisión.
  - Está **«Al día»** hasta 12 meses después de emitida; después dice **«Vencida»**, para que se actualice una vez por año.
  - Las constancias anteriores quedan guardadas.
- **«Compras del mes a su nombre»:** solo la ve quien ve las facturas.

## Quién puede hacer qué (no cambió)

- **El Superadministrador:** todo, incluidas las marcas y las razones sociales.
- **El Director de Marca:**
  - crea locales de su marca;
  - edita su marca y sus locales (también el tipo y el estado);
  - no elige la razón social.
- **El Gerente:**
  - edita los datos y las áreas de su local;
  - no lo cierra, no cambia su tipo ni su razón social.
- **Dirección General:** ve todo, sin editar.
- **La Cocinera:** no ve el Panel.

## Lo que me aparté del boceto

- **El estado del local:** la tarjeta tiene En apertura · Abierto, y «Cerrar el local» queda solo arriba. Así no hay dos controles para lo mismo.
- **La jurisdicción sede:** ofrece las 24 provincias, no solo CABA y Buenos Aires.
- **El código postal:** se escribe a mano, porque el servicio de direcciones no lo devuelve.
- **El mapa:** dice «© colaboradores de OpenStreetMap», como pide su política de uso.
