-- ════════════════════════════════════════════════════════════════════════
--  FEBECA · Migración 004
--  Jefe de compras: alcance por ORIGEN de la marca, no por asignación
--
--  Hay exactamente dos jefes: uno de marcas nacionales y otro de marcas
--  internacionales. Su alcance no se define marca por marca —sería un
--  mantenimiento eterno cada vez que entra una marca nueva— sino por el
--  origen que supervisan. Una marca nueva cae sola bajo el jefe que toca.
--
--  Un comprador puede llevar marcas de ambos orígenes; en ese caso
--  responde ante un jefe por unas marcas y ante el otro por las demás.
--  El modelo lo soporta sin nada especial.
-- ════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────
--  0. NOTA SOBRE EL CAMBIO DE ENUM
--
--  Postgres no deja alterar un tipo del que dependen funciones o vistas.
--  El orden obligatorio es: soltar dependencias → cambiar el tipo →
--  reconstruir. La migración 002 no lo hacía y fallaba aquí; esto lo
--  deja corregido.
-- ─────────────────────────────────────────────────────────────────────

drop view if exists app.v_actividad;
drop view if exists app.v_asignaciones;
drop view if exists app.v_cumplimiento_carga;

drop function if exists app.rol_actual();
drop function if exists app.responsables(uuid, date);

alter type app.rol rename to rol_v3;
create type app.rol as enum ('admin','gerencia','jefe_compras','comprador','lectura');

alter table app.perfiles
  alter column rol drop default,
  alter column rol type app.rol using rol::text::app.rol,
  alter column rol set default 'lectura';

drop type app.rol_v3;

create or replace function app.rol_actual() returns app.rol
language sql stable security definer set search_path = app, public as $$
  select rol from app.perfiles where id = auth.uid() and activo
$$;

-- ─────────────────────────────────────────────────────────────────────
--  1. ORIGEN DE MARCA COMO TIPO
-- ─────────────────────────────────────────────────────────────────────

create type app.origen_marca as enum ('nacional','internacional');

alter table app.marcas drop constraint if exists marcas_origen_check;
alter table app.marcas
  alter column origen type app.origen_marca using origen::app.origen_marca,
  alter column origen set not null;

create index on app.marcas (origen) where activa;

-- ─────────────────────────────────────────────────────────────────────
--  2. JEFATURAS
--  Con vigencia temporal, igual que las asignaciones de marca: un jefe
--  también sale de vacaciones y el otro cubre los dos orígenes.
-- ─────────────────────────────────────────────────────────────────────

create table app.jefaturas (
  id             bigint generated always as identity primary key,
  usuario_id     uuid not null references app.perfiles(id) on delete cascade,
  origen         app.origen_marca not null,
  vigente_desde  date not null default current_date,
  vigente_hasta  date,
  motivo         text,
  creado_por     uuid references app.perfiles(id),
  creado_en      timestamptz not null default now(),
  constraint jefatura_rango_valido
    check (vigente_hasta is null or vigente_hasta > vigente_desde)
);

alter table app.jefaturas
  add column vigencia daterange
  generated always as (daterange(vigente_desde, vigente_hasta, '[)')) stored;

-- La misma persona no puede tener dos jefaturas solapadas del mismo
-- origen. Dos personas sí pueden solaparse: es el traspaso o la cobertura.
alter table app.jefaturas
  add constraint jefatura_sin_solapes
  exclude using gist (usuario_id with =, origen with =, vigencia with &&);

create index jefaturas_vigencia_idx on app.jefaturas using gist (vigencia);
create index jefaturas_origen_idx on app.jefaturas (origen)
  where vigente_hasta is null;

alter table app.jefaturas enable row level security;

create policy jefatura_lectura on app.jefaturas for select
  using (usuario_id = auth.uid() or app.rol_actual() in ('admin','gerencia','jefe_compras'));

create policy jefatura_gestion on app.jefaturas for all
  using (app.rol_actual() in ('admin','gerencia'))
  with check (app.rol_actual() in ('admin','gerencia'));

create trigger aud_jefaturas after insert or update or delete on app.jefaturas
  for each row execute function app.fn_auditar();

-- ─────────────────────────────────────────────────────────────────────
--  3. FUNCIONES DE ALCANCE
--
--  Hay tres alcances distintos y conviene no confundirlos:
--
--    marcas_asignadas()   → las que la persona lleva directamente
--    marcas_en_ambito()   → las que supervisa por ser jefe de ese origen
--    marcas_escribibles() → dónde puede cargar y corregir datos
--    marcas_visibles()    → dónde puede mirar
-- ─────────────────────────────────────────────────────────────────────

