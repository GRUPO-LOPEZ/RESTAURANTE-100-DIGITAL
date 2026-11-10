-- Superadministrador de prueba SIN doble verificación (ADR-0037). TEMPORAL Y SOLO PARA TESTEAR. SOLO DATOS FICTICIOS.
-- Pedido por Joaco el 2026-11-10: el MFA ya se probó y funciona; para testear se necesita entrar sin el código.
--
-- No es una migración ni va en seed.sql: el catálogo del Módulo 0 sigue siendo de 10 roles y la regla de MFA no cambia
-- para nadie más. Se corre a pedido, con psql 15 o más, y se puede correr más de una vez: si ya está, no cambia nada.
--   Local:    npm run db:test-admin   (después de cada npm run db:reset)
--   Staging:  Actions → Publicar en staging → "Crear el superadministrador de prueba"
--
-- Contraseña por variable de entorno (TEST_ADMIN_PASSWORD), nunca escrita en este archivo.
-- Se niega a correr si la base tiene otro grupo que no sea el ficticio de prueba: en producción no hace nada.
-- Lo que hace y lo que no, y cómo se quita: ADR-0037.

\set ON_ERROR_STOP on

\getenv test_admin_password TEST_ADMIN_PASSWORD
\if :{?test_admin_password}
\else
  do $$ begin raise exception 'Falta TEST_ADMIN_PASSWORD (la contraseña del superadministrador de prueba).'; end $$;
\endif
\getenv run_id GITHUB_RUN_ID
\if :{?run_id}
  \set change_reason 'Superadministrador de prueba sin doble verificación (ADR-0037, temporal; corrida ' :run_id ' de GitHub Actions)'
\else
  \set change_reason 'Superadministrador de prueba sin doble verificación (ADR-0037, temporal; a mano)'
\endif

-- La única sentencia que lleva la contraseña, y es una consulta (no un INSERT, que Postgres puede registrar con su
-- texto si falla). Valida y calcula el hash con el costo de Supabase Auth (10); de acá en adelante solo se usa el hash.
select length(:'test_admin_password') >= 16
         and :'test_admin_password' ~ '[A-Za-z]'
         and :'test_admin_password' ~ '[0-9]' as password_ok,
       extensions.crypt(:'test_admin_password', extensions.gen_salt('bf', 10)) as test_admin_hash \gset
\unset test_admin_password
\if :password_ok
\else
  do $$ begin raise exception 'TEST_ADMIN_PASSWORD tiene que tener al menos 16 caracteres, con letras y números.'; end $$;
\endif

begin;

-- Solo sobre una base cuyo único grupo es el ficticio de prueba (local y staging). Con cualquier otro grupo, no corre.
do $$
begin
  if not exists (select 1 from org.groups where id = '00000000-0000-4000-8000-000000000001')
     or exists (select 1 from org.groups where id <> '00000000-0000-4000-8000-000000000001') then
    raise exception 'Esta base no es solo la del grupo ficticio de prueba: el superadministrador de prueba no se crea acá.';
  end if;
end
$$;

-- El motivo y el origen quedan en la auditoría de todo lo que sigue (misma transacción).
select 1 as change_context_set
  from (select core.set_change_context(:'change_reason', 'maintenance')) as x \gset

-- El rol de prueba: los mismos permisos que el Superadministrador, sin doble verificación.
insert into core.roles (code, name, description, requires_mfa)
select 'superadmin_test', 'Superadministrador de prueba',
       'TEMPORAL (ADR-0037): los permisos del Superadministrador, sin doble verificación. Solo para testear, nunca en producción. No asignar a nadie más.',
       false
 where not exists (select 1 from core.roles where code = 'superadmin_test' and deleted_at is null);

insert into core.role_permissions (role_id, permission_id)
select t.id, rp.permission_id
  from core.roles t
  join core.roles s on s.code = 'superadmin' and s.deleted_at is null
  join core.role_permissions rp on rp.role_id = s.id and rp.deleted_at is null
 where t.code = 'superadmin_test' and t.deleted_at is null
   and not exists (select 1 from core.role_permissions x
                    where x.role_id = t.id and x.permission_id = rp.permission_id and x.deleted_at is null);

-- La persona (el perfil y el actor los crea el trigger de alta, como en el seed). Sin código MFA registrado.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select '00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-000000000420', 'authenticated', 'authenticated',
       'superadmin.prueba@ejemplo.test', :'test_admin_hash', now(),
       '{"provider": "email", "providers": ["email"]}',
       jsonb_build_object('first_name', 'Super', 'last_name', 'Prueba (sin MFA)'),
       now(), now(), '', '', '', ''
 where not exists (select 1 from auth.users where id = '00000000-0000-4000-8000-000000000420');

insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), '00000000-0000-4000-8000-000000000420', '00000000-0000-4000-8000-000000000420', 'email',
       jsonb_build_object('sub', '00000000-0000-4000-8000-000000000420', 'email', 'superadmin.prueba@ejemplo.test',
                          'email_verified', true),
       now(), now(), now()
 where not exists (select 1 from auth.identities where user_id = '00000000-0000-4000-8000-000000000420');

insert into core.user_memberships (user_id, group_id)
select '00000000-0000-4000-8000-000000000420', '00000000-0000-4000-8000-000000000001'
 where not exists (select 1 from core.user_memberships
                    where user_id = '00000000-0000-4000-8000-000000000420'
                      and group_id = '00000000-0000-4000-8000-000000000001');

insert into core.user_role_assignments (user_id, role_id, scope_type, group_id)
select '00000000-0000-4000-8000-000000000420', r.id, 'group', '00000000-0000-4000-8000-000000000001'
  from core.roles r
 where r.code = 'superadmin_test' and r.deleted_at is null
   and not exists (select 1 from core.user_role_assignments a
                    where a.user_id = '00000000-0000-4000-8000-000000000420' and a.role_id = r.id and a.deleted_at is null);

commit;

\echo 'Listo: superadmin.prueba@ejemplo.test (Superadministrador de prueba, sin doble verificación).'
