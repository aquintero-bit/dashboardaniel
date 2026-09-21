-- ════════════════════════════════════════════════════════════════════════
--  FEBECA · Migración 003
--  Asignaciones de marca con vigencia temporal
--
--  Antes: usuario_marca era una relación plana, sin fechas. Quitarle una
--  marca a alguien era un DELETE y se perdía el rastro de quién la llevaba
--  en agosto.
--
--  Ahora: cada asignación tiene un rango de fechas. El permiso caduca solo,
--  sin ningún job programado, porque la vigencia se evalúa en cada consulta.
--  Una suplencia de vacaciones se registra hoy con las fechas de la semana
--  que viene y se activa y desactiva sola.
-- ════════════════════════════════════════════════════════════════════════

create extension if not exists btree_gist;

-- ─────────────────────────────────────────────────────────────────────
--  1. NUEVA ESTRUCTURA DE usuario_marca
-- ─────────────────────────────────────────────────────────────────────

alter table app.usuario_marca drop constraint usuario_marca_pkey;

alter table app.usuario_marca
  add column id             bigint generated always as identity,
  add column vigente_desde  date,
  add column vigente_hasta  date,          -- null = indefinido
  add column motivo         text,
  add column creado_por     uuid references app.perfiles(id);

-- Las asignaciones existentes arrancan el día en que se crearon y siguen
-- abiertas.
update app.usuario_marca
   set vigente_desde = coalesce(asignado_en::date, current_date)
 where vigente_desde is null;

alter table app.usuario_marca
  alter column vigente_desde set not null,
  alter column vigente_desde set default current_date,
  add primary key (id),
  add constraint rango_valido
      check (vigente_hasta is null or vigente_hasta > vigente_desde);

-- Rango materializado para poder indexarlo y comparar solapes.
-- '[)' = incluye el día de inicio, excluye el de fin. Así una asignación
-- que termina el 30 y otra que empieza el 30 no se solapan.
alter table app.usuario_marca
  add column vigencia daterange
  generated always as (daterange(vigente_desde, vigente_hasta, '[)')) stored;

-- Una misma persona no puede tener dos asignaciones solapadas sobre la
-- misma marca. Dos personas distintas sí pueden solaparse: es exactamente
-- lo que pasa durante una suplencia.
alter table app.usuario_marca
  add constraint sin_solapes
  exclude using gist (usuario_id with =, marca_id with =, vigencia with &&);

create index usuario_marca_vigencia_idx on app.usuario_marca using gist (vigencia);
create index usuario_marca_activa_idx on app.usuario_marca (marca_id, usuario_id)
  where vigente_hasta is null;

comment on column app.usuario_marca.titular is
  'true = responsable de la marca. false = suplente que cubre temporalmente.';

-- ─────────────────────────────────────────────────────────────────────
--  2. FUNCIONES DE VIGENCIA
-- ─────────────────────────────────────────────────────────────────────

-- Marcas que la persona tiene asignadas HOY. Es la que gobierna la
-- escritura: si la asignación venció, se acabó el permiso de cargar.
create or replace function app.marcas_asignadas() returns setof uuid
language sql stable security definer set search_path = app, public as $$
  select marca_id from app.usuario_marca
   where usuario_id = auth.uid()
     and vigencia @> current_date
$$;

-- Misma consulta a una fecha cualquiera. Sirve para auditar: "¿quién
-- llevaba PCP cuando se cargó este archivo?"
create or replace function app.marcas_asignadas_en(p_usuario uuid, p_fecha date)
returns setof uuid
language sql stable security definer set search_path = app, public as $$
  select marca_id from app.usuario_marca
   where usuario_id = p_usuario and vigencia @> p_fecha
$$;

-- Marcas que la persona llevó alguna vez, vigentes o no.
create or replace function app.marcas_historicas() returns setof uuid
language sql stable security definer set search_path = app, public as $$
  select distinct marca_id from app.usuario_marca where usuario_id = auth.uid()
$$;

