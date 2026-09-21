-- ════════════════════════════════════════════════════════════════════════
--  FEBECA · Dashboard de Compras · ESQUEMA CONSOLIDADO
--  Pegar completo en el SQL Editor de Supabase (una sola ejecución).
--  Probado contra PostgreSQL 16 con auth/storage simulados.
-- ════════════════════════════════════════════════════════════════════════

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

create type app.rol as enum ('admin','gerencia','jefe_compras','comprador','lectura');

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
alter table app.indicadores        enable row level security;

-- Indicadores: catálogo de solo lectura para cualquier usuario autenticado;
-- solo admin lo modifica. Un factor_escala equivocado deja todos los números
-- mal en silencio (regla 2), así que la escritura no puede quedar abierta.
create policy ind_lectura on app.indicadores for select
  to authenticated using (true);
create policy ind_admin on app.indicadores for all
  using (app.rol_actual() = 'admin') with check (app.rol_actual() = 'admin');

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

-- (enum ya definido con los cinco roles en el esquema base)

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
-- La versión de 3 parámetros (migración 002) se elimina: si convive con las de
-- 5 parámetros, PostgREST no puede elegir entre ellas y devuelve 300 (PGRST203).
drop function if exists app.reasignar_marca(uuid, uuid, uuid);

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
drop view if exists app.v_asignaciones;
create view app.v_asignaciones with (security_invoker = true) as
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
drop view if exists app.v_marcas_sin_responsable;
create view app.v_marcas_sin_responsable with (security_invoker = true) as
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
drop view if exists app.v_suplencias_por_vencer;
create view app.v_suplencias_por_vencer with (security_invoker = true) as
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
drop view if exists app.v_cumplimiento_carga;
create view app.v_cumplimiento_carga with (security_invoker = true) as
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

drop view if exists app.v_actividad;
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

-- rol_actual se redefine con create or replace

-- (enum ya incluye jefe_compras)

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

drop view if exists app.v_jefaturas;
create view app.v_jefaturas with (security_invoker = true) as
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
drop view if exists app.v_origenes_sin_jefe;
create view app.v_origenes_sin_jefe with (security_invoker = true) as
select o.origen,
       (select count(*) from app.marcas m where m.activa and m.origen = o.origen) as marcas
from (select unnest(enum_range(null::app.origen_marca)) as origen) o
where app.ve_todo()
  and not exists (
    select 1 from app.jefaturas j
     join app.perfiles p on p.id = j.usuario_id and p.activo
    where j.origen = o.origen and j.vigencia @> current_date
  );

drop view if exists app.v_asignaciones;
create view app.v_asignaciones with (security_invoker = true) as
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

drop view if exists app.v_cumplimiento_carga;
create view app.v_cumplimiento_carga with (security_invoker = true) as
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
drop view if exists app.v_equipo;
create view app.v_equipo with (security_invoker = true) as
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
drop view if exists app.v_actividad;
create view app.v_actividad with (security_invoker = true) as
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


-- ════════════════════════════════════════════════════════════════════════
--  FEBECA · Migración 005
--  Flujo de ingesta completo: inicio, lotes, finalización, inventario
--
--  Corrige ingerir_hechos para trabajar por lotes: la versión anterior
--  marcaba la carga como 'ok' en el primer lote y sobreescribía el conteo.
-- ════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────
--  1. INICIAR CARGA
--  Valida lo que el cliente no puede validar solo y devuelve el id.
--  Si el mismo archivo ya se procesó bien, lo informa sin bloquear:
--  recargar es legítimo cuando el SIM corrigió cifras.
-- ─────────────────────────────────────────────────────────────────────

alter table app.cargas
  add column if not exists lotes_esperados   int,
  add column if not exists lotes_recibidos   int not null default 0,
  add column if not exists indicadores_desconocidos text[] default '{}',
  add column if not exists duplicado_de      uuid references app.cargas(id);

create or replace function app.iniciar_carga(
  p_marca_codigo    text,
  p_archivo_nombre  text,
  p_archivo_hash    text,
  p_grano           app.grano,
  p_mascara         app.mascara,
  p_periodo_desde   date,
  p_periodo_hasta   date,
  p_filas_leidas    int,
  p_filas_subtotal  int,
  p_truncado        boolean,
  p_filtros_crudos  text,
  p_lotes_esperados int
) returns table (carga_id uuid, marca_id uuid, duplicado_de uuid, aviso text)
language plpgsql security invoker set search_path = app, public as $$
declare
  v_marca uuid;
  v_dup   uuid;
  v_id    uuid;
  v_aviso text;
