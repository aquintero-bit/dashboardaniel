-- ════════════════════════════════════════════════════════════════════════
--  FEBECA · Migración 002
--  Modelo de permisos definitivo, ajustes manuales y auditoría de cambios
-- ════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────
--  1. ROLES
--  Se elimina 'jefe_compras': el modelo real son tres roles operativos
--  más uno de solo lectura para invitados.
--
--    admin     → configura el sistema, gestiona usuarios, puede cargar
--    gerencia  → ve todas las marcas, gestiona usuarios, NO carga datos
--    comprador → solo sus marcas asignadas, carga y corrige sus datos
--    lectura   → solo sus marcas asignadas, sin escribir nada
-- ─────────────────────────────────────────────────────────────────────

alter type app.rol rename to rol_v1;

create type app.rol as enum ('admin','gerencia','comprador','lectura');

alter table app.perfiles
  alter column rol drop default,
  alter column rol type app.rol using (
    case rol::text
      when 'jefe_compras' then 'gerencia'
      else rol::text
    end
  )::app.rol,
  alter column rol set default 'lectura';

drop type app.rol_v1;

-- ─────────────────────────────────────────────────────────────────────
--  2. FUNCIONES DE SEGURIDAD
--  Una función por capacidad, no por rol. Cuando mañana aparezca un rol
--  nuevo se toca aquí y no en las veinte políticas.
-- ─────────────────────────────────────────────────────────────────────

create or replace function app.rol_actual() returns app.rol
language sql stable security definer set search_path = app, public as $$
  select rol from app.perfiles where id = auth.uid() and activo
$$;

-- Ve todas las marcas sin necesidad de asignación explícita.
create or replace function app.ve_todo() returns boolean
language sql stable security definer set search_path = app, public as $$
  select coalesce(app.rol_actual() in ('admin','gerencia'), false)
$$;

-- Puede subir archivos y corregir datos de las marcas que tiene asignadas.
create or replace function app.puede_cargar() returns boolean
language sql stable security definer set search_path = app, public as $$
  select coalesce(app.rol_actual() in ('admin','comprador'), false)
$$;

-- Puede crear usuarios, cambiarles el rol y asignarles marcas.
create or replace function app.gestiona_usuarios() returns boolean
language sql stable security definer set search_path = app, public as $$
  select coalesce(app.rol_actual() in ('admin','gerencia'), false)
$$;

-- Puede ver el rastro de lo que hicieron los demás.
create or replace function app.ve_auditoria() returns boolean
language sql stable security definer set search_path = app, public as $$
  select coalesce(app.rol_actual() in ('admin','gerencia'), false)
$$;

-- Marcas asignadas explícitamente. Separada de marcas_visibles() porque
-- cargar exige asignación real: gerencia ve todo pero no carga nada.
create or replace function app.marcas_asignadas() returns setof uuid
language sql stable security definer set search_path = app, public as $$
  select marca_id from app.usuario_marca where usuario_id = auth.uid()
$$;

create or replace function app.marcas_visibles() returns setof uuid
language sql stable security definer set search_path = app, public as $$
  select m.id from app.marcas m where app.ve_todo()
  union
  select app.marcas_asignadas()
$$;

-- ─────────────────────────────────────────────────────────────────────
--  3. POLÍTICAS ACTUALIZADAS
-- ─────────────────────────────────────────────────────────────────────

-- ── Perfiles ────────────────────────────────────────────────────────
drop policy if exists perfil_propio on app.perfiles;
drop policy if exists perfil_admin  on app.perfiles;

create policy perfil_lectura on app.perfiles for select
  using (id = auth.uid() or app.gestiona_usuarios());

create policy perfil_gestion on app.perfiles for insert
  with check (app.gestiona_usuarios());

create policy perfil_edicion on app.perfiles for update
  using (app.gestiona_usuarios()) with check (app.gestiona_usuarios());

-- Nadie borra perfiles: se desactivan. Así las cargas históricas
-- conservan su autor.
create policy perfil_sin_borrado on app.perfiles for delete using (false);

-- ── Asignación de marcas ────────────────────────────────────────────
drop policy if exists um_lectura on app.usuario_marca;
drop policy if exists um_admin   on app.usuario_marca;

create policy um_lectura on app.usuario_marca for select
  using (usuario_id = auth.uid() or app.gestiona_usuarios());

create policy um_gestion on app.usuario_marca for all
  using (app.gestiona_usuarios()) with check (app.gestiona_usuarios());

-- ── Parámetros de marca ─────────────────────────────────────────────
drop policy if exists param_escritura on app.parametros_marca;

