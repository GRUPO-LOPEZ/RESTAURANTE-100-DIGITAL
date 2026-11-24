-- Ficha de la persona en una pantalla (Tanda 1 de Soy, Usuarios, ADR-0062): guardado en lote con sello y motivo, los
-- mismos permisos y aprobaciones de roles, todo o nada, y cerrar las sesiones de otra persona.
-- Personas del seed: ...0401 superadministrador, ...0402 Dirección General, ...0403 directora de Demo Pastas (...101),
-- ...0404 gerente y ...0406 jefe de cocina de ...201, ...0409 cocinera de ...201, ...0410 auditor, ...0408 compras.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(87);

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
create function pg_temp.u(p_n int) returns uuid language sql strict as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.state(p_user int, p_target int) returns jsonb language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select core.user_sheet_state(%L)::text', pg_temp.u(p_target)))::jsonb
$$;
-- Guarda con el sello vigente y devuelve «resultado: mensaje», o el error.
create function pg_temp.save(p_user int, p_target int, p_changes jsonb, p_reason text default 'Cambio de prueba')
returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format(
    'select (r ->> ''result'') || '': '' || (r ->> ''message'') from core.save_user_sheet(%L, %L, %L, %L) r',
    pg_temp.u(p_target), core.user_sheet_stamp_internal(pg_temp.u(p_target)), p_changes, p_reason))
$$;
create function pg_temp.role_at(p_role text, p_scope text, p_brand int default null, p_rest int default null)
returns jsonb language sql as $$
  select jsonb_build_object('role_code', p_role, 'scope_type', p_scope, 'group_id', pg_temp.u(1),
                            'brand_id', pg_temp.u(p_brand), 'restaurant_id', pg_temp.u(p_rest))
$$;
create function pg_temp.denials(p_op text) returns int language sql as $$
  select count(*)::int from audit.authentication_security_events where event_type = 'operation_denied' and operation = p_op
$$;

-- Qué puede hacer cada uno.
select is(pg_temp.state(404, 409) - array['stamp', 'revocable', 'areas', 'changes_30d', 'rejected_7d', 'mfa', 'sessions'],
  '{"is_me": false, "can_edit_profile": true, "can_edit_job": true, "can_assign": true, "can_close_sessions": true, "can_unlock": true,
    "can_suspend": true, "can_deactivate": true, "can_reactivate": true}'::jsonb,
  'el Gerente edita y administra a la cocinera de su local');
select is(pg_temp.state(410, 409) ->> 'can_edit_profile', 'false', 'el Auditor ve la ficha, pero no edita');
select is(pg_temp.state(410, 409) ->> 'can_suspend', 'false', 'ni suspende');
select is(pg_temp.state(410, 409) ->> 'sessions', null, 'ni ve sus sesiones');
select is(pg_temp.state(410, 409) ->> 'mfa', null, 'ni si tiene doble verificación');
select is(pg_temp.state(404, 403) ->> 'can_edit_profile', null, 'el Gerente no ve la ficha de su Directora');
select is(pg_temp.state(409, 406)::text, null, 'la cocinera no ve fichas de otras personas');
select is(pg_temp.state(404, 404) ->> 'can_edit_profile', 'false', 'la ficha propia no se edita desde acá (va en Mi cuenta)');
select is(pg_temp.state(404, 404) ->> 'can_assign', 'false', 'y nadie se da roles a sí mismo');
select is(pg_temp.state(404, 409) ->> 'rejected_7d', null, 'los accesos rechazados, solo quien ve el registro de seguridad');
select ok((pg_temp.state(401, 409) ->> 'rejected_7d') is not null, 'el Superadministrador los ve');
select ok((pg_temp.state(401, 402) ->> 'can_deactivate')::boolean, 'a alguien de Dirección, el Superadministrador la baja la puede pedir');
select is(pg_temp.state(401, 402) ->> 'can_edit_profile', 'false', 'pero no edita su nombre: tiene permisos que el Superadministrador no tiene');
select is(pg_temp.state(401, 402) ->> 'can_edit_job', 'true', 'sí su puesto y su área, que no dan permisos');
select is(pg_temp.state(410, 409) ->> 'can_edit_job', 'false', 'el Auditor, tampoco eso');
select is(pg_temp.state(401, 401) ->> 'can_edit_job', 'false', 'ni lo propio');