begin
  select id into v_marca from app.marcas where codigo = upper(trim(p_marca_codigo));
  if v_marca is null then
    raise exception 'La marca % no está registrada. Pídele al administrador que la cree.',
                    p_marca_codigo;
  end if;

  if v_marca not in (select app.marcas_escribibles()) then
    raise exception 'No tienes permiso para cargar datos de la marca %', p_marca_codigo;
  end if;

  select id into v_dup from app.cargas
   where archivo_hash = p_archivo_hash and estado = 'ok'
   order by creado_en desc limit 1;

  if v_dup is not null then
    v_aviso := 'Este archivo ya se cargó antes con el mismo contenido. Se procesará igual; '
            || 'los valores se sobreescribirán sin cambios.';
  end if;

  if p_truncado then
    v_aviso := coalesce(v_aviso || ' ', '')
            || 'La exportación viene TRUNCADA por el SIM: faltan filas. '
            || 'Revisa las dimensiones que pediste y el rango de fechas.';
  end if;

  insert into app.cargas (usuario_id, marca_id, archivo_nombre, archivo_hash, grano, mascara,
                          periodo_desde, periodo_hasta, filas_leidas, filas_subtotal,
                          truncado, filtros_crudos, lotes_esperados, duplicado_de, estado)
  values (auth.uid(), v_marca, p_archivo_nombre, p_archivo_hash, p_grano, p_mascara,
          p_periodo_desde, p_periodo_hasta, p_filas_leidas, p_filas_subtotal,
          p_truncado, p_filtros_crudos, p_lotes_esperados, v_dup, 'procesando')
  returning id into v_id;

  return query select v_id, v_marca, v_dup, v_aviso;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
--  2. INGERIR HECHOS (por lotes)
--
--  El indicador llega con la etiqueta del SIM ("Venta Neta") o con el
--  código interno ("venta_neta"); ambos se resuelven. Los que no existen
--  en el catálogo se cuentan y se devuelven: nunca se descartan en silencio.
-- ─────────────────────────────────────────────────────────────────────

drop function if exists app.ingerir_hechos(uuid, jsonb);
create or replace function app.ingerir_hechos(
  p_carga_id uuid,
  p_filas    jsonb
) returns table (hechos_escritos int, entidades_nuevas int,
                 indicadores_desconocidos text[], lotes_recibidos int)
language plpgsql security invoker set search_path = app, public as $$
declare
  v_marca   uuid;
  v_estado  text;
  v_hechos  int := 0;
  v_ents    int := 0;
  v_desc    text[];
  v_lotes   int;
