-- ════════════════════════════════════════════════════════════════════════
--  FEBECA · Migración 006
--  Alta de usuarios, catálogo de marcas y flujo de asignación
-- ════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────
--  1. PERFIL AUTOMÁTICO AL REGISTRARSE
--  Supabase Auth crea la fila en auth.users; este trigger crea la de
--  app.perfiles con rol 'lectura' y sin marcas. Nadie nace con permisos.
-- ─────────────────────────────────────────────────────────────────────

create or replace function app.fn_nuevo_usuario() returns trigger
language plpgsql security definer set search_path = app, public as $$
begin
  insert into app.perfiles (id, nombre, rol, activo)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nombre',
             new.raw_user_meta_data->>'full_name',
             split_part(new.email, '@', 1)),
    'lectura',
    true
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists al_crear_usuario on auth.users;
create trigger al_crear_usuario
  after insert on auth.users
  for each row execute function app.fn_nuevo_usuario();

-- Cambiar el rol de alguien. Solo admin y gerencia; nadie se cambia a sí
-- mismo (evita que gerencia se auto-promueva a admin sin rastro de otro).
create or replace function app.cambiar_rol(p_usuario uuid, p_rol app.rol)
returns void language plpgsql security invoker set search_path = app, public as $$
begin
  if not app.gestiona_usuarios() then
    raise exception 'Solo admin o gerencia puede cambiar roles';
  end if;
  if p_usuario = auth.uid() then
    raise exception 'No puedes cambiar tu propio rol';
  end if;
  if p_rol = 'admin' and app.rol_actual() <> 'admin' then
    raise exception 'Solo un admin puede nombrar a otro admin';
  end if;
  update app.perfiles set rol = p_rol, actualizado_en = now() where id = p_usuario;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
--  2. MARCAS: CLASIFICACIÓN PENDIENTE
--  Una marca recién descubierta no tiene origen hasta que alguien lo
--  decida. Mientras tanto no se puede asignar: si se asignara, no la
--  vería ninguno de los dos jefes.
-- ─────────────────────────────────────────────────────────────────────

alter table app.marcas
  alter column origen drop not null,
  add column if not exists codigo_maestro    text,     -- 'MARCA COM.' del maestro, p.ej. '214'
  add column if not exists proveedor         text,
  add column if not exists venta_12m_usd     numeric(18,2),
  add column if not exists descubierta_en    timestamptz not null default now(),
  add column if not exists clasificada_por   uuid references app.perfiles(id),
  add column if not exists clasificada_en    timestamptz;

create index if not exists marcas_sin_clasificar_idx on app.marcas (id) where origen is null;

create or replace function app.clasificar_marca(p_marca uuid, p_origen app.origen_marca)
returns void language plpgsql security invoker set search_path = app, public as $$
begin
  if not app.gestiona_usuarios() then
    raise exception 'Solo admin o gerencia clasifica marcas';
  end if;
  update app.marcas
     set origen = p_origen, clasificada_por = auth.uid(), clasificada_en = now()
   where id = p_marca;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
--  3. IMPORTAR EL CATÁLOGO DESDE EL SIM
--
--  Fuente: exportación con Parameter = Marca, SIN filtro U_MARCA,
--  12 meses, indicador Venta Neta. Una fila por marca con venta.
--  Es la única lista fiable de qué marcas están vivas hoy.
--
--  Las marcas nuevas entran con origen NULL. Las existentes solo
--  actualizan su venta de referencia; su clasificación no se toca.
-- ─────────────────────────────────────────────────────────────────────