-- Visibilidad de lectura. Por defecto el acceso termina con la asignación:
-- si un comprador deja de llevar una marca, deja de ver sus datos.
-- Para que conserve acceso de solo lectura a lo que llevó antes, cambiar
-- marcas_asignadas() por marcas_historicas() en esta función. La escritura
-- no se ve afectada porque usa marcas_asignadas() directamente.
create or replace function app.marcas_visibles() returns setof uuid
language sql stable security definer set search_path = app, public as $$
  select m.id from app.marcas m where app.ve_todo()
  union
  select app.marcas_asignadas()
$$;

-- Quién responde por una marca en una fecha dada.
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
--  3. OPERACIONES DE ASIGNACIÓN
-- ─────────────────────────────────────────────────────────────────────

-- Asignar una marca. Si ya la tiene vigente, no hace nada.
create or replace function app.asignar_marca(
  p_marca_id  uuid,
  p_usuario   uuid,
  p_desde     date default current_date,
  p_hasta     date default null,
  p_titular   boolean default true,
  p_motivo    text default null
) returns bigint
language plpgsql security invoker set search_path = app, public as $$
declare v_id bigint;
begin
  if not app.gestiona_usuarios() then
    raise exception 'Solo admin o gerencia puede asignar marcas';
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

-- Cerrar una asignación. Nunca se borra: se le pone fecha de fin.
create or replace function app.terminar_asignacion(
  p_id     bigint,
  p_hasta  date default current_date,
  p_motivo text default null
) returns void
language plpgsql security invoker set search_path = app, public as $$
declare v_desde date;
begin
  if not app.gestiona_usuarios() then
    raise exception 'Solo admin o gerencia puede terminar asignaciones';
  end if;

  select vigente_desde into v_desde from app.usuario_marca where id = p_id;
  if v_desde is null then
    raise exception 'Asignación % inexistente', p_id;
  end if;
  if p_hasta <= v_desde then
    raise exception 'La fecha de fin debe ser posterior al inicio (%)', v_desde;
  end if;

  update app.usuario_marca
     set vigente_hasta = p_hasta,
         motivo = coalesce(p_motivo, motivo)
   where id = p_id;
end;
$$;

-- Traspaso permanente: se le cierra al saliente y se le abre al entrante
-- el mismo día, sin solape y sin hueco.
create or replace function app.reasignar_marca(
  p_marca_id  uuid,
  p_nuevo_id  uuid,
  p_quitar_al uuid default null,
  p_desde     date default current_date,
  p_motivo    text default null
) returns bigint
language plpgsql security invoker set search_path = app, public as $$
declare v_id bigint;
begin
  if not app.gestiona_usuarios() then
    raise exception 'Solo admin o gerencia puede reasignar marcas';
  end if;

  if p_quitar_al is not null then
    update app.usuario_marca
       set vigente_hasta = p_desde,
           motivo = coalesce(p_motivo, 'Traspaso de marca')
     where marca_id = p_marca_id
       and usuario_id = p_quitar_al
       and vigencia @> p_desde;
  end if;

  select app.asignar_marca(p_marca_id, p_nuevo_id, p_desde, null, true,
                           coalesce(p_motivo, 'Traspaso de marca'))
    into v_id;

  return v_id;
end;
$$;

-- Suplencia de vacaciones. Se registra con antelación y se activa sola.
-- Por omisión el titular conserva el acceso durante la suplencia; pasar
-- p_suspender_titular = true si la cobertura debe ser exclusiva.
create or replace function app.programar_suplencia(
  p_marca_id          uuid,
  p_suplente          uuid,
  p_desde             date,
  p_hasta             date,
  p_motivo            text default 'Suplencia por ausencia',
  p_suspender_titular boolean default false
) returns bigint
language plpgsql security invoker set search_path = app, public as $$
declare
  v_titular uuid;
  v_id      bigint;