begin
  select marca_id, estado into v_marca, v_estado from app.cargas where id = p_carga_id;
  if v_marca is null then
    raise exception 'Carga % inexistente', p_carga_id;
  end if;
  if v_estado <> 'procesando' then
    raise exception 'La carga % ya está %; no admite más lotes', p_carga_id, v_estado;
  end if;

  create temp table if not exists _lote (
    grano app.grano, clave text, nombre text, atributos jsonb,
    periodo date, indicador text, mascara app.mascara, valor numeric
  ) on commit drop;
  truncate _lote;

  insert into _lote
  select (x.grano)::app.grano, trim(x.clave), x.nombre, coalesce(x.atributos,'{}'::jsonb),
         date_trunc('month', x.periodo)::date, trim(x.indicador),
         (x.mascara)::app.mascara, x.valor
  from jsonb_to_recordset(p_filas)
       as x(grano text, clave text, nombre text, atributos jsonb,
            periodo date, indicador text, mascara text, valor numeric)
  where x.valor is not null and x.clave is not null and x.clave <> '';

  -- Indicadores que el catálogo no reconoce
  select array_agg(distinct l.indicador) into v_desc
  from _lote l
  where not exists (select 1 from app.indicadores i
                     where i.activo and (i.etiqueta_sim = l.indicador or i.codigo = l.indicador));

  -- Entidades: crear las nuevas, refrescar nombre y atributos de las existentes
  with distintas as (
    select distinct on (grano, clave) grano, clave, nombre, atributos from _lote
  ),
  ins as (
    insert into app.entidades (marca_id, grano, clave_natural, nombre, atributos)
    select v_marca, grano, clave, coalesce(nombre, clave), atributos from distintas
    on conflict (marca_id, grano, clave_natural) do update
      set nombre    = excluded.nombre,
          atributos = app.entidades.atributos || excluded.atributos
    returning (xmax = 0) as nueva
  )
  select count(*) filter (where nueva) into v_ents from ins;

  -- Hechos: upsert con factor de escala
  with resuelto as (
    select e.id as entidad_id, l.periodo, i.id as indicador_id, l.mascara,
           l.valor * i.factor_escala as valor
    from _lote l
    join app.entidades  e on e.marca_id = v_marca and e.grano = l.grano
                         and e.clave_natural = l.clave
    join app.indicadores i on i.activo
                          and (i.etiqueta_sim = l.indicador or i.codigo = l.indicador)
  ),
  ins as (
    insert into app.hechos (marca_id, entidad_id, periodo, indicador_id, mascara, valor, carga_id)
    select v_marca, entidad_id, periodo, indicador_id, mascara, valor, p_carga_id
    from resuelto
    on conflict (entidad_id, periodo, indicador_id, mascara) do update
      set valor = excluded.valor, carga_id = excluded.carga_id, actualizado_en = now()
    returning 1
  )
  select count(*) into v_hechos from ins;

  update app.cargas
     set hechos_escritos = app.cargas.hechos_escritos + v_hechos,
         lotes_recibidos = app.cargas.lotes_recibidos + 1,
         indicadores_desconocidos =
           (select array_agg(distinct u) from unnest(
              app.cargas.indicadores_desconocidos || coalesce(v_desc,'{}')) u)
   where id = p_carga_id
   returning app.cargas.lotes_recibidos into v_lotes;

  return query select v_hechos, v_ents, coalesce(v_desc,'{}'::text[]), v_lotes;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
--  3. PERÍODOS
--  El último mes con Venta Neta es el mes en curso: va parcial y no
--  entra en promedios, pronósticos ni cobertura.
-- ─────────────────────────────────────────────────────────────────────

create or replace function app.marcar_periodos(p_marca uuid, p_corte_al date default current_date)
returns void language plpgsql security invoker set search_path = app, public as $$
declare v_ultimo date;
begin
  select max(h.periodo) into v_ultimo
  from app.hechos h
  join app.indicadores i on i.id = h.indicador_id and i.codigo = 'venta_neta'
  where h.marca_id = p_marca and h.mascara = 'usd';

  if v_ultimo is null then return; end if;

  insert into app.periodos (marca_id, periodo, cerrado, corte_al)
  select p_marca, h.periodo, (h.periodo < v_ultimo),
         case when h.periodo = v_ultimo then p_corte_al end
  from (select distinct periodo from app.hechos where marca_id = p_marca) h
  on conflict (marca_id, periodo) do update
    set cerrado  = excluded.cerrado,
        corte_al = excluded.corte_al;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
--  4. FINALIZAR CARGA
--  Se llama una vez, cuando llegaron todos los lotes.
-- ─────────────────────────────────────────────────────────────────────

create or replace function app.finalizar_carga(p_carga_id uuid, p_url_archivo text default null)
returns table (estado text, hechos int, lotes int, esperados int, avisos text[])
language plpgsql security invoker set search_path = app, public as $$
declare
  c app.cargas%rowtype;
  v_avisos text[] := '{}';
begin
  select * into c from app.cargas where id = p_carga_id;
  if c.id is null then raise exception 'Carga % inexistente', p_carga_id; end if;
  if c.estado <> 'procesando' then
    raise exception 'La carga % ya está %', p_carga_id, c.estado;
  end if;

  if c.lotes_esperados is not null and c.lotes_recibidos < c.lotes_esperados then
    update app.cargas set estado = 'error',
      error_detalle = format('Llegaron %s de %s lotes', c.lotes_recibidos, c.lotes_esperados)
    where id = p_carga_id;
    raise exception 'Carga incompleta: llegaron % de % lotes. Reintenta los que faltan.',
                    c.lotes_recibidos, c.lotes_esperados;
  end if;

  if c.hechos_escritos = 0 then
    v_avisos := v_avisos || 'El archivo no produjo ningún dato. Revisa que el corte sea el correcto.';
  end if;
  if c.truncado then
    v_avisos := v_avisos || 'Exportación truncada por el SIM: los totales van a quedar incompletos.';
  end if;
  if coalesce(array_length(c.indicadores_desconocidos,1),0) > 0 then
    v_avisos := v_avisos || ('Indicadores no reconocidos y omitidos: '
                             || array_to_string(c.indicadores_desconocidos, ', '));
  end if;

  perform app.marcar_periodos(c.marca_id);

  update app.cargas
     set estado = 'ok', archivo_url = coalesce(p_url_archivo, archivo_url)
   where id = p_carga_id;

  perform app.refrescar_agregados();

  return query select 'ok'::text, c.hechos_escritos, c.lotes_recibidos,
                      c.lotes_esperados, v_avisos;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