create or replace function app.es_jefe() returns boolean
language sql stable security definer set search_path = app, public as $$
  select exists (
    select 1 from app.jefaturas
     where usuario_id = auth.uid() and vigencia @> current_date
  )
$$;

create or replace function app.origenes_a_cargo() returns setof app.origen_marca
language sql stable security definer set search_path = app, public as $$
  select origen from app.jefaturas
   where usuario_id = auth.uid() and vigencia @> current_date
$$;

-- Marcas del o los orígenes que supervisa. Una marca nueva de ese origen
-- entra al ámbito sola, sin tocar nada.
create or replace function app.marcas_en_ambito() returns setof uuid
language sql stable security definer set search_path = app, public as $$
  select m.id from app.marcas m
   where m.activa and m.origen in (select app.origenes_a_cargo())
$$;

-- Dónde puede escribir. El jefe carga y corrige en todo su ámbito: es
-- quien cubre cuando un comprador no subió su marca a tiempo.
create or replace function app.marcas_escribibles() returns setof uuid
language sql stable security definer set search_path = app, public as $$
  select m.id from app.marcas m where app.rol_actual() = 'admin'
  union
  select app.marcas_asignadas()
  union
  select app.marcas_en_ambito()
$$;

-- Dónde puede mirar. Gerencia y admin ven todo; el jefe ve su ámbito;
-- el comprador ve lo suyo.
create or replace function app.marcas_visibles() returns setof uuid
language sql stable security definer set search_path = app, public as $$
  select m.id from app.marcas m where app.ve_todo()
  union
  select app.marcas_asignadas()
  union
  select app.marcas_en_ambito()
$$;

-- Puede cargar archivos. Se suma el jefe.
create or replace function app.puede_cargar() returns boolean
language sql stable security definer set search_path = app, public as $$
  select coalesce(app.rol_actual() in ('admin','comprador','jefe_compras'), false)
$$;

-- Puede asignar marcas y programar suplencias sobre una marca concreta.
-- Admin y gerencia sobre cualquiera; el jefe solo dentro de su ámbito.
create or replace function app.puede_asignar(p_marca uuid) returns boolean
language sql stable security definer set search_path = app, public as $$
  select app.gestiona_usuarios()
      or (app.rol_actual() = 'jefe_compras'
          and p_marca in (select app.marcas_en_ambito()))
$$;

-- El jefe ve la auditoría de su ámbito, no la del sistema entero.
create or replace function app.ve_auditoria() returns boolean
language sql stable security definer set search_path = app, public as $$
  select coalesce(app.rol_actual() in ('admin','gerencia'), false)
$$;

-- Los compradores que dependen de la persona que consulta.
create or replace function app.mi_equipo() returns setof uuid
language sql stable security definer set search_path = app, public as $$
  select distinct um.usuario_id
    from app.usuario_marca um
   where um.vigencia @> current_date
     and um.marca_id in (select app.marcas_en_ambito())
$$;

create or replace function app.responsables(p_marca uuid, p_fecha date default current_date)
returns table (usuario_id uuid, nombre text, titular boolean)
language sql stable security definer set search_path = app, public as $$
  select um.usuario_id, p.nombre, um.titular
  from app.usuario_marca um
  join app.perfiles p on p.id = um.usuario_id
  where um.marca_id = p_marca and um.vigencia @> p_fecha and p.activo
  order by um.titular desc, p.nombre
$$;

-- ─────────────────────────────────────────────────────────────────────
--  4. POLÍTICAS: la escritura pasa de marcas_asignadas a marcas_escribibles
-- ─────────────────────────────────────────────────────────────────────

drop policy if exists ent_escritura     on app.entidades;
drop policy if exists hecho_escritura   on app.hechos;
drop policy if exists periodo_escritura on app.periodos;
drop policy if exists carga_escritura   on app.cargas;
drop policy if exists ajuste_escritura  on app.ajustes;
drop policy if exists ajuste_anulacion  on app.ajustes;
drop policy if exists param_escritura   on app.parametros_marca;

create policy ent_escritura on app.entidades for all
  using (app.puede_cargar() and marca_id in (select app.marcas_escribibles()))
  with check (app.puede_cargar() and marca_id in (select app.marcas_escribibles()));