begin
  if not app.gestiona_usuarios() then
    raise exception 'Solo admin o gerencia puede programar suplencias';
  end if;
  if p_hasta <= p_desde then
    raise exception 'La suplencia debe terminar después de empezar';
  end if;

  if p_suspender_titular then
    -- Se parte el rango del titular en dos: antes y después de la ausencia.
    select usuario_id into v_titular
      from app.usuario_marca
     where marca_id = p_marca_id and titular and vigencia @> p_desde
     limit 1;

    if v_titular is not null then
      update app.usuario_marca
         set vigente_hasta = p_desde
       where marca_id = p_marca_id and usuario_id = v_titular
         and vigencia @> p_desde;

      insert into app.usuario_marca (usuario_id, marca_id, titular,
                                     vigente_desde, motivo, creado_por)
      values (v_titular, p_marca_id, true, p_hasta,
              'Retorno de ausencia', auth.uid());
    end if;
  end if;

  select app.asignar_marca(p_marca_id, p_suplente, p_desde, p_hasta,
                           false, p_motivo)
    into v_id;

  return v_id;
end;
$$;

-- Desactivar a alguien cierra sus asignaciones vigentes en lugar de
-- borrarlas, para que la historia siga siendo legible.
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
     set vigente_hasta = current_date,
         motivo = coalesce(motivo, 'Usuario desactivado')
   where usuario_id = p_usuario_id
     and vigencia @> current_date
     and vigente_desde < current_date;

  -- Las que arrancaban hoy o a futuro no se pueden cerrar sin violar
  -- el check de rango: se eliminan porque nunca llegaron a estar activas.
  delete from app.usuario_marca
   where usuario_id = p_usuario_id and vigente_desde >= current_date;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
--  4. AUDITORÍA
--  Ahora que la tabla tiene id propio sirve el trigger genérico.
-- ─────────────────────────────────────────────────────────────────────

drop trigger if exists aud_usuario_marca on app.usuario_marca;
drop function if exists app.fn_auditar_usuario_marca();

create trigger aud_usuario_marca
  after insert or update or delete on app.usuario_marca
  for each row execute function app.fn_auditar();

-- ─────────────────────────────────────────────────────────────────────
--  5. VISTAS DE ADMINISTRACIÓN
-- ─────────────────────────────────────────────────────────────────────

-- Todas las asignaciones con su estado temporal, para la pantalla de
-- gestión. Incluye las programadas a futuro y las ya terminadas.
create or replace view app.v_asignaciones with (security_invoker = true) as
select um.id,
       um.marca_id,
       m.codigo            as marca,
       um.usuario_id,
       p.nombre            as usuario,
       p.rol,
       p.activo            as usuario_activo,
       um.titular,
       um.vigente_desde,
       um.vigente_hasta,
       um.motivo,
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
where app.gestiona_usuarios() or um.usuario_id = auth.uid();

-- Marcas huérfanas: activas y sin nadie que responda por ellas hoy.
-- Con vigencias temporales esto puede pasar solo, cuando vence una
-- suplencia y nadie abrió la asignación de vuelta.
create or replace view app.v_marcas_sin_responsable with (security_invoker = true) as
select m.id as marca_id,
       m.codigo,
       m.nombre,
       (select max(um.vigente_hasta) from app.usuario_marca um
         where um.marca_id = m.id) as sin_responsable_desde
from app.marcas m
where m.activa
  and app.ve_todo()
  and not exists (
    select 1 from app.usuario_marca um
     join app.perfiles p on p.id = um.usuario_id and p.activo
    where um.marca_id = m.id and um.vigencia @> current_date
  );

-- Suplencias que vencen pronto, para avisar antes de que caduque el acceso.
create or replace view app.v_suplencias_por_vencer with (security_invoker = true) as
select um.id, m.codigo as marca, p.nombre as suplente,
       um.vigente_hasta, um.vigente_hasta - current_date as dias_restantes,
       um.motivo
from app.usuario_marca um
join app.marcas   m on m.id = um.marca_id
join app.perfiles p on p.id = um.usuario_id
where app.gestiona_usuarios()
  and um.vigencia @> current_date
  and um.vigente_hasta is not null
  and um.vigente_hasta <= current_date + 7
order by um.vigente_hasta;

-- El cumplimiento de carga solo mira asignaciones vigentes.
create or replace view app.v_cumplimiento_carga with (security_invoker = true) as
select p.id             as usuario_id,
       p.nombre,
       m.codigo         as marca,
       um.titular,
       um.vigente_hasta,
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
  and (app.ve_todo() or um.usuario_id = auth.uid())
group by p.id, p.nombre, m.codigo, um.titular, um.vigente_hasta;