--  5. INVENTARIO (infocompras)
--  Foto con fecha, no serie mensual. Solo la hoja de marcas escribibles.
-- ─────────────────────────────────────────────────────────────────────

create or replace function app.ingerir_inventario(
  p_marca_codigo text,
  p_tomado_en    date,
  p_archivo_nombre text,
  p_filas        jsonb   -- [{"codigo":"22-13-007","nombre":"...","disponible":1802,
                         --   "transito":87632,"costo":0.83,"precio_venta":1.21,
                         --   "ultima_compra":"2026-07-14","descontinuado":false,
                         --   "subcategoria":"Aspersores"}]
) returns table (carga_id uuid, articulos int, sin_cruce int)
language plpgsql security invoker set search_path = app, public as $$
declare
  v_marca uuid; v_carga uuid; v_n int; v_sin int;
begin
  select id into v_marca from app.marcas where codigo = upper(trim(p_marca_codigo));
  if v_marca is null then
    raise exception 'La marca % no está registrada', p_marca_codigo;
  end if;
  if v_marca not in (select app.marcas_escribibles()) then
    raise exception 'No tienes permiso sobre la marca %', p_marca_codigo;
  end if;

  insert into app.cargas (usuario_id, marca_id, archivo_nombre, archivo_hash, grano, mascara,
                          periodo_desde, periodo_hasta, estado)
  values (auth.uid(), v_marca, p_archivo_nombre, md5(p_filas::text), 'articulo', 'unidades',
          p_tomado_en, p_tomado_en, 'procesando')
  returning id into v_carga;

  -- Asegurar que existan las entidades de artículo (por si el infocompras
  -- trae códigos que el SIM aún no ha reportado)
  insert into app.entidades (marca_id, grano, clave_natural, nombre, atributos)
  select v_marca, 'articulo', trim(x.codigo), coalesce(x.nombre, x.codigo),
         jsonb_strip_nulls(jsonb_build_object('subcategoria', x.subcategoria))
  from jsonb_to_recordset(p_filas)
       as x(codigo text, nombre text, subcategoria text)
  where x.codigo is not null
  on conflict (marca_id, grano, clave_natural) do update
    set atributos = app.entidades.atributos || excluded.atributos;

  with ins as (
    insert into app.inventario_snapshot
      (entidad_id, tomado_en, disponible, transito, costo, precio_venta,
       ultima_compra, descontinuado, carga_id)
    select e.id, p_tomado_en, x.disponible, x.transito, x.costo, x.precio_venta,
           x.ultima_compra, coalesce(x.descontinuado,false), v_carga
    from jsonb_to_recordset(p_filas)
         as x(codigo text, disponible numeric, transito numeric, costo numeric,
              precio_venta numeric, ultima_compra date, descontinuado boolean)
    join app.entidades e on e.marca_id = v_marca and e.grano = 'articulo'
                        and e.clave_natural = trim(x.codigo)
    on conflict (entidad_id, tomado_en) do update
      set disponible = excluded.disponible, transito = excluded.transito,
          costo = excluded.costo, precio_venta = excluded.precio_venta,
          ultima_compra = excluded.ultima_compra, descontinuado = excluded.descontinuado,
          carga_id = excluded.carga_id
    returning 1
  )
  select count(*) into v_n from ins;

  select count(*) into v_sin
  from jsonb_to_recordset(p_filas) as x(codigo text)
  where not exists (select 1 from app.hechos h join app.entidades e on e.id = h.entidad_id
                     where e.marca_id = v_marca and e.clave_natural = trim(x.codigo));

  update app.cargas set estado = 'ok', hechos_escritos = v_n where id = v_carga;

  return query select v_carga, v_n, v_sin;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
