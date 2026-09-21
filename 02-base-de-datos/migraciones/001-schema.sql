-- ════════════════════════════════════════════════════════════════════════
--  FEBECA · Dashboard de Compras
--  Esquema Postgres con control de usuarios, roles y RLS
--  Compatible con Supabase (usa auth.users). Para Postgres puro,
--  reemplazar auth.users por una tabla propia de usuarios.
-- ════════════════════════════════════════════════════════════════════════

create extension if not exists "pgcrypto";
create schema if not exists app;

-- ─────────────────────────────────────────────────────────────────────
--  1. TIPOS
-- ─────────────────────────────────────────────────────────────────────

create type app.rol as enum (
  'admin',          -- configura todo, gestiona usuarios
  'gerencia',       -- ve todas las marcas, no carga archivos
  'jefe_compras',   -- ve todas las marcas, carga y ajusta parámetros
  'comprador',      -- solo sus marcas asignadas
  'lectura'         -- solo sus marcas, sin cargar ni modificar
);

create type app.grano as enum (
  'marca', 'categoria', 'articulo', 'cliente', 'vendedor',
  'estado', 'supervisor', 'region', 'cliente_articulo'
);

create type app.mascara as enum ('usd', 'unidades', 'toneladas');

-- Cómo se agrega cada indicador al sumar filas. Crítico: el SIM repite
-- Inventario y Rotación idénticos en cada fila de los cortes por vendedor
-- o cliente, y los ratios nunca se suman.
create type app.agregacion as enum (
  'suma',      -- Venta Neta, Contribución, Presupuesto
  'ultimo',    -- Inventario (snapshot de fin de mes)
  'ratio',     -- Margen, GMROI: se recalculan desde sus componentes
  'conteo',    -- SKU activados, Clientes activados
  'ninguna'    -- se ignora al agregar
);

-- ─────────────────────────────────────────────────────────────────────
--  2. USUARIOS Y ROLES
-- ─────────────────────────────────────────────────────────────────────

create table app.perfiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  nombre       text not null,
  rol          app.rol not null default 'lectura',
  activo       boolean not null default true,
  creado_en    timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create table app.marcas (
  id           uuid primary key default gen_random_uuid(),
  codigo       text not null unique,          -- 'PCP', 'BOSCH', 'EMTOP'
  nombre       text not null,
  origen       text check (origen in ('nacional','internacional')),
  activa       boolean not null default true,
  creado_en    timestamptz not null default now()
);

-- Un comprador lleva varias marcas; una marca puede tener más de un
-- responsable (titular y suplente durante vacaciones).
create table app.usuario_marca (
  usuario_id   uuid not null references app.perfiles(id) on delete cascade,
  marca_id     uuid not null references app.marcas(id) on delete cascade,
  titular      boolean not null default true,
  asignado_en  timestamptz not null default now(),
  primary key (usuario_id, marca_id)
);

create index on app.usuario_marca (marca_id);

-- ─────────────────────────────────────────────────────────────────────
--  3. PARÁMETROS POR MARCA
--  Versionados: cambiar el lead time no debe reescribir la historia de
--  los pedidos sugeridos que ya se calcularon.
-- ─────────────────────────────────────────────────────────────────────

create table app.parametros_marca (
  id                uuid primary key default gen_random_uuid(),
  marca_id          uuid not null references app.marcas(id) on delete cascade,
  vigente_desde     date not null,
  lead_time_meses   numeric(4,2) not null default 1.5,   -- PCP: 45 días
  ciclo_meses       numeric(4,2) not null default 1.0,   -- PCP: compra mensual
  seguridad_meses   numeric(4,2) not null default 0.5,
  kg_por_unidad     numeric(10,4),                       -- PCP: 2.3901
  definido_por      uuid references app.perfiles(id),
  nota              text,
  unique (marca_id, vigente_desde)
);

-- ─────────────────────────────────────────────────────────────────────
--  4. CATÁLOGO DE INDICADORES
--  Tabla, no enum: el SIM puede sumar indicadores sin que haya migración.
-- ─────────────────────────────────────────────────────────────────────

