-- Ficha única de materia prima (ADR-0043, Prompt 3 de Soy del 2026-11-12): guardado en lote en una transacción con un
-- solo motivo, sin pisar lo de otra persona, con las reglas de siempre (catalog.manage, unidad de recetas fija con
-- precios y el rubro editable por Compras desde el ADR-0044, aprobación para dejar de comprarla congelada) y la tabla de productos con su
-- precio en el local, igual que el motor de costos.
-- Personas del seed: Dirección 402, Gerente 404 (Demo Pastas Centro, 201), Jefe de Cocina 406 (201), Compras 408,
-- Cocinera 409 (201), una cuenta sin membresía 499.
-- Materias primas: Tomate perita 801 (con precio), Queso provolone 825, Harina 0000 828 y Sémola 829 (sin precios).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(49);

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
-- El sello actual, leído como postgres (la ficha lo recibe al abrirse).
create function pg_temp.stamp(p_n int) returns text language sql as $$
  select catalog.ingredient_sheet_stamp_internal(pg_temp.u(p_n))::text
$$;
grant execute on function pg_temp.u(int), pg_temp.stamp(int) to authenticated;

-- ---------------------------------------------------------------------------
-- Firmas
-- ---------------------------------------------------------------------------
select has_function('catalog', 'save_ingredient_sheet',
                    array['uuid', 'timestamp with time zone', 'jsonb', 'text[]', 'jsonb', 'jsonb', 'boolean', 'text'],
                    'existe el guardado en lote de la ficha');
select has_function('catalog', 'ingredient_sheet_state', array['uuid'], 'existe el estado de la ficha');
select has_function('costing', 'ingredient_product_prices', array['uuid', 'uuid'], 'existe la tabla de productos con precio');

-- ---------------------------------------------------------------------------
-- Guardado en lote: todo en una transacción y con un solo motivo
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(408), format($$select catalog.save_ingredient_sheet(pg_temp.u(828), %L,
            '{"name": "Harina 0000 de prueba", "notes": "Bolsa abierta va al tacho hermético", "purchase_unit": "kg"}',
            array['harina fina', 'cuatro ceros'],
            '[{"kind": "density", "factor": "0.55", "source": "measured", "measured_on": "2026-11-10", "measured_by": "Pablo"}]',
            jsonb_build_array(jsonb_build_object('allergen_id', pg_temp.u(951), 'status', 'contains', 'source', 'supplier')),
            null, 'Ficha en lote (prueba)') ->> 'result'$$, pg_temp.stamp(828))),
          'applied', 'Compras guarda datos, otros nombres, una conversión y un alérgeno en un solo guardado');
select is((select name from catalog.ingredients where id = pg_temp.u(828)), 'Harina 0000 de prueba', 'el nombre quedó');
select is((select u.code from catalog.ingredients i join catalog.units u on u.id = i.purchase_unit_id
            where i.id = pg_temp.u(828)), 'kg', 'la unidad de compra quedó');
select is((select array_agg(alias order by alias) from catalog.ingredient_aliases
            where ingredient_id = pg_temp.u(828) and deleted_at is null),
          array['cuatro ceros', 'harina fina'], 'los otros nombres quedaron');
select is((select factor from catalog.ingredient_unit_conversions
            where ingredient_id = pg_temp.u(828) and kind = 'density' and deleted_at is null), 0.55::numeric,
          'la densidad quedó');
select is((select status::text from catalog.ingredient_allergens
            where ingredient_id = pg_temp.u(828) and allergen_id = pg_temp.u(951) and deleted_at is null), 'contains',
          'el alérgeno quedó');
select ok((select count(*) >= 4 from audit.audit_events
            where reason = 'Ficha en lote (prueba)'
              and table_name in ('ingredients', 'ingredient_aliases', 'ingredient_unit_conversions', 'ingredient_allergens')),
          'la auditoría registra cada cambio');
select is((select count(distinct table_name)::int from audit.audit_events where reason = 'Ficha en lote (prueba)'), 4,
          'el mismo motivo queda en las cuatro tablas');

-- Con el sello viejo (otra persona guardó en el medio), no se pisa nada.
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.save_ingredient_sheet(pg_temp.u(828), '2000-01-01 00:00:00+00',
            '{"name": "Pisada"}', null, null, null, null, 'Pisar (prueba)')$$),
          'Otra persona cambió esta materia prima mientras la editabas: recargá la página para ver sus cambios.',
          'con el sello viejo lo rechaza');
select is((select name from catalog.ingredients where id = pg_temp.u(828)), 'Harina 0000 de prueba', 'y el nombre no cambió');

