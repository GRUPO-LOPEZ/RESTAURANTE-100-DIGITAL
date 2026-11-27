-- Listas de precios, parte D de las correcciones de Compras (ADR-0071): versiones, anulación, controles antes de
-- aceptar (variación, umbral de Dirección, «Revisar» a 10 veces y precio por unidad de uso), el artículo recordado y
-- los archivos de Excel y CSV. Los precios de lista siguen sin tocar costos (ADR-0052, caso 10).

-- ---------------------------------------------------------------------------
-- 1. Versiones y anulación
-- ---------------------------------------------------------------------------
alter table purchasing.price_lists
  add column version             integer not null default 1,
  add column previous_version_id uuid,
  add column voided_reason       text,
  add column voided_at           timestamptz,
  add column voided_by           uuid references core.actors (id) on delete restrict,
  add constraint price_lists_version_check check (version between 1 and 999),
  add constraint price_lists_previous_fkey foreign key (previous_version_id, group_id)
    references purchasing.price_lists (id, group_id) on delete restrict,
  add constraint price_lists_previous_check check ((version = 1) = (previous_version_id is null)),
  add constraint price_lists_voided_check check ((status = 'voided')
                                                 = (voided_reason is not null and voided_at is not null)),
  add constraint price_lists_voided_reason_check check (voided_reason is null
                                                        or length(btrim(voided_reason)) between 3 and 500);
-- Una recibida no tiene aceptación; una aceptada o reemplazada, sí; una anulada puede venir de cualquiera de las dos.
alter table purchasing.price_lists drop constraint price_lists_accepted_check;
alter table purchasing.price_lists add constraint price_lists_accepted_check check (
  (status = 'received' and accepted_at is null and accepted_by is null)
  or (status in ('accepted', 'replaced') and accepted_at is not null)
  or status = 'voided');
-- Una lista se corrige una sola vez: la corrección de la corrección sale de la versión nueva. Una corrección anulada
-- no cuenta (si se anula la versión 2 y vuelve la 1, la 1 se puede corregir de nuevo).
create unique index price_lists_previous_key on purchasing.price_lists (previous_version_id)
  where previous_version_id is not null and status <> 'voided';
create index price_lists_previous_fk_idx on purchasing.price_lists (previous_version_id, group_id)
  where previous_version_id is not null;
create index price_lists_voided_by_idx on purchasing.price_lists (voided_by) where voided_by is not null;
comment on column purchasing.price_lists.version is
  'Versión de la lista: 1 la cargada; 2, 3… sus correcciones (cada una con motivo; la anterior queda reemplazada).';
comment on column purchasing.price_lists.previous_version_id is 'La versión que esta corrige (vacío en la versión 1).';
comment on column purchasing.price_lists.voided_reason is 'Por qué se anuló (una lista cargada por error no se borra).';
comment on column purchasing.price_lists.voided_at is 'Cuándo se anuló.';
comment on column purchasing.price_lists.voided_by is 'Quién la anuló.';

-- ---------------------------------------------------------------------------
-- 2. Los controles de un renglón (una sola regla para la carga y la ficha)
-- ---------------------------------------------------------------------------
-- La variación contra el neto anterior, si pasa el umbral de Dirección (costing.price_settings, 15 % por defecto),
-- «Revisar» si es 10 veces mayor o menor, y el precio por unidad de uso del envase (por kg o por litro si el
-- contenido viene en gramos o mililitros).
create function purchasing.price_line_check(p_group_id uuid, p_product_id uuid, p_net numeric, p_previous numeric)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with t as (
    select coalesce((select s.approval_variation_pct from costing.price_settings s
                      where s.group_id = p_group_id and s.deleted_at is null), 15) as threshold),
  u as (
    select p.units_per_package * p.content_per_unit as content, un.code, un.abbreviation
      from catalog.purchase_products p
      left join catalog.units un on un.id = p.content_unit_id
     where p.id = p_product_id),
  change as (
    select case when p_previous > 0 and p_net is not null then round(100 * (p_net / p_previous - 1), 2) end as pct)
  select jsonb_build_object(
    'change_pct', c.pct,
    -- Solo las subas (decisión 19 de Soy: «las subas que pasan el umbral de Dirección se resaltan»); una baja no se
    -- resalta. Distinto del umbral de costing, que mira las dos direcciones para pedir la aprobación de Dirección.
    'over_threshold', coalesce(c.pct > t.threshold, false),
    'review', coalesce(p_previous > 0 and p_net > 0 and (p_net >= 10 * p_previous or p_net * 10 <= p_previous), false),
    'per_use_price', case when u.content > 0 and p_net is not null then
                       round(p_net / u.content * case when u.code in ('g', 'ml') then 1000 else 1 end, 2) end,
    'per_use_unit', case when u.content > 0 then
                      case u.code when 'g' then 'kg' when 'ml' then 'l' else u.abbreviation end end)
    from t cross join change c left join u on true