create table app.indicadores (
  id            smallserial primary key,
  codigo        text not null unique,        -- 'venta_neta'
  etiqueta_sim  text not null,               -- 'Venta Neta' (como viene en el xlsx)
  nombre        text not null,
  agregacion    app.agregacion not null default 'suma',
  factor_escala numeric not null default 1,  -- ver nota abajo
  activo        boolean not null default true
);

-- IMPORTANTE sobre factor_escala:
-- La máscara del SIM dice "Miles de dólares", pero Presupuesto bruto llega
-- en dólares absolutos mientras el resto llega en miles. Se normaliza TODO
-- a dólares en la ingesta: venta_neta lleva 1000, presupuesto_bruto lleva 1.
-- En la base nunca hay ambigüedad de escala.
insert into app.indicadores (codigo, etiqueta_sim, nombre, agregacion, factor_escala) values
  ('venta_neta',          'Venta Neta',                  'Venta neta',               'suma',   1000),
  ('venta_bruta',         'Venta Bruta',                 'Venta bruta',              'suma',   1000),
  ('contribucion',        'Contribución',                'Contribución',             'suma',   1000),
  ('inventario',          'Inventario',                  'Inventario',               'ultimo', 1000),
  ('presupuesto_bruto',   'Presupuesto bruto',           'Presupuesto bruto',        'suma',   1),
  ('presupuesto_neto',    'Presupuesto neto',            'Presupuesto neto',         'suma',   1000),
  ('presupuesto_contrib', 'Presupuesto de contribución', 'Presupuesto contribución', 'suma',   1000),
  ('oc_por_recibir',      'OC por recibir',              'OC por recibir',           'suma',   1000),
  ('margen',              'Margen',                      'Margen',                   'ratio',  1),
  ('rotacion',            'Rotación',                    'Rotación',                 'ratio',  1),
  ('gm_roi',              'GM ROI',                      'GMROI',                    'ratio',  1),
  ('clientes_activados',  'Clientes activados',          'Clientes activados',       'conteo', 1),
  ('clientes_inactivos',  'Clientes Inactivos',          'Clientes inactivos',       'conteo', 1),
  ('sku_activados',       'SKU activados',               'SKU activados',            'conteo', 1);

-- ─────────────────────────────────────────────────────────────────────
--  5. ENTIDADES (dimensiones unificadas)
--  Un artículo, un cliente, un vendedor, un estado: todos son entidades.
--  Los atributos propios de cada grano van en jsonb, porque cambian por
--  marca y por corte sin que valga la pena una tabla por tipo.
-- ─────────────────────────────────────────────────────────────────────

create table app.entidades (
  id             bigserial primary key,
  marca_id       uuid not null references app.marcas(id) on delete cascade,
  grano          app.grano not null,
  clave_natural  text not null,   -- artículo: '22-13-007' · cliente: razón social
  nombre         text not null,
  atributos      jsonb not null default '{}'::jsonb,
  -- Generaliza el caso EPA: cualquier cliente atípico se marca aquí y el
  -- motor lo excluye de pronósticos y pedido sugerido. Nunca hardcodear.
  excluir_de_analisis boolean not null default false,
  activo         boolean not null default true,
  creado_en      timestamptz not null default now(),
  unique (marca_id, grano, clave_natural)
);

create index on app.entidades (marca_id, grano);
create index on app.entidades using gin (atributos);

-- atributos por grano, a modo de referencia:
--   articulo:  {"categoria":"Plomería","subcategoria":"Aspersores","descontinuado":false}
--   cliente:   {"estado":"Carabobo","razones_sociales":["FERRETERIA EPA, C.A.", ...]}
--   vendedor:  {"no_clasificado":true}
--   estado:    {"pais":"Venezuela","region":"CENTRO"}