create policy hecho_escritura on app.hechos for all
  using (app.puede_cargar() and marca_id in (select app.marcas_escribibles()))
  with check (app.puede_cargar() and marca_id in (select app.marcas_escribibles()));

create policy periodo_escritura on app.periodos for all
  using (app.puede_cargar() and marca_id in (select app.marcas_escribibles()))
  with check (app.puede_cargar() and marca_id in (select app.marcas_escribibles()));

create policy carga_escritura on app.cargas for insert
  with check (app.puede_cargar()
              and marca_id in (select app.marcas_escribibles())
              and usuario_id = auth.uid());

create policy ajuste_escritura on app.ajustes for insert
  with check (app.puede_cargar()
              and marca_id in (select app.marcas_escribibles())
              and creado_por = auth.uid());

create policy ajuste_anulacion on app.ajustes for update
  using (app.rol_actual() = 'admin'
         or (app.puede_cargar() and marca_id in (select app.marcas_escribibles())))
  with check (anulado = true);

-- Parámetros de compra: el comprador los ajusta en sus marcas y el jefe
-- en todo su ámbito, porque es quien negocia los contratos marco.
create policy param_escritura on app.parametros_marca for all
  using (app.rol_actual() = 'admin'
         or marca_id in (select app.marcas_escribibles()))
  with check (app.rol_actual() = 'admin'
         or marca_id in (select app.marcas_escribibles()));

-- Asignaciones: el jefe puede mover compradores dentro de su ámbito.
drop policy if exists um_lectura on app.usuario_marca;
drop policy if exists um_gestion on app.usuario_marca;

create policy um_lectura on app.usuario_marca for select
  using (usuario_id = auth.uid()
         or app.gestiona_usuarios()
         or marca_id in (select app.marcas_en_ambito()));

create policy um_gestion on app.usuario_marca for all
  using (app.puede_asignar(marca_id))
  with check (app.puede_asignar(marca_id));

-- Perfiles: el jefe ve a su equipo, pero no crea usuarios ni cambia roles.
drop policy if exists perfil_lectura on app.perfiles;
create policy perfil_lectura on app.perfiles for select
  using (id = auth.uid()
         or app.gestiona_usuarios()
         or id in (select app.mi_equipo()));

-- ─────────────────────────────────────────────────────────────────────
--  5. OPERACIONES: el jefe entra donde corresponde
-- ─────────────────────────────────────────────────────────────────────

create or replace function app.asignar_marca(
  p_marca_id uuid, p_usuario uuid,
  p_desde date default current_date, p_hasta date default null,
  p_titular boolean default true, p_motivo text default null
) returns bigint
language plpgsql security invoker set search_path = app, public as $$
declare v_id bigint;
begin
  if not app.puede_asignar(p_marca_id) then
    raise exception 'No tienes alcance sobre esa marca para asignarla';
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

create or replace function app.terminar_asignacion(
  p_id bigint, p_hasta date default current_date, p_motivo text default null
) returns void
language plpgsql security invoker set search_path = app, public as $$
declare v_desde date; v_marca uuid;
begin
  select vigente_desde, marca_id into v_desde, v_marca
    from app.usuario_marca where id = p_id;
  if v_desde is null then
    raise exception 'Asignación % inexistente', p_id;
  end if;
  if not app.puede_asignar(v_marca) then
    raise exception 'No tienes alcance sobre esa marca';
  end if;
  if p_hasta <= v_desde then
    raise exception 'La fecha de fin debe ser posterior al inicio (%)', v_desde;
  end if;

  update app.usuario_marca
     set vigente_hasta = p_hasta, motivo = coalesce(p_motivo, motivo)
   where id = p_id;
end;
$$;

create or replace function app.reasignar_marca(
  p_marca_id uuid, p_nuevo_id uuid, p_quitar_al uuid default null,
  p_desde date default current_date, p_motivo text default null
) returns bigint
language plpgsql security invoker set search_path = app, public as $$
declare v_id bigint;
begin
  if not app.puede_asignar(p_marca_id) then
    raise exception 'No tienes alcance sobre esa marca';
  end if;

  if p_quitar_al is not null then
    update app.usuario_marca
       set vigente_hasta = p_desde,
           motivo = coalesce(p_motivo, 'Traspaso de marca')
     where marca_id = p_marca_id and usuario_id = p_quitar_al
       and vigencia @> p_desde;
  end if;

  select app.asignar_marca(p_marca_id, p_nuevo_id, p_desde, null, true,
                           coalesce(p_motivo, 'Traspaso de marca')) into v_id;
  return v_id;