-- Los datos.
select is(pg_temp.save(404, 409, '{"profile": {"job_title": " Cocinera de pastas ", "area_id": "00000000-0000-4000-8000-000000000312"}}', 'Cambió de puesto'),
  'applied: Cambios guardados.', 'el Gerente cambia el puesto y el área');
select is((select job_title || '/' || area_id from core.user_profiles where id = pg_temp.u(409)),
  'Cocinera de pastas/00000000-0000-4000-8000-000000000312', 'quedan guardados');
select ok(exists (select 1 from audit.audit_events where table_name = 'user_profiles' and record_id = pg_temp.u(409)
                    and reason = 'Cambió de puesto' and actor_user_id = pg_temp.u(404)), 'con quién y por qué en la auditoría');
select is(pg_temp.save(404, 409, '{"profile": {"first_name": " "}}'), 'ERROR El nombre y el apellido no pueden quedar vacíos.',
  'el nombre no queda vacío');
select ok(pg_temp.save(404, 409, '{"profile": {"first_name": "Administrador"}}') like 'ERROR Ese nombre se confunde con el sistema%',
  'ni se confunde con el sistema o con un rol');
select ok(pg_temp.save(404, 409, '{"profile": {"email": "otro@ejemplo.test"}}') like 'ERROR %', 'el correo no se edita');
select ok(pg_temp.save(404, 409, '{"profile": {"status": "deactivated"}}') like 'ERROR %', 'el estado tampoco: va por suspender y desactivar');
select is(pg_temp.save(410, 409, '{"profile": {"job_title": "Otro"}}'), 'denied: La persona tiene roles fuera de tu alcance.',
  'el Auditor no edita datos');
select is(pg_temp.denials('core.save_user_sheet'), 1, 'y el rechazo queda en el registro de seguridad');
select is(pg_temp.save(401, 402, '{"profile": {"first_name": "Otro"}}'), 'denied: La persona tiene permisos que vos no tenés.',
  'nadie le cambia el nombre a quien tiene más permisos que uno, ni el Superadministrador');
select is(pg_temp.save(401, 402, '{"profile": {"job_title": "Directora general"}}'), 'applied: Cambios guardados.',
  'el puesto, sí');
select is((select first_name || '/' || job_title from core.user_profiles where id = pg_temp.u(402)), 'Diego/Directora general',
  'y solo cambia eso');
select is(pg_temp.save(401, 405, '{"profile": {"area_id": "00000000-0000-4000-8000-000000000312"}}'), 'applied: Cambios guardados.',
  'y el área de quien trabaja en varios locales');

-- El registro de seguridad no se llena con texto libre (revisión de seguridad, M1) y cada rechazo lleva su grupo (M2).
select ok(pg_temp.save(410, 409, jsonb_build_object('profile', jsonb_build_object(repeat('x', 1000), 'a'))) like 'ERROR %',
  'una clave inventada se rechaza antes de registrar nada');
select is(pg_temp.denials('core.save_user_sheet'), 2, 'y no suma nada al registro');
select is(pg_temp.save(409, 406, '{"profile": {"job_title": "Otro"}}'), 'denied: La persona no existe o no la podés ver.',
  'quien no ve la ficha no la guarda');
select is((select count(*)::int from audit.authentication_security_events where operation = 'core.save_user_sheet'
            and event_type = 'operation_denied' and scope_group_id is null), 0, 'todos los rechazos llevan su grupo');
select is(pg_temp.save(410, 409, jsonb_build_object('roles_add', jsonb_build_array(pg_temp.role_at('cook', 'restaurant', 101, 201)))),
  'denied: No tenés permiso para dar ni quitar roles.', 'quien no da roles en ningún lado se frena antes');
-- Nombres y puestos que imitan a otro (M3).
select is(pg_temp.save(404, 409, jsonb_build_object('profile', jsonb_build_object('first_name', chr(8203) || 'Administrador'))),
  'ERROR El nombre tiene caracteres que no se ven: escribilo de nuevo.', 'ni con un carácter invisible adelante');
select is(pg_temp.save(404, 409, jsonb_build_object('profile', jsonb_build_object('last_name', 'Uno' || chr(10) || 'Dos'))),
  'ERROR El nombre tiene caracteres que no se ven: escribilo de nuevo.', 'ni con un salto de línea');