-- ─────────────────────────────────────────────────────────────────────
--  6. CARGAS (auditoría de ingesta)
--  Cada archivo subido deja rastro: quién, cuándo, qué detectó el parser
--  y si el SIM lo truncó. Sin esto, un archivo incompleto muestra ceros
--  en silencio y nadie se entera.
-- ─────────────────────────────────────────────────────────────────────

create table app.cargas (
  id                uuid primary key default gen_random_uuid(),
  usuario_id        uuid not null references app.perfiles(id),
  marca_id          uuid not null references app.marcas(id),
  archivo_nombre    text not null,
  archivo_hash      text not null,        -- sha256: detecta recargas idénticas
  archivo_url       text,                 -- object storage, para reprocesar
  grano             app.grano not null,
  mascara           app.mascara not null,
  periodo_desde     date not null,
  periodo_hasta     date not null,
  filas_leidas      int not null default 0,
  filas_subtotal    int not null default 0,   -- filas "Total" descartadas
  hechos_escritos   int not null default 0,
  truncado          boolean not null default false,
  filtros_crudos    text,                 -- bloque "Filtros aplicados" literal
  estado            text not null default 'procesando'
                    check (estado in ('procesando','ok','error','revertida')),
  error_detalle     text,
  creado_en         timestamptz not null default now()
);

create index on app.cargas (marca_id, creado_en desc);
create index on app.cargas (archivo_hash);

-- ─────────────────────────────────────────────────────────────────────
--  7. HECHOS MENSUALES
--  Una sola tabla larga. La clave única hace la ingesta idempotente:
--  volver a subir un mes lo sobreescribe, que es exactamente lo que hace
--  falta porque el SIM corrige cifras hacia atrás.
-- ─────────────────────────────────────────────────────────────────────

create table app.hechos (
  id            bigserial primary key,
  marca_id      uuid not null references app.marcas(id) on delete cascade,
  entidad_id    bigint not null references app.entidades(id) on delete cascade,
  periodo       date not null,            -- siempre día 1 del mes
  indicador_id  smallint not null references app.indicadores(id),
  mascara       app.mascara not null,
  valor         numeric(18,4) not null,
  carga_id      uuid references app.cargas(id),
  actualizado_en timestamptz not null default now(),
  unique (entidad_id, periodo, indicador_id, mascara)
);

-- marca_id está denormalizado a propósito: la política RLS lo filtra sin
-- tener que unir contra entidades en cada consulta.
create index on app.hechos (marca_id, periodo, indicador_id);
create index on app.hechos (entidad_id, periodo);
create index on app.hechos (carga_id);

-- Estado del período: el último mes con venta va incompleto y no puede
-- entrar en promedios ni pronósticos.
create table app.periodos (
  marca_id      uuid not null references app.marcas(id) on delete cascade,
  periodo       date not null,
  cerrado       boolean not null default false,
  corte_al      date,                     -- hasta qué día trae datos si va parcial
  primary key (marca_id, periodo)
);

-- ─────────────────────────────────────────────────────────────────────
--  8. INVENTARIO (infocompras)
--  No es mensual: es una foto del momento en que se bajó el archivo.
--  Se guarda con fecha para poder reconstruir por qué se sugirió un pedido.
-- ─────────────────────────────────────────────────────────────────────

create table app.inventario_snapshot (
  id              bigserial primary key,
  entidad_id      bigint not null references app.entidades(id) on delete cascade,
  tomado_en       date not null,
  disponible      numeric(14,2),          -- DISP, en unidades
  transito        numeric(14,2),          -- TRANSITO, en unidades
  costo           numeric(14,4),
  precio_venta    numeric(14,4),
  ultima_compra   date,                   -- ULT_COM: de aquí sale la frecuencia
  descontinuado   boolean default false,
  carga_id        uuid references app.cargas(id),
  unique (entidad_id, tomado_en)
);

create index on app.inventario_snapshot (entidad_id, tomado_en desc);

-- ─────────────────────────────────────────────────────────────────────
--  9. PRONÓSTICOS CALCULADOS
--  Se persisten para poder auditar qué se proyectó y con qué método,
--  y para no recalcular Holt-Winters en cada carga de página.
-- ─────────────────────────────────────────────────────────────────────

