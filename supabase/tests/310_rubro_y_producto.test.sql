-- Rubro con precios editable y producto de compra con envase fijo (ADR-0044, decisiones de Joaco del 2026-11-13).
-- Compras (catalog.manage) cambia el rubro de una materia prima con precios, con motivo y auditoría; la unidad de recetas
-- sigue fija. Un producto con precios no cambia su envase ni su contenido (por cualquier camino), y sí lo demás.
-- Personas del seed: Dirección 402, Jefe de Cocina 406, Compras 408, Cocinera 409.
-- Materias primas: Tomate perita 801 (con precio), Harina 0000 828 (sin precios).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(29);

create function pg_temp.q(p_user uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin
    execute p_sql into v;
  exception when others then
    v := 'ERROR ' || sqlstate;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.msg(p_user uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin
    execute p_sql;
    v := 'sin error';
  exception when others then
    v := sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
grant execute on function pg_temp.u(int) to authenticated;

-- Un producto del Tomate perita con precios cargados, y el rubro de otra materia prima (para moverlo).
create temporary table fx (priced uuid, other_category uuid, fresh uuid);
insert into fx (priced, other_category)
select (select pp.id from catalog.purchase_products pp
         where pp.ingredient_id = pg_temp.u(801) and pp.deleted_at is null
           and exists (select 1 from costing.price_records r where r.purchase_product_id = pp.id and r.deleted_at is null)
         order by pp.id limit 1),
       (select category_id from catalog.ingredients where id = pg_temp.u(828));
grant select, update on fx to authenticated;
select ok((select priced is not null and other_category is not null from fx), 'el seed tiene un producto con precios');
select ok((select other_category from fx) is distinct from (select category_id from catalog.ingredients where id = pg_temp.u(801)),
          'y otro rubro al que moverla');

-- ---------------------------------------------------------------------------
-- Firmas: la regla del rubro ya no existe; la de los productos es interna
-- ---------------------------------------------------------------------------
select hasnt_function('catalog', 'category_locked_by_prices', array['uuid', 'uuid'], 'la regla del rubro trabado ya no existe');
select has_function('catalog', 'purchase_product_has_prices_internal', array['uuid'], 'existe la regla del envase fijo');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.purchase_product_has_prices_internal((select priced from fx))::text$$),
          'ERROR 42501', 'la regla es interna: la app no la llama');

-- ---------------------------------------------------------------------------
-- Rubro con precios: lo cambia Compras, con motivo y auditoría
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(408), format($$select catalog.update_ingredient(%L, jsonb_build_object('category_id', %L), 'Cambio de rubro (prueba)')$$,
                                            pg_temp.u(801), (select other_category from fx))),
          'sin error', 'Compras cambia el rubro de una materia prima con precios');
select is((select category_id from catalog.ingredients where id = pg_temp.u(801)), (select other_category from fx),
          'y el rubro queda cambiado');
select ok(exists (select 1 from audit.audit_events
                   where table_name = 'ingredients' and record_id = pg_temp.u(801) and reason = 'Cambio de rubro (prueba)'
                     and new_values ->> 'category_id' = (select other_category from fx)::text),
          'queda en la auditoría, con su motivo');
select is(pg_temp.msg(pg_temp.u(408), format($$select catalog.update_ingredient(%L, '{"recipe_unit": "ml"}', 'Otra unidad (prueba)')$$,
                                            pg_temp.u(801))),
          'Esta materia prima ya tiene precios: su unidad de uso no cambia (los precios se guardaron en esa unidad).',
          'la unidad de recetas sigue fija con precios');
select is(pg_temp.q(pg_temp.u(402), format($$select catalog.update_ingredient(%L, jsonb_build_object('category_id', %L), 'x')::text$$,
                                          pg_temp.u(801), (select other_category from fx))),
          'ERROR 42501', 'Dirección, sin catalog.manage, no cambia el rubro');
select is(pg_temp.q(pg_temp.u(406), format($$select catalog.update_ingredient(%L, jsonb_build_object('category_id', %L), 'x')::text$$,
                                          pg_temp.u(801), (select other_category from fx))),
          'ERROR 42501', 'el Jefe de Cocina tampoco');
select is(pg_temp.q(pg_temp.u(409), format($$select catalog.update_ingredient(%L, jsonb_build_object('category_id', %L), 'x')::text$$,
                                          pg_temp.u(801), (select other_category from fx))),
          'ERROR 42501', 'ni la Cocinera');

