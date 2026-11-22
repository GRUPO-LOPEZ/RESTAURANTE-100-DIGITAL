-- Razón social con los datos de la constancia de ARCA y el PDF adjunto (Tanda 1 de Soy, ADR-0061).
-- Personas del seed: ...0401 superadministrador, ...0403 directora de Demo Pastas, ...0404 gerente de ...201,
-- ...0409 cocinera. Razones sociales: ...1501 (completa, con 2 actividades) y ...1502 (incompleta).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(41);

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
    v := 'ERROR ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.save(p_user int, p_id uuid, p_changes jsonb, p_reason text default 'Datos de ARCA')
returns text language sql as $$
  select regexp_replace(pg_temp.q(pg_temp.u(p_user), format('select org.save_legal_entity_sheet(%L, %L, %L, %L)::text',
                                  p_id, org.legal_entity_sheet_stamp_internal(p_id), p_changes, p_reason)),
                        '^\{"stamp".*\}$', '')
$$;
-- Un PDF «subido» por una persona: la fila en storage.objects, como la deja Storage.
create function pg_temp.upload(p_user int, p_entity uuid, p_file int) returns text language sql as $$
  insert into storage.objects (bucket_id, name, owner_id)
  values ('org-documents', format('%s/legal_entities/%s/%s.pdf', pg_temp.u(1), p_entity, pg_temp.u(p_file)), pg_temp.u(p_user)::text)
  returning name
$$;

-- El CUIT con su dígito verificador.
select is(pg_temp.q(pg_temp.u(401), format($$select org.create_legal_entity(%L, 'Mal S.A.', '30-12345678-0', 'registered', 'Prueba')$$, pg_temp.u(1))),
  'ERROR El CUIT no es válido: revisá los números.', 'un CUIT con el dígito verificador mal se rechaza');
select ok(pg_temp.q(pg_temp.u(401), format($$select org.create_legal_entity(%L, 'Bien S.A. (ficticia)', '30-88888888-4', 'registered', 'Prueba')$$, pg_temp.u(1)))
            ~ '^[0-9a-f-]{36}$', 'uno válido se acepta');
select is(pg_temp.save(401, pg_temp.u(1501), '{"entity": {"tax_id": "30-77777777-0"}}'),
  'ERROR El CUIT no es válido: revisá los números.', 'desde la ficha, también');

-- Lo que falta y el estado de la constancia.
select is(pg_temp.q(pg_temp.u(401), format('select org.legal_entity_sheet_state(%L) ->> ''missing''', pg_temp.u(1501))), '[]',
  'la razón social del seed tiene todo lo de la constancia');
select is(pg_temp.q(pg_temp.u(401), format('select org.legal_entity_sheet_state(%L) ->> ''missing''', pg_temp.u(1502))),
  '["calle y número", "localidad", "código postal", "provincia", "número de Ingresos Brutos", "actividad principal"]',
  'y la otra dice lo que le falta');
select is(pg_temp.q(pg_temp.u(401), format('select org.legal_entity_sheet_state(%L) ->> ''document_status''', pg_temp.u(1501))),
  'missing', 'sin PDF, la constancia no da un estado positivo');

-- Guardar los datos de ARCA y las actividades, todo junto.
select is(pg_temp.save(401, pg_temp.u(1502), jsonb_build_object(
  'entity', jsonb_build_object('fiscal_street', 'Calle de Prueba 45', 'fiscal_locality', 'Balvanera', 'fiscal_postal_code', 'c1030',
                               'fiscal_province', '02', 'gross_income_regime', 'exempt', 'is_withholding_agent', true,
                               'electronic_domicile', 'Cafe@Ejemplo.test'),
  'activities', jsonb_build_array(jsonb_build_object('code', '561019', 'description', 'Servicios de expendio de comidas', 'is_primary', true))),
  'Constancia nueva'), '', 'se guardan los datos de la constancia y una actividad principal');
select is((select fiscal_postal_code || ' ' || gross_income_regime || ' ' || is_withholding_agent || ' ' || electronic_domicile
             from org.legal_entities where id = pg_temp.u(1502)), 'C1030 exempt true cafe@ejemplo.test',
  'con el CP en mayúsculas, los toggles y el correo en minúsculas');
select is(pg_temp.q(pg_temp.u(401), format('select org.legal_entity_sheet_state(%L) ->> ''missing''', pg_temp.u(1502))), '[]',
  'exenta de Ingresos Brutos no pide el número, y ya está completa');