create table app.pronosticos (
  id              bigserial primary key,
  entidad_id      bigint not null references app.entidades(id) on delete cascade,
  mascara         app.mascara not null,
  calculado_en    timestamptz not null default now(),
  sin_excluidos   boolean not null default true,  -- calculado sin EPA y similares
  metodo          text not null,                  -- 'holt_winters' | 'media_ponderada'
  meses_historia  int not null,
  rmse            numeric(18,4),
  horizonte       jsonb not null,                 -- [{"periodo":"2026-10-01","valor":123.4}]
  vigente         boolean not null default true
);

create index on app.pronosticos (entidad_id, vigente) where vigente;

-- ─────────────────────────────────────────────────────────────────────
--  10. AUDITORÍA DE CAMBIOS SENSIBLES
-- ─────────────────────────────────────────────────────────────────────

create table app.auditoria (
  id          bigserial primary key,
  usuario_id  uuid references app.perfiles(id),
  accion      text not null,      -- 'carga', 'revertir_carga', 'cambio_parametros', ...
  tabla       text,
  registro_id text,
  antes       jsonb,
  despues     jsonb,
  creado_en   timestamptz not null default now()
);

create index on app.auditoria (creado_en desc);

-- ─────────────────────────────────────────────────────────────────────
--  11. FUNCIONES DE SEGURIDAD
--  STABLE para que el planificador las evalúe una sola vez por consulta:
--  si fueran VOLATILE, la política RLS se ejecutaría fila por fila.
-- ─────────────────────────────────────────────────────────────────────

create or replace function app.rol_actual() returns app.rol
language sql stable security definer set search_path = app, public as $$
  select rol from app.perfiles where id = auth.uid() and activo
$$;

create or replace function app.ve_todo() returns boolean
language sql stable security definer set search_path = app, public as $$
  select coalesce(app.rol_actual() in ('admin','gerencia','jefe_compras'), false)
$$;

create or replace function app.puede_cargar() returns boolean
language sql stable security definer set search_path = app, public as $$
  select coalesce(app.rol_actual() in ('admin','jefe_compras','comprador'), false)
$$;

create or replace function app.marcas_visibles() returns setof uuid
language sql stable security definer set search_path = app, public as $$
  select m.id from app.marcas m where app.ve_todo()
  union
  select um.marca_id from app.usuario_marca um where um.usuario_id = auth.uid()
$$;

-- ─────────────────────────────────────────────────────────────────────
--  12. ROW LEVEL SECURITY
-- ─────────────────────────────────────────────────────────────────────

alter table app.perfiles           enable row level security;
alter table app.marcas             enable row level security;
alter table app.usuario_marca      enable row level security;
alter table app.parametros_marca   enable row level security;
alter table app.entidades          enable row level security;
alter table app.hechos             enable row level security;
alter table app.periodos           enable row level security;
alter table app.cargas             enable row level security;
alter table app.inventario_snapshot enable row level security;
alter table app.pronosticos        enable row level security;
alter table app.auditoria          enable row level security;

-- Perfiles: cada quien se ve a sí mismo; admin ve y edita a todos.
create policy perfil_propio on app.perfiles for select
  using (id = auth.uid() or app.rol_actual() = 'admin');
create policy perfil_admin on app.perfiles for all
  using (app.rol_actual() = 'admin') with check (app.rol_actual() = 'admin');

-- Marcas: se ven las visibles; solo admin las crea o modifica.
create policy marca_lectura on app.marcas for select
  using (id in (select app.marcas_visibles()));
create policy marca_admin on app.marcas for all
  using (app.rol_actual() = 'admin') with check (app.rol_actual() = 'admin');

create policy um_lectura on app.usuario_marca for select
  using (usuario_id = auth.uid() or app.ve_todo());
create policy um_admin on app.usuario_marca for all
  using (app.rol_actual() = 'admin') with check (app.rol_actual() = 'admin');