-- El comprador ajusta el lead time de SUS marcas: es quien habla con el
-- proveedor. Gerencia no toca parámetros operativos.
create policy param_escritura on app.parametros_marca for all
  using (app.rol_actual() = 'admin'
         or (app.rol_actual() = 'comprador'
             and marca_id in (select app.marcas_asignadas())))
  with check (app.rol_actual() = 'admin'
         or (app.rol_actual() = 'comprador'
             and marca_id in (select app.marcas_asignadas())));

-- ── Entidades, hechos y períodos ────────────────────────────────────
-- Cargar exige marca ASIGNADA, no solo visible. Gerencia ve todo pero
-- no puede escribir en ninguna marca.
drop policy if exists ent_escritura    on app.entidades;
drop policy if exists hecho_escritura  on app.hechos;
drop policy if exists periodo_escritura on app.periodos;

create policy ent_escritura on app.entidades for all
  using (app.puede_cargar() and marca_id in (select app.marcas_asignadas()))
  with check (app.puede_cargar() and marca_id in (select app.marcas_asignadas()));

create policy hecho_escritura on app.hechos for all
  using (app.puede_cargar() and marca_id in (select app.marcas_asignadas()))
  with check (app.puede_cargar() and marca_id in (select app.marcas_asignadas()));

create policy periodo_escritura on app.periodos for all
  using (app.puede_cargar() and marca_id in (select app.marcas_asignadas()))
  with check (app.puede_cargar() and marca_id in (select app.marcas_asignadas()));

drop policy if exists carga_escritura on app.cargas;
create policy carga_escritura on app.cargas for insert
  with check (app.puede_cargar()
              and marca_id in (select app.marcas_asignadas())
              and usuario_id = auth.uid());

create policy carga_actualizacion on app.cargas for update
  using (usuario_id = auth.uid() or app.rol_actual() = 'admin');

-- ── Auditoría ───────────────────────────────────────────────────────
drop policy if exists audit_lectura on app.auditoria;
create policy audit_lectura on app.auditoria for select
  using (app.ve_auditoria());

-- La auditoría se escribe solo por trigger, nunca desde el cliente.
create policy audit_sin_escritura on app.auditoria for insert with check (false);
create policy audit_sin_borrado   on app.auditoria for delete using (false);

-- ─────────────────────────────────────────────────────────────────────
--  4. AJUSTES MANUALES
--
--  El problema: si el comprador corrige un hecho directamente sobre
--  app.hechos y luego recarga ese mes, el upsert de la ingesta le borra
--  la corrección en silencio.
--
--  La solución: los datos del SIM quedan intactos en app.hechos y las
--  correcciones viven en una capa aparte que se aplica encima. Así la
--  corrección sobrevive a cualquier recarga, es visible, se puede
--  revertir y siempre queda claro qué dijo el SIM y qué puso la persona.
-- ─────────────────────────────────────────────────────────────────────

create table app.ajustes (
  id            bigserial primary key,
  marca_id      uuid    not null references app.marcas(id) on delete cascade,
  entidad_id    bigint  not null references app.entidades(id) on delete cascade,
  periodo       date    not null,
  indicador_id  smallint not null references app.indicadores(id),
  mascara       app.mascara not null,
  valor_sim     numeric(18,4),          -- lo que decía el SIM al momento del ajuste
  valor_ajustado numeric(18,4) not null,
  motivo        text not null,          -- obligatorio: sin justificación no hay ajuste
  creado_por    uuid not null references app.perfiles(id),
  creado_en     timestamptz not null default now(),
  anulado       boolean not null default false,
  anulado_por   uuid references app.perfiles(id),
  anulado_en    timestamptz
);

create unique index ajuste_vigente_unico
  on app.ajustes (entidad_id, periodo, indicador_id, mascara)
  where not anulado;

create index on app.ajustes (marca_id, creado_en desc);

alter table app.ajustes enable row level security;

create policy ajuste_lectura on app.ajustes for select
  using (marca_id in (select app.marcas_visibles()));

create policy ajuste_escritura on app.ajustes for insert
  with check (app.puede_cargar()
              and marca_id in (select app.marcas_asignadas())
              and creado_por = auth.uid());

-- Anular un ajuste es un UPDATE, no un DELETE: el rastro no se borra.
create policy ajuste_anulacion on app.ajustes for update
  using (app.rol_actual() = 'admin'
         or (app.puede_cargar() and marca_id in (select app.marcas_asignadas())))
  with check (anulado = true);

create policy ajuste_sin_borrado on app.ajustes for delete using (false);