create or replace function app.importar_catalogo_marcas(
  p_marcas jsonb   -- [{"codigo":"PCP","nombre":"PCP","venta_12m_usd":1584210}, ...]
) returns table (nuevas int, actualizadas int, sin_clasificar int)
language plpgsql security invoker set search_path = app, public as $$
declare v_nuevas int; v_act int; v_pend int;
begin
  if not app.gestiona_usuarios() then
    raise exception 'Solo admin o gerencia importa el catálogo de marcas';
  end if;

  with src as (
    select upper(trim(x.codigo)) as codigo,
           coalesce(nullif(trim(x.nombre),''), upper(trim(x.codigo))) as nombre,
           x.venta_12m_usd
    from jsonb_to_recordset(p_marcas) as x(codigo text, nombre text, venta_12m_usd numeric)
    where x.codigo is not null and trim(x.codigo) <> ''
  ),
  ins as (
    insert into app.marcas (codigo, nombre, venta_12m_usd, activa)
    select codigo, nombre, venta_12m_usd, true from src
    on conflict (codigo) do update
      set venta_12m_usd = excluded.venta_12m_usd,
          nombre = case when app.marcas.nombre = app.marcas.codigo
                        then excluded.nombre else app.marcas.nombre end,
          activa = true
    returning (xmax = 0) as nueva
  )
  select count(*) filter (where nueva), count(*) filter (where not nueva)
    into v_nuevas, v_act from ins;

  select count(*) into v_pend from app.marcas where origen is null and activa;
  return query select v_nuevas, v_act, v_pend;
end;
$$;

-- Enriquecer desde el maestro de materiales (código interno y proveedor).
-- El maestro está desactualizado: solo completa lo que falta, no manda.
create or replace function app.enriquecer_marcas_desde_maestro(
  p_filas jsonb   -- [{"nombre":"STANLEY","codigo_maestro":"214","proveedor":"NINGBO..."}, ...]
) returns int
language plpgsql security invoker set search_path = app, public as $$
declare v_n int;
begin
  if not app.gestiona_usuarios() then
    raise exception 'Solo admin o gerencia';
  end if;
  with src as (
    select upper(trim(x.nombre)) as nombre, x.codigo_maestro, x.proveedor
    from jsonb_to_recordset(p_filas) as x(nombre text, codigo_maestro text, proveedor text)
  ),
  upd as (
    update app.marcas m
       set codigo_maestro = coalesce(m.codigo_maestro, s.codigo_maestro),
           proveedor      = coalesce(m.proveedor, s.proveedor)
      from src s
     where upper(m.nombre) = s.nombre or upper(m.codigo) = s.nombre
    returning 1
  )
  select count(*) into v_n from upd;
  return v_n;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
--  4. ASIGNAR EXIGE MARCA CLASIFICADA
-- ─────────────────────────────────────────────────────────────────────