-- Un bloque inválido no guarda nada: el nombre nuevo tampoco.
select is(pg_temp.q(pg_temp.u(408), format($$select catalog.save_ingredient_sheet(pg_temp.u(828), %L,
            '{"name": "No tiene que quedar"}', null, '[{"kind": "volumen", "factor": "2"}]', null, null,
            'Bloque inválido (prueba)')::text$$, pg_temp.stamp(828))),
          'ERROR 22023', 'una conversión inválida corta el guardado');
select is((select name from catalog.ingredients where id = pg_temp.u(828)), 'Harina 0000 de prueba',
          'y no se guardó nada a medias');
select is(pg_temp.msg(pg_temp.u(408), format($$select catalog.save_ingredient_sheet(pg_temp.u(828), %L,
            '{"name": "Sin motivo"}', null, null, null, null, ' ')$$, pg_temp.stamp(828))),
          'Escribí el motivo de los cambios.', 'sin motivo no guarda');

-- ---------------------------------------------------------------------------
-- Unidad de recetas: la base de su tipo (ADR-0041), fija si tiene precios
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(408), format($$select catalog.save_ingredient_sheet(pg_temp.u(825), %L,
            '{"recipe_unit": "kg"}', null, null, null, null, 'Se pesa por kilo (prueba)') ->> 'result'$$,
            pg_temp.stamp(825))), 'applied', 'elegir Kilogramo se acepta');
select is((select u.code from catalog.ingredients i join catalog.units u on u.id = i.recipe_unit_id
            where i.id = pg_temp.u(825)), 'g', 'y se guarda en gramos, la base del peso');
-- La regla de siempre: un producto que se compra en otra medida necesita la densidad antes.
select is(pg_temp.msg(pg_temp.u(408), format($$select catalog.save_ingredient_sheet(pg_temp.u(829), %L,
            '{"recipe_unit": "l"}', null, null, null, null, 'En volumen (prueba)')$$, pg_temp.stamp(829))),
          'No se puede cambiar la unidad de uso: el producto «Sémola, bolsa de 5 kg» se compra en otra unidad y necesita su densidad.',
          'pasarla a volumen sin densidad se rechaza, como siempre');
select is(pg_temp.msg(pg_temp.u(408), format($$select catalog.save_ingredient_sheet(pg_temp.u(825), %L,
            '{"recipe_unit": "box"}', null, null, null, null, 'En cajas (prueba)')$$, pg_temp.stamp(825))),
          'Elegí una medida de peso, de volumen o de cantidad.', 'un envase no es unidad de recetas');
select is(pg_temp.msg(pg_temp.u(408), format($$select catalog.save_ingredient_sheet(pg_temp.u(801), %L,
            '{"recipe_unit": "unit"}', null, null, null, null, 'Por unidad (prueba)')$$, pg_temp.stamp(801))),
          'Esta materia prima ya tiene precios: su unidad de uso no cambia (los precios se guardaron en esa unidad).',
          'con precios, la unidad de recetas no cambia');

-- ---------------------------------------------------------------------------
-- Rubro con precios: lo cambia quien edita el catálogo (catalog.manage), con motivo y auditoría (ADR-0044)
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(408), format($$select catalog.save_ingredient_sheet(pg_temp.u(801), %L,
            jsonb_build_object('category_id', (select category_id from catalog.ingredients where id = pg_temp.u(811))),
            null, null, null, null, 'Otro rubro (prueba)') ->> 'result'$$, pg_temp.stamp(801))),
          'applied', 'Compras cambia el rubro de una materia prima con precios');
-- Dirección tiene prices.configure pero no catalog.manage: no edita la ficha (como antes de la ficha única).
select is(pg_temp.q(pg_temp.u(402), format($$select catalog.save_ingredient_sheet(pg_temp.u(801), %L,
            jsonb_build_object('category_id', (select category_id from catalog.ingredients where id = pg_temp.u(811))),
            null, null, null, null, 'Otro rubro (prueba)') ->> 'result'$$, pg_temp.stamp(801))),
          'denied', 'Dirección, sin catalog.manage, no edita la ficha');
select ok(exists (select 1 from audit.audit_events
                   where table_name = 'ingredients' and record_id = pg_temp.u(801) and reason = 'Otro rubro (prueba)'
                     and old_values ->> 'category_id' is distinct from new_values ->> 'category_id'),
          'el cambio de rubro queda en la auditoría, con su motivo');