--  6. ARTÍCULOS SIN CLIENTES EXCLUIDOS
--  Los archivos filtrados a EPA entran con grano 'cliente_articulo' y
--  clave 'RAZON SOCIAL|CODIGO'. Esta vista resta a cada artículo lo que
--  vendió a clientes marcados con excluir_de_analisis. El botón de la
--  interfaz elige entre v_articulo_mes y esta.
-- ─────────────────────────────────────────────────────────────────────

drop view if exists app.v_articulo_mes_sin_excluidos;
create view app.v_articulo_mes_sin_excluidos with (security_invoker = true) as
with excluidos as (
  select ca.marca_id, h.periodo, h.mascara, i.codigo,
         split_part(ca.clave_natural, '|', 2) as codigo_articulo,
         sum(h.valor) as valor
  from app.hechos h
  join app.entidades ca on ca.id = h.entidad_id and ca.grano = 'cliente_articulo'
  join app.entidades cl on cl.marca_id = ca.marca_id and cl.grano = 'cliente'
                       and cl.clave_natural = split_part(ca.clave_natural, '|', 1)
                       and cl.excluir_de_analisis
  join app.indicadores i on i.id = h.indicador_id
  group by ca.marca_id, h.periodo, h.mascara, i.codigo, split_part(ca.clave_natural,'|',2)
)
select a.marca_id, a.entidad_id, a.periodo,
       a.venta_usd    - coalesce(eu.valor, 0) as venta_usd,
       a.venta_unid   - coalesce(eq.valor, 0) as venta_unid,
       a.contribucion - coalesce(ec.valor, 0) as contribucion
from app.mv_articulo_mes a
join app.entidades e on e.id = a.entidad_id
left join excluidos eu on eu.marca_id = a.marca_id and eu.periodo = a.periodo
                      and eu.codigo_articulo = e.clave_natural
                      and eu.codigo = 'venta_neta' and eu.mascara = 'usd'
left join excluidos eq on eq.marca_id = a.marca_id and eq.periodo = a.periodo
                      and eq.codigo_articulo = e.clave_natural
                      and eq.codigo = 'venta_neta' and eq.mascara = 'unidades'
left join excluidos ec on ec.marca_id = a.marca_id and ec.periodo = a.periodo
                      and ec.codigo_articulo = e.clave_natural
                      and ec.codigo = 'contribucion' and ec.mascara = 'usd'
where a.marca_id in (select app.marcas_visibles());

-- ─────────────────────────────────────────────────────────────────────
--  7. STORAGE
--  Bucket privado; cada usuario solo escribe bajo las marcas que puede
--  escribir, y lee las que puede ver. La ruta es sim-exports/{codigo}/...
-- ─────────────────────────────────────────────────────────────────────

insert into storage.buckets (id, name, public) values ('sim-exports','sim-exports', false)
on conflict (id) do nothing;

create policy "subir exportaciones de marcas propias" on storage.objects for insert
  with check (
    bucket_id = 'sim-exports'
    and (storage.foldername(name))[1] in
        (select codigo from app.marcas where id in (select app.marcas_escribibles()))
  );

create policy "leer exportaciones de marcas visibles" on storage.objects for select
  using (
    bucket_id = 'sim-exports'
    and (storage.foldername(name))[1] in
        (select codigo from app.marcas where id in (select app.marcas_visibles()))
  );

