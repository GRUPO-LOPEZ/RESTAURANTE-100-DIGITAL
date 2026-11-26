-- Filtros del listado de facturas (PR C, ADR-0070): «Para dar conforme» (las observadas que la sesión puede dar por
-- conforme y no cargó ella: doble firma) y «Vencidas» (liberadas con saldo y vencidas), en la lista y en su conteo por
-- proveedor (los dos con el mismo filtro). Personas: ...0404 gerente (...201), ...0407 controller, ...0408 compras.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(10);

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
    v := 'ERROR ' || sqlstate || ' ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.listed(p_user int, p_filter text) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format(
    'select coalesce(max(total), 0)::text from purchasing.invoice_list(p_status => %L, p_limit => 1)', p_filter))
$$;
create function pg_temp.counted(p_user int, p_filter text) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format(
    'select coalesce(sum(total), 0)::text from purchasing.invoice_supplier_counts(p_status => %L)', p_filter))
$$;

-- «Para dar conforme».
select ok((select count(*) from purchasing.invoices where status = 'observed' and deleted_at is null) >= 1,
          'el seed tiene facturas observadas');
select is(pg_temp.listed(407, 'to_approve'),
          (select count(*)::text from purchasing.invoices
            where status = 'observed' and deleted_at is null and created_by is distinct from pg_temp.u(407)),
          'el Controller ve para dar conforme las observadas que no cargó él');
select ok(pg_temp.listed(407, 'to_approve')::int >= 1, 'y son al menos una');
select is(pg_temp.listed(408, 'to_approve'),
          (select count(*)::text from purchasing.invoices
            where status = 'observed' and deleted_at is null and created_by is distinct from pg_temp.u(408)),
          'Compras no ve para dar conforme las que cargó ella (doble firma)');
select is(pg_temp.listed(404, 'to_approve'), '0', 'el gerente no da conformes: no tiene ninguna');
select is(pg_temp.counted(407, 'to_approve'), pg_temp.listed(407, 'to_approve'),
          'el conteo por proveedor coincide con la lista');

-- «Vencidas».
select is(pg_temp.listed(408, 'overdue'),
          (select count(*)::text from purchasing.invoices i
            where i.status = 'released' and i.deleted_at is null and i.due_on < recipes.today()
              and purchasing.invoice_balance(i.id) > 0.005),
          'vencidas: liberadas con saldo y con el vencimiento pasado');
select ok(pg_temp.listed(408, 'overdue')::int >= 1, 'el seed tiene al menos una vencida');
select is(pg_temp.counted(408, 'overdue'), pg_temp.listed(408, 'overdue'),
          'el conteo por proveedor coincide con la lista');
select ok(not has_function_privilege('anon',
            'purchasing.invoice_status_matches(uuid, purchasing.invoice_status, uuid, uuid, date, text)', 'execute'),
          'anon no usa el filtro');

select * from finish();
rollback;
