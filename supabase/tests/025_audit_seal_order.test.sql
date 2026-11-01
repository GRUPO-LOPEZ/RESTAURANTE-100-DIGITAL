-- Sellado continuo (ADR-0028): si un evento con número más bajo tiene una hora más nueva, el sellado se
-- detiene ahí y no lo saltea. Antes lo salteaba, el sello quedaba con un hueco y la verificación daba
-- "alterado" sin que nadie hubiera tocado nada. Vale para la auditoría y para el registro de seguridad.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(14);

-- Los sellos solo los maneja audit_owner, que no ve pgTAP: los resultados pasan por tablas temporales.
create temporary table results (step text primary key, sealed int, last_seq bigint, valid boolean);
grant insert, update, select on results to audit_owner;
create temporary table marks (k text primary key, seq bigint);
grant insert, select on marks to audit_owner;

-- ---------------------------------------------------------------------------
-- Registro de seguridad
-- ---------------------------------------------------------------------------
set local role audit_owner;
-- Primero se sella todo lo que ya había. (La verificación recorre todos los sellos de la base: después de
-- un db reset, todos son del código nuevo.)
insert into results select 'sec_previous', s.event_count, s.last_sequence, null
  from audit.seal_security_events(interval '-1 minute') s;
-- Con solo eventos nuevos sin sellar, no se crea ningún sello.
insert into audit.authentication_security_events (event_type, operation, reason, scope_group_id)
values ('login_succeeded', 'auth.login', 'Prueba de sellado (solo nuevo)', '00000000-0000-4000-8000-000000000001');
insert into results select 'sec_only_new', count(*), null, null
  from (select audit.seal_security_events(interval '10 minutes') as s) x where x.s is not null;
insert into results select 'sec_previous_2', s.event_count, s.last_sequence, null
  from audit.seal_security_events(interval '-1 minute') s;
-- Dos eventos viejos, uno nuevo y dos viejos, en ese orden de secuencia.
insert into audit.authentication_security_events (event_type, occurred_at, operation, reason, scope_group_id)
select 'login_succeeded', case when n = 3 then now() else now() - interval '1 day' end, 'auth.login', 'Prueba de sellado ' || n,
       '00000000-0000-4000-8000-000000000001'
  from generate_series(1, 5) n
 order by n;
insert into marks
select 'sec_new', min(sequence_number) from audit.authentication_security_events where reason = 'Prueba de sellado 3';
insert into results
select 'sec_first', s.event_count, s.last_sequence, null
  from audit.seal_security_events(interval '10 minutes') s;
update results set valid = (select bool_and(is_valid) from audit.verify_security_seals()) where step = 'sec_first';
insert into results
select 'sec_rest', s.event_count, s.last_sequence, null
  from audit.seal_security_events(interval '-1 minute') s;
update results set valid = (select bool_and(is_valid) from audit.verify_security_seals()) where step = 'sec_rest';
reset role;

select is((select sealed from results where step = 'sec_only_new'), 0, 'con solo eventos nuevos no se crea ningún sello');
select is((select sealed from results where step = 'sec_first'), 2, 'el sellado toma los dos eventos viejos del principio');
select is((select last_seq from results where step = 'sec_first'), (select seq - 1 from marks where k = 'sec_new'),
  'y se detiene justo antes del nuevo, sin saltearlo');
select ok((select valid from results where step = 'sec_first'), 'el sello verifica: no hay falsa alarma');
select is((select sealed from results where step = 'sec_rest'), 3, 'la corrida siguiente sella el resto');
select ok((select valid from results where step = 'sec_rest'), 'y todo sigue verificando');

-- ---------------------------------------------------------------------------
-- Auditoría (los eventos los genera el trigger; para fecharlos hacia atrás, audit_owner levanta la
-- protección un momento, como en la prueba de ataque de la 020)
-- ---------------------------------------------------------------------------
set local role audit_owner;
insert into results select 'aud_previous', s.event_count, s.last_sequence, null
  from audit.seal_events(interval '-1 minute') s;
reset role;
select core.set_change_context('Prueba de sellado', 'maintenance');
update org.groups set name = 'Grupo prueba de sellado 1' where id = '00000000-0000-4000-8000-000000000001';
update org.groups set name = 'Grupo prueba de sellado 2' where id = '00000000-0000-4000-8000-000000000001';
update org.groups set name = 'Grupo prueba de sellado 3' where id = '00000000-0000-4000-8000-000000000001';
update org.groups set name = 'Grupo prueba de sellado 4' where id = '00000000-0000-4000-8000-000000000001';
update org.groups set name = 'Grupo prueba de sellado 5' where id = '00000000-0000-4000-8000-000000000001';
set local role audit_owner;
insert into marks
select 'aud_' || row_number() over (order by sequence_number), sequence_number
  from audit.audit_events where reason = 'Prueba de sellado' and table_name = 'groups';
alter table audit.audit_events disable trigger audit_events_no_update_delete;
update audit.audit_events set occurred_at = occurred_at - interval '1 day'
 where sequence_number in (select seq from marks where k in ('aud_1', 'aud_2', 'aud_4', 'aud_5'));
alter table audit.audit_events enable trigger audit_events_no_update_delete;
insert into results
select 'aud_first', s.event_count, s.last_sequence, null
  from audit.seal_events(interval '10 minutes') s;
update results set valid = (select bool_and(is_valid) from audit.verify_seals()) where step = 'aud_first';
insert into results
select 'aud_rest', s.event_count, s.last_sequence, null
  from audit.seal_events(interval '-1 minute') s;
update results set valid = (select bool_and(is_valid) from audit.verify_seals()) where step = 'aud_rest';
reset role;

select is((select count(*)::int from marks where k like 'aud_%'), 5, 'cinco cambios dejaron cinco eventos');
select is((select sealed from results where step = 'aud_first'), 2, 'la auditoría sella los dos viejos del principio');
select is((select last_seq from results where step = 'aud_first'), (select seq from marks where k = 'aud_2'),
  'y se detiene antes del evento nuevo');
select ok((select valid from results where step = 'aud_first'), 'el sello de la auditoría verifica');
select is((select sealed from results where step = 'aud_rest'), 3, 'la corrida siguiente sella los otros tres');
select ok((select valid from results where step = 'aud_rest'), 'y después de sellar el resto, también');

-- Un evento con fecha futura frenaría el sellado para siempre: no entra, ni siquiera a mano.
set local role audit_owner;
create temporary table future_try (target text primary key, result text);
do $$
begin
  begin
    insert into audit.authentication_security_events (event_type, occurred_at, operation, reason, scope_group_id)
    values ('login_succeeded', now() + interval '10 years', 'auth.login', 'Futuro', '00000000-0000-4000-8000-000000000001');
    insert into future_try values ('seguridad', 'entró');
  exception when check_violation then
    insert into future_try values ('seguridad', sqlerrm);
  end;
end
$$;
grant select on future_try to postgres;
reset role;
select is((select result from future_try where target = 'seguridad'), 'Un evento de auditoría no puede tener fecha futura.',
  'un evento de seguridad con fecha futura se rechaza');
select ok(exists (select 1 from pg_trigger where tgname = 'reject_future_event' and tgrelid = 'audit.audit_events'::regclass),
  'la auditoría tiene el mismo control');

select * from finish();
rollback;