end;
$$;

create or replace function app.programar_suplencia(
  p_marca_id uuid, p_suplente uuid, p_desde date, p_hasta date,
  p_motivo text default 'Suplencia por ausencia',
  p_suspender_titular boolean default false
) returns bigint
language plpgsql security invoker set search_path = app, public as $$
declare v_titular uuid; v_id bigint;
begin
  if not app.puede_asignar(p_marca_id) then
    raise exception 'No tienes alcance sobre esa marca';
  end if;
  if p_hasta <= p_desde then
    raise exception 'La suplencia debe terminar después de empezar';
  end if;

  if p_suspender_titular then
    select usuario_id into v_titular from app.usuario_marca
     where marca_id = p_marca_id and titular and vigencia @> p_desde limit 1;

    if v_titular is not null then
      update app.usuario_marca set vigente_hasta = p_desde
       where marca_id = p_marca_id and usuario_id = v_titular
         and vigencia @> p_desde;

      insert into app.usuario_marca (usuario_id, marca_id, titular,
                                     vigente_desde, motivo, creado_por)
      values (v_titular, p_marca_id, true, p_hasta, 'Retorno de ausencia', auth.uid());
    end if;
  end if;

  select app.asignar_marca(p_marca_id, p_suplente, p_desde, p_hasta, false, p_motivo)
    into v_id;
  return v_id;
end;
$$;