-- ─────────────────────────────────────────────────────────────────────
--  6. FEED DE ACTIVIDAD
--  Se agregan los eventos de asignación en lenguaje humano, con fechas.
-- ─────────────────────────────────────────────────────────────────────

create or replace view app.v_actividad with (security_invoker = true) as
select
  c.creado_en                                   as cuando,
  p.nombre                                      as quien,
  p.rol                                         as rol,
  m.codigo                                      as marca,
  'carga'                                       as tipo,
  case
    when c.estado = 'revertida' then 'Revirtió la carga de ' || c.archivo_nombre
    when c.truncado then 'Cargó ' || c.archivo_nombre || ' (EXPORTACIÓN TRUNCADA)'
    else 'Cargó ' || c.archivo_nombre || ' · ' || c.grano::text
         || ' · ' || c.hechos_escritos || ' datos'
  end                                           as detalle,
  c.truncado                                    as requiere_atencion,
  c.id::text                                    as referencia
from app.cargas c
join app.perfiles p on p.id = c.usuario_id
join app.marcas   m on m.id = c.marca_id
where c.marca_id in (select app.marcas_visibles())

union all

select
  a.creado_en,
  coalesce(p.nombre, 'sistema'),
  p.rol,
  m.codigo,
  'cambio',
  case a.tabla
    when 'ajustes' then
      case when (a.despues->>'anulado')::boolean then 'Anuló un ajuste manual'
           else 'Ajustó un valor a mano: ' || coalesce(a.despues->>'motivo','sin motivo') end

    when 'usuario_marca' then
      case
        when a.accion = 'insert' and (a.despues->>'titular')::boolean = false then
          'Programó una suplencia del ' || (a.despues->>'vigente_desde')
          || ' al ' || coalesce(a.despues->>'vigente_hasta','indefinido')
        when a.accion = 'insert' then
          'Asignó la marca desde el ' || (a.despues->>'vigente_desde')
        when a.accion = 'update'
             and (a.antes->>'vigente_hasta') is null
             and (a.despues->>'vigente_hasta') is not null then
          'Terminó la asignación el ' || (a.despues->>'vigente_hasta')
          || coalesce(' · ' || (a.despues->>'motivo'), '')
        when a.accion = 'delete' then 'Eliminó una asignación programada'
        else 'Cambió una asignación de marca'
      end

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
  (a.tabla in ('perfiles','usuario_marca','ajustes')),
  a.registro_id
from app.auditoria a
left join app.perfiles p on p.id = a.usuario_id
left join app.marcas   m on m.id = a.marca_id
where app.ve_auditoria()
   or a.marca_id in (select app.marcas_asignadas());

-- ─────────────────────────────────────────────────────────────────────
--  7. EJEMPLOS DE USO
-- ─────────────────────────────────────────────────────────────────────
--
--  -- Adriana lleva PCP de forma indefinida
--  select app.asignar_marca('<pcp>', '<adriana>');
--
--  -- Se va de vacaciones del 1 al 15 de diciembre y la cubre Carlos.
--  -- Se registra hoy; el acceso de Carlos se abre y se cierra solo.
--  select app.programar_suplencia('<pcp>', '<carlos>',
--         date '2026-12-01', date '2026-12-16', 'Vacaciones de Adriana');
--
--  -- Si la cobertura debe ser exclusiva, se le suspende el acceso a
--  -- Adriana durante esos días y se le devuelve el 16 automáticamente:
--  select app.programar_suplencia('<pcp>', '<carlos>',
--         date '2026-12-01', date '2026-12-16', 'Vacaciones', true);
--
--  -- Traspaso definitivo de la marca
--  select app.reasignar_marca('<pcp>', '<nuevo>', '<adriana>',
--         current_date, 'Cambio de cartera');
--
--  -- ¿Quién respondía por PCP cuando se cargó este archivo?
--  select * from app.responsables('<pcp>', date '2026-08-15');
--
--  -- Pantalla de gestión
--  select * from app.v_asignaciones where marca = 'PCP' order by vigente_desde desc;
--  select * from app.v_suplencias_por_vencer;
--  select * from app.v_marcas_sin_responsable;
