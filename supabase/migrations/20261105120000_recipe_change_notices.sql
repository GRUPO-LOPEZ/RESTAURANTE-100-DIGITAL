-- A quién se avisa cuando cambia una preparación: respuesta 5 de Soy (ADR-0026). Reemplaza la regla
-- provisoria de ADR-0025 (Compras y Dirección de todo el grupo).
--
-- "De todos los restaurantes que usan ese producto o receta": se avisa a quien puede publicar cada
-- plato afectado (el Chef) y a Compras, Dirección General y Gerencia de cada local que usa alguno de esos
-- platos (asignación vigente). Una persona de grupo los cubre a todos; una de marca, a los de su marca;
-- una de local, al suyo. Nunca a quien aprobó el cambio.

create or replace function recipes.notify_recipe_changed(p_version_id uuid, p_approver uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r recipes.recipes;
  v_v recipes.recipe_versions;
begin
  select * into v_v from recipes.recipe_versions where id = p_version_id;
  select * into v_r from recipes.recipes where id = v_v.recipe_id;
  if not exists (select 1 from recipes.recipe_components c
                   join recipes.recipe_versions pv on pv.id = c.recipe_version_id and pv.status = 'published'
                   join recipes.recipes p on p.id = pv.recipe_id and p.deleted_at is null and p.is_active
                  where c.sub_recipe_id = v_r.id and c.deleted_at is null) then
    return;
  end if;
  -- Alcances distintos de los platos afectados (para el Chef) y locales que los usan hoy (para Compras,
  -- Dirección y Gerencia): pocas filas aunque la usen miles de platos, así el permiso se pregunta pocas
  -- veces (revisión de base, M3). El aviso no cuenta platos: no hace falta saber de los de otros locales.
  insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
  with dishes as materialized (
    select distinct p.id, p.scope_type::text::core.scope_type as scope_type, p.brand_id, p.restaurant_id
      from recipes.recipe_components c
      join recipes.recipe_versions pv on pv.id = c.recipe_version_id and pv.status = 'published'
      join recipes.recipes p on p.id = pv.recipe_id and p.deleted_at is null and p.is_active
     where c.sub_recipe_id = v_r.id and c.deleted_at is null),
  scopes as materialized (
    select distinct scope_type, brand_id, restaurant_id from dishes),
  places as materialized (
    select distinct rest.id as restaurant_id, rest.brand_id
      from recipes.recipe_assignments a
      join dishes d on d.id = a.recipe_id
      join org.restaurants rest on rest.id = a.restaurant_id and rest.deleted_at is null
     where a.deleted_at is null and a.valid_from <= recipes.today()
       and (a.valid_to is null or a.valid_to > recipes.today()))
  select u.user_id, v_r.group_id, 'recipe_changed',
         format('Cambió «%s» (v%s)', v_r.name, v_v.version_number),
         'Las recetas que la usan ya usan la versión nueva. Revisá si hace falta ajustar algo.',
         '/recetas/' || v_r.id
    from (select distinct a.user_id
            from core.user_role_assignments a
           where a.group_id = v_r.group_id and a.deleted_at is null
             and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())) u
   where u.user_id is distinct from p_approver
     and (exists (select 1 from scopes f
                   where core.user_has_permission_for_scope(u.user_id, 'recipes.publish', f.scope_type, v_r.group_id,
                                                            f.brand_id, f.restaurant_id))
          or exists (select 1 from places l
                      where core.user_has_role_for_scope(u.user_id, array['purchasing', 'general_management', 'restaurant_manager'],
                                                         'restaurant', v_r.group_id, l.brand_id, l.restaurant_id)));
end
$$;
comment on function recipes.notify_recipe_changed(uuid, uuid) is
  'Interna: avisa que cambió una preparación a quien puede publicar cada plato que la usa y a Compras, Dirección General y Gerencia de los locales que usan esos platos (respuesta 5 de Soy, ADR-0026), salvo a quien la aprobó.';