-- Vista que la aplicación consume SIEMPRE en lugar de app.hechos.
-- Devuelve el valor efectivo y marca si viene corregido.
create view app.v_hechos with (security_invoker = true) as
select h.marca_id,
       h.entidad_id,
       h.periodo,
       h.indicador_id,
       h.mascara,
       coalesce(a.valor_ajustado, h.valor) as valor,
       h.valor        as valor_sim,
       a.valor_ajustado,
       a.motivo       as motivo_ajuste,
       a.creado_por   as ajustado_por,
       (a.id is not null) as ajustado,
       h.carga_id
from app.hechos h
left join app.ajustes a
       on a.entidad_id = h.entidad_id
      and a.periodo = h.periodo
      and a.indicador_id = h.indicador_id
      and a.mascara = h.mascara
      and not a.anulado
where h.marca_id in (select app.marcas_visibles());

-- Registrar un ajuste capturando de paso lo que decía el SIM.
create or replace function app.ajustar_hecho(
  p_entidad_id   bigint,
  p_periodo      date,
  p_indicador    text,
  p_mascara      app.mascara,
  p_valor        numeric,
  p_motivo       text
) returns bigint
language plpgsql security invoker set search_path = app, public as $$
declare
  v_marca uuid;
  v_ind   smallint;
  v_sim   numeric;
  v_id    bigint;