create or replace function app.asignar_marca(
  p_marca_id uuid, p_usuario uuid,
  p_desde date default current_date, p_hasta date default null,
  p_titular boolean default true, p_motivo text default null
) returns bigint
language plpgsql security invoker set search_path = app, public as $$
declare v_id bigint; v_origen app.origen_marca; v_rol app.rol; v_activo boolean;
begin
  select origen into v_origen from app.marcas where id = p_marca_id and activa;
  if not found then
    raise exception 'Marca inexistente o inactiva';
  end if;
  if v_origen is null then
    raise exception 'La marca no está clasificada como nacional o internacional. '
                    'Pídele al administrador que la clasifique antes de asignarla.';
  end if;

  if not app.puede_asignar(p_marca_id) then
    raise exception 'No tienes alcance sobre esa marca para asignarla';
  end if;

  select rol, activo into v_rol, v_activo from app.perfiles where id = p_usuario;
  if not found or not v_activo then
    raise exception 'Usuario inexistente o desactivado';
  end if;
  if v_rol in ('admin','gerencia','jefe_compras') then
    raise exception 'El rol % ya ve la marca por su alcance; no necesita asignación directa', v_rol;
  end if;

  if exists (select 1 from app.usuario_marca
              where usuario_id = p_usuario and marca_id = p_marca_id
                and vigencia && daterange(p_desde, p_hasta, '[)')) then
    raise exception 'Esa persona ya tiene la marca asignada en ese rango de fechas';
  end if;

  insert into app.usuario_marca (usuario_id, marca_id, titular,
                                 vigente_desde, vigente_hasta, motivo, creado_por)
  values (p_usuario, p_marca_id, p_titular, p_desde, p_hasta, p_motivo, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
--  5. VISTAS PARA LA PANTALLA DE MARCAS
-- ─────────────────────────────────────────────────────────────────────

-- Pendientes de clasificar: lo primero que ve el admin al entrar.
create or replace view app.v_marcas_sin_clasificar with (security_invoker = true) as
select id, codigo, nombre, proveedor, venta_12m_usd, descubierta_en
from app.marcas
where origen is null and activa and app.gestiona_usuarios()
order by venta_12m_usd desc nulls last;

-- Catálogo completo con su estado operativo.
create or replace view app.v_marcas with (security_invoker = true) as
select m.id, m.codigo, m.nombre, m.origen, m.proveedor, m.venta_12m_usd, m.activa,
       (m.origen is null)                              as sin_clasificar,
       (select string_agg(p.nombre, ', ' order by um.titular desc, p.nombre)
          from app.usuario_marca um join app.perfiles p on p.id = um.usuario_id
         where um.marca_id = m.id and um.vigencia @> current_date and p.activo) as responsables,
       (select p.nombre from app.jefaturas j join app.perfiles p on p.id = j.usuario_id
         where j.origen = m.origen and j.vigencia @> current_date and p.activo
         order by j.vigente_hasta nulls first limit 1)                        as jefe,
       (select max(c.creado_en) from app.cargas c
         where c.marca_id = m.id and c.estado = 'ok')                          as ultima_carga,
       (select count(*) from app.entidades e
         where e.marca_id = m.id and e.grano = 'articulo' and e.activo)        as articulos,
       case
         when m.origen is null then 'sin clasificar'
         when not exists (select 1 from app.usuario_marca um
                           where um.marca_id = m.id and um.vigencia @> current_date)
              then 'sin responsable'
         when not exists (select 1 from app.cargas c where c.marca_id = m.id and c.estado = 'ok')
              then 'sin datos'
         else 'operativa'
       end as estado
from app.marcas m
where m.id in (select app.marcas_visibles())
   or app.gestiona_usuarios();

-- Para el buscador de la pantalla de asignación: qué compradores hay
-- disponibles y cuánto llevan ya.
create or replace view app.v_compradores with (security_invoker = true) as
select p.id, p.nombre, p.rol, p.activo,
       count(um.id) filter (where um.vigencia @> current_date)               as marcas_vigentes,
       string_agg(m.codigo, ', ' order by m.codigo)
         filter (where um.vigencia @> current_date)                           as marcas
from app.perfiles p
left join app.usuario_marca um on um.usuario_id = p.id
left join app.marcas m on m.id = um.marca_id
where p.rol in ('comprador','lectura')
  and (app.gestiona_usuarios() or app.rol_actual() = 'jefe_compras')
group by p.id, p.nombre, p.rol, p.activo;

-- ─────────────────────────────────────────────────────────────────────
--  6. SECUENCIA DE ARRANQUE (referencia)
-- ─────────────────────────────────────────────────────────────────────
--
--  -- a) Primer admin: se crea en Supabase Auth, el trigger le da perfil
--  --    'lectura', y se promueve UNA VEZ con el service role:
--  update app.perfiles set rol = 'admin' where id = '<uuid del primer admin>';
--
--  -- b) Importar el catálogo desde la exportación del SIM
--  --    (Parameter = Marca, sin filtro, 12 meses, Venta Neta):
--  select * from app.importar_catalogo_marcas('[{"codigo":"PCP","nombre":"PCP","venta_12m_usd":1584210}, ...]');
--
--  -- c) Enriquecer con el maestro (opcional; solo rellena huecos):
--  select app.enriquecer_marcas_desde_maestro('[{"nombre":"PCP","codigo_maestro":"PCP","proveedor":"BAMERICA CORPORATION"}, ...]');
--
--  -- d) Clasificar (pantalla de admin, una a una o en lote):
--  select app.clasificar_marca(id, 'internacional') from app.marcas where codigo in ('PCP','BOSCH','DAEWOO');
--  select app.clasificar_marca(id, 'nacional')      from app.marcas where codigo in ('TUBRICA','CODIRE');
--
--  -- e) Nombrar los dos jefes:
--  select app.nombrar_jefe('<jefe_intl>', 'internacional');
--  select app.nombrar_jefe('<jefe_nac>',  'nacional');
--
--  -- f) Invitar compradores (Supabase Auth → trigger crea perfil) y darles rol:
--  select app.cambiar_rol('<adriana>', 'comprador');
--
--  -- g) Asignar. El jefe de internacionales puede hacerlo directamente:
--  select app.asignar_marca((select id from app.marcas where codigo='PCP'), '<adriana>');
--
--  -- h) Verificar:
--  select * from app.v_marcas where estado <> 'operativa';