select is(pg_temp.save(404, 409, jsonb_build_object('profile', jsonb_build_object('last_name', chr(8238) || 'olos'))),
  'ERROR El nombre tiene caracteres que no se ven: escribilo de nuevo.', 'ni dado vuelta');
select ok(pg_temp.save(404, 409, jsonb_build_object('profile', jsonb_build_object('first_name', chr(160) || 'Sistema'))) like 'ERROR Ese nombre se confunde%',
  'ni con un espacio duro adelante');
select ok(pg_temp.save(404, 409, '{"profile": {"first_name": ".Super Administrador"}}') like 'ERROR Ese nombre se confunde%',
  'ni con un punto adelante o separado');
select is(pg_temp.save(404, 409, jsonb_build_object('profile', jsonb_build_object('last_name', 'Operadora' || chr(160) || 'Sosa'))),
  'applied: Cambios guardados.', 'un espacio duro pegado de Excel no molesta');
select is((select last_name from core.user_profiles where id = pg_temp.u(409)), 'Operadora Sosa', 'y se guarda como espacio');
select ok(pg_temp.save(404, 409, jsonb_build_object('profile', jsonb_build_object('first_name', chr(65313) || 'dministrador'))) like 'ERROR Ese nombre se confunde%',
  'ni con letras que se le parecen');
select ok(pg_temp.save(404, 409, '{"profile": {"job_title": "Superadministrador"}}') like 'ERROR Ese puesto se confunde%',
  'el puesto no imita al sistema');
select is(pg_temp.save(404, 409, '{"profile": {"job_title": "Jefe de Cocina"}}'), 'applied: Cambios guardados.',
  'pero sí se llama como un rol');
select is(pg_temp.save(404, 409, '{"profile": {"job_title": "Cocinera de pastas", "last_name": "Operadora Ñandú"}}'),
  'applied: Cambios guardados.', 'un apellido con tilde y ñ va bien');
select ok(exists (select 1 from core.notifications where recipient_user_id = pg_temp.u(409) and kind = 'account_changed'
                    and title = 'Cambiaron tu nombre' and body like '%Gonzalo Gerente%'), 'y a la persona le llega el aviso con quién fue');

-- Motivo, sello y cambios.
select is(pg_temp.save(404, 409, '{"profile": {"job_title": "X1"}}', ' '), 'ERROR Escribí el motivo de los cambios (de 3 a 500 caracteres).', 'sin motivo no se guarda');
select is(pg_temp.save(404, 409, '{}'), 'ERROR No hay cambios para guardar.', 'sin cambios tampoco');
select is(pg_temp.q(pg_temp.u(404), format('select core.save_user_sheet(%L, ''viejo'', ''{"profile": {"job_title": "X1"}}'', ''Prueba'')::text', pg_temp.u(409))),
  'ERROR Otra persona cambió esta ficha mientras la editabas: recargá la página para ver sus cambios.',
  'si alguien la cambió en el medio, se rechaza');

-- Los roles, con sus reglas de siempre.
select is(pg_temp.save(404, 404, jsonb_build_object('roles_add', jsonb_build_array(pg_temp.role_at('cook', 'restaurant', 101, 201)))),
  'denied: No podés hacer esto sobre tu propia cuenta.', 'nadie se da roles a sí mismo, tampoco por la ficha');
select is(pg_temp.save(403, 409, jsonb_build_object('roles_add', jsonb_build_array(pg_temp.role_at('cook', 'restaurant', 102, 203)))),
  'denied: No tenés permiso para dar roles en ese lugar.', 'no se dan roles en otra marca');
-- Todo o nada: los datos que iban en el mismo guardado no quedan, y el rechazo se registra igual.
select is(pg_temp.save(403, 409, jsonb_build_object('profile', jsonb_build_object('job_title', 'No tiene que quedar'),
    'roles_add', jsonb_build_array(pg_temp.role_at('cook', 'restaurant', 102, 203)))),
  'denied: No tenés permiso para dar roles en ese lugar.', 'un rol rechazado rechaza todo el guardado');
select is((select job_title from core.user_profiles where id = pg_temp.u(409)), 'Cocinera de pastas', 'no queda nada a medias');
select is(pg_temp.denials('core.assign_role'), 2, 'y cada rechazo queda registrado, como dar un rol');
select is((select scope_brand_id || '/' || scope_restaurant_id || '/' || (detail ->> 'role') from audit.authentication_security_events
            where operation = 'core.assign_role' order by occurred_at desc, id limit 1),
  pg_temp.u(102) || '/' || pg_temp.u(203) || '/cook', 'con el rol y el lugar');