select ok(exists (select 1 from audit.audit_events where table_name = 'legal_entity_activities' and reason = 'Constancia nueva'),
  'la actividad nueva queda en la auditoría con el motivo');

-- Una sola principal: si otra pasa a principal, la anterior deja de serlo en el mismo guardado.
select is(pg_temp.save(401, pg_temp.u(1501), jsonb_build_object('activities', jsonb_build_array(jsonb_build_object(
    'id', (select id from org.legal_entity_activities where legal_entity_id = pg_temp.u(1501) and code = '561020'), 'is_primary', true)))),
  '', 'otra actividad pasa a ser la principal');
select is((select string_agg(code || ':' || is_primary, ',' order by code) from org.legal_entity_activities
            where legal_entity_id = pg_temp.u(1501) and deleted_at is null), '561011:false,561020:true',
  'y queda una sola principal');
select is(pg_temp.save(401, pg_temp.u(1501), '{"activities": [{"code": "561020", "description": "Repetida"}]}'),
  'ERROR Esa actividad ya está cargada.', 'una actividad no se carga dos veces');
select is(pg_temp.save(401, pg_temp.u(1501), '{"activities": [{"code": "5610", "description": "Corta"}]}'),
  'ERROR El código de la actividad tiene 6 cifras.', 'el código de la actividad tiene 6 cifras');
select is(pg_temp.save(401, pg_temp.u(1501), jsonb_build_object('activities', jsonb_build_array(jsonb_build_object(
    'id', (select id from org.legal_entity_activities where legal_entity_id = pg_temp.u(1501) and code = '561011'), 'remove', true)))),
  '', 'una actividad se quita');
select is((select count(*)::int from org.legal_entity_activities where legal_entity_id = pg_temp.u(1501) and code = '561011'
             and deleted_at is not null), 1, 'con baja lógica, sin borrarla');

-- Valores fuera de la lista y fechas imposibles.
select is(pg_temp.save(401, pg_temp.u(1501), '{"entity": {"name": ""}}'),
  'ERROR La razón social, el CUIT y el IVA no pueden quedar vacíos.', 'el nombre no queda vacío');
select is(pg_temp.save(401, pg_temp.u(1501), '{"entity": {"activity_start": "2999-01-01"}}'),
  'ERROR El inicio de actividades no puede ser una fecha futura.', 'el inicio de actividades no es futuro');

-- Solo quien administra todo el grupo cambia una razón social.
select is(pg_temp.save(403, pg_temp.u(1501), '{"entity": {"trade_name": "Otro"}}'),
  'ERROR No tenés permiso para editar esta razón social.', 'la Directora de Marca no la edita');
select is(pg_temp.save(404, pg_temp.u(1501), '{"entity": {"trade_name": "Otro"}}'),
  'ERROR No tenés permiso para editar esta razón social.', 'el Gerente tampoco');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from org.legal_entity_activities'), '0',
  'la Cocinera no ve las actividades');
select is(pg_temp.q(pg_temp.u(409), format('select coalesce(org.legal_entity_sheet_state(%L)::text, ''nada'')', pg_temp.u(1501))),
  'nada', 'ni la ficha de la razón social');

-- La constancia en PDF: subir, registrar y no cambiar.
select ok(pg_temp.q(pg_temp.u(401), format('select org.can_upload_document(%L)::text',
            format('%s/legal_entities/%s/%s.pdf', pg_temp.u(1), pg_temp.u(1501), pg_temp.u(7001)))) = 'true',
  'el Superadministrador puede subir la constancia a la carpeta de la razón social');
select is(pg_temp.q(pg_temp.u(403), format('select org.can_upload_document(%L)::text',
            format('%s/legal_entities/%s/%s.pdf', pg_temp.u(1), pg_temp.u(1501), pg_temp.u(7001)))), 'false',
  'la Directora de Marca no');
select ok(pg_temp.q(pg_temp.u(401), format('select org.add_legal_entity_document(%L, %L, %L)::text',
            pg_temp.u(1501), pg_temp.upload(401, pg_temp.u(1501), 7001),
            ((now() at time zone 'America/Argentina/Buenos_Aires')::date - 30)::text)) ~ '^[0-9a-f-]{36}$',
  'se registra la constancia subida, con su fecha de emisión');
select is(pg_temp.q(pg_temp.u(401), format('select org.legal_entity_sheet_state(%L) ->> ''document_status''', pg_temp.u(1501))),
  'current', 'y la constancia queda Al día');