$$;
comment on function purchasing.price_line_check(uuid, uuid, numeric, numeric) is
  'Interna: los controles de un renglón de lista: variación contra el neto anterior, si pasa el umbral de Dirección del grupo, «Revisar» si es 10 veces mayor o menor, y el precio por unidad de uso del envase.';
revoke execute on function purchasing.price_line_check(uuid, uuid, numeric, numeric) from public, anon, authenticated;

-- El producto de un renglón: el elegido a mano (si es del proveedor) o el reconocido por código o nombre.
create function purchasing.price_line_product(p_supplier_id uuid, p_item jsonb)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if nullif(p_item ->> 'purchase_product_id', '') is not null then
    select p.id into v_id from catalog.purchase_products p
     where p.id = (p_item ->> 'purchase_product_id')::uuid and p.supplier_id = p_supplier_id
       and p.is_active and p.deleted_at is null;
    if v_id is null then
      raise exception 'Ese artículo no es de este proveedor.' using errcode = '22023';
    end if;
    return v_id;
  end if;
  return purchasing.match_article(p_supplier_id, p_item ->> 'sku', p_item ->> 'name');
end
$$;
comment on function purchasing.price_line_product(uuid, jsonb) is
  'Interna: el producto de compra de un renglón de lista: el elegido a mano (controlando que sea del proveedor) o el que reconoce purchasing.match_article por código o nombre.';
