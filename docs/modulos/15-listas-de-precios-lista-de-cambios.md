# Listas de precios y artículos sin mapear (lista de cambios para Soy)

Segunda entrega del módulo de compras y facturas (Fase 3). Detalle técnico en ADR-0052.

## Qué cambia para cada persona

- **Compras:**
  - tiene la pantalla **Listas de precios**, en la barra lateral, en «Gestión y análisis»;
  - carga la lista que mandó un proveedor: la fecha en que llegó, desde cuándo vale, el archivo (opcional) y un renglón por artículo, como viene en la lista;
  - en cada renglón pone el precio de lista, hasta dos bonificaciones en % y una bonificación en pesos por unidad, que se resta después (lo que respondiste en P6), y el IVA, que también puede ser de 2,5 % o 5 % (P5). El neto se ve antes de guardar;
  - **acepta** la lista con un motivo. La anterior queda como «Reemplazada» y no se pierde;
  - el sistema le avisa cuando una lista **vence**: 7, 15 o 31 días después de su vigencia, según cada cuánto manda la lista ese proveedor.
- **Chefs (del grupo, de una marca o de un local):**
  - lo que el sistema no reconoce en una lista va a **Artículos sin mapear**, y le llega un aviso;
  - lo resuelve **una sola vez**: dice a qué materia prima corresponde y cómo viene (por ejemplo, «1 bolsa = 50 kg»), que es el mismo que otro producto que el proveedor ya tenía (lo renombró), o lo descarta;
  - la próxima vez, ese artículo se reconoce solo.
- **Controller, Dirección, director de marca, gerente y auditor:** ven las listas, los precios y cuánto subió cada artículo contra la lista anterior. No las cargan.
- **Cocinero:** no ve listas ni precios. Eso lo decide la base de datos, no la pantalla.
- **Rubros:** Limpieza y Descartables quedan como **«No va a recetas»**. Sus materias primas no aparecen al armar una receta. Compras o Dirección lo cambian con un clic en la tarjeta del rubro. Las recetas que ya las usaban no se tocan.

## Qué controla el sistema

- **Una sola lista vigente por proveedor.** Una lista más vieja que la vigente no se acepta.
- **Un neto en cero o negativo** (bonificaciones de más) no se carga.
- **Los precios de lista no cambian ningún costo.** Los costos siguen saliendo de las facturas y los precios cargados, como hasta ahora.
- **El archivo de la lista** es privado: lo ven solo quienes ven listas, y no se puede cambiar ni borrar.

## Lo que todavía no está

- **Pegar la lista desde una planilla:** por ahora se carga renglón por renglón.
- **Archivos de más de 3,5 MB:** una foto grande conviene achicarla antes.
- **Los otros 3 indicadores de la ficha del proveedor** (saldo, órdenes de compra y última compra) llegan con las próximas entregas.

## Para probar en staging

1. Con el usuario de Compras: Listas de precios → «+ Cargar lista», elegir un proveedor, cargar dos renglones (uno con un nombre nuevo) y cargar.
2. Con un chef: Materias primas → «Artículos sin mapear», «Mapear» el artículo nuevo y elegir su materia prima y su envase.
3. Volver con Compras a la lista, «Aceptar» con un motivo y mirar el indicador en la ficha del proveedor.
4. En Rubros, mirar que Limpieza diga «No va a recetas».