begin
  if coalesce(trim(p_motivo),'') = '' then
    raise exception 'El motivo del ajuste es obligatorio';
  end if;

  select marca_id into v_marca from app.entidades where id = p_entidad_id;
  select id into v_ind from app.indicadores where codigo = p_indicador;
  if v_ind is null then
    raise exception 'Indicador % desconocido', p_indicador;
  end if;

  select valor into v_sim from app.hechos
   where entidad_id = p_entidad_id and periodo = date_trunc('month', p_periodo)::date
     and indicador_id = v_ind and mascara = p_mascara;

  -- Un ajuste nuevo sobre la misma celda anula el anterior.
  update app.ajustes
     set anulado = true, anulado_por = auth.uid(), anulado_en = now()
   where entidad_id = p_entidad_id
     and periodo = date_trunc('month', p_periodo)::date
     and indicador_id = v_ind and mascara = p_mascara and not anulado;

  insert into app.ajustes (marca_id, entidad_id, periodo, indicador_id, mascara,
                           valor_sim, valor_ajustado, motivo, creado_por)
  values (v_marca, p_entidad_id, date_trunc('month', p_periodo)::date, v_ind,
          p_mascara, v_sim, p_valor, p_motivo, auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
--  5. AUDITORÍA POR TRIGGER
--
--  Nota de rendimiento: NO se audita app.hechos fila por fila. Una carga
--  normal escribe decenas de miles de filas y generaría un volumen de
--  auditoría inútil. Las cargas masivas ya quedan registradas en
--  app.cargas con su hash, su autor y su conteo. Aquí se auditan solo
--  las acciones deliberadas de una persona.
-- ─────────────────────────────────────────────────────────────────────

alter table app.auditoria
  add column if not exists marca_id uuid references app.marcas(id),
  add column if not exists resumen  text;

create index if not exists auditoria_marca_idx on app.auditoria (marca_id, creado_en desc);
create index if not exists auditoria_usuario_idx on app.auditoria (usuario_id, creado_en desc);

create or replace function app.fn_auditar() returns trigger
language plpgsql security definer set search_path = app, public as $$
declare
  v_antes   jsonb;
  v_despues jsonb;
  v_id      text;
  v_marca   uuid;
begin
  if tg_op = 'DELETE' then
    v_antes := to_jsonb(old);
    v_id := old.id::text;
  elsif tg_op = 'UPDATE' then
    v_antes := to_jsonb(old);
    v_despues := to_jsonb(new);
    v_id := new.id::text;
  else
    v_despues := to_jsonb(new);
    v_id := new.id::text;
  end if;

  v_marca := nullif(coalesce(v_despues->>'marca_id', v_antes->>'marca_id'), '')::uuid;

  insert into app.auditoria (usuario_id, accion, tabla, registro_id,
                             marca_id, antes, despues)
  values (auth.uid(), lower(tg_op), tg_table_name, v_id, v_marca, v_antes, v_despues);

  return coalesce(new, old);
end;
$$;

create trigger aud_perfiles       after insert or update or delete on app.perfiles
  for each row execute function app.fn_auditar();
create trigger aud_usuario_marca  after insert or update or delete on app.usuario_marca
  for each row execute function app.fn_auditar();
create trigger aud_parametros     after insert or update or delete on app.parametros_marca
  for each row execute function app.fn_auditar();
create trigger aud_ajustes        after insert or update on app.ajustes
  for each row execute function app.fn_auditar();
create trigger aud_entidades      after update on app.entidades
  for each row execute function app.fn_auditar();
create trigger aud_marcas         after insert or update or delete on app.marcas
  for each row execute function app.fn_auditar();

-- usuario_marca no tiene columna id; se audita con clave compuesta.
create or replace function app.fn_auditar_usuario_marca() returns trigger
language plpgsql security definer set search_path = app, public as $$
declare v_antes jsonb; v_despues jsonb; v_reg text; v_marca uuid;
begin
  if tg_op = 'DELETE' then
    v_antes := to_jsonb(old);
    v_reg := old.usuario_id::text || ':' || old.marca_id::text;
    v_marca := old.marca_id;
  else
    v_despues := to_jsonb(new);
    if tg_op = 'UPDATE' then v_antes := to_jsonb(old); end if;
    v_reg := new.usuario_id::text || ':' || new.marca_id::text;
    v_marca := new.marca_id;
  end if;

  insert into app.auditoria (usuario_id, accion, tabla, registro_id,
                             marca_id, antes, despues)
  values (auth.uid(), lower(tg_op), 'usuario_marca', v_reg, v_marca, v_antes, v_despues);
  return coalesce(new, old);
end;
$$;

drop trigger if exists aud_usuario_marca on app.usuario_marca;
create trigger aud_usuario_marca after insert or update or delete on app.usuario_marca
  for each row execute function app.fn_auditar_usuario_marca();

-- ─────────────────────────────────────────────────────────────────────
--  6. PANTALLA DE ACTIVIDAD
--  Un feed único que mezcla cargas de archivos y cambios auditados,
--  ya traducido a lenguaje humano. Es lo que ve gerencia.
-- ─────────────────────────────────────────────────────────────────────

create view app.v_actividad with (security_invoker = true) as
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
    when 'usuario_marca' then
      case a.accion when 'insert' then 'Asignó una marca a un comprador'
                    when 'delete' then 'Quitó una marca a un comprador'
                    else 'Cambió una asignación de marca' end
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

-- Resumen por comprador: quién está al día y quién no subió nada.
create view app.v_cumplimiento_carga with (security_invoker = true) as
select p.id            as usuario_id,
       p.nombre,
       m.codigo        as marca,
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
join app.perfiles p on p.id = um.usuario_id
join app.marcas   m on m.id = um.marca_id
left join app.cargas c on c.marca_id = um.marca_id and c.usuario_id = um.usuario_id
where app.ve_todo() or um.usuario_id = auth.uid()
group by p.id, p.nombre, m.codigo;

-- ─────────────────────────────────────────────────────────────────────
--  7. GESTIÓN DE USUARIOS
--  Reasignar una marca no borra la historia: las cargas viejas siguen
--  atribuidas a quien las hizo.
-- ─────────────────────────────────────────────────────────────────────

create or replace function app.reasignar_marca(
  p_marca_id   uuid,
  p_nuevo_id   uuid,
  p_quitar_al  uuid default null
) returns void
language plpgsql security invoker set search_path = app, public as $$
begin
  if not app.gestiona_usuarios() then
    raise exception 'Solo admin o gerencia puede reasignar marcas';
  end if;

  if p_quitar_al is not null then
    delete from app.usuario_marca
     where marca_id = p_marca_id and usuario_id = p_quitar_al;
  end if;

  insert into app.usuario_marca (usuario_id, marca_id, titular)
  values (p_nuevo_id, p_marca_id, true)
  on conflict (usuario_id, marca_id) do update set titular = true;
end;
$$;

-- Desactivar en vez de borrar, y liberar sus marcas.
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
  delete from app.usuario_marca where usuario_id = p_usuario_id;
end;
$$;

-- Salvaguarda: siempre tiene que quedar al menos un admin activo.
create or replace function app.fn_proteger_ultimo_admin() returns trigger
language plpgsql set search_path = app, public as $$
begin
  if (old.rol = 'admin' and (new.rol <> 'admin' or new.activo = false))
     and (select count(*) from app.perfiles
           where rol = 'admin' and activo and id <> old.id) = 0 then
    raise exception 'No se puede dejar el sistema sin ningún administrador activo';
  end if;
  return new;
end;
$$;

create trigger proteger_ultimo_admin before update on app.perfiles
  for each row execute function app.fn_proteger_ultimo_admin();
