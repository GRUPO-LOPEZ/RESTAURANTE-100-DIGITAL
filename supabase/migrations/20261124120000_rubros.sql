-- Rubros del recetario (ADR-0038, pedido de Soy del 2026-11-10).
--
-- Un rubro es una categoría del primer nivel, con un código (MP-CAR, SR-SAL, PL-PAS) y una clase:
--   purchase  (MP) Rubros de compra: categorías de materias primas (catalog.ingredient_categories).
--   subrecipe (SR) Sub-recetas: categorías de preparaciones y componentes unitarios (recipes.recipe_categories).
--   menu      (PL) Rubros de menú: categorías de platos (recipes.recipe_categories).
--
-- Decisión de Joaco: cambios solo aditivos. No hay tabla nueva ni llaves que cambien; las dos tablas de
-- categorías suman código, clase y «activo», y la vista recipes.top_categories las junta. Las
-- subcategorías siguen como estaban, dentro de su rubro y sin código.
--
-- «Dado de baja» es is_active = false: se puede reactivar. deleted_at sigue siendo el borrado lógico.
-- El costeo en cascada (materia prima o sub-receta en recipe_components) ya existe (ADR-0025, ADR-0032).

-- ---------------------------------------------------------------------------
-- 1. Clase de rubro y columnas nuevas
-- ---------------------------------------------------------------------------
create type recipes.category_class as enum ('purchase', 'subrecipe', 'menu');
comment on type recipes.category_class is
  'Clase de rubro: purchase (MP, rubros de compra), subrecipe (SR, sub-recetas) o menu (PL, rubros de menú).';

alter table catalog.ingredient_categories
  add column code      text,
  add column is_active boolean not null default true;
comment on column catalog.ingredient_categories.code is
  'Código del rubro (MP-XXX), solo en el primer nivel. Se genera solo si no se indica y no cambia.';
comment on column catalog.ingredient_categories.is_active is
  'Si el rubro está activo. Dado de baja (false) no admite materias primas nuevas; se puede reactivar.';

alter table recipes.recipe_categories
  add column code      text,
  add column kind      recipes.category_class,
  add column is_active boolean not null default true;
comment on column recipes.recipe_categories.code is
  'Código del rubro (SR-XXX o PL-XXX), solo en el primer nivel. Se genera solo si no se indica y no cambia.';
comment on column recipes.recipe_categories.kind is
  'Clase: subrecipe (preparaciones y componentes unitarios) o menu (platos). Las subcategorías heredan la de su rubro. Obligatoria en lo vigente (lo borrado antes de los rubros no la tiene).';
comment on column recipes.recipe_categories.is_active is
  'Si el rubro está activo. Dado de baja (false) no admite recetas nuevas; se puede reactivar.';

-- ---------------------------------------------------------------------------
-- 2. Código automático
-- ---------------------------------------------------------------------------
-- Prefijo + 3 letras del nombre sin tildes (Salsas → SR-SAL). Si está tomado: 2 letras y un dígito,
-- después 1 letra y dos dígitos.
create function catalog.free_category_code(p_prefix text, p_name text, p_taken text[])
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_taken   text[] := coalesce(p_taken, '{}');
  v_letters text;
  v_code    text;
begin
  v_letters := regexp_replace(
    upper(translate(coalesce(p_name, ''), 'áàâäéèêëíìîïóòôöúùûüñçÁÀÂÄÉÈÊËÍÌÎÏÓÒÔÖÚÙÛÜÑÇ',
                                          'aaaaeeeeiiiioooouuuuncAAAAEEEEIIIIOOOOUUUUNC')),
    '[^A-Z]', '', 'g');
  if v_letters = '' then
    v_letters := 'RUB';
  end if;
  v_code := p_prefix || '-' || rpad(left(v_letters, 3), 3, 'X');
  if not v_code = any (v_taken) then
    return v_code;
  end if;
  for d in 1..9 loop
    v_code := p_prefix || '-' || rpad(left(v_letters, 2), 2, 'X') || d;
    if not v_code = any (v_taken) then
      return v_code;
    end if;
  end loop;
  for n in 1..99 loop
    v_code := p_prefix || '-' || left(v_letters, 1) || lpad(n::text, 2, '0');
    if not v_code = any (v_taken) then
      return v_code;
    end if;
  end loop;
  raise exception 'No quedan códigos libres para ese nombre: probá con otro.' using errcode = '23514';
end
$$;
comment on function catalog.free_category_code(text, text, text[]) is
  'Interna: primer código de rubro libre para un nombre (prefijo + 3 letras sin tildes, y variantes con dígitos).';
revoke execute on function catalog.free_category_code(text, text, text[]) from public;

-- ---------------------------------------------------------------------------
-- 3. Reglas de las categorías (código, clase y rubro activo)
-- ---------------------------------------------------------------------------
create function catalog.enforce_rubro_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent_active boolean;
begin
  if tg_op = 'UPDATE' and old.code is not null and new.code is distinct from old.code then
    raise exception 'El código de un rubro no cambia.' using errcode = '42501';
  end if;
  if new.parent_id is not null then
    if tg_op = 'INSERT' or new.parent_id is distinct from old.parent_id then
      -- Con «for share»: si el rubro se está dando de baja, espera y después ve la baja.
      select is_active into v_parent_active from catalog.ingredient_categories where id = new.parent_id for share;
      if v_parent_active is false then
        raise exception 'Ese rubro está dado de baja: elegí otro.' using errcode = '23514';
      end if;
    end if;
  elsif new.code is null then
    new.code := catalog.free_category_code('MP', new.name,
      array(select code from catalog.ingredient_categories
             where group_id = new.group_id and code is not null and id <> new.id));
  end if;
  return new;
end
$$;
comment on function catalog.enforce_rubro_fields() is
  'Trigger (BEFORE INSERT OR UPDATE) de ingredient_categories: el código del rubro se genera solo (sin reutilizar el de uno borrado) y no cambia; no se cuelga una subcategoría de un rubro dado de baja.';