-- Cambiar un rol por otro que espera aprobación no la deja sin rol (db-reviewer, G1).
select is(pg_temp.save(403, 406, jsonb_build_object(
    'roles_remove', (select jsonb_agg(id) from core.user_role_assignments where user_id = pg_temp.u(406) and deleted_at is null),
    'roles_add', jsonb_build_array(pg_temp.role_at('executive_chef', 'brand', 101)))),
  'ERROR El rol nuevo espera una aprobación: guardalo primero y, cuando lo aprueben, quitá el anterior.',
  'no se quita un rol por otro que todavía no está dado');
select is((select count(*)::int from core.user_role_assignments where user_id = pg_temp.u(406) and deleted_at is null), 1,
  'y conserva el que tenía');
-- Otro Superadministrador: ni sus datos ni sus sesiones sin Dirección.
update core.user_role_assignments set deleted_at = now() where user_id = pg_temp.u(407);
insert into core.user_role_assignments (user_id, role_id, scope_type, group_id)
  select pg_temp.u(407), id, 'group', pg_temp.u(1) from core.roles where code = 'superadmin';
select is(pg_temp.save(401, 407, '{"profile": {"job_title": "Otro"}}'), 'denied: A esta persona solo la cambia Dirección General.',
  'un Superadministrador no le cambia el puesto a otro');
select is(pg_temp.save(401, 407, '{"profile": {"first_name": "Otro"}}') like 'denied: %', true, 'ni el nombre');
select is(pg_temp.save(404, 405, '{"profile": {"job_title": "Otro"}}') like 'denied: %', true,
  'el Gerente no le cambia el puesto a quien trabaja fuera de su local');
select is(pg_temp.q(pg_temp.u(401), format('select core.close_user_sessions(%L, ''Prueba'') ->> ''message''', pg_temp.u(407))),
  'A esta persona solo la cambia Dirección General.', 'ni le cierra las sesiones');
-- Datos raros.
select is(pg_temp.save(404, 409, '{"profile": {"area_id": "00000000-0000-4000-8000-000000000331"}}'),
  'denied: Elegí un área de un local donde trabaja y que administrás.', 'un área de otra marca no');
select is((select detail ->> 'area_id' from audit.authentication_security_events where operation = 'core.save_user_sheet'
            and detail ? 'area_id'), '00000000-0000-4000-8000-000000000331', 'y el rechazo queda registrado');
select is(pg_temp.save(404, 409, '{"profile": {"area_id": "cualquiera"}}'),
  'ERROR Elegí un área de un local donde trabaja y que administrás.', 'ni un área que no es un identificador');
select is(pg_temp.save(404, 409, jsonb_build_object('profile', jsonb_build_object('job_title', repeat('x', 81)))),
  'ERROR El nombre, el apellido y el puesto tienen hasta 80 caracteres.', 'ni un puesto larguísimo');
select is(pg_temp.save(404, 409, '{"profile": {"job_title": {"a": 1}}}'), 'ERROR Revisá los datos: van como texto.', 'ni algo que no es texto');
select is(pg_temp.save(404, 409, '{"profile": {}}'), 'ERROR No hay cambios para guardar.', 'ni un guardado vacío');
select is(pg_temp.save(404, 409, '{"roles_add": [{"scope_type": "group", "group_id": "00000000-0000-4000-8000-000000000001"}]}'),
  'ERROR Elegí el rol y el lugar.', 'ni un rol sin nombre');
-- Los rechazos son los de la persona, no los que otros intentaron sobre ella.
select is(pg_temp.state(401, 407) ->> 'rejected_7d', '0', 'lo que otro intentó sobre su cuenta no cuenta como suyo');
select is(pg_temp.save(404, 406, jsonb_build_object('roles_remove', jsonb_build_array(
    (select id from core.user_role_assignments where user_id = pg_temp.u(409) and deleted_at is null limit 1)))),
  'denied: Ese rol no es de esta persona.', 'no se quita un rol de otra persona por esta ficha');