-- Parámetros: los ve quien ve la marca; los cambia jefe de compras o admin.
create policy param_lectura on app.parametros_marca for select
  using (marca_id in (select app.marcas_visibles()));
create policy param_escritura on app.parametros_marca for all
  using (app.rol_actual() in ('admin','jefe_compras'))
  with check (app.rol_actual() in ('admin','jefe_compras'));

-- Entidades y hechos: lectura por marca visible; escritura solo por quien
-- puede cargar Y tiene esa marca asignada.
create policy ent_lectura on app.entidades for select
  using (marca_id in (select app.marcas_visibles()));
create policy ent_escritura on app.entidades for all
  using (app.puede_cargar() and marca_id in (select app.marcas_visibles()))
  with check (app.puede_cargar() and marca_id in (select app.marcas_visibles()));

create policy hecho_lectura on app.hechos for select
  using (marca_id in (select app.marcas_visibles()));
create policy hecho_escritura on app.hechos for all
  using (app.puede_cargar() and marca_id in (select app.marcas_visibles()))
  with check (app.puede_cargar() and marca_id in (select app.marcas_visibles()));

create policy periodo_lectura on app.periodos for select
  using (marca_id in (select app.marcas_visibles()));
create policy periodo_escritura on app.periodos for all
  using (app.puede_cargar() and marca_id in (select app.marcas_visibles()))
  with check (app.puede_cargar() and marca_id in (select app.marcas_visibles()));

create policy carga_lectura on app.cargas for select
  using (marca_id in (select app.marcas_visibles()));
create policy carga_escritura on app.cargas for insert
  with check (app.puede_cargar() and marca_id in (select app.marcas_visibles())
              and usuario_id = auth.uid());

create policy inv_lectura on app.inventario_snapshot for select
  using (entidad_id in (select id from app.entidades
                        where marca_id in (select app.marcas_visibles())));
create policy inv_escritura on app.inventario_snapshot for all
  using (app.puede_cargar()) with check (app.puede_cargar());

create policy pron_lectura on app.pronosticos for select
  using (entidad_id in (select id from app.entidades
                        where marca_id in (select app.marcas_visibles())));

create policy audit_lectura on app.auditoria for select
  using (app.rol_actual() in ('admin','jefe_compras'));

-- ─────────────────────────────────────────────────────────────────────
--  13. INGESTA IDEMPOTENTE
--  El parser corre en el navegador (Web Worker con SheetJS) y manda lotes
--  normalizados. Esta función resuelve entidades y hace upsert de hechos.
-- ─────────────────────────────────────────────────────────────────────

create or replace function app.ingerir_hechos(
  p_carga_id uuid,
  p_filas    jsonb   -- [{"grano":"articulo","clave":"22-13-007","nombre":"...",
                     --   "atributos":{...},"periodo":"2026-08-01",
                     --   "indicador":"venta_neta","mascara":"usd","valor":13.824}]
) returns int
language plpgsql security invoker set search_path = app, public as $$
declare
  v_marca uuid;
  v_n int;