revoke execute on function catalog.enforce_rubro_fields() from public;

create function recipes.enforce_rubro_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent recipes.recipe_categories;
begin
  if tg_op = 'UPDATE' and old.code is not null and new.code is distinct from old.code then
    raise exception 'El código de un rubro no cambia.' using errcode = '42501';
  end if;
  if new.parent_id is not null then
    -- Con «for share»: si el rubro se está dando de baja, espera y después ve la baja.
    select * into v_parent from recipes.recipe_categories where id = new.parent_id for share;
    new.kind := v_parent.kind;
    if (tg_op = 'INSERT' or new.parent_id is distinct from old.parent_id) and v_parent.is_active is false then
      raise exception 'Ese rubro está dado de baja: elegí otro.' using errcode = '23514';
    end if;
  else
    if new.kind is null then
      raise exception 'Elegí la clase del rubro: sub-recetas o menú.' using errcode = '23514';
    end if;
    if new.code is null then
      new.code := catalog.free_category_code(case new.kind when 'menu' then 'PL' else 'SR' end, new.name,
        array(select code from recipes.recipe_categories
               where group_id = new.group_id and code is not null and id <> new.id));
    end if;
  end if;
  if tg_op = 'UPDATE' and old.kind is not null and new.kind is distinct from old.kind then
    raise exception 'La clase de un rubro no cambia.' using errcode = '42501';
  end if;
  return new;
end
$$;
comment on function recipes.enforce_rubro_fields() is
  'Trigger (BEFORE INSERT OR UPDATE) de recipe_categories: la subcategoría hereda la clase de su rubro; el código se genera solo; código y clase no cambian; no se cuelga una subcategoría de un rubro dado de baja.';
revoke execute on function recipes.enforce_rubro_fields() from public;

-- ---------------------------------------------------------------------------
-- 4. Los 46 rubros de Soy, por grupo
-- ---------------------------------------------------------------------------
create function recipes.default_categories()
returns table (category_class recipes.category_class, code text, name text)
language sql
immutable
set search_path = ''
as $$
  select c.category_class::recipes.category_class, c.code, c.name
    from (values
      ('purchase', 'MP-CAR', 'Carnes y aves'), ('purchase', 'MP-PES', 'Pescados y mariscos'),
      ('purchase', 'MP-FIA', 'Fiambres y embutidos'), ('purchase', 'MP-LAC', 'Lácteos y quesos'),
      ('purchase', 'MP-HUE', 'Huevos'), ('purchase', 'MP-VER', 'Verduras y hortalizas'),
      ('purchase', 'MP-FRU', 'Frutas'), ('purchase', 'MP-HIE', 'Hierbas frescas'),
      ('purchase', 'MP-HAR', 'Harinas, cereales y legumbres'), ('purchase', 'MP-PAS', 'Pastas secas y frescas compradas'),
      ('purchase', 'MP-ACE', 'Aceites, vinagres y grasas'), ('purchase', 'MP-ESP', 'Especias y condimentos'),
      ('purchase', 'MP-CON', 'Conservas y enlatados'), ('purchase', 'MP-DUL', 'Azúcares, chocolate y pastelería'),
      ('purchase', 'MP-CGL', 'Congelados'), ('purchase', 'MP-BEB', 'Bebidas sin alcohol'),
      ('purchase', 'MP-VIN', 'Vinos y bebidas con alcohol'), ('purchase', 'MP-CAF', 'Café, té e infusiones'),
      ('purchase', 'MP-DES', 'Descartables y packaging'), ('purchase', 'MP-LIM', 'Limpieza'),
      ('subrecipe', 'SR-SAL', 'Salsas'), ('subrecipe', 'SR-FON', 'Fondos y caldos'), ('subrecipe', 'SR-MAS', 'Masas'),
      ('subrecipe', 'SR-REL', 'Rellenos'), ('subrecipe', 'SR-ADE', 'Aderezos y vinagretas'),
      ('subrecipe', 'SR-MAR', 'Marinadas y adobos'), ('subrecipe', 'SR-COC', 'Cocciones base'),
      ('subrecipe', 'SR-PAN', 'Panificados'), ('subrecipe', 'SR-PST', 'Bases de pastelería'),
      ('subrecipe', 'SR-GUA', 'Guarniciones pre-elaboradas'), ('subrecipe', 'SR-BAR', 'Bases de barra'),
      ('menu', 'PL-ENT', 'Entradas'), ('menu', 'PL-ENS', 'Ensaladas'), ('menu', 'PL-SOP', 'Sopas'),
      ('menu', 'PL-PAS', 'Pastas'), ('menu', 'PL-RIS', 'Risottos y arroces'), ('menu', 'PL-CAR', 'Principales de carne'),
      ('menu', 'PL-PES', 'Principales de pescado'), ('menu', 'PL-VEG', 'Principales vegetarianos'),
      ('menu', 'PL-GUA', 'Guarniciones'), ('menu', 'PL-POS', 'Postres'), ('menu', 'PL-MEN', 'Menú del día'),
      ('menu', 'PL-INF', 'Menú infantil'), ('menu', 'PL-BEB', 'Bebidas sin alcohol'), ('menu', 'PL-VIN', 'Vinos y tragos'),
      ('menu', 'PL-CAF', 'Cafetería')
    ) as c (category_class, code, name)
$$;
comment on function recipes.default_categories() is
  'Los 46 rubros iniciales de Soy (20 de compra, 11 de sub-recetas y 15 de menú), con su código y su nombre.';
revoke execute on function recipes.default_categories() from public;