-- ─────────────────────────────────────────────────────────────────────
--  8. SECUENCIA DESDE EL CLIENTE (referencia)
-- ─────────────────────────────────────────────────────────────────────
--
--  const { data: [c] } = await sb.rpc('iniciar_carga', {
--    p_marca_codigo: 'PCP', p_archivo_nombre: file.name, p_archivo_hash: hash,
--    p_grano: 'articulo', p_mascara: 'usd',
--    p_periodo_desde: '2023-08-01', p_periodo_hasta: '2026-09-01',
--    p_filas_leidas: 194, p_filas_subtotal: 12, p_truncado: false,
--    p_filtros_crudos: bloqueFiltros, p_lotes_esperados: lotes.length,
--  });
--  if (c.aviso) mostrar(c.aviso);
--
--  await sb.storage.from('sim-exports')
--    .upload(`PCP/2026/${c.carga_id}.xlsx`, file);
--
--  for (const [i, lote] of lotes.entries()) {
--    const { data: [r] } = await sb.rpc('ingerir_hechos',
--      { p_carga_id: c.carga_id, p_filas: lote });
--    progreso(i + 1, lotes.length, r.hechos_escritos);
--  }
--
--  const { data: [fin] } = await sb.rpc('finalizar_carga',
--    { p_carga_id: c.carga_id, p_url_archivo: `PCP/2026/${c.carga_id}.xlsx` });
--  fin.avisos.forEach(mostrar);
--
--  -- Si un lote falla, se reintenta ese lote solamente. Si el usuario
--  -- cierra la pestaña a la mitad, la carga queda en 'procesando' y un
--  -- job diario la marca como 'error' pasadas 24 horas.


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
drop view if exists app.v_marcas_sin_clasificar;
create view app.v_marcas_sin_clasificar with (security_invoker = true) as
select id, codigo, nombre, proveedor, venta_12m_usd, descubierta_en
from app.marcas
where origen is null and activa and app.gestiona_usuarios()
order by venta_12m_usd desc nulls last;

-- Catálogo completo con su estado operativo.
drop view if exists app.v_marcas;
create view app.v_marcas with (security_invoker = true) as
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
drop view if exists app.v_compradores;
create view app.v_compradores with (security_invoker = true) as
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


-- ════════════════════════════════════════════════════════════════════════
--  PERMISOS PARA LA API (PostgREST)
--  Supabase expone el esquema `app` solo si (1) se agrega a "Exposed
--  schemas" en Settings → API y (2) el rol authenticated tiene grants.
--  RLS sigue mandando: los grants dan la puerta, las políticas el filtro.
-- ════════════════════════════════════════════════════════════════════════

grant usage on schema app to authenticated, anon, service_role;
grant select, insert, update, delete on all tables in schema app to authenticated, service_role;
grant select on all tables in schema app to anon;
grant usage, select on all sequences in schema app to authenticated, service_role;
grant execute on all functions in schema app to authenticated, service_role;
alter default privileges in schema app grant select, insert, update, delete on tables to authenticated, service_role;
alter default privileges in schema app grant usage, select on sequences to authenticated, service_role;
alter default privileges in schema app grant execute on functions to authenticated, service_role;

-- Las vistas materializadas no aceptan RLS: solo las lee el dueño y las
-- funciones security definer. El cliente usa las vistas v_* encima.
revoke all on app.mv_marca_mes, app.mv_articulo_mes from authenticated, anon;


-- ════════════════════════════════════════════════════════════════════════
--  AJUSTES TRAS LA PRUEBA FUNCIONAL
-- ════════════════════════════════════════════════════════════════════════

-- Búsqueda de marca que ignora RLS. Sin esto, cuando un usuario no tiene
-- acceso a una marca, las funciones dicen "no existe" en vez de "no tienes
-- permiso", que es engañoso y dificulta el soporte.
create or replace function app.buscar_marca(p_id uuid default null, p_codigo text default null)
returns table (id uuid, codigo text, origen app.origen_marca, activa boolean)
language sql stable security definer set search_path = app, public as $$
  select m.id, m.codigo, m.origen, m.activa from app.marcas m
   where (p_id is not null and m.id = p_id)
      or (p_codigo is not null and m.codigo = upper(trim(p_codigo)))
   limit 1
$$;