-- ---------------------------------------------------------------------------
-- Se compra congelada: marcarla se aplica; desmarcarla pide aprobación (ADR-0040)
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(408), format($$select catalog.save_ingredient_sheet(pg_temp.u(825), %L,
            null, null, null, null, true, 'Viene congelado (prueba)') ->> 'thawing'$$, pg_temp.stamp(825))),
          'applied', 'marcarla congelada se aplica en el momento');
select is(pg_temp.q(pg_temp.u(408), format($$select catalog.save_ingredient_sheet(pg_temp.u(825), %L,
            null, null, null, null, false, 'Viene fresco (prueba)') ->> 'thawing'$$, pg_temp.stamp(825))),
          'pending_approval', 'desmarcarla queda pendiente');
select ok((select requires_thawing from catalog.ingredients where id = pg_temp.u(825)),
          'y hasta que lo aprueben sigue congelada');
select is((select count(*)::int from workflow.approval_requests r
             join workflow.approval_workflows w on w.id = r.workflow_id
            where w.code = 'catalog.change_requires_thawing' and r.entity_id = pg_temp.u(825) and r.status = 'pending'),
          1, 'con su pedido de aprobación');

-- ---------------------------------------------------------------------------
-- Quién puede: catalog.manage; los demás, rechazados y registrados
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(406), format($$select catalog.save_ingredient_sheet(pg_temp.u(828), %L,
            '{"name": "Jefe"}', null, null, null, null, 'Prueba') ->> 'result'$$, pg_temp.stamp(828))),
          'denied', 'el Jefe de Cocina, sin catalog.manage, no guarda');
select is(pg_temp.q(pg_temp.u(409), format($$select catalog.save_ingredient_sheet(pg_temp.u(828), %L,
            '{"name": "Cocinera"}', null, null, null, null, 'Prueba') ->> 'result'$$, pg_temp.stamp(828))),
          'denied', 'la Cocinera tampoco');
select is(pg_temp.q(pg_temp.u(499), format($$select catalog.save_ingredient_sheet(pg_temp.u(828), %L,
            '{"name": "Sin membresía"}', null, null, null, null, 'Prueba') ->> 'result'$$, pg_temp.stamp(828))),
          'denied', 'una cuenta sin membresía tampoco');
select is((select array_agg(distinct right(actor_id::text, 3) order by right(actor_id::text, 3))
             from audit.authentication_security_events
            where operation = 'catalog.save_ingredient_sheet' and detail ->> 'ingredient_id' = pg_temp.u(828)::text),
          array['406', '409', '499'], 'cada rechazo queda registrado, uno por persona');
select is((select count(*)::int from audit.authentication_security_events
            where operation = 'catalog.save_ingredient_sheet' and detail ->> 'ingredient_id' = pg_temp.u(828)::text),
          3, 'y solo esos tres');
select is(pg_temp.msg(pg_temp.u(408), format($$select catalog.save_ingredient_sheet(pg_temp.u(828), %L,
            '{}', null, null, null, null, 'Vacío (prueba)')$$, pg_temp.stamp(828))),
          'Los datos generales van como un objeto con algún cambio.', 'un bloque de datos vacío no se acepta');
select is((select name from catalog.ingredients where id = pg_temp.u(828)), 'Harina 0000 de prueba',
          'y nada cambió');
set local role anon;
select throws_ok($$select catalog.save_ingredient_sheet(pg_temp.u(828), now(), null, null, null, null, null, 'x')$$,
                 '42501', null, 'anónimo no puede llamarla');
reset role;
select is(pg_temp.q(pg_temp.u(406), $$select catalog.ingredient_sheet_state(pg_temp.u(828))::text$$), null,
          'el estado de la ficha es solo para quien la puede editar');
-- El Tomate perita tiene dos productos y solo DEMO-PROD-001 tiene precio en el seed.
select is(pg_temp.q(pg_temp.u(408), $$select (catalog.ingredient_sheet_state(pg_temp.u(801)) -> 'priced_products')::text$$),
          (select jsonb_build_array(id)::text from catalog.purchase_products where code = 'DEMO-PROD-001'),
          'a Compras, la ficha le dice qué productos tienen precios (su envase no cambia), y solo esos');
select is(pg_temp.q(pg_temp.u(408), $$select (catalog.ingredient_sheet_state(pg_temp.u(828)) ->> 'has_prices')$$), 'false',
          'sin precios, la unidad de recetas se puede cambiar');
select is(pg_temp.q(pg_temp.u(408), $$select (catalog.ingredient_sheet_state(pg_temp.u(828)) ->> 'stamp')::timestamptz::text$$),
          pg_temp.stamp(828), 'y trae el mismo sello que controla el guardado');

