-- Arreglo de la Fase 1 (ADR-0028): el sellado de la auditoría no deja huecos en la secuencia.
--
-- Antes, seal_events y seal_security_events sellaban los eventos con más de p_min_age de antigüedad y
-- salteaban los más nuevos aunque quedaran en el medio de la secuencia. El sello guarda hasta qué número
-- llega y cuántos eventos tiene; la verificación recorre todo lo que hay hasta ese número. Con un evento
-- nuevo salteado en el medio, la cuenta no coincidía y el sello daba inválido: una falsa alarma de
-- "auditoría alterada". Pasa cuando un evento con número más bajo tiene una hora más nueva (transacciones
-- que se cruzan, o el seed, que carga eventos con fechas viejas).
--
-- Ahora el sellado toma solo el tramo continuo: recorre en orden y se detiene en el primer evento
-- demasiado nuevo. Lo demás se sella en la corrida siguiente. Las verificaciones no cambian.

set role audit_owner;

create or replace function audit.seal_events(p_min_age interval default interval '10 minutes')
returns audit.audit_seals
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_last    audit.audit_seals;
  v_hash    bytea;
  v_prev    bytea;
  v_first   bigint;
  v_lastseq bigint;
  v_count   int := 0;
  v_event   audit.audit_events;
  v_seal    audit.audit_seals;
begin
  lock table audit.audit_seals in exclusive mode;

  select * into v_last from audit.audit_seals order by id desc limit 1;
  v_prev := coalesce(v_last.chain_hash, audit.genesis_hash());
  v_hash := v_prev;

  for v_event in
    select * from audit.audit_events
     where sequence_number > coalesce(v_last.last_sequence, 0)
     order by sequence_number
  loop
    -- Tramo continuo: en el primer evento demasiado nuevo se corta (sin saltearlo).
    exit when v_event.occurred_at >= now() - p_min_age;
    v_hash := sha256(v_hash || audit.event_digest(v_event));
    v_first := coalesce(v_first, v_event.sequence_number);
    v_lastseq := v_event.sequence_number;
    v_count := v_count + 1;
  end loop;

  if v_count = 0 then
    return null;
  end if;

  insert into audit.audit_seals (first_sequence, last_sequence, event_count, previous_hash, chain_hash)
  values (v_first, v_lastseq, v_count, v_prev, v_hash)
  returning * into v_seal;

  return v_seal;
end
$$;
comment on function audit.seal_events(interval) is
  'Sella el tramo continuo de eventos todavía no sellados, en orden de secuencia, hasta el primero con menos de p_min_age de antigüedad (sin saltearlo). Devuelve el sello nuevo, o nulo si no había nada para sellar.';

create or replace function audit.seal_security_events(p_min_age interval default '00:10:00'::interval)
returns audit.authentication_security_event_seals
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_last    audit.authentication_security_event_seals;
  v_hash    bytea;
  v_prev    bytea;
  v_first   bigint;
  v_lastseq bigint;
  v_count   int := 0;
  v_event   audit.authentication_security_events;
  v_seal    audit.authentication_security_event_seals;
begin
  lock table audit.authentication_security_event_seals in exclusive mode;

  select * into v_last from audit.authentication_security_event_seals order by id desc limit 1;
  v_prev := coalesce(v_last.chain_hash, audit.security_genesis_hash());
  v_hash := v_prev;

  for v_event in
    select * from audit.authentication_security_events
     where sequence_number > coalesce(v_last.last_sequence, 0)
     order by sequence_number
  loop
    -- Tramo continuo: en el primer evento demasiado nuevo se corta (sin saltearlo).
    exit when v_event.occurred_at >= now() - p_min_age;
    v_hash := sha256(v_hash || audit.security_event_digest(v_event));
    v_first := coalesce(v_first, v_event.sequence_number);
    v_lastseq := v_event.sequence_number;
    v_count := v_count + 1;
  end loop;

  if v_count = 0 then
    return null;
  end if;

  insert into audit.authentication_security_event_seals (first_sequence, last_sequence, event_count, previous_hash, chain_hash)
  values (v_first, v_lastseq, v_count, v_prev, v_hash)
  returning * into v_seal;
  return v_seal;
end
$$;
comment on function audit.seal_security_events(interval) is
  'Sella el tramo continuo de eventos de seguridad todavía no sellados, en orden de secuencia, hasta el primero con menos de p_min_age de antigüedad (sin saltearlo).';

-- Un evento con fecha futura frenaría el sellado continuo para siempre, sin aviso (revisión de seguridad,
-- menor 1). Los triggers nunca la ponen (usan now()); se rechaza también a mano.
create function audit.reject_future_event()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.occurred_at > clock_timestamp() + interval '1 minute' then
    raise exception 'Un evento de auditoría no puede tener fecha futura.' using errcode = '23514';
  end if;
  return new;
end
$$;
comment on function audit.reject_future_event() is
  'Trigger (BEFORE INSERT) de audit_events y authentication_security_events: rechaza eventos con fecha futura, que frenarían el sellado.';
revoke execute on function audit.reject_future_event() from public;

create trigger reject_future_event before insert on audit.audit_events
  for each row execute function audit.reject_future_event();
create trigger reject_future_event before insert on audit.authentication_security_events
  for each row execute function audit.reject_future_event();

reset role;