create or replace function app.iniciar_carga(
  p_marca_codigo text, p_archivo_nombre text, p_archivo_hash text,
  p_grano app.grano, p_mascara app.mascara, p_periodo_desde date, p_periodo_hasta date,
  p_filas_leidas int, p_filas_subtotal int, p_truncado boolean, p_filtros_crudos text,
  p_lotes_esperados int
) returns table (carga_id uuid, marca_id uuid, duplicado_de uuid, aviso text)
language plpgsql security invoker set search_path = app, public as $$
declare v_marca uuid; v_activa boolean; v_dup uuid; v_id uuid; v_aviso text;
begin
  select b.id, b.activa into v_marca, v_activa from app.buscar_marca(null, p_marca_codigo) b;
  if v_marca is null then
    raise exception 'La marca % no está registrada. Pídele al administrador que la cree.', p_marca_codigo;
  end if;
  if not v_activa then
    raise exception 'La marca % está inactiva', p_marca_codigo;
  end if;
  if v_marca not in (select app.marcas_escribibles()) then
    raise exception 'No tienes permiso para cargar datos de la marca %', p_marca_codigo;
  end if;

  select c.id into v_dup from app.cargas c
   where c.archivo_hash = p_archivo_hash and c.estado = 'ok'
   order by c.creado_en desc limit 1;
  if v_dup is not null then
    v_aviso := 'Este archivo ya se cargó antes con el mismo contenido. Se procesará igual.';
  end if;
  if p_truncado then
    v_aviso := coalesce(v_aviso || ' ', '') ||
      'La exportación viene TRUNCADA por el SIM: faltan filas. Revisa dimensiones y rango de fechas.';
  end if;

  insert into app.cargas (usuario_id, marca_id, archivo_nombre, archivo_hash, grano, mascara,
                          periodo_desde, periodo_hasta, filas_leidas, filas_subtotal, truncado,
                          filtros_crudos, lotes_esperados, duplicado_de, estado)
  values (auth.uid(), v_marca, p_archivo_nombre, p_archivo_hash, p_grano, p_mascara,
          p_periodo_desde, p_periodo_hasta, p_filas_leidas, p_filas_subtotal, p_truncado,
          p_filtros_crudos, p_lotes_esperados, v_dup, 'procesando')
  returning id into v_id;
  return query select v_id, v_marca, v_dup, v_aviso;
end;
$$;