begin
  select marca_id into v_marca from app.cargas where id = p_carga_id;
  if v_marca is null then
    raise exception 'Carga % inexistente', p_carga_id;
  end if;

  -- 1. Resolver entidades (crea las nuevas, actualiza nombre y atributos)
  with f as (
    select distinct on (x.grano, x.clave)
           (x.grano)::app.grano as grano, x.clave, x.nombre, x.atributos
    from jsonb_to_recordset(p_filas)
         as x(grano text, clave text, nombre text, atributos jsonb,
              periodo date, indicador text, mascara text, valor numeric)
  )
  insert into app.entidades (marca_id, grano, clave_natural, nombre, atributos)
  select v_marca, f.grano, f.clave, coalesce(f.nombre, f.clave),
         coalesce(f.atributos, '{}'::jsonb)
  from f
  on conflict (marca_id, grano, clave_natural) do update
    set nombre    = excluded.nombre,
        atributos = app.entidades.atributos || excluded.atributos;

  -- 2. Upsert de hechos, aplicando el factor de escala del indicador
  with f as (
    select (x.grano)::app.grano as grano, x.clave, x.periodo,
           x.indicador, (x.mascara)::app.mascara as mascara, x.valor
    from jsonb_to_recordset(p_filas)
         as x(grano text, clave text, nombre text, atributos jsonb,
              periodo date, indicador text, mascara text, valor numeric)
  ),
  resuelto as (
    select e.id as entidad_id, f.periodo, i.id as indicador_id,
           f.mascara, f.valor * i.factor_escala as valor
    from f
    join app.entidades  e on e.marca_id = v_marca
                         and e.grano = f.grano
                         and e.clave_natural = f.clave
    join app.indicadores i on i.codigo = f.indicador
  ),
  ins as (
    insert into app.hechos (marca_id, entidad_id, periodo, indicador_id,
                            mascara, valor, carga_id)
    select v_marca, entidad_id, date_trunc('month', periodo)::date,
           indicador_id, mascara, valor, p_carga_id
    from resuelto
    on conflict (entidad_id, periodo, indicador_id, mascara) do update
      set valor = excluded.valor,
          carga_id = excluded.carga_id,
          actualizado_en = now()
    returning 1
  )
  select count(*) into v_n from ins;

  update app.cargas
     set hechos_escritos = v_n, estado = 'ok'
   where id = p_carga_id;

  return v_n;
end;
$$;

-- Revertir una carga equivocada: borra solo los hechos que escribió.
-- Ojo: si una carga posterior sobreescribió esos hechos, ya no le pertenecen
-- y quedan intactos, que es el comportamiento correcto.
create or replace function app.revertir_carga(p_carga_id uuid)
returns int language plpgsql security invoker set search_path = app, public as $$
declare v_n int;
begin
  if app.rol_actual() not in ('admin','jefe_compras') then
    raise exception 'Solo admin o jefe de compras puede revertir cargas';
  end if;
  delete from app.hechos where carga_id = p_carga_id;
  get diagnostics v_n = row_count;
  update app.cargas set estado = 'revertida' where id = p_carga_id;
  insert into app.auditoria (usuario_id, accion, tabla, registro_id)
  values (auth.uid(), 'revertir_carga', 'hechos', p_carga_id::text);
  return v_n;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
--  14. AGREGADOS
--  Las vistas de la aplicación nunca recorren app.hechos en crudo.
-- ─────────────────────────────────────────────────────────────────────

create materialized view app.mv_marca_mes as
select h.marca_id,
       h.periodo,
       sum(h.valor) filter (where i.codigo='venta_neta'    and h.mascara='usd')       as venta_usd,
       sum(h.valor) filter (where i.codigo='venta_neta'    and h.mascara='unidades')  as venta_unid,
       sum(h.valor) filter (where i.codigo='contribucion'  and h.mascara='usd')       as contribucion,
       sum(h.valor) filter (where i.codigo='inventario'    and h.mascara='usd')       as inventario,
       sum(h.valor) filter (where i.codigo='presupuesto_bruto')                       as presupuesto,
       sum(h.valor) filter (where i.codigo='oc_por_recibir')                          as oc_por_recibir,
       bool_or(p.cerrado)                                                             as cerrado
from app.hechos h
join app.indicadores i on i.id = h.indicador_id
join app.entidades  e on e.id = h.entidad_id and e.grano = 'articulo'
left join app.periodos p on p.marca_id = h.marca_id and p.periodo = h.periodo
group by h.marca_id, h.periodo;

create unique index on app.mv_marca_mes (marca_id, periodo);

create materialized view app.mv_articulo_mes as
select h.marca_id, h.entidad_id, h.periodo,
       sum(h.valor) filter (where i.codigo='venta_neta'   and h.mascara='usd')      as venta_usd,
       sum(h.valor) filter (where i.codigo='venta_neta'   and h.mascara='unidades') as venta_unid,
       sum(h.valor) filter (where i.codigo='contribucion' and h.mascara='usd')      as contribucion
