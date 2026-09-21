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

create or replace view app.v_articulo_mes_sin_excluidos with (security_invoker = true) as
with excluidos as (
  select ca.marca_id, ca.periodo, h.mascara, i.codigo,
         split_part(ca.clave_natural, '|', 2) as codigo_articulo,
         sum(h.valor) as valor
  from app.hechos h
  join app.entidades ca on ca.id = h.entidad_id and ca.grano = 'cliente_articulo'
  join app.entidades cl on cl.marca_id = ca.marca_id and cl.grano = 'cliente'
                       and cl.clave_natural = split_part(ca.clave_natural, '|', 1)
                       and cl.excluir_de_analisis
  join app.indicadores i on i.id = h.indicador_id
  group by ca.marca_id, ca.periodo, h.mascara, i.codigo, split_part(ca.clave_natural,'|',2)
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
