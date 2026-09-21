\set ON_ERROR_STOP off
\pset format unaligned
\pset tuples_only on

-- Usuarios simulados
insert into auth.users (id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000001','admin@febeca.com','{"nombre":"Admin"}'),
 ('00000000-0000-0000-0000-000000000002','gerencia@febeca.com','{"nombre":"Gerente"}'),
 ('00000000-0000-0000-0000-000000000003','jefe.intl@febeca.com','{"nombre":"Jefe Intl"}'),
 ('00000000-0000-0000-0000-000000000004','jefe.nac@febeca.com','{"nombre":"Jefe Nac"}'),
 ('00000000-0000-0000-0000-000000000005','adriana@febeca.com','{"nombre":"Adriana"}'),
 ('00000000-0000-0000-0000-000000000006','carlos@febeca.com','{"nombre":"Carlos"}'),
 ('00000000-0000-0000-0000-000000000007','lector@febeca.com','{"nombre":"Lector"}');

\echo '1. trigger creó perfiles con rol lectura:'
select count(*) || ' perfiles, roles: ' || string_agg(distinct rol::text, ',') from app.perfiles;

update app.perfiles set rol='admin' where id='00000000-0000-0000-0000-000000000001';

-- ── como ADMIN ──
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
\echo '2. admin importa catálogo:'
select 'nuevas=' || nuevas || ' pend=' || sin_clasificar from app.importar_catalogo_marcas(
 '[{"codigo":"PCP","nombre":"PCP","venta_12m_usd":1584210},{"codigo":"BOSCH","nombre":"BOSCH","venta_12m_usd":12180000},{"codigo":"TUBRICA","nombre":"TUBRICA","venta_12m_usd":9000000}]');
select app.cambiar_rol('00000000-0000-0000-0000-000000000002','gerencia');
select app.cambiar_rol('00000000-0000-0000-0000-000000000005','comprador');
select app.cambiar_rol('00000000-0000-0000-0000-000000000006','comprador');
\echo '3. admin intenta cambiar su propio rol (debe fallar):'
select app.cambiar_rol('00000000-0000-0000-0000-000000000001','lectura');
\echo '4. asignar BOSCH sin clasificar (debe fallar):'
select app.asignar_marca((select id from app.marcas where codigo='BOSCH'),'00000000-0000-0000-0000-000000000005');
select app.clasificar_marca(id,'internacional') from app.marcas where codigo in ('PCP','BOSCH');
select app.clasificar_marca(id,'nacional') from app.marcas where codigo='TUBRICA';
select app.nombrar_jefe('00000000-0000-0000-0000-000000000003','internacional');
select app.nombrar_jefe('00000000-0000-0000-0000-000000000004','nacional');
\echo '5. estado de marcas tras clasificar:'
select codigo || ' → ' || estado from app.v_marcas order by codigo;

-- ── como JEFE INTL ──
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
\echo '6. jefe intl ve marcas:'
select string_agg(codigo, ',' order by codigo) from app.marcas where id in (select app.marcas_visibles());
\echo '7. jefe intl asigna PCP a Adriana (ok):'
select 'asignacion id=' || app.asignar_marca((select id from app.marcas where codigo='PCP'),'00000000-0000-0000-0000-000000000005');
\echo '8. jefe intl asigna TUBRICA (nacional, debe fallar con "alcance"):'
reset role; select set_config('app.tub',(select id::text from app.marcas where codigo='TUBRICA'),false) \g /dev/null
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
select app.asignar_marca(current_setting('app.tub')::uuid,'00000000-0000-0000-0000-000000000006');
\echo '9. jefe intl intenta cambiar un rol (debe fallar):'
select app.cambiar_rol('00000000-0000-0000-0000-000000000006','gerencia');

-- ── como ADRIANA ──
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000005';
\echo '10. Adriana ve:'
select coalesce(string_agg(codigo, ','), '(nada)') from app.marcas where id in (select app.marcas_visibles());
\echo '11. Adriana inicia carga de BOSCH (debe fallar):'
select carga_id from app.iniciar_carga('BOSCH','x.xlsx','h1','articulo','usd','2026-08-01','2026-08-01',1,0,false,'',1);
\echo '12. Adriana inicia carga de PCP (ok) e ingiere lote:'
select carga_id as cid from app.iniciar_carga('PCP','data23.xlsx','hash-a','articulo','usd','2026-07-01','2026-09-01',3,1,false,'Filtros...',1) \gset
select 'hechos=' || hechos_escritos || ' nuevas=' || entidades_nuevas || ' desconocidos=' || array_to_string(indicadores_desconocidos,',')
from app.ingerir_hechos(:'cid', '[
 {"grano":"articulo","clave":"22-13-007","nombre":"22-13-007 Canilla plástica","atributos":{"categoria":"Plomería"},"periodo":"2026-07-01","indicador":"Venta Neta","mascara":"usd","valor":12.5},
 {"grano":"articulo","clave":"22-13-007","nombre":"22-13-007 Canilla plástica","atributos":{"categoria":"Plomería"},"periodo":"2026-08-01","indicador":"Venta Neta","mascara":"usd","valor":13.424},
 {"grano":"articulo","clave":"22-13-007","nombre":"22-13-007 Canilla plástica","atributos":{},"periodo":"2026-08-01","indicador":"Presupuesto bruto","mascara":"usd","valor":14000},
 {"grano":"articulo","clave":"22-13-007","nombre":"22-13-007 Canilla plástica","atributos":{},"periodo":"2026-09-01","indicador":"Venta Neta","mascara":"usd","valor":3.1},
 {"grano":"articulo","clave":"22-13-007","nombre":"x","atributos":{},"periodo":"2026-08-01","indicador":"Indicador Raro","mascara":"usd","valor":1}
]'::jsonb);
select 'finalizar: ' || estado || ' hechos=' || hechos || ' avisos=' || array_to_string(avisos,' | ') from app.finalizar_carga(:'cid');
\echo '13. escalas normalizadas (venta ×1000, presupuesto ×1) y período parcial:'
select i.codigo || ' ' || h.periodo || ' = ' || h.valor from app.hechos h join app.indicadores i on i.id=h.indicador_id order by 1;
select periodo || ' cerrado=' || cerrado from app.periodos order by 1;
\echo '14. Adriana ajusta agosto a mano y recarga: el ajuste sobrevive'
select 'ajuste id=' || app.ajustar_hecho((select id from app.entidades where clave_natural='22-13-007'),'2026-08-01','venta_neta','usd',13000,'Nota de crédito no reflejada en el SIM');
select carga_id as cid2 from app.iniciar_carga('PCP','data23-v2.xlsx','hash-b','articulo','usd','2026-08-01','2026-08-01',1,0,false,'',1) \gset
select hechos_escritos from app.ingerir_hechos(:'cid2','[{"grano":"articulo","clave":"22-13-007","nombre":"x","atributos":{},"periodo":"2026-08-01","indicador":"Venta Neta","mascara":"usd","valor":13.9}]'::jsonb);
select estado from app.finalizar_carga(:'cid2');
select 'v_hechos ago: sim=' || valor_sim || ' efectivo=' || valor || ' ajustado=' || ajustado from app.v_hechos where periodo='2026-08-01' and indicador_id=(select id from app.indicadores where codigo='venta_neta');

-- ── como CARLOS (comprador sin marcas) ──
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000006';
\echo '15. Carlos ve hechos de PCP (debe ser 0):'
select count(*) from app.v_hechos;
\echo '16. Carlos intenta insertar en hechos directamente (debe fallar):'
reset role;
select set_config('app.tm',(select id::text from app.marcas where codigo='PCP'),false) \g /dev/null
select set_config('app.te',(select id::text from app.entidades where grano='articulo' and clave_natural='22-13-007'),false) \g /dev/null
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000006';
insert into app.hechos (marca_id,entidad_id,periodo,indicador_id,mascara,valor) values (current_setting('app.tm')::uuid, current_setting('app.te')::bigint,'2026-01-01',1,'usd',1);


-- ── como GERENCIA ──
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
\echo '17. Gerencia ve hechos (debe ser >0) pero no escribe:'
select count(*) || ' hechos visibles' from app.v_hechos;
select carga_id from app.iniciar_carga('PCP','x.xlsx','h9','articulo','usd','2026-08-01','2026-08-01',1,0,false,'',1);
\echo '18. Gerencia programa suplencia de Carlos en PCP para mañana:'
select 'suplencia id=' || app.programar_suplencia((select id from app.marcas where codigo='PCP'),'00000000-0000-0000-0000-000000000006', current_date+1, current_date+8, 'Vacaciones Adriana');
\echo '19. Feed de actividad (gerencia):'
select tipo || ' · ' || quien || ' · ' || detalle from app.v_actividad order by cuando limit 12;

-- ── CARLOS otra vez: hoy no, mañana sí ──
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000006';
\echo '20. Carlos hoy ve PCP? (no) / tendrá acceso mañana? (sí):'
select coalesce(string_agg(codigo, ','),'(nada)') from app.marcas where id in (select app.marcas_visibles());
select string_agg(codigo, ',') from app.marcas where id in (select app.marcas_asignadas_en('00000000-0000-0000-0000-000000000006', current_date+1));

reset role;
\echo '21. auditoría escrita solo por triggers:'
select count(*) || ' eventos: ' || string_agg(distinct tabla, ',') from app.auditoria;
\echo '22. pedido sugerido (sin pronósticos aún → vacío, sin error):'
select count(*) from app.v_pedido_sugerido;

-- ── INDICADORES: catálogo protegido ──
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000007';
\echo '23. lector lee indicadores (14) pero no los modifica (0); anon no ve ninguno (0):'
select count(*) || ' indicadores visibles para lector' from app.indicadores;
with u as (update app.indicadores set factor_escala = 999 where codigo='venta_neta' returning 1)
select count(*) || ' filas modificadas por lector' from u;
set role anon;
select count(*) || ' indicadores visibles para anon' from app.indicadores;
reset role;
select 'factor_escala venta_neta sigue en ' || factor_escala from app.indicadores where codigo='venta_neta';