select is(pg_temp.q(pg_temp.u(401), format('select org.add_legal_entity_document(%L, %L, %L)::text',
            pg_temp.u(1501), pg_temp.upload(401, pg_temp.u(1502), 7002), '2026-01-01')),
  'ERROR El archivo no está subido en la carpeta de esta razón social.', 'un archivo de otra carpeta no se registra');
select is(pg_temp.q(pg_temp.u(401), format('select org.add_legal_entity_document(%L, %L, %L)::text',
            pg_temp.u(1501), pg_temp.upload(401, pg_temp.u(1501), 7003), '2999-01-01')),
  'ERROR Escribí la fecha de emisión de la constancia (no puede ser futura).', 'una constancia del futuro no se registra');
select throws_ok(format('update org.legal_entity_documents set issued_on = ''2020-01-01'' where legal_entity_id = %L', pg_temp.u(1501)),
  '42501', 'Una constancia subida no se cambia ni se borra: subí una nueva.', 'una constancia registrada no se cambia');
select is(org.document_status(((now() at time zone 'America/Argentina/Buenos_Aires')::date - 400)), 'stale',
  'con más de 12 meses, la constancia queda Vencida');

-- Quién ve los datos de ARCA (auditoría de seguridad, M1): el Gerente ve los de la razón social de su local, no los de
-- otra del grupo aunque tenga precios en su local.
select ok(pg_temp.q(pg_temp.u(404), format('select count(*)::text from org.legal_entity_activities where legal_entity_id = %L',
                                           pg_temp.u(1501)))::int > 0, 'el Gerente ve las actividades de la razón social de su local');
select is(pg_temp.q(pg_temp.u(404), format('select count(*)::text from org.legal_entity_activities where legal_entity_id = %L',
                                           pg_temp.u(1502))), '0', 'pero no las de otra razón social del grupo');
select is(pg_temp.q(pg_temp.u(404), format('select coalesce(org.legal_entity_sheet_state(%L)::text, ''nada'')', pg_temp.u(1502))),
  'nada', 'ni su ficha');

-- Estructura: las tablas nuevas de org, con RLS y sin escritura directa para nadie.
select is((select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'org' and c.relrowsecurity
              and c.relname in ('provinces', 'legal_entity_activities', 'restaurant_legal_entities', 'legal_entity_documents')),
  4, 'las 4 tablas nuevas de org tienen RLS');
select is((select count(*)::int from information_schema.role_table_grants
            where table_schema = 'org' and grantee = 'authenticated' and privilege_type <> 'SELECT'
              and table_name in ('provinces', 'legal_entity_activities', 'restaurant_legal_entities', 'legal_entity_documents')),
  0, 'y authenticated solo las lee: se escriben por funciones');

-- Storage: sube a la carpeta de una razón social solo quien administra todo el grupo; lee quien la ve.
select is(pg_temp.q(pg_temp.u(401), format(
    $$insert into storage.objects (bucket_id, name, owner_id) values ('org-documents', %L, %L) returning 'ok'$$,
    format('%s/legal_entities/%s/%s.pdf', pg_temp.u(1), pg_temp.u(1501), pg_temp.u(7101)), pg_temp.u(401))),
  'ok', 'el Superadministrador sube un PDF a la carpeta de la razón social');
select ok(pg_temp.q(pg_temp.u(403), format(
    $$insert into storage.objects (bucket_id, name, owner_id) values ('org-documents', %L, %L) returning 'ok'$$,
    format('%s/legal_entities/%s/%s.pdf', pg_temp.u(1), pg_temp.u(1501), pg_temp.u(7102)), pg_temp.u(403)))
  ~ 'row-level security', 'la Directora de Marca no sube');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from storage.objects where bucket_id = 'org-documents'$$), '0',
  'la Cocinera no ve ninguna constancia');
select ok(pg_temp.q(pg_temp.u(407), format('select count(*)::text from org.legal_entity_documents where legal_entity_id = %L',
                                           pg_temp.u(1501)))::int = 1,
  'quien ve precios sin administrar el grupo (Controller) ve la constancia registrada');
select ok(pg_temp.q(pg_temp.u(407), 'select count(*)::text from org.restaurant_legal_entities')::int >= 4,
  'y el historial de razones sociales de los locales');
select is(pg_temp.q(pg_temp.u(401), format('select org.add_legal_entity_document(%L, %L, %L)::text',
            pg_temp.u(1501), (select storage_path from org.legal_entity_documents where legal_entity_id = pg_temp.u(1501) limit 1),
            '2026-01-01')),
  'ERROR Esa constancia ya está registrada.', 'la misma constancia no se registra dos veces');

select * from finish();
rollback;