-- ---------------------------------------------------------------------------
-- Producto con precios: el envase y el contenido no cambian
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.update_purchase_product((select priced from fx), '{"content_per_unit": 1234}', 'Otro contenido')$$),
          'Este producto ya tiene precios: el envase y el contenido no cambian. Si cambió, agregá otro producto de compra.',
          'con precios, el contenido no cambia');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.update_purchase_product((select priced from fx), '{"units_per_package": 7}', 'Otro envase')$$),
          'Este producto ya tiene precios: el envase y el contenido no cambian. Si cambió, agregá otro producto de compra.',
          'ni las unidades por envase');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.update_purchase_product((select priced from fx), '{"package_unit": "bag"}', 'Otro envase')$$),
          'Este producto ya tiene precios: el envase y el contenido no cambian. Si cambió, agregá otro producto de compra.',
          'ni en qué viene');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.update_purchase_product((select priced from fx), '{"content_unit": "ml"}', 'Otra unidad')$$),
          'Este producto ya tiene precios: el envase y el contenido no cambian. Si cambió, agregá otro producto de compra.',
          'ni la unidad del contenido');
select throws_ok($$update catalog.purchase_products set content_per_unit = content_per_unit + 1 where id = (select priced from fx)$$,
                 '23514', null, 'la regla vale por cualquier camino, también sin pasar por la función');

-- Lo demás sí: descripción, marca, observaciones y dejar de comprarlo.
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.update_purchase_product((select priced from fx),
            '{"description": "Tomate perita, cajón (editado)", "brand_name": "Marca nueva", "notes": "Llega los martes", "is_active": false}',
            'Corrijo la descripción (prueba)')$$),
          'sin error', 'con precios, se editan la descripción, la marca, las observaciones y si se sigue comprando');
select ok((select description = 'Tomate perita, cajón (editado)' and brand_name = 'Marca nueva' and notes = 'Llega los martes'
                  and not is_active
             from catalog.purchase_products where id = (select priced from fx)),
          'y quedan guardados');
select ok(exists (select 1 from audit.audit_events
                   where table_name = 'purchase_products' and record_id = (select priced from fx)
                     and reason = 'Corrijo la descripción (prueba)'),
          'con su motivo en la auditoría');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.update_purchase_product((select priced from fx), '{"is_active": true}', 'Se vuelve a comprar')$$),
          'sin error', 'y se vuelve a activar');
select is(pg_temp.q(pg_temp.u(406), $$select catalog.update_purchase_product((select priced from fx), '{"notes": "x"}', 'x')::text$$),
          'ERROR 42501', 'el Jefe de Cocina no edita productos');
select is(pg_temp.q(pg_temp.u(409), $$select catalog.update_purchase_product((select priced from fx), '{"notes": "x"}', 'x')::text$$),
          'ERROR 42501', 'la Cocinera tampoco');

-- ---------------------------------------------------------------------------
-- Producto sin precios: se edita todo
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(408), $$update fx set fresh = catalog.create_purchase_product(pg_temp.u(828), 'PRU-310',
            'Harina 0000, bolsa de 25 kg', 'bag', 1, 25, 'kg', '{}', 'Producto de prueba')$$),
          'sin error', 'Compras agrega un producto sin precios');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.update_purchase_product((select fresh from fx),
            '{"package_unit": "box", "units_per_package": 2, "content_per_unit": 10, "content_unit": "kg"}', 'Era otro envase')$$),
          'sin error', 'sin precios, el envase y el contenido se cambian');
select ok((select units_per_package = 2 and content_per_unit = 10 from catalog.purchase_products where id = (select fresh from fx)),
          'y quedan guardados');

-- Un producto borrado no aparece entre los que traban el envase; la materia prima sigue con precios (unidad fija).
update catalog.purchase_products set deleted_at = now() where id = (select priced from fx);
select is(pg_temp.q(pg_temp.u(408), $$select (catalog.ingredient_sheet_state(pg_temp.u(801)) -> 'priced_products')::text$$),
          '[]', 'un producto borrado no figura entre los que tienen el envase fijo');
select is(pg_temp.q(pg_temp.u(408), $$select (catalog.ingredient_sheet_state(pg_temp.u(801)) ->> 'has_prices')$$),
          'true', 'y la materia prima sigue con precios: su unidad de recetas sigue fija');

set local role anon;
select throws_ok($$select catalog.update_purchase_product('00000000-0000-4000-8000-000000000001', '{}', 'x')$$,
                 '42501', null, 'anónimo no puede llamarla');
reset role;

select * from finish();
rollback;