-- ---------------------------------------------------------------------------
-- Productos de compra con su precio: el mismo que usa el costo
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(404), $$select (p.unit_cost = r.unit_cost and p.stale is not distinct from r.stale
                                              and p.valid_from = r.valid_from)::text
             from costing.ingredient_product_prices(pg_temp.u(801), pg_temp.u(201)) p
             join costing.resolve_price(pg_temp.u(801), pg_temp.u(201)) r on r.purchase_product_id = p.purchase_product_id$$),
          'true', 'el producto que usa el costo da el mismo costo por unidad, fecha y vencimiento que el motor');
select is(pg_temp.q(pg_temp.u(404), $$select count(*)::text from costing.ingredient_product_prices(pg_temp.u(801), pg_temp.u(201))
                                      where unit_cost is not null$$),
          '1', 'el Gerente ve el precio en su local');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from costing.ingredient_product_prices(pg_temp.u(801), pg_temp.u(201))$$),
          '0', 'la Cocinera, sin prices.view, no recibe ninguna fila');
select is(pg_temp.q(pg_temp.u(404), $$select count(*)::text from costing.ingredient_product_prices(pg_temp.u(801), pg_temp.u(203))$$),
          '0', 'un local fuera de su alcance tampoco');

-- ---------------------------------------------------------------------------
-- Con el rubro dado de baja (ADR-0038) también: Compras la saca de ahí
-- ---------------------------------------------------------------------------
update catalog.ingredient_categories set is_active = false where id = pg_temp.u(701);
select is(pg_temp.q(pg_temp.u(408), $$select (catalog.ingredient_sheet_state(pg_temp.u(828)) -> 'priced_products')::text$$),
          '[]', 'sin precios, ningún producto queda con el envase fijo');
select is(pg_temp.q(pg_temp.u(408), format($$select catalog.save_ingredient_sheet(pg_temp.u(802), %L,
            jsonb_build_object('category_id', (select category_id from catalog.ingredients where id = pg_temp.u(811))),
            null, null, null, null, 'Sale del rubro dado de baja (prueba)') ->> 'result'$$, pg_temp.stamp(802))),
          'applied', 'y la base lo acepta: la pantalla y la base dicen lo mismo');
update catalog.ingredient_categories set is_active = true where id = pg_temp.u(701);

-- ---------------------------------------------------------------------------
-- Un producto que ya no se compra, con el precio que usa el costo, sigue en la tabla
-- ---------------------------------------------------------------------------
update catalog.purchase_products set is_active = false where ingredient_id = pg_temp.u(801);
select is(pg_temp.q(pg_temp.u(404), $$select (p.unit_cost = r.unit_cost and not p.is_active)::text
             from costing.ingredient_product_prices(pg_temp.u(801), pg_temp.u(201)) p
             join costing.resolve_price(pg_temp.u(801), pg_temp.u(201)) r on r.purchase_product_id = p.purchase_product_id$$),
          'true', 'el producto desactivado que usa el costo aparece, marcado y con el mismo costo');
update catalog.purchase_products set is_active = true where ingredient_id = pg_temp.u(801);

-- ---------------------------------------------------------------------------
-- El sello se mueve con un cambio solo en un alérgeno o en otro nombre
-- ---------------------------------------------------------------------------
-- En una prueba todo pasa en una transacción y now() no avanza: se simula un cambio confirmado después, corriendo la
-- fecha a mano (sin los triggers, que la volverían a now()).
create temp table sello (v text);
insert into sello select pg_temp.stamp(828);
set local session_replication_role = replica;
update catalog.ingredient_allergens set updated_at = now() + interval '1 minute'
 where ingredient_id = pg_temp.u(828) and allergen_id = pg_temp.u(951);
set local session_replication_role = origin;
select is(pg_temp.msg(pg_temp.u(408), format($$select catalog.save_ingredient_sheet(pg_temp.u(828), %L,
            '{"notes": "Pisaría el alérgeno"}', null, null, null, null, 'Sello viejo (prueba)')$$, (select v from sello))),
          'Otra persona cambió esta materia prima mientras la editabas: recargá la página para ver sus cambios.',
          'un alérgeno cambiado por otra persona mueve el sello y frena el guardado');
update sello set v = pg_temp.stamp(828);
set local session_replication_role = replica;
update catalog.ingredient_aliases set updated_at = now() + interval '2 minutes', deleted_at = now()
 where ingredient_id = pg_temp.u(828) and alias = 'cuatro ceros';
set local session_replication_role = origin;
select ok(pg_temp.stamp(828)::timestamptz > (select v from sello)::timestamptz,
          'un otro nombre quitado también mueve el sello');

select * from finish();
rollback;
