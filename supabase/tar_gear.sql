-- Tour des Aiguilles Rouges 2027 · lista de material compartida
-- Ejecutar una vez en Supabase → SQL Editor. Crea una tabla aparte (no toca nada existente).
-- Acceso: la tabla queda cerrada a la anon key; solo se lee/escribe mediante dos funciones
-- que exigen el código secreto del viaje (≥ 16 caracteres) que va en el enlace compartido.

create table if not exists public.tar_gear_items (
  trip        text        not null,
  item_id     text        not null,
  data        jsonb       not null default '{}'::jsonb,
  deleted     boolean     not null default false,
  updated_at  timestamptz not null default clock_timestamp(),
  primary key (trip, item_id)
);

alter table public.tar_gear_items enable row level security;
-- Sin políticas: anon/authenticated no pueden leer ni escribir la tabla directamente.
revoke all on public.tar_gear_items from anon, authenticated;

create or replace function public.tar_get(p_trip text, p_since timestamptz default '-infinity')
returns setof public.tar_gear_items
language sql stable security definer set search_path = public as $$
  select * from public.tar_gear_items
  where trip = p_trip and length(p_trip) >= 16 and updated_at > p_since
  order by updated_at
$$;

create or replace function public.tar_put(p_trip text, p_item text, p_data jsonb, p_deleted boolean default false)
returns timestamptz
language plpgsql security definer set search_path = public as $$
declare t timestamptz := clock_timestamp();
begin
  if length(p_trip) < 16 or length(p_trip) > 64 then raise exception 'codigo de viaje no valido'; end if;
  if length(p_item) > 64 or pg_column_size(p_data) > 4000 then raise exception 'item demasiado grande'; end if;
  if (select count(*) from public.tar_gear_items where trip = p_trip) >= 400
     and not exists (select 1 from public.tar_gear_items where trip = p_trip and item_id = p_item) then
    raise exception 'demasiados items';
  end if;
  insert into public.tar_gear_items (trip, item_id, data, deleted, updated_at)
  values (p_trip, p_item, coalesce(p_data, '{}'::jsonb), p_deleted, t)
  on conflict (trip, item_id) do update
    set data = excluded.data, deleted = excluded.deleted, updated_at = t;
  return t;
end $$;

revoke all on function public.tar_get(text, timestamptz) from public;
revoke all on function public.tar_put(text, text, jsonb, boolean) from public;
grant execute on function public.tar_get(text, timestamptz) to anon, authenticated;
grant execute on function public.tar_put(text, text, jsonb, boolean) to anon, authenticated;
