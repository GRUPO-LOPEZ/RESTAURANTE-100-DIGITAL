-- Fase 1 · M8 (paso previo) — Origen "auth" para los cambios que hace Supabase Auth (el hook de
-- ingreso, ADR-0010). Va en su propia migración: Postgres no deja usar un valor nuevo de un enum
-- en la misma transacción que lo agrega.
set role audit_owner;
alter type audit.change_origin add value if not exists 'auth';
comment on type audit.change_origin is
  'Desde dónde se hizo un cambio: app (la aplicación), edge_function (función de servidor), agent (agente de IA), import (carga masiva), seed (datos de prueba), maintenance (mantenimiento documentado) o auth (Supabase Auth, por ejemplo al ingresar).';
reset role;