create or replace function app.asignar_marca(
  p_marca_id uuid, p_usuario uuid,
  p_desde date default current_date, p_hasta date default null,
  p_titular boolean default true, p_motivo text default null
) returns bigint
language plpgsql security invoker set search_path = app, public as $$
declare v_id bigint; v_origen app.origen_marca; v_activa boolean; v_rol app.rol; v_activo boolean;
begin
  select b.origen, b.activa into v_origen, v_activa from app.buscar_marca(p_marca_id, null) b;
  if not found then
    raise exception 'Marca inexistente';
  end if;
  if not v_activa then
    raise exception 'La marca está inactiva';
  end if;
  if not app.puede_asignar(p_marca_id) then
    raise exception 'No tienes alcance sobre esa marca para asignarla';
  end if;
  if v_origen is null then
    raise exception 'La marca no está clasificada como nacional o internacional. '
                    'Pídele al administrador que la clasifique antes de asignarla.';
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

  insert into app.usuario_marca (usuario_id, marca_id, titular, vigente_desde, vigente_hasta,
                                 motivo, creado_por)
  values (p_usuario, p_marca_id, p_titular, p_desde, p_hasta, p_motivo, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

-- El feed decía "Modificó una marca" para una clasificación. Ahora lo dice.
drop view if exists app.v_actividad;
create view app.v_actividad with (security_invoker = true) as
select c.creado_en as cuando, p.nombre as quien, p.rol as rol,
       m.codigo as marca, m.origen, 'carga' as tipo,
       case
         when c.estado = 'revertida' then 'Revirtió la carga de ' || c.archivo_nombre
         when c.truncado then 'Cargó ' || c.archivo_nombre || ' (EXPORTACIÓN TRUNCADA)'
         else 'Cargó ' || c.archivo_nombre || ' · ' || c.grano::text || ' · ' || c.hechos_escritos || ' datos'
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
        when 'insert' then 'Nombró jefe de marcas ' || (a.despues->>'origen') || ' desde el ' || (a.despues->>'vigente_desde')
             || coalesce(' hasta el ' || (a.despues->>'vigente_hasta'), '')
        when 'update' then 'Modificó una jefatura de compras'
        else 'Eliminó una jefatura programada' end
    when 'usuario_marca' then
      case
        when a.accion = 'insert' and (a.despues->>'titular')::boolean = false then
          'Programó una suplencia del ' || (a.despues->>'vigente_desde') || ' al ' || coalesce(a.despues->>'vigente_hasta','indefinido')
        when a.accion = 'insert' then 'Asignó la marca desde el ' || (a.despues->>'vigente_desde')
        when a.accion = 'update' and (a.antes->>'vigente_hasta') is null and (a.despues->>'vigente_hasta') is not null then
          'Terminó la asignación el ' || (a.despues->>'vigente_hasta') || coalesce(' · ' || (a.despues->>'motivo'), '')
        when a.accion = 'delete' then 'Eliminó una asignación programada'
        else 'Cambió una asignación de marca' end
    when 'perfiles' then
      case a.accion
        when 'insert' then 'Creó el usuario ' || coalesce(a.despues->>'nombre','')
        when 'update' then
          case when (a.antes->>'rol') is distinct from (a.despues->>'rol')
               then 'Cambió el rol de ' || coalesce(a.despues->>'nombre','') || ': ' || (a.antes->>'rol') || ' → ' || (a.despues->>'rol')
               when (a.antes->>'activo') is distinct from (a.despues->>'activo')
               then case when (a.despues->>'activo')::boolean then 'Reactivó a ' else 'Desactivó a ' end || coalesce(a.despues->>'nombre','')
               else 'Editó el usuario ' || coalesce(a.despues->>'nombre','') end
        else 'Modificó un usuario' end
    when 'parametros_marca' then 'Cambió los parámetros de compra'
    when 'marcas' then
      case
        when a.accion = 'insert' then 'Registró la marca ' || coalesce(a.despues->>'codigo','')
        when (a.antes->>'origen') is distinct from (a.despues->>'origen') then
          'Clasificó ' || coalesce(a.despues->>'codigo','') || ' como ' || coalesce(a.despues->>'origen','')
        when (a.antes->>'activa') is distinct from (a.despues->>'activa') then
          case when (a.despues->>'activa')::boolean then 'Reactivó' else 'Desactivó' end || ' la marca ' || coalesce(a.despues->>'codigo','')
        else 'Modificó la marca ' || coalesce(a.despues->>'codigo','') end
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

grant execute on all functions in schema app to authenticated, service_role;

-- El jefe necesita ver a todos los compradores y lectores para poder
-- asignarles marcas; con la política anterior solo veía a quienes ya
-- tenían una marca suya, y no podía incorporar gente nueva a su equipo.
drop policy if exists perfil_lectura on app.perfiles;
create policy perfil_lectura on app.perfiles for select
  using (id = auth.uid()
         or app.gestiona_usuarios()
         or (app.rol_actual() = 'jefe_compras' and rol in ('comprador','lectura')));

-- Búsqueda de perfil que ignora RLS, para mensajes de error precisos.
create or replace function app.buscar_perfil(p_id uuid)
returns table (id uuid, nombre text, rol app.rol, activo boolean)
language sql stable security definer set search_path = app, public as $$
  select p.id, p.nombre, p.rol, p.activo from app.perfiles p where p.id = p_id
$$;

create or replace function app.asignar_marca(
  p_marca_id uuid, p_usuario uuid,
  p_desde date default current_date, p_hasta date default null,
  p_titular boolean default true, p_motivo text default null
) returns bigint
language plpgsql security invoker set search_path = app, public as $$
declare v_id bigint; v_origen app.origen_marca; v_activa boolean; v_rol app.rol; v_activo boolean;
begin
  select b.origen, b.activa into v_origen, v_activa from app.buscar_marca(p_marca_id, null) b;
  if not found then raise exception 'Marca inexistente'; end if;
  if not v_activa then raise exception 'La marca está inactiva'; end if;
  if not app.puede_asignar(p_marca_id) then
    raise exception 'No tienes alcance sobre esa marca para asignarla';
  end if;
  if v_origen is null then
    raise exception 'La marca no está clasificada como nacional o internacional. '
                    'Pídele al administrador que la clasifique antes de asignarla.';
  end if;

  select b.rol, b.activo into v_rol, v_activo from app.buscar_perfil(p_usuario) b;
  if not found then raise exception 'Usuario inexistente'; end if;
  if not v_activo then raise exception 'El usuario está desactivado'; end if;
  if v_rol in ('admin','gerencia','jefe_compras') then
    raise exception 'El rol % ya ve la marca por su alcance; no necesita asignación directa', v_rol;
  end if;
  if exists (select 1 from app.usuario_marca
              where usuario_id = p_usuario and marca_id = p_marca_id
                and vigencia && daterange(p_desde, p_hasta, '[)')) then
    raise exception 'Esa persona ya tiene la marca asignada en ese rango de fechas';
  end if;

  insert into app.usuario_marca (usuario_id, marca_id, titular, vigente_desde, vigente_hasta,
                                 motivo, creado_por)
  values (p_usuario, p_marca_id, p_titular, p_desde, p_hasta, p_motivo, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;
grant execute on all functions in schema app to authenticated, service_role;