select is((select count(*)::int from audit.authentication_security_events where operation = 'core.revoke_role'
            and event_type = 'operation_denied' and user_id = pg_temp.u(406)), 1, 'y el intento queda registrado');
select is((select count(*)::int from core.user_role_assignments where user_id = pg_temp.u(409) and deleted_at is null), 1,
  'sin tocar el de la otra persona');
-- Un rol que aprueba queda pendiente; los datos del mismo guardado quedan guardados.
select is(pg_temp.save(403, 406, jsonb_build_object('profile', jsonb_build_object('job_title', 'Chef de marca'),
    'roles_add', jsonb_build_array(pg_temp.role_at('executive_chef', 'brand', 101)))),
  'pending_approval: Guardado. Un cambio de rol queda pendiente hasta que otra persona lo apruebe.',
  'un rol que aprueba espera a otra persona');
select is((select job_title || '/' || (select count(*) from core.user_role_assignments a join core.roles r on r.id = a.role_id
                                        where a.user_id = u.id and r.code = 'executive_chef' and a.deleted_at is null)
             from core.user_profiles u where u.id = pg_temp.u(406)), 'Chef de marca/0', 'los datos quedan y el rol todavía no');
-- Dar y quitar roles comunes, en un guardado.
select is(pg_temp.save(403, 409, jsonb_build_object(
    'roles_remove', (select jsonb_agg(id) from core.user_role_assignments where user_id = pg_temp.u(409) and deleted_at is null),
    'roles_add', jsonb_build_array(pg_temp.role_at('cook', 'restaurant', 101, 201)))),
  'applied: Cambios guardados.', 'se quita y se da un rol en un guardado');
select is((select count(*)::int from core.user_role_assignments where user_id = pg_temp.u(409) and deleted_at is null), 1,
  'y queda el nuevo');

-- Cerrar las sesiones de otra persona.
insert into auth.sessions (id, user_id, created_at, updated_at) values
  (gen_random_uuid(), pg_temp.u(409), now(), now()), (gen_random_uuid(), pg_temp.u(409), now(), now());
select ok((pg_temp.state(404, 409) ->> 'sessions')::int >= 2, 'quien la administra ve cuántas sesiones tiene abiertas');
select ok(pg_temp.q(pg_temp.u(404), format('select core.close_user_sessions(%L, ''Perdió el celular'') ->> ''message''', pg_temp.u(409)))
            ~ '^Se cerraron [0-9]+ sesiones\.$', 'el Gerente cierra las sesiones de la cocinera');
select is((select count(*)::int from auth.sessions where user_id = pg_temp.u(409)), 0, 'y no queda ninguna');
select ok(exists (select 1 from audit.authentication_security_events where event_type = 'sessions_closed'
                    and user_id = pg_temp.u(409) and reason = 'Perdió el celular'), 'con su motivo en el registro de seguridad');
select is((select status::text from core.user_profiles where id = pg_temp.u(409)), 'active', 'sin suspender la cuenta');
select ok(exists (select 1 from core.notifications where recipient_user_id = pg_temp.u(409) and kind = 'account_changed'
                    and title = 'Cerraron tus sesiones' and body like 'Gonzalo Gerente%'), 'y le llega el aviso con quién fue');
select is(pg_temp.q(pg_temp.u(410), format('select core.close_user_sessions(%L, ''Prueba'') ->> ''result''', pg_temp.u(409))), 'denied',
  'el Auditor no las cierra');
select is(pg_temp.q(pg_temp.u(404), format('select core.close_user_sessions(%L, ''Prueba'') ->> ''result''', pg_temp.u(404))), 'denied',
  'las propias van en Mi cuenta');
select is(pg_temp.q(pg_temp.u(401), format('select core.close_user_sessions(%L, ''Prueba'') ->> ''result''', pg_temp.u(402))), 'denied',
  'las de Dirección, tampoco');
select is(pg_temp.q(pg_temp.u(404), format('select core.close_user_sessions(%L, '' '')::text', pg_temp.u(409))),
  'ERROR Escribí el motivo (de 3 a 500 caracteres).', 'sin motivo no se cierran');
select is(pg_temp.q(pg_temp.u(404), format('select core.close_user_sessions(%L, ''Prueba'') ->> ''message''', pg_temp.u(409))),
  'No tenía sesiones abiertas.', 'y si no hay ninguna, lo dice');

select * from finish();
rollback;