revoke execute on function purchasing.price_line_product(uuid, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Cargar los renglones (lo comparten la carga y la corrección)
-- ---------------------------------------------------------------------------
create function purchasing.add_price_list_items(p_list purchasing.price_lists, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item     jsonb;
  v_order    integer := 0;
  v_product  uuid;
  v_unmapped uuid;
  v_new      integer := 0;
  v_queued   integer := 0;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La lista no tiene renglones.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) > 2000 then
    raise exception 'Una lista va hasta 2000 renglones.' using errcode = '22023';
  end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    perform org.check_keys(v_item, array['name', 'sku', 'package_hint', 'list_price', 'bonus1_pct', 'bonus2_pct',
                                         'bonus_per_unit_amount', 'vat_rate', 'includes_vat', 'purchase_product_id']);
    v_order := v_order + 1;
    if nullif(btrim(v_item ->> 'name'), '') is null then
      raise exception 'Al renglón % le falta el nombre del artículo.', v_order using errcode = '23514';
    end if;
    v_product := purchasing.price_line_product(p_list.supplier_id, v_item);
    v_unmapped := null;
    if v_product is null then
      -- Primero lo pendiente; si el chef ya lo descartó, el renglón queda con ese artículo y no vuelve a la cola.
      select id into v_unmapped from purchasing.unmapped_articles
       where supplier_id = p_list.supplier_id and normalized_name = purchasing.normalize_name(v_item ->> 'name')
         and status in ('pending', 'discarded') and deleted_at is null
       order by status = 'pending' desc, resolved_at desc nulls first
       limit 1;
      if v_unmapped is null then
        insert into purchasing.unmapped_articles (group_id, supplier_id, raw_name, supplier_sku, package_hint,
                                                  found_in, source_id)
        values (p_list.group_id, p_list.supplier_id, btrim(v_item ->> 'name'),
                purchasing.normalize_sku(v_item ->> 'sku'), nullif(btrim(v_item ->> 'package_hint'), ''),
                'price_list', p_list.id)
        returning id into v_unmapped;
        v_new := v_new + 1;
      end if;
      if (select status from purchasing.unmapped_articles where id = v_unmapped) = 'pending' then
        v_queued := v_queued + 1;
      end if;
    end if;
    insert into purchasing.price_list_items (group_id, price_list_id, line_order, purchase_product_id,
                                             unmapped_article_id, raw_name, supplier_sku, list_price, bonus1_pct,
                                             bonus2_pct, bonus_per_unit_amount, vat_rate, includes_vat)
    values (p_list.group_id, p_list.id, v_order, v_product, v_unmapped, btrim(v_item ->> 'name'),
            purchasing.normalize_sku(v_item ->> 'sku'), (v_item ->> 'list_price')::numeric,
            coalesce((v_item ->> 'bonus1_pct')::numeric, 0), coalesce((v_item ->> 'bonus2_pct')::numeric, 0),
            coalesce((v_item ->> 'bonus_per_unit_amount')::numeric, 0), (v_item ->> 'vat_rate')::numeric,
            coalesce((v_item ->> 'includes_vat')::boolean, false));
  end loop;
  perform purchasing.notify_unmapped(p_list.supplier_id, v_new);
  return jsonb_build_object('items', v_order, 'queued', v_queued, 'new_unmapped', v_new);
end
$$;
comment on function purchasing.add_price_list_items(purchasing.price_lists, jsonb) is
  'Interna: carga los renglones de una lista (reconoce cada uno o lo manda a la cola de mapeo y avisa al chef). La usan create_price_list y correct_price_list.';
revoke execute on function purchasing.add_price_list_items(purchasing.price_lists, jsonb)
  from public, anon, authenticated;

-- El artículo recordado (decisión 21 de Soy, con la confirmación del chef que decidió Joaco): al aceptar, cada renglón
-- con un producto elegido a mano que no se reconocía por su código o su nombre entra a la cola de mapeo con esa
-- sugerencia. Cuando el chef la confirma, queda como otro nombre y la próxima lista lo reconoce sola.
-- Lo que Compras eligió a mano («Es…») no se recuerda solo: entra a la cola de mapeo con su sugerencia y el chef la
-- confirma (decisión de Joaco, 2026-11-27: el recuerdo también reconoce facturas, que escriben costos).
alter table purchasing.unmapped_articles
  add column suggested_product_id uuid,
  add constraint unmapped_articles_suggested_fkey foreign key (suggested_product_id, group_id)
    references catalog.purchase_products (id, group_id) on delete restrict;
create index unmapped_articles_suggested_idx on purchasing.unmapped_articles (suggested_product_id, group_id)
  where suggested_product_id is not null;
comment on column purchasing.unmapped_articles.suggested_product_id is
  'El producto del proveedor que Compras eligió a mano en una lista («Es…»). Es una sugerencia: queda recordado recién cuando el chef la confirma («Es el mismo que…»).';

create function purchasing.remember_list_aliases(p_list_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  insert into purchasing.unmapped_articles (group_id, supplier_id, raw_name, supplier_sku, found_in, source_id,
                                            suggested_product_id)
  select i.group_id, l.supplier_id, i.raw_name, i.supplier_sku, 'price_list', l.id, i.purchase_product_id
    from purchasing.price_list_items i
    join purchasing.price_lists l on l.id = i.price_list_id
   where i.price_list_id = p_list_id and i.deleted_at is null and i.purchase_product_id is not null
     and purchasing.match_article(l.supplier_id, i.supplier_sku, i.raw_name) is distinct from i.purchase_product_id
  on conflict do nothing;
  get diagnostics v_count = row_count;
  if v_count > 0 then
    perform purchasing.notify_unmapped((select supplier_id from purchasing.price_lists where id = p_list_id), v_count);
  end if;
  return v_count;
end
$$;
comment on function purchasing.remember_list_aliases(uuid) is
  'Interna: manda a la cola de mapeo, con la sugerencia de Compras, cada renglón con un producto elegido a mano que no se reconocía solo, y avisa al chef. Al confirmarla («Es el mismo que…») queda recordado. Se llama al aceptar o corregir una lista.';
revoke execute on function purchasing.remember_list_aliases(uuid) from public, anon, authenticated;

-- Cuántos renglones de una lista están en «Revisar» (10 veces más o menos que la lista anterior).
create function purchasing.price_list_review_count(p_list_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from reporting.v_price_list_changes c
   where c.price_list_id = p_list_id and c.previous_net_price > 0 and c.net_price > 0
     and (c.net_price >= 10 * c.previous_net_price or c.net_price * 10 <= c.previous_net_price)
$$;
comment on function purchasing.price_list_review_count(uuid) is
  'Interna: cuántos renglones de la lista tienen un neto 10 o más veces mayor o menor que el de la lista anterior del proveedor («Revisar»).';
revoke execute on function purchasing.price_list_review_count(uuid) from public, anon, authenticated;

-- La carga: igual que antes (ADR-0052), con los renglones por la función compartida y el producto elegido a mano.
create or replace function purchasing.create_price_list(p_supplier_id uuid, p_received_on date, p_valid_from date,
                                                        p_items jsonb, p_notes text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_s          catalog.suppliers;
  v_list       purchasing.price_lists;
  v_res        jsonb;
  v_constraint text;
  v_message    text;
begin
  select * into v_s from catalog.suppliers where id = p_supplier_id and deleted_at is null;
  if v_s.id is null or not core.has_permission_in_group('purchasing.manage_price_lists', v_s.group_id) then
    return core.deny('purchasing.create_price_list', 'No tenés permiso para cargar listas de este proveedor.', null,
                     jsonb_build_object('supplier_id', p_supplier_id), v_s.group_id);
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo de la carga.' using errcode = '22023';
  end if;
  if p_received_on is null or p_valid_from is null then
    raise exception 'Faltan la fecha en que llegó y desde cuándo vale.' using errcode = '22023';
  end if;
  if p_received_on > recipes.today() then
    raise exception 'La fecha en que llegó la lista no puede ser futura.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  insert into purchasing.price_lists (group_id, supplier_id, received_on, valid_from, notes)
  values (v_s.group_id, v_s.id, p_received_on, p_valid_from, nullif(btrim(p_notes), ''))
  returning * into v_list;
  v_res := purchasing.add_price_list_items(v_list, p_items);
  return jsonb_build_object('result', 'applied', 'price_list_id', v_list.id) || v_res;
exception
  when unique_violation or check_violation or foreign_key_violation or not_null_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    perform purchasing.raise_price_list_error(sqlstate, v_constraint, v_message);
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Revisá los números de la lista: precios, bonificaciones e IVA van con números y en su rango.'
      using errcode = '22023';
end
$$;

-- Aceptar: además de lo de antes, pide confirmar los renglones en «Revisar» y recuerda los artículos.
drop function purchasing.accept_price_list(uuid, text);
create function purchasing.accept_price_list(p_id uuid, p_reason text, p_confirm_review boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_list       purchasing.price_lists;
  v_current    purchasing.price_lists;
  v_review     integer;
  v_constraint text;
  v_message    text;
begin
  select * into v_list from purchasing.price_lists where id = p_id and deleted_at is null;
  if v_list.id is null or not core.has_permission_in_group('purchasing.manage_price_lists', v_list.group_id) then
    return core.deny('purchasing.accept_price_list', 'No tenés permiso para aceptar esta lista.', null,
                     jsonb_build_object('price_list_id', p_id), v_list.group_id);
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo.' using errcode = '22023';
  end if;
  -- Dos aceptaciones del mismo proveedor van de a una.
  perform 1 from catalog.suppliers where id = v_list.supplier_id for update;
  select * into v_list from purchasing.price_lists where id = p_id;
  if v_list.status <> 'received' then
    raise exception 'Esta lista ya no está para aceptar (está %).',
      case v_list.status when 'accepted' then 'aceptada' when 'voided' then 'anulada' else 'reemplazada' end
      using errcode = '23514';
  end if;
  select * into v_current from purchasing.price_lists
   where supplier_id = v_list.supplier_id and status = 'accepted' and deleted_at is null;
  if v_current.id is not null and v_current.valid_from > v_list.valid_from then
    raise exception 'La lista vigente de este proveedor es más nueva (vale desde el %).',
      to_char(v_current.valid_from, 'DD/MM/YYYY') using errcode = '23514';
  end if;
  v_review := purchasing.price_list_review_count(v_list.id);
  if v_review > 0 and not coalesce(p_confirm_review, false) then
    raise exception '%', case when v_review = 1
      then 'Hay 1 precio para revisar (10 veces más o menos que en la lista anterior): confirmalo antes de aceptar.'
      else format('Hay %s precios para revisar (10 veces más o menos que en la lista anterior): confirmalos antes de aceptar.', v_review)
      end using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  if v_current.id is not null then
    update purchasing.price_lists set status = 'replaced' where id = v_current.id;
  end if;
  update purchasing.price_lists
     set status = 'accepted', accepted_at = now(), accepted_by = core.current_actor_id()
   where id = v_list.id;
  return jsonb_build_object('result', 'applied', 'replaced', v_current.id,
                            'remembered', purchasing.remember_list_aliases(v_list.id));
exception when unique_violation or check_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform purchasing.raise_price_list_error(sqlstate, v_constraint, v_message);
end
$$;
comment on function purchasing.accept_price_list(uuid, text, boolean) is
  'Acepta una lista recibida: pasa a ser la vigente del proveedor y la anterior queda reemplazada, en una transacción y con motivo. No acepta una lista más vieja que la vigente; si hay precios en «Revisar» (10 veces más o menos), pide confirmarlos (p_confirm_review). Recuerda los artículos que no se reconocían solos. Pide purchasing.manage_price_lists.';
revoke execute on function purchasing.accept_price_list(uuid, text, boolean) from public, anon;
grant execute on function purchasing.accept_price_list(uuid, text, boolean) to authenticated;

-- Corregir la vigente: una versión nueva, ya aceptada, con la misma vigencia; la anterior queda reemplazada.
create function purchasing.correct_price_list(p_id uuid, p_items jsonb, p_reason text,
                                              p_confirm_review boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old        purchasing.price_lists;
  v_new        purchasing.price_lists;
  v_res        jsonb;
  v_review     integer;
  v_constraint text;
  v_message    text;
begin
  select * into v_old from purchasing.price_lists where id = p_id and deleted_at is null;
  if v_old.id is null or not core.has_permission_in_group('purchasing.manage_price_lists', v_old.group_id) then
    return core.deny('purchasing.correct_price_list', 'No tenés permiso para corregir esta lista.', null,
                     jsonb_build_object('price_list_id', p_id), v_old.group_id);
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí por qué se corrige.' using errcode = '22023';
  end if;
  perform 1 from catalog.suppliers where id = v_old.supplier_id for update;
  select * into v_old from purchasing.price_lists where id = p_id;
  if v_old.status <> 'accepted' then
    raise exception 'Solo se corrige la lista vigente: una recibida se corrige cargándola de nuevo.'
      using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update purchasing.price_lists set status = 'replaced' where id = v_old.id;
  insert into purchasing.price_lists (group_id, supplier_id, received_on, valid_from, notes, status, accepted_at,
                                      accepted_by, version, previous_version_id, expired_notified_at)
  values (v_old.group_id, v_old.supplier_id, v_old.received_on, v_old.valid_from, v_old.notes, 'accepted', now(),
          core.current_actor_id(), v_old.version + 1, v_old.id, v_old.expired_notified_at)
  returning * into v_new;
  v_res := purchasing.add_price_list_items(v_new, p_items);
  v_review := purchasing.price_list_review_count(v_new.id);
  if v_review > 0 and not coalesce(p_confirm_review, false) then
    raise exception '%', case when v_review = 1
      then 'Hay 1 precio para revisar (10 veces más o menos que en la versión anterior): confirmalo antes de guardar.'
      else format('Hay %s precios para revisar (10 veces más o menos que en la versión anterior): confirmalos antes de guardar.', v_review)
      end using errcode = '23514';
  end if;
  return jsonb_build_object('result', 'applied', 'price_list_id', v_new.id, 'version', v_new.version,
                            'remembered', purchasing.remember_list_aliases(v_new.id)) || v_res;
exception
  when unique_violation or check_violation or foreign_key_violation or not_null_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    if v_constraint = 'price_lists_previous_key' then
      raise exception 'Esta versión ya se corrigió: corregí la vigente.' using errcode = '23514';
    end if;
    perform purchasing.raise_price_list_error(sqlstate, v_constraint, v_message);
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Revisá los números de la lista: precios, bonificaciones e IVA van con números y en su rango.'
      using errcode = '22023';
end
$$;
comment on function purchasing.correct_price_list(uuid, jsonb, text, boolean) is
  'Corrige la lista vigente de un proveedor (decisión 13 de Soy): crea la versión siguiente, ya aceptada y con la misma vigencia, y la anterior queda reemplazada, en una transacción y con motivo. Pide confirmar los precios en «Revisar». Pide purchasing.manage_price_lists. No toca costos.';
revoke execute on function purchasing.correct_price_list(uuid, jsonb, text, boolean) from public, anon;
grant execute on function purchasing.correct_price_list(uuid, jsonb, text, boolean) to authenticated;

-- Anular una lista cargada por error (decisión 24): no se borra. Si era la vigente, vuelve la anterior.
create function purchasing.void_price_list(p_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_list     purchasing.price_lists;
  v_restored uuid;
begin
  select * into v_list from purchasing.price_lists where id = p_id and deleted_at is null;
  if v_list.id is null or not core.has_permission_in_group('purchasing.manage_price_lists', v_list.group_id) then
    return core.deny('purchasing.void_price_list', 'No tenés permiso para anular esta lista.', null,
                     jsonb_build_object('price_list_id', p_id), v_list.group_id);
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí por qué se anula.' using errcode = '22023';
  end if;
  perform 1 from catalog.suppliers where id = v_list.supplier_id for update;
  select * into v_list from purchasing.price_lists where id = p_id;
  if v_list.status not in ('received', 'accepted') then
    raise exception 'Solo se anula una lista recibida o la vigente (esta está %).',
      case v_list.status when 'voided' then 'anulada' else 'reemplazada' end using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update purchasing.price_lists
     set status = 'voided', voided_reason = left(btrim(p_reason), 500), voided_at = now(),
         voided_by = core.current_actor_id()
   where id = v_list.id;
  -- Si era la vigente, vuelve a valer la última reemplazada (la versión que corregía, o la lista anterior).
  if v_list.status = 'accepted' then
    select id into v_restored from purchasing.price_lists
     where supplier_id = v_list.supplier_id and status = 'replaced' and deleted_at is null
     order by (id = v_list.previous_version_id) desc, valid_from desc, created_at desc
     limit 1;
    if v_restored is not null then
      update purchasing.price_lists set status = 'accepted' where id = v_restored;
    end if;
  end if;
  return jsonb_build_object('result', 'applied', 'status', 'voided', 'restored', v_restored);
end
$$;
comment on function purchasing.void_price_list(uuid, text) is
  'Anula una lista cargada por error (decisión 24 de Soy), con motivo y sin borrarla: una recibida o la vigente. Si era la vigente, vuelve a valer la última reemplazada del proveedor (la versión que corregía o la lista anterior). Pide purchasing.manage_price_lists.';
revoke execute on function purchasing.void_price_list(uuid, text) from public, anon;
grant execute on function purchasing.void_price_list(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Lecturas con los controles
-- ---------------------------------------------------------------------------
-- La vista previa de la carga (sin escribir nada): por renglón, lo reconocido, el neto, el anterior de la vigente y
-- los controles. Pide ver listas del grupo.
create function purchasing.price_list_preview(p_supplier_id uuid, p_items jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_s       catalog.suppliers;
  v_current uuid;
  v_out     jsonb := '[]'::jsonb;
  v_item    jsonb;
  v_n       integer := 0;
  v_product uuid;
  v_name    text;
  v_net     numeric;
  v_prev    numeric;
begin
  select * into v_s from catalog.suppliers where id = p_supplier_id and deleted_at is null;
  if v_s.id is null or not exists (select 1 from core.visible_group_ids('purchasing.view_price_lists') g
                                    where g = v_s.group_id) then
    return null;
  end if;
  -- Hasta 500 renglones, como la carga desde un archivo.
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 500 then
    return '[]'::jsonb;
  end if;
  select id into v_current from purchasing.price_lists
   where supplier_id = v_s.id and status = 'accepted' and deleted_at is null;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_n := v_n + 1;
    begin
      v_product := purchasing.price_line_product(v_s.id, v_item);
    exception when others then
      v_product := null;
    end;
    v_name := (select coalesce(p.description, '') from catalog.purchase_products p where p.id = v_product);
    begin
      v_net := case when jsonb_typeof(v_item -> 'list_price') = 'number' and (v_item ->> 'list_price')::numeric > 0
                    then purchasing.net_list_price((v_item ->> 'list_price')::numeric,
                                                   coalesce((v_item ->> 'bonus1_pct')::numeric, 0),
                                                   coalesce((v_item ->> 'bonus2_pct')::numeric, 0),
                                                   coalesce((v_item ->> 'bonus_per_unit_amount')::numeric, 0)) end;
    exception when invalid_text_representation or numeric_value_out_of_range then
      v_net := null;
    end;
    v_prev := (select purchasing.net_list_price(i.list_price, i.bonus1_pct, i.bonus2_pct, i.bonus_per_unit_amount)
                 from purchasing.price_list_items i
                where i.price_list_id = v_current and i.purchase_product_id = v_product and i.deleted_at is null
                order by i.line_order limit 1);
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'line', v_n, 'purchase_product_id', v_product, 'product_name', v_name, 'net_price', v_net,
      'previous_net_price', v_prev) || purchasing.price_line_check(v_s.group_id, v_product, v_net, v_prev));
  end loop;
  return v_out;
end
$$;
comment on function purchasing.price_list_preview(uuid, jsonb) is
  'Los controles de una lista antes de cargarla, sin escribir nada: por renglón, el producto reconocido (o el elegido a mano, si es del proveedor), el neto, el de la lista vigente, la variación, si pasa el umbral de Dirección, «Revisar» a 10 veces y el precio por unidad de uso. Nulo si la sesión no ve las listas del grupo.';
revoke execute on function purchasing.price_list_preview(uuid, jsonb) from public, anon;
grant execute on function purchasing.price_list_preview(uuid, jsonb) to authenticated;

-- El detalle de una lista con los mismos controles (la ficha).
drop function purchasing.price_list_changes(uuid);
create function purchasing.price_list_changes(p_price_list_id uuid)
returns table (purchase_product_id uuid, raw_name text, net_price numeric, previous_net_price numeric,
               change_pct numeric, over_threshold boolean, review boolean, per_use_price numeric,
               per_use_unit text)
language sql
stable
security definer
set search_path = ''
as $$
  select c.purchase_product_id, c.raw_name, c.net_price, c.previous_net_price, c.change_pct,
         (k ->> 'over_threshold')::boolean, (k ->> 'review')::boolean, (k ->> 'per_use_price')::numeric,
         k ->> 'per_use_unit'
    from reporting.v_price_list_changes c
    join purchasing.price_lists l on l.id = c.price_list_id and l.deleted_at is null
    cross join lateral purchasing.price_line_check(c.group_id, c.purchase_product_id, c.net_price,
                                                   c.previous_net_price) k
   where c.price_list_id = p_price_list_id
     and l.group_id in (select core.visible_group_ids('purchasing.view_price_lists'))
$$;
comment on function purchasing.price_list_changes(uuid) is
  'Los renglones de una lista con su neto, el de la lista aceptada anterior, la variación en %, si pasa el umbral de Dirección, «Revisar» a 10 veces y el precio por unidad de uso, si la sesión ve las listas del grupo. Vacío si no.';
revoke execute on function purchasing.price_list_changes(uuid) from public, anon;
grant execute on function purchasing.price_list_changes(uuid) to authenticated;

-- El listado y su conteo por proveedor: suman la versión y el estado «anulada». «Todas» no muestra las anuladas.
drop function purchasing.price_list_list(uuid, text, integer, integer);
create function purchasing.price_list_list(p_supplier_id uuid default null, p_status text default null,
                                           p_limit integer default 15, p_offset integer default 0)
returns table (id uuid, supplier_id uuid, supplier_name text, received_on date, valid_from date,
               status purchasing.price_list_status, expired boolean, items bigint, queued bigint, version integer,
               total bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  with base as (
    select l.id, l.supplier_id, coalesce(s.trade_name, s.name) as supplier_name, l.received_on, l.valid_from,
           l.status, purchasing.price_list_expired(l.id) as expired, l.version,
           (select count(*) from purchasing.price_list_items i where i.price_list_id = l.id and i.deleted_at is null)
             as items,
           (select count(*) from purchasing.price_list_items i
              join purchasing.unmapped_articles a on a.id = i.unmapped_article_id and a.status = 'pending'
             where i.price_list_id = l.id and i.deleted_at is null) as queued
      from purchasing.price_lists l
      join catalog.suppliers s on s.id = l.supplier_id
     where l.deleted_at is null
       and (p_supplier_id is null or l.supplier_id = p_supplier_id)),
  filtered as (
    select * from base
     where (p_status is null and status <> 'voided')
        or (p_status = 'expired' and expired)
        or (p_status = 'accepted' and status = 'accepted' and not expired)
        or (p_status in ('received', 'replaced', 'voided') and status::text = p_status))
  select f.id, f.supplier_id, f.supplier_name, f.received_on, f.valid_from, f.status, f.expired, f.items, f.queued,
         f.version, count(*) over ()
    from filtered f
   order by f.received_on desc, f.supplier_name, f.version desc, f.id
   limit least(greatest(coalesce(p_limit, 15), 1), 50) offset greatest(coalesce(p_offset, 0), 0)
$$;
comment on function purchasing.price_list_list(uuid, text, integer, integer) is
  'Listado de listas de precios (las más nuevas primero), con permisos de quien consulta: proveedor, fechas, estado, si venció, cuántos renglones tiene, cuántos esperan en la cola y la versión. Filtra por proveedor y estado (accepted, received, replaced, expired o voided; sin filtro, todas menos las anuladas) y pagina.';
revoke execute on function purchasing.price_list_list(uuid, text, integer, integer) from public, anon;
grant execute on function purchasing.price_list_list(uuid, text, integer, integer) to authenticated;

create or replace function purchasing.price_list_supplier_counts(p_status text default null)
returns table (supplier_id uuid, supplier_name text, total bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  with base as (
    select l.supplier_id, coalesce(s.trade_name, s.name) as supplier_name, l.status,
           purchasing.price_list_expired(l.id) as expired
      from purchasing.price_lists l
      join catalog.suppliers s on s.id = l.supplier_id
     where l.deleted_at is null)
  select b.supplier_id, b.supplier_name, count(*)
    from base b
   where (p_status is null and b.status <> 'voided')
      or (p_status = 'expired' and b.expired)
      or (p_status = 'accepted' and b.status = 'accepted' and not b.expired)
      or (p_status in ('received', 'replaced', 'voided') and b.status::text = p_status)
   group by b.supplier_id, b.supplier_name
   order by lower(b.supplier_name), b.supplier_id
$$;

-- ---------------------------------------------------------------------------
-- 5. Archivos: también Excel y CSV (el original importado queda guardado, decisión 12)
-- ---------------------------------------------------------------------------
update storage.buckets
   set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'application/pdf',
                                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                                  'text/csv']
 where id = 'purchasing-documents';

create or replace function purchasing.document_parts(p_name text)
returns table (group_id uuid, source_table text, source_id uuid)
language sql
immutable
set search_path = ''
as $$
  select split_part(p_name, '/', 1)::uuid, split_part(p_name, '/', 2), split_part(p_name, '/', 3)::uuid
   where p_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[a-z_]+/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp|pdf|xlsx|csv)$'
$$;
comment on function purchasing.document_parts(text) is
  'El grupo, la tabla y el registro de un archivo del bucket purchasing-documents, si el nombre tiene la forma <grupo>/<tabla>/<registro>/<uuid>.<ext> (jpg, png, webp, pdf, xlsx o csv). Vacío si no.';

alter table purchasing.attachments drop constraint attachments_storage_path_check;
alter table purchasing.attachments add constraint attachments_storage_path_check check (
  storage_path ~ '^[0-9a-f-]{36}/[a-z_]+/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp|pdf|xlsx|csv)$');

-- Comentarios al día con el estado «anulada».
comment on column purchasing.price_lists.status is
  'Recibida, aceptada (la vigente), reemplazada (por otra lista o por su versión corregida) o anulada (cargada por error, con motivo).';
comment on function purchasing.price_list_supplier_counts(text) is
  'Cuántas listas de precios hay por proveedor, con el mismo filtro de estado y los permisos de purchasing.price_list_list (sin filtro, todas menos las anuladas). Para el panel izquierdo del listado.';

