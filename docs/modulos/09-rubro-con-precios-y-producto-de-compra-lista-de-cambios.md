# Rubro con precios y edición de productos de compra: lista de cambios

Para Soy. Fecha: 2026-11-13. Detalle técnico en el ADR-0044.

## Qué cambia en la ficha de una materia prima

1. **El rubro se puede cambiar aunque la materia prima tenga precios.**
   - Lo cambia quien edita el catálogo (Compras) desde la ficha, con un motivo, y queda en el historial.
   - Antes nadie lo podía cambiar.
   - Ojo: el rubro decide a los cuántos días un precio aparece como «vencido». Al cambiar el rubro, puede cambiar eso.
2. **«Se usa en recetas en» sigue sin cambiar si ya tiene precios,** como antes.
3. **Cada producto de compra tiene un botón «Editar»** (en la computadora).
   - Se pueden corregir la descripción, la marca, el proveedor y las observaciones, y marcar si se sigue comprando.
   - **Si ya tiene precios, el envase y el contenido no se cambian.** Por ejemplo, de «bolsa de 5 kg» a «bolsa de 10 kg». Los precios se cargan por envase: si el mismo producto cambiara de envase, los precios nuevos no se podrían comparar con los anteriores, y un precio que está esperando aprobación quedaría rechazado. Los costos de las recetas no se mueven, porque cada precio guarda con qué envase se cargó. Si cambió el envase, se agrega otro producto y el viejo se marca como que ya no se compra. La pantalla lo explica con un ícono de ayuda.
   - Si todavía no tiene precios, se cambia todo.
4. **«Ya no se compran»:** debajo de la tabla aparecen los productos que se dejaron de comprar, para corregirlos o volver a activarlos. Antes desaparecían.
5. **«Proponer precio» sigue disponible en el celular,** como hasta ahora.

## Qué no cambia

- El catálogo lo siguen editando los mismos de antes: Compras y el Superadministrador.
- Los precios se siguen proponiendo y aprobando como siempre.
- En el celular, la ficha sigue siendo de consulta.