from app.hechos h
join app.indicadores i on i.id = h.indicador_id
join app.entidades  e on e.id = h.entidad_id and e.grano = 'articulo'
group by h.marca_id, h.entidad_id, h.periodo;

create unique index on app.mv_articulo_mes (entidad_id, periodo);
create index on app.mv_articulo_mes (marca_id, periodo);

-- Las vistas materializadas no respetan RLS: se exponen mediante vistas
-- normales con security_invoker, que sí la aplican.
create view app.v_marca_mes with (security_invoker = true) as
  select * from app.mv_marca_mes where marca_id in (select app.marcas_visibles());

create view app.v_articulo_mes with (security_invoker = true) as
  select * from app.mv_articulo_mes where marca_id in (select app.marcas_visibles());

create or replace function app.refrescar_agregados() returns void
language sql security definer set search_path = app, public as $$
  refresh materialized view concurrently app.mv_marca_mes;
  refresh materialized view concurrently app.mv_articulo_mes;
$$;

-- ─────────────────────────────────────────────────────────────────────
--  15. VISTA DE PEDIDO SUGERIDO
--  Une demanda pronosticada, stock e inventario en tránsito.
-- ─────────────────────────────────────────────────────────────────────

create view app.v_pedido_sugerido with (security_invoker = true) as
with ult_param as (
  select distinct on (marca_id) marca_id, lead_time_meses, ciclo_meses,
         seguridad_meses, kg_por_unidad
  from app.parametros_marca
  where vigente_desde <= current_date
  order by marca_id, vigente_desde desc
),
ult_inv as (
  select distinct on (entidad_id) entidad_id, disponible, transito, costo
  from app.inventario_snapshot
  order by entidad_id, tomado_en desc
),
demanda as (
  select p.entidad_id,
         (select avg((v->>'valor')::numeric)
            from jsonb_array_elements(p.horizonte) v) as demanda_mes
  from app.pronosticos p
  where p.vigente and p.mascara = 'unidades' and p.sin_excluidos
)
select e.marca_id,
       e.id as entidad_id,
       e.clave_natural as codigo,
       e.nombre,
       d.demanda_mes,
       i.disponible,
       i.transito,
       case when d.demanda_mes > 0
            then (coalesce(i.disponible,0) + coalesce(i.transito,0)) / d.demanda_mes
       end as cobertura_meses,
       greatest(0, d.demanda_mes * (pm.lead_time_meses + pm.ciclo_meses + pm.seguridad_meses)
                   - coalesce(i.disponible,0) - coalesce(i.transito,0)) as sugerido_unid,
       greatest(0, d.demanda_mes * (pm.lead_time_meses + pm.ciclo_meses + pm.seguridad_meses)
                   - coalesce(i.disponible,0) - coalesce(i.transito,0)) * pm.kg_por_unidad as sugerido_kg,
       greatest(0, d.demanda_mes * (pm.lead_time_meses + pm.ciclo_meses + pm.seguridad_meses)
                   - coalesce(i.disponible,0) - coalesce(i.transito,0)) * i.costo as sugerido_usd
from app.entidades e
join demanda   d  on d.entidad_id = e.id
join ult_param pm on pm.marca_id = e.marca_id
left join ult_inv i on i.entidad_id = e.id
where e.grano = 'articulo' and e.activo;

-- ─────────────────────────────────────────────────────────────────────
--  16. SEMILLA
-- ─────────────────────────────────────────────────────────────────────

insert into app.marcas (codigo, nombre, origen) values
  ('PCP','PCP','internacional')
on conflict (codigo) do nothing;

insert into app.parametros_marca (marca_id, vigente_desde, lead_time_meses,
                                  ciclo_meses, seguridad_meses, kg_por_unidad, nota)
select id, date '2026-01-01', 1.5, 1.0, 0.5, 2.3901,
       'Confirmado con compras: compra mensual, 45 días de tránsito'
from app.marcas where codigo = 'PCP'
on conflict do nothing;