-- Nombre para comparar: sin tildes ni mayúsculas.
create function catalog.category_match_name(p_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select lower(translate(btrim(p_name), 'áàâäéèêëíìîïóòôöúùûüñçÁÀÂÄÉÈÊËÍÌÎÏÓÒÔÖÚÙÛÜÑÇ',
                                        'aaaaeeeeiiiioooouuuuncAAAAEEEEIIIIOOOOUUUUNC'))
$$;
comment on function catalog.category_match_name(text) is 'Interna: nombre de categoría sin tildes ni mayúsculas, para comparar.';
revoke execute on function catalog.category_match_name(text) from public;

-- Carga los rubros que falten en un grupo. Si ya hay una categoría del primer nivel sin código con el
-- mismo nombre (y la misma clase), le pone el código en vez de crear otra. Si el nombre ya lo usa otra
-- categoría, ese rubro no se crea (la existente queda con su código). Se puede repetir.
create function recipes.install_default_categories(p_group_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  d    record;
  v_n  integer := 0;
  v_id uuid;
begin
  for d in select * from recipes.default_categories() loop
    if d.category_class = 'purchase' then
      continue when exists (select 1 from catalog.ingredient_categories
                             where group_id = p_group_id and code = d.code and deleted_at is null);
      update catalog.ingredient_categories set code = d.code
       where id = (select id from catalog.ingredient_categories
                    where group_id = p_group_id and parent_id is null and code is null and deleted_at is null
                      and catalog.category_match_name(name) = catalog.category_match_name(d.name)
                    order by created_at limit 1)
      returning id into v_id;
      if v_id is null then
        insert into catalog.ingredient_categories (group_id, name, code) values (p_group_id, d.name, d.code)
        on conflict do nothing returning id into v_id;
      end if;
    else
      continue when exists (select 1 from recipes.recipe_categories
                             where group_id = p_group_id and code = d.code and deleted_at is null);
      update recipes.recipe_categories set code = d.code
       where id = (select id from recipes.recipe_categories
                    where group_id = p_group_id and parent_id is null and code is null and deleted_at is null
                      and kind = d.category_class
                      and catalog.category_match_name(name) = catalog.category_match_name(d.name)
                    order by created_at limit 1)
      returning id into v_id;
      if v_id is null then
        insert into recipes.recipe_categories (group_id, name, code, kind)
        values (p_group_id, d.name, d.code, d.category_class)
        on conflict do nothing returning id into v_id;
      end if;
    end if;
    if v_id is not null then
      v_n := v_n + 1;
    end if;
    v_id := null;
  end loop;
  return v_n;
end
$$;
comment on function recipes.install_default_categories(uuid) is
  'Carga en un grupo los rubros de Soy que falten (o les pone el código a las categorías con el mismo nombre). Devuelve cuántos tocó. Solo la usan migraciones y el seed.';
revoke execute on function recipes.install_default_categories(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Datos actuales: clase, rubros de Soy y códigos
-- ---------------------------------------------------------------------------
-- Primera palabra del nombre, sin tildes ni mayúsculas («Carnes y aves» → «carnes»).
create function catalog.category_first_word(p_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select split_part(btrim(regexp_replace(catalog.category_match_name(p_name), '[^a-z0-9]+', ' ', 'g')), ' ', 1)
$$;
comment on function catalog.category_first_word(text) is 'Interna: primera palabra del nombre de una categoría, para emparejarla con un rubro de Soy.';
revoke execute on function catalog.category_first_word(text) from public;

-- Convierte las categorías ya cargadas de un grupo en rubros. Corre una vez, en esta migración (y en las
-- pruebas, sobre datos viejos simulados). Los triggers de código y clase todavía no existen cuando corre.
--   1. Clase de las categorías de recetas del primer nivel sin clase: la del tipo de la mayoría de sus recetas
--      (también las de sus subcategorías); en empate o sin recetas, sub-recetas si el nombre es el de un rubro
--      SR de Soy; si no, menú. Las subcategorías heredan la de su rubro.
--   2. Código de Soy para cada categoría del primer nivel sin código, si se puede emparejar con un rubro de su
--      clase, en este orden: (a) la equivalencia acordada (p_equivalences: nombre sin tildes → código);
--      (b) el mismo nombre sin tildes ni mayúsculas; (c) la misma primera palabra, si del lado de Soy hay un
--      solo rubro con esa palabra y del lado viejo una sola categoría («Carnes» → MP-CAR «Carnes y aves»).
--      La emparejada toma también el nombre de Soy, salvo que otro rubro vigente del grupo ya se llame así.
--   3. Los rubros de Soy que falten (recipes.install_default_categories).
--   4. Un código propio, con el prefijo, para lo que no se emparejó.
-- Lo borrado queda como estaba (un registro borrado no se edita: core.set_control_columns); las reglas de
-- código y clase valen para lo vigente.
-- Devuelve cuántas categorías viejas recibieron un código de Soy.
create function recipes.map_legacy_categories(p_group_id uuid, p_equivalences jsonb default '{}'::jsonb)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_cat   record;
  v_code  text;
  v_first text;
  v_name  text;
  v_n     integer := 0;
begin
  -- 1. Clase.
  update recipes.recipe_categories t
     set kind = case
       when coalesce(u.dishes, 0) > coalesce(u.others, 0) then 'menu'
       when coalesce(u.others, 0) > coalesce(u.dishes, 0) then 'subrecipe'
       when exists (select 1 from recipes.default_categories() d
                     where d.category_class = 'subrecipe'
                       and catalog.category_match_name(d.name) = catalog.category_match_name(t.name)) then 'subrecipe'
       else 'menu' end::recipes.category_class
    from recipes.recipe_categories t2
    left join (select coalesce(c.parent_id, c.id) as top_id,
                      count(*) filter (where r.recipe_type = 'dish') as dishes,
                      count(*) filter (where r.recipe_type <> 'dish') as others
                 from recipes.recipes r
                 join recipes.recipe_categories c on c.id = r.category_id
                where r.deleted_at is null and r.group_id = p_group_id
                group by 1) u on u.top_id = t2.id
   where t.id = t2.id and t.group_id = p_group_id and t.parent_id is null and t.kind is null and t.deleted_at is null;
  update recipes.recipe_categories s set kind = p.kind
    from recipes.recipe_categories p
   where s.parent_id = p.id and s.group_id = p_group_id and s.kind is distinct from p.kind and s.deleted_at is null;

  -- 2. Código de Soy para lo que se puede emparejar.
  for v_cat in
    select 'purchase'::recipes.category_class as cls, c.id, c.name
      from catalog.ingredient_categories c
     where c.group_id = p_group_id and c.parent_id is null and c.code is null and c.deleted_at is null
    union all
    select c.kind, c.id, c.name
      from recipes.recipe_categories c
     where c.group_id = p_group_id and c.parent_id is null and c.code is null and c.deleted_at is null
     order by 3
  loop
    select d.code into v_code from recipes.default_categories() d
     where d.category_class = v_cat.cls and d.code = p_equivalences ->> catalog.category_match_name(v_cat.name);
    if v_code is null then
      select d.code into v_code from recipes.default_categories() d
       where d.category_class = v_cat.cls and catalog.category_match_name(d.name) = catalog.category_match_name(v_cat.name);
    end if;
    if v_code is null then
      v_first := catalog.category_first_word(v_cat.name);
      select min(d.code) into v_code from recipes.default_categories() d
       where d.category_class = v_cat.cls and catalog.category_first_word(d.name) = v_first
      having count(*) = 1;
      -- Del lado viejo también tiene que ser la única con esa primera palabra.
      if v_code is not null and (
           (v_cat.cls = 'purchase' and (select count(*) from catalog.ingredient_categories c
                                          where c.group_id = p_group_id and c.parent_id is null and c.deleted_at is null
                                            and catalog.category_first_word(c.name) = v_first) > 1)
           or (v_cat.cls <> 'purchase' and (select count(*) from recipes.recipe_categories c
                                              where c.group_id = p_group_id and c.parent_id is null
                                                and c.deleted_at is null and c.kind = v_cat.cls
                                                and catalog.category_first_word(c.name) = v_first) > 1)) then
        v_code := null;
      end if;
    end if;
    -- El código tiene que estar libre (otra categoría vieja pudo quedarse con él antes). La emparejada toma
    -- también el nombre de Soy (decisión de Soy, 2026-11-11: «Carne» → «Carnes y aves», «PASTAS» → «Pastas»),
    -- salvo que otro rubro vigente del grupo ya se llame así: entonces conserva el suyo.
    if v_code is not null then
      select d.name into v_name from recipes.default_categories() d where d.code = v_code;
      if v_cat.cls = 'purchase' then
        if not exists (select 1 from catalog.ingredient_categories where group_id = p_group_id and code = v_code) then
          update catalog.ingredient_categories c
             set code = v_code,
                 name = case when exists (select 1 from catalog.ingredient_categories o
                                           where o.group_id = p_group_id and o.parent_id is null and o.deleted_at is null
                                             and o.id <> c.id and lower(o.name) = lower(v_name))
                             then c.name else v_name end
           where c.id = v_cat.id;
          v_n := v_n + 1;
        end if;
      elsif not exists (select 1 from recipes.recipe_categories where group_id = p_group_id and code = v_code) then
        update recipes.recipe_categories c
           set code = v_code,
               name = case when exists (select 1 from recipes.recipe_categories o
                                         where o.group_id = p_group_id and o.parent_id is null and o.deleted_at is null
                                           and o.id <> c.id and lower(o.name) = lower(v_name))
                           then c.name else v_name end
         where c.id = v_cat.id;
        v_n := v_n + 1;
      end if;
    end if;
    v_code := null;
  end loop;

  -- 3. Los rubros de Soy que falten.
  perform recipes.install_default_categories(p_group_id);

  -- 4. Código propio para lo demás vigente.
  for v_cat in select id, name from catalog.ingredient_categories
                where group_id = p_group_id and parent_id is null and code is null and deleted_at is null
                order by created_at loop
    update catalog.ingredient_categories
       set code = catalog.free_category_code('MP', v_cat.name,
             array(select code from catalog.ingredient_categories where group_id = p_group_id and code is not null))
     where id = v_cat.id;
  end loop;
  for v_cat in select id, name, kind from recipes.recipe_categories
                where group_id = p_group_id and parent_id is null and code is null and deleted_at is null
                order by created_at loop
    update recipes.recipe_categories
       set code = catalog.free_category_code(case v_cat.kind when 'menu' then 'PL' else 'SR' end, v_cat.name,
             array(select code from recipes.recipe_categories where group_id = p_group_id and code is not null))
     where id = v_cat.id;
  end loop;
  return v_n;
end
$$;
comment on function recipes.map_legacy_categories(uuid, jsonb) is
  'Convierte las categorías ya cargadas de un grupo en rubros: clase, código y nombre de Soy si se empareja (equivalencia acordada, mismo nombre o misma primera palabra única), los rubros de Soy que falten y un código propio para el resto. Solo la usan esta migración y las pruebas.';
revoke execute on function recipes.map_legacy_categories(uuid, jsonb) from public, anon, authenticated;

do $$
declare
  v_grp record;
begin
  perform core.set_change_context('Rubros del recetario: clase y código de las categorías (ADR-0038)', 'maintenance');
  -- Equivalencias de nombres viejos a rubros de Soy (nombre en minúsculas y sin tildes → código), aprobadas por
  -- Soy el 2026-11-11 a partir de las categorías de staging. «PASTAS» y «POSTRES» se emparejan solas por el nombre.
  for v_grp in select id from org.groups loop
    perform recipes.map_legacy_categories(v_grp.id,
      '{"carne": "MP-CAR", "quesos": "MP-LAC", "verdura": "MP-VER", "carnes": "PL-CAR", "pescados": "PL-PES"}'::jsonb);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 6. Restricciones (después de completar los datos)
-- ---------------------------------------------------------------------------
alter table catalog.ingredient_categories
  add constraint ingredient_categories_code_check check (code ~ '^MP-[A-Z0-9]{3}$'),
  -- Para lo vigente: lo borrado antes de los rubros queda como estaba.
  add constraint ingredient_categories_code_level check (deleted_at is not null or (parent_id is null) = (code is not null));
create unique index ingredient_categories_code_key on catalog.ingredient_categories (group_id, code)
  where code is not null and deleted_at is null;

alter table recipes.recipe_categories
  add constraint recipe_categories_kind_required check (deleted_at is not null or kind is not null),
  add constraint recipe_categories_kind_check check (kind in ('subrecipe', 'menu')),
  add constraint recipe_categories_code_check check (
    (kind = 'subrecipe' and code ~ '^SR-[A-Z0-9]{3}$') or (kind = 'menu' and code ~ '^PL-[A-Z0-9]{3}$')),
  add constraint recipe_categories_code_level check (deleted_at is not null or (parent_id is null) = (code is not null));
create unique index recipe_categories_code_key on recipes.recipe_categories (group_id, code)
  where code is not null and deleted_at is null;
create index recipe_categories_kind_idx on recipes.recipe_categories (group_id, kind) where deleted_at is null;

create trigger enforce_rubro_fields before insert or update on catalog.ingredient_categories
  for each row execute function catalog.enforce_rubro_fields();
create trigger enforce_rubro_fields before insert or update on recipes.recipe_categories
  for each row execute function recipes.enforce_rubro_fields();

-- ---------------------------------------------------------------------------
-- 7. Reglas de las materias primas y las recetas
-- ---------------------------------------------------------------------------
-- Una materia prima nueva (o que cambia de categoría) no entra en un rubro dado de baja.
create function catalog.enforce_active_category()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_active boolean;
  v_parent uuid;
  v_parent_active boolean;
begin
  if tg_op = 'INSERT' or new.category_id is distinct from old.category_id then
    -- Con «for share» (la categoría y su rubro): si se está dando de baja, espera y después ve la baja.
    select is_active, parent_id into v_active, v_parent from catalog.ingredient_categories
     where id = new.category_id for share;
    if v_parent is not null then
      select is_active into v_parent_active from catalog.ingredient_categories where id = v_parent for share;
    end if;
    if v_active is false or v_parent_active is false then
      raise exception 'Ese rubro está dado de baja: elegí otro.' using errcode = '23514';
    end if;
  end if;
  return new;
end
$$;
comment on function catalog.enforce_active_category() is
  'Trigger (BEFORE INSERT OR UPDATE) de ingredients: no se asigna un rubro dado de baja (ni una subcategoría suya).';
revoke execute on function catalog.enforce_active_category() from public;
create trigger enforce_active_category before insert or update of category_id on catalog.ingredients
  for each row execute function catalog.enforce_active_category();

-- Un plato va en un rubro de menú; una preparación o un componente unitario, en uno de sub-recetas.
-- Se controla al crear la receta o al cambiarle la categoría: lo ya cargado no se toca.
create function recipes.enforce_recipe_category_class()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind          recipes.category_class;
  v_active        boolean;
  v_parent        uuid;
  v_parent_active boolean;
begin
  if new.category_id is null
     or (tg_op = 'UPDATE' and new.category_id is not distinct from old.category_id
         and new.recipe_type is not distinct from old.recipe_type) then
    return new;
  end if;
  -- Una variante nueva copia el rubro de su maestra: si la maestra quedó de antes en un rubro de la otra
  -- clase, la variante no se frena (lo ya cargado no se toca; se corrige en la maestra).
  if tg_op = 'INSERT' and new.variant_of_recipe_id is not null
     and new.category_id = (select category_id from recipes.recipes where id = new.variant_of_recipe_id) then
    return new;
  end if;
  -- Con «for share» (la categoría y su rubro): si se está dando de baja, espera y después ve la baja.
  select kind, is_active, parent_id into v_kind, v_active, v_parent from recipes.recipe_categories
   where id = new.category_id for share;
  if v_parent is not null then
    select is_active into v_parent_active from recipes.recipe_categories where id = v_parent for share;
  end if;
  if v_active is false or v_parent_active is false then
    raise exception 'Ese rubro está dado de baja: elegí otro.' using errcode = '23514';
  end if;
  if (new.recipe_type = 'dish') <> (v_kind = 'menu') then
    raise exception 'Un plato va en un rubro de menú; una preparación o un componente, en un rubro de sub-recetas.'
      using errcode = '23514';
  end if;
  return new;
end
$$;
comment on function recipes.enforce_recipe_category_class() is
  'Trigger (BEFORE INSERT OR UPDATE) de recipes: plato con rubro de menú, preparación o componente con rubro de sub-recetas, y el rubro activo. Solo al crear o al cambiar la categoría o el tipo; una variante nueva que copia el rubro de su maestra pasa.';
revoke execute on function recipes.enforce_recipe_category_class() from public;
create trigger enforce_recipe_category_class before insert or update of category_id, recipe_type on recipes.recipes
  for each row execute function recipes.enforce_recipe_category_class();

-- ---------------------------------------------------------------------------
-- 8. Lectura: la vista de rubros y los conteos del panel
-- ---------------------------------------------------------------------------
create view recipes.top_categories with (security_invoker = true) as
  select 'purchase'::recipes.category_class as category_class, c.id, c.group_id, c.code, c.name, c.is_active,
         c.created_at, c.updated_at
    from catalog.ingredient_categories c
   where c.parent_id is null and c.deleted_at is null
  union all
  select c.kind, c.id, c.group_id, c.code, c.name, c.is_active, c.created_at, c.updated_at
    from recipes.recipe_categories c
   where c.parent_id is null and c.deleted_at is null;
comment on view recipes.top_categories is
  'Rubros (categorías del primer nivel) de compra, de sub-recetas y de menú, juntos. Con los permisos de quien consulta.';
comment on column recipes.top_categories.category_class is 'Clase: purchase (compra), subrecipe (sub-recetas) o menu (menú).';
comment on column recipes.top_categories.id is 'Identificador de la categoría del primer nivel.';
comment on column recipes.top_categories.group_id is 'Grupo al que pertenece.';
comment on column recipes.top_categories.code is 'Código del rubro (MP-, SR- o PL- y tres letras o números).';
comment on column recipes.top_categories.name is 'Nombre del rubro.';
comment on column recipes.top_categories.is_active is 'Si está activo (dado de baja = false; se puede reactivar).';
comment on column recipes.top_categories.created_at is 'Cuándo se creó.';
comment on column recipes.top_categories.updated_at is 'Cuándo se cambió por última vez.';
revoke all on recipes.top_categories from public, anon, authenticated, service_role;
grant select on recipes.top_categories to authenticated;

-- Una consulta agrupada por rubro: cuántas materias primas o recetas tiene cada uno (sumando las de sus
-- subcategorías) y cuántas recetas quedaron en un rubro de la otra clase. Con los permisos de quien
-- consulta (RLS): quien ve un solo local cuenta solo las recetas que ve.
create function recipes.category_overview(p_group_id uuid)
returns table (category_class recipes.category_class, id uuid, code text, name text, is_active boolean,
               uses bigint, mismatched bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  with ing as (
    select coalesce(c.parent_id, c.id) as top_id, count(*) as uses
      from catalog.ingredients i
      join catalog.ingredient_categories c on c.id = i.category_id
     where i.group_id = p_group_id and i.deleted_at is null
     group by 1),
  rec as (
    select coalesce(c.parent_id, c.id) as top_id, count(*) as uses,
           count(*) filter (where (r.recipe_type = 'dish') <> (c.kind = 'menu')) as mismatched
      from recipes.recipes r
      join recipes.recipe_categories c on c.id = r.category_id
     where r.group_id = p_group_id and r.deleted_at is null
     group by 1)
  select 'purchase'::recipes.category_class, c.id, c.code, c.name, c.is_active, coalesce(ing.uses, 0), 0::bigint
    from catalog.ingredient_categories c
    left join ing on ing.top_id = c.id
   where c.group_id = p_group_id and c.parent_id is null and c.deleted_at is null
  union all
  select c.kind, c.id, c.code, c.name, c.is_active, coalesce(rec.uses, 0), coalesce(rec.mismatched, 0)
    from recipes.recipe_categories c
    left join rec on rec.top_id = c.id
   where c.group_id = p_group_id and c.parent_id is null and c.deleted_at is null
$$;
comment on function recipes.category_overview(uuid) is
  'Panel de Rubros: cada rubro del grupo con su clase, código, nombre, si está activo, cuántos usos tiene (materias primas o recetas, sumando subcategorías) y cuántas recetas están en un rubro de la otra clase. Con los permisos de quien consulta.';
revoke execute on function recipes.category_overview(uuid) from public;
grant execute on function recipes.category_overview(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Escritura: alta, nombre, baja con destino y reactivación
-- ---------------------------------------------------------------------------
-- Permiso propio para los rubros de sub-recetas y menú (decisión de Joaco, 2026-11-10): Soy se lo puede dar a
-- otro rol. Arranca en los roles que hoy tienen recipes.draft, que es lo que ya permitía crear categorías.
do $$
begin
  perform core.set_change_context('Permiso de rubros de sub-recetas y menú (ADR-0038)', 'maintenance');
  insert into core.permissions (code, module, action, description, is_sensitive) values
    ('recipes.manage_categories', 'recipes', 'manage_categories',
     'Dar de alta, renombrar, dar de baja y reactivar los rubros de sub-recetas y de menú.', false);
  insert into core.role_permissions (role_id, permission_id)
  select rp.role_id, p.id
    from core.role_permissions rp
    join core.permissions d on d.id = rp.permission_id and d.code = 'recipes.draft'
    cross join core.permissions p
   where p.code = 'recipes.manage_categories' and rp.deleted_at is null;
end
$$;

-- Quién administra los rubros de cada clase, para todo el grupo (decisiones de Joaco, 2026-11-10):
--   compra: Compras (catalog.manage) o Dirección (prices.configure), cada uno por su cuenta;
--   sub-recetas y menú: recipes.manage_categories.
create function recipes.can_manage_category(p_class recipes.category_class, p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case p_class
           when 'purchase' then core.has_permission_in_group('catalog.manage', p_group_id)
                             or core.has_permission_in_group('prices.configure', p_group_id)
           else core.has_permission_in_group('recipes.manage_categories', p_group_id)
         end
$$;
comment on function recipes.can_manage_category(recipes.category_class, uuid) is
  'Interna: si la sesión administra los rubros de esa clase en el grupo (compra: catalog.manage o prices.configure; sub-recetas y menú: recipes.manage_categories).';
revoke execute on function recipes.can_manage_category(recipes.category_class, uuid) from public;

-- Grupo de un rubro vigente de esa clase, o error "sin permiso" (no revela si existe).
create function recipes.top_category_group(p_class recipes.category_class, p_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_group uuid;
begin
  if p_class = 'purchase' then
    select group_id into v_group from catalog.ingredient_categories
     where id = p_id and parent_id is null and deleted_at is null;
  else
    select group_id into v_group from recipes.recipe_categories
     where id = p_id and parent_id is null and deleted_at is null and kind = p_class;
  end if;
  perform org.require(v_group is not null
                      and recipes.can_manage_category(p_class, v_group),
                      'editar este rubro');
  return v_group;
end
$$;
comment on function recipes.top_category_group(recipes.category_class, uuid) is
  'Interna: grupo del rubro vigente de esa clase si la sesión puede administrarlo; si no, "sin permiso".';
revoke execute on function recipes.top_category_group(recipes.category_class, uuid) from public;

-- Errores de las altas y los cambios de nombre, en español.
create function recipes.raise_category_error(p_class recipes.category_class, p_state text, p_constraint text,
                                             p_message text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_constraint in ('ingredient_categories_code_key', 'recipe_categories_code_key') then
    raise exception 'Se creó otro rubro con el mismo código recién: probá de nuevo.' using errcode = p_state;
  elsif p_constraint in ('ingredient_categories_name_key', 'recipe_categories_name_key') then
    raise exception 'Ya existe un rubro con ese nombre.' using errcode = p_state;
  elsif p_class = 'purchase' then
    perform catalog.raise_friendly(p_state, p_constraint, p_message);
  else
    perform recipes.raise_friendly(p_state, p_constraint, p_message);
  end if;
end
$$;
comment on function recipes.raise_category_error(recipes.category_class, text, text, text) is
  'Interna: vuelve a lanzar un error de restricción de un rubro con un mensaje en español.';
revoke execute on function recipes.raise_category_error(recipes.category_class, text, text, text) from public;

create function recipes.create_top_category(p_group_id uuid, p_class recipes.category_class, p_name text,
                                            p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id         uuid;
  v_constraint text;
  v_message    text;
begin
  perform org.require(recipes.can_manage_category(p_class, p_group_id),
                      'crear rubros en este grupo');
  perform catalog.require_name(p_name);
  perform core.set_change_context(p_reason, 'manual');
  if p_class = 'purchase' then
    insert into catalog.ingredient_categories (group_id, name) values (p_group_id, btrim(p_name)) returning id into v_id;
  else
    insert into recipes.recipe_categories (group_id, name, kind) values (p_group_id, btrim(p_name), p_class)
    returning id into v_id;
  end if;
  return v_id;
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform recipes.raise_category_error(p_class, sqlstate, v_constraint, v_message);
end
$$;
comment on function recipes.create_top_category(uuid, recipes.category_class, text, text) is
  'Crea un rubro de compra, de sub-recetas o de menú, con el código generado (prefijo + 3 letras). Pide el permiso de su clase en el grupo (recipes.can_manage_category) y un motivo.';

create function recipes.rename_top_category(p_class recipes.category_class, p_id uuid, p_name text, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
  v_message    text;
begin
  perform recipes.top_category_group(p_class, p_id);
  perform catalog.require_name(p_name);
  perform core.set_change_context(p_reason, 'manual');
  if p_class = 'purchase' then
    update catalog.ingredient_categories set name = btrim(p_name) where id = p_id;
  else
    update recipes.recipe_categories set name = btrim(p_name) where id = p_id;
  end if;
exception when unique_violation or check_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform recipes.raise_category_error(p_class, sqlstate, v_constraint, v_message);
end
$$;
comment on function recipes.rename_top_category(recipes.category_class, uuid, text, text) is
  'Cambia el nombre de un rubro (el código no cambia). Pide el permiso de su clase y un motivo.';

-- Baja: si tiene materias primas o recetas (también en sus subcategorías), se pasan todas al rubro
-- destino, de la misma clase y activo, en la misma transacción. Devuelve cuántas se pasaron.
create function recipes.deactivate_top_category(p_class recipes.category_class, p_id uuid, p_reason text,
                                                p_target_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group  uuid := recipes.top_category_group(p_class, p_id);
  v_active boolean;
  v_ids    uuid[];
  v_uses   integer;
  v_wrong  integer;
  v_ok     boolean;
begin
  -- Se bloquean el rubro y sus subcategorías: quien les asigne algo en este momento espera (los triggers
  -- leen con «for share») y después ve la baja.
  if p_class = 'purchase' then
    perform 1 from catalog.ingredient_categories where id = p_id or parent_id = p_id for update;
    select is_active into v_active from catalog.ingredient_categories where id = p_id;
    v_ids := array(select id from catalog.ingredient_categories
                    where (id = p_id or parent_id = p_id) and deleted_at is null);
    select count(*) into v_uses from catalog.ingredients where category_id = any (v_ids) and deleted_at is null;
  else
    perform 1 from recipes.recipe_categories where id = p_id or parent_id = p_id for update;
    select is_active into v_active from recipes.recipe_categories where id = p_id;
    v_ids := array(select id from recipes.recipe_categories
                    where (id = p_id or parent_id = p_id) and deleted_at is null);
    select count(*) into v_uses from recipes.recipes where category_id = any (v_ids) and deleted_at is null;
    -- Recetas cargadas antes de los rubros en la clase equivocada: no se pueden pasar a un rubro de esta clase.
    select count(*) into v_wrong from recipes.recipes
     where category_id = any (v_ids) and deleted_at is null and (recipe_type = 'dish') <> (p_class = 'menu');
    if v_wrong > 0 then
      raise exception '% de la otra clase (un plato va en menú; una preparación o un componente, en sub-recetas): %',
        case when v_wrong = 1 then 'Tiene 1 receta' else format('Tiene %s recetas', v_wrong) end,
        'corregí su rubro antes de darlo de baja.'
        using errcode = '23514';
    end if;
  end if;
  if not v_active then
    raise exception 'Ese rubro ya está dado de baja.' using errcode = '23514';
  end if;
  if v_uses > 0 then
    if p_target_id is null then
      raise exception 'Tiene % %: elegí a qué rubro %pasarl% antes de darlo de baja.', v_uses,
        case when p_class = 'purchase' then (case when v_uses = 1 then 'materia prima' else 'materias primas' end)
             else (case when v_uses = 1 then 'receta' else 'recetas' end) end,
        '', case when v_uses = 1 then 'a' else 'as' end
        using errcode = '23514';
    end if;
    -- El destino: otro rubro vigente y activo, de la misma clase y del mismo grupo.
    if p_class = 'purchase' then
      select true into v_ok from catalog.ingredient_categories
       where id = p_target_id and id <> p_id and group_id = v_group and parent_id is null and deleted_at is null
         and is_active for share;
    else
      select true into v_ok from recipes.recipe_categories
       where id = p_target_id and id <> p_id and group_id = v_group and parent_id is null and deleted_at is null
         and is_active and kind = p_class for share;
    end if;
    if v_ok is null then
      raise exception 'Elegí otro rubro activo de la misma clase como destino.' using errcode = '22023';
    end if;
  end if;
  perform core.set_change_context(p_reason, 'manual');
  -- Primero la baja y después el pase: así catalog.guard_priced_ingredient ve que las materias primas con
  -- precio salen de un rubro dado de baja, y deja hacerlo a Compras (decisión de Joaco, 2026-11-10).
  if p_class = 'purchase' then
    update catalog.ingredient_categories set is_active = false where id = p_id;
  else
    update recipes.recipe_categories set is_active = false where id = p_id;
  end if;
  if v_uses > 0 then
    if p_class = 'purchase' then
      update catalog.ingredients set category_id = p_target_id where category_id = any (v_ids) and deleted_at is null;
    else
      update recipes.recipes set category_id = p_target_id where category_id = any (v_ids) and deleted_at is null;
    end if;
  end if;
  return v_uses;
end
$$;
comment on function recipes.deactivate_top_category(recipes.category_class, uuid, text, uuid) is
  'Da de baja un rubro (se puede reactivar). Si tiene materias primas o recetas, también en sus subcategorías, las pasa al rubro destino (misma clase, activo) en la misma transacción. Pide el permiso de su clase y un motivo.';

create function recipes.reactivate_top_category(p_class recipes.category_class, p_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_active boolean;
begin
  perform recipes.top_category_group(p_class, p_id);
  if p_class = 'purchase' then
    select is_active into v_active from catalog.ingredient_categories where id = p_id for update;
  else
    select is_active into v_active from recipes.recipe_categories where id = p_id for update;
  end if;
  if v_active then
    raise exception 'Ese rubro ya está activo.' using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  if p_class = 'purchase' then
    update catalog.ingredient_categories set is_active = true where id = p_id;
  else
    update recipes.recipe_categories set is_active = true where id = p_id;
  end if;
end
$$;
comment on function recipes.reactivate_top_category(recipes.category_class, uuid, text) is
  'Vuelve a activar un rubro dado de baja. Pide el permiso de su clase y un motivo.';

-- Las funciones de escritura: solo authenticated (ADR-0005).
revoke execute on function recipes.create_top_category(uuid, recipes.category_class, text, text),
  recipes.rename_top_category(recipes.category_class, uuid, text, text),
  recipes.deactivate_top_category(recipes.category_class, uuid, text, uuid),
  recipes.reactivate_top_category(recipes.category_class, uuid, text) from public, anon;
grant execute on function recipes.create_top_category(uuid, recipes.category_class, text, text),
  recipes.rename_top_category(recipes.category_class, uuid, text, text),
  recipes.deactivate_top_category(recipes.category_class, uuid, text, uuid),
  recipes.reactivate_top_category(recipes.category_class, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Materias primas con precio al dar de baja su rubro (decisión de Joaco, 2026-11-10)
-- ---------------------------------------------------------------------------
-- La regla de ADR-0029 sigue: con precios aprobados, la unidad de uso no cambia y la categoría la cambia quien
-- configura precios (Dirección). Se agrega un caso: si la materia prima sale de un rubro dado de baja, también
-- la puede pasar Compras (catalog.manage). Es lo que hace recipes.deactivate_top_category, que da de baja antes
-- de pasar. Un rubro dado de baja no recibe nada nuevo, así que no se pueden mover materias primas sueltas por
-- este caso. Pero dar de baja y reactivar enseguida permite a Compras cambiar cuándo vencen los precios de todo un
-- rubro sin Dirección. Joaco lo aceptó el 2026-11-10, porque queda auditado (ADR-0038, Riesgos).
create or replace function catalog.guard_priced_ingredient()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.recipe_unit_id is distinct from old.recipe_unit_id or new.category_id is distinct from old.category_id)
     and exists (select 1 from costing.price_records p join catalog.purchase_products pp on pp.id = p.purchase_product_id
                  where pp.ingredient_id = new.id and p.deleted_at is null) then
    if new.recipe_unit_id is distinct from old.recipe_unit_id then
      raise exception 'Esta materia prima ya tiene precios: su unidad de uso no cambia (los precios se guardaron en esa unidad).'
        using errcode = '23514';
    end if;
    if core.current_actor_id() is not null
       and not core.has_permission_in_group('prices.configure', new.group_id)
       and not (core.has_permission_in_group('catalog.manage', new.group_id)
                and exists (select 1 from catalog.ingredient_categories c
                              left join catalog.ingredient_categories r on r.id = c.parent_id
                             where c.id = old.category_id and not coalesce(r.is_active, c.is_active))) then
      raise exception 'Esta materia prima ya tiene precios: cambiar su categoría cambia cuándo un precio está desactualizado, y eso lo decide Dirección General.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end
$$;
comment on function catalog.guard_priced_ingredient() is
  'Trigger de catalog.ingredients: con precios aprobados, la unidad de uso no cambia y la categoría la cambia quien tiene prices.configure, o quien tiene catalog.manage si la saca de un rubro dado de baja (ADR-0038).';
revoke execute on function catalog.guard_priced_ingredient() from public;

-- ---------------------------------------------------------------------------
-- 11. Cambiar un rubro de recetas pide recipes.manage_categories, por cualquier camino (revisión de seguridad)
-- ---------------------------------------------------------------------------
-- recipes.rename_category y recipes.archive_category (de antes de los rubros) piden recipes.draft y aceptan un
-- rubro. El trigger hace valer el permiso propio en la tabla, así no hay dos reglas: si Soy se lo saca a un rol,
-- ese rol ya no renombra ni borra rubros por la función vieja. Las subcategorías siguen con recipes.draft. Sin
-- persona en la sesión (migraciones, seed) no se controla, como en los demás guardias.
create function recipes.guard_top_category()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.parent_id is null and old.kind is not null and core.current_actor_id() is not null
     and not recipes.can_manage_category(old.kind, old.group_id) then
    raise exception 'No tenés permiso para editar este rubro.' using errcode = '42501';
  end if;
  return new;
end
$$;
comment on function recipes.guard_top_category() is
  'Trigger de recipes.recipe_categories: cambiar un rubro (primer nivel) pide recipes.manage_categories para todo el grupo, también desde las funciones de antes de los rubros.';
revoke execute on function recipes.guard_top_category() from public;
create trigger guard_top_category before update on recipes.recipe_categories
  for each row execute function recipes.guard_top_category();