-- Nombrar jefe de un origen. Solo admin y gerencia.
create or replace function app.nombrar_jefe(
  p_usuario uuid, p_origen app.origen_marca,
  p_desde date default current_date, p_hasta date default null,
  p_motivo text default null
) returns bigint
language plpgsql security invoker set search_path = app, public as $$
declare v_id bigint;
begin
  if not app.gestiona_usuarios() then
    raise exception 'Solo admin o gerencia puede nombrar jefes de compras';
  end if;

  update app.perfiles set rol = 'jefe_compras', actualizado_en = now()
   where id = p_usuario and rol not in ('admin','gerencia');

  insert into app.jefaturas (usuario_id, origen, vigente_desde, vigente_hasta,
                             motivo, creado_por)
  values (p_usuario, p_origen, p_desde, p_hasta, p_motivo, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

-- Cobertura entre jefes: el de nacionales cubre también internacionales
-- durante una ausencia, y se revierte solo.
create or replace function app.cubrir_jefatura(
  p_suplente uuid, p_origen app.origen_marca,
  p_desde date, p_hasta date, p_motivo text default 'Cobertura de jefatura'
) returns bigint
language plpgsql security invoker set search_path = app, public as $$
begin
  if not app.gestiona_usuarios() then
    raise exception 'Solo admin o gerencia puede asignar coberturas de jefatura';
  end if;
  if p_hasta <= p_desde then
    raise exception 'La cobertura debe terminar después de empezar';
  end if;
  return app.nombrar_jefe(p_suplente, p_origen, p_desde, p_hasta, p_motivo);
end;
$$;

create or replace function app.desactivar_usuario(p_usuario_id uuid)
returns void language plpgsql security invoker set search_path = app, public as $$
begin
  if not app.gestiona_usuarios() then
    raise exception 'Solo admin o gerencia puede desactivar usuarios';
  end if;
  if p_usuario_id = auth.uid() then
    raise exception 'No puedes desactivarte a ti mismo';
  end if;

  update app.perfiles set activo = false, actualizado_en = now()
   where id = p_usuario_id;

  update app.usuario_marca
     set vigente_hasta = current_date, motivo = coalesce(motivo,'Usuario desactivado')
   where usuario_id = p_usuario_id and vigencia @> current_date
     and vigente_desde < current_date;
  delete from app.usuario_marca
   where usuario_id = p_usuario_id and vigente_desde >= current_date;

  update app.jefaturas
     set vigente_hasta = current_date, motivo = coalesce(motivo,'Usuario desactivado')
   where usuario_id = p_usuario_id and vigencia @> current_date
     and vigente_desde < current_date;
  delete from app.jefaturas
   where usuario_id = p_usuario_id and vigente_desde >= current_date;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
--  6. VISTAS
-- ─────────────────────────────────────────────────────────────────────

create or replace view app.v_jefaturas with (security_invoker = true) as
select j.id, j.usuario_id, p.nombre as jefe, j.origen,
       j.vigente_desde, j.vigente_hasta, j.motivo,
       case
         when j.vigente_desde > current_date then 'programada'
         when j.vigencia @> current_date and j.vigente_hasta is null then 'vigente'
         when j.vigencia @> current_date then 'cobertura temporal'
         else 'terminada'
       end as estado,
       (select count(*) from app.marcas m where m.activa and m.origen = j.origen) as marcas_en_ambito
from app.jefaturas j
join app.perfiles p on p.id = j.usuario_id
where app.rol_actual() in ('admin','gerencia') or j.usuario_id = auth.uid();

-- Orígenes que se quedaron sin jefe vigente.
create or replace view app.v_origenes_sin_jefe with (security_invoker = true) as
select o.origen,
       (select count(*) from app.marcas m where m.activa and m.origen = o.origen) as marcas
from (select unnest(enum_range(null::app.origen_marca)) as origen) o
where app.ve_todo()
  and not exists (
    select 1 from app.jefaturas j
     join app.perfiles p on p.id = j.usuario_id and p.activo
    where j.origen = o.origen and j.vigencia @> current_date
  );

create or replace view app.v_asignaciones with (security_invoker = true) as
select um.id, um.marca_id, m.codigo as marca, m.origen,
       um.usuario_id, p.nombre as usuario, p.rol, p.activo as usuario_activo,
       um.titular, um.vigente_desde, um.vigente_hasta, um.motivo,
       case
         when um.vigente_desde > current_date then 'programada'
         when um.vigencia @> current_date and um.titular then 'vigente'
         when um.vigencia @> current_date then 'suplencia activa'
         else 'terminada'
       end as estado,
       case when um.vigente_hasta is not null and um.vigencia @> current_date
            then um.vigente_hasta - current_date end as dias_restantes
from app.usuario_marca um
join app.marcas   m on m.id = um.marca_id
join app.perfiles p on p.id = um.usuario_id
where app.gestiona_usuarios()
   or um.usuario_id = auth.uid()
   or um.marca_id in (select app.marcas_en_ambito());

create or replace view app.v_cumplimiento_carga with (security_invoker = true) as
select p.id as usuario_id, p.nombre, m.codigo as marca, m.origen,
       um.titular, um.vigente_hasta,
       max(c.creado_en) as ultima_carga,
       count(c.id) filter (where c.creado_en > now() - interval '7 days') as cargas_semana,
       bool_or(c.truncado) filter (where c.creado_en > now() - interval '7 days') as tuvo_truncados,
       case
         when max(c.creado_en) is null then 'sin cargar nunca'
         when max(c.creado_en) < now() - interval '14 days' then 'atrasado'
         when max(c.creado_en) < now() - interval '7 days'  then 'pendiente'
         else 'al día'
       end as estado
from app.usuario_marca um
join app.perfiles p on p.id = um.usuario_id and p.activo
join app.marcas   m on m.id = um.marca_id
left join app.cargas c on c.marca_id = um.marca_id and c.usuario_id = um.usuario_id
where um.vigencia @> current_date
  and (app.ve_todo()
       or um.usuario_id = auth.uid()
       or um.marca_id in (select app.marcas_en_ambito()))
group by p.id, p.nombre, m.codigo, m.origen, um.titular, um.vigente_hasta;

-- Tablero del jefe: su equipo, cuántas marcas lleva cada quien y cómo va.
create or replace view app.v_equipo with (security_invoker = true) as
select p.id as usuario_id, p.nombre, p.rol, p.activo,
       count(distinct um.marca_id)                            as marcas,
       count(distinct um.marca_id) filter (where not um.titular) as como_suplente,
       max(c.creado_en)                                       as ultima_carga,
       count(distinct um.marca_id) filter (
         where not exists (select 1 from app.cargas c2
                            where c2.marca_id = um.marca_id
                              and c2.creado_en > now() - interval '7 days')
       ) as marcas_sin_cargar_esta_semana
from app.usuario_marca um
join app.perfiles p on p.id = um.usuario_id
left join app.cargas c on c.usuario_id = p.id and c.marca_id = um.marca_id
where um.vigencia @> current_date
  and (app.ve_todo() or um.marca_id in (select app.marcas_en_ambito()))
group by p.id, p.nombre, p.rol, p.activo;

-- Feed de actividad, ahora también acotado al ámbito del jefe.
create or replace view app.v_actividad with (security_invoker = true) as
select c.creado_en as cuando, p.nombre as quien, p.rol as rol,
       m.codigo as marca, m.origen, 'carga' as tipo,
       case
         when c.estado = 'revertida' then 'Revirtió la carga de ' || c.archivo_nombre
         when c.truncado then 'Cargó ' || c.archivo_nombre || ' (EXPORTACIÓN TRUNCADA)'
         else 'Cargó ' || c.archivo_nombre || ' · ' || c.grano::text
              || ' · ' || c.hechos_escritos || ' datos'
       end as detalle,
       c.truncado as requiere_atencion, c.id::text as referencia
from app.cargas c
join app.perfiles p on p.id = c.usuario_id
join app.marcas   m on m.id = c.marca_id
where c.marca_id in (select app.marcas_visibles())

union all

select a.creado_en, coalesce(p.nombre,'sistema'), p.rol, m.codigo, m.origen, 'cambio',
  case a.tabla
    when 'ajustes' then
      case when (a.despues->>'anulado')::boolean then 'Anuló un ajuste manual'
           else 'Ajustó un valor a mano: ' || coalesce(a.despues->>'motivo','sin motivo') end
    when 'jefaturas' then
      case a.accion
        when 'insert' then 'Nombró jefe de marcas ' || (a.despues->>'origen')
             || ' desde el ' || (a.despues->>'vigente_desde')
             || coalesce(' hasta el ' || (a.despues->>'vigente_hasta'), '')
        when 'update' then 'Modificó una jefatura de compras'
        else 'Eliminó una jefatura programada' end
    when 'usuario_marca' then
      case
        when a.accion = 'insert' and (a.despues->>'titular')::boolean = false then
          'Programó una suplencia del ' || (a.despues->>'vigente_desde')
          || ' al ' || coalesce(a.despues->>'vigente_hasta','indefinido')
        when a.accion = 'insert' then 'Asignó la marca desde el ' || (a.despues->>'vigente_desde')
        when a.accion = 'update' and (a.antes->>'vigente_hasta') is null
             and (a.despues->>'vigente_hasta') is not null then
          'Terminó la asignación el ' || (a.despues->>'vigente_hasta')
          || coalesce(' · ' || (a.despues->>'motivo'), '')
        when a.accion = 'delete' then 'Eliminó una asignación programada'
        else 'Cambió una asignación de marca' end
    when 'perfiles' then
      case a.accion
        when 'insert' then 'Creó el usuario ' || coalesce(a.despues->>'nombre','')
        when 'update' then
          case when (a.antes->>'rol') is distinct from (a.despues->>'rol')
               then 'Cambió el rol de ' || coalesce(a.despues->>'nombre','')
                    || ': ' || (a.antes->>'rol') || ' → ' || (a.despues->>'rol')
               when (a.antes->>'activo') is distinct from (a.despues->>'activo')
               then case when (a.despues->>'activo')::boolean then 'Reactivó a ' else 'Desactivó a ' end
                    || coalesce(a.despues->>'nombre','')
               else 'Editó el usuario ' || coalesce(a.despues->>'nombre','') end
        else 'Modificó un usuario' end
    when 'parametros_marca' then 'Cambió los parámetros de compra'
    when 'marcas' then 'Modificó una marca'
    else a.accion || ' en ' || a.tabla
  end,
  (a.tabla in ('perfiles','usuario_marca','jefaturas','ajustes')),
  a.registro_id
from app.auditoria a
left join app.perfiles p on p.id = a.usuario_id
left join app.marcas   m on m.id = a.marca_id
where app.ve_auditoria()
   or a.marca_id in (select app.marcas_asignadas())
   or a.marca_id in (select app.marcas_en_ambito());

-- ─────────────────────────────────────────────────────────────────────
--  7. EJEMPLOS
-- ─────────────────────────────────────────────────────────────────────
--
--  -- Los dos jefes
--  select app.nombrar_jefe('<jefe_intl>', 'internacional');
--  select app.nombrar_jefe('<jefe_nac>',  'nacional');
--
--  -- El jefe de internacionales asigna PCP a Adriana (PCP es internacional,
--  -- así que está dentro de su ámbito y no necesita a gerencia)
--  select app.asignar_marca('<pcp>', '<adriana>');
--
--  -- El jefe de nacionales se va dos semanas; lo cubre el de internacionales
--  select app.cubrir_jefatura('<jefe_intl>', 'nacional',
--         date '2026-12-01', date '2026-12-16');
--
--  -- Tableros
--  select * from app.v_equipo order by marcas_sin_cargar_esta_semana desc;
--  select * from app.v_jefaturas;
--  select * from app.v_origenes_sin_jefe;
