# CLAUDE.md — Dashboard de Compras · Febeca

Traspaso para continuar el desarrollo. Leer completo antes de tocar código.
Documentación extendida en `01-documentacion/contexto-dashboard-febeca.md`.

## Qué es

Dashboard para el departamento de compras de Febeca (mayorista de ferretería, Venezuela).
Reemplaza el trabajo manual de extraer reportes del **SIM** (sistema de reportería) y armar la
presentación semanal para gerencia. Calcula pronósticos, pedidos sugeridos y rankings.
Marca piloto: **PCP**. Usuarios: compradores, dos jefes de compras, gerencia, admin.

## Stack decidido

- **Base de datos:** Supabase (Postgres 16, Auth, RLS, Storage). Esquema `app`, no `public`.
- **Frontend:** React + Tailwind + lucide-react + Recharts. Habla con Supabase por **REST puro
  (`fetch`)**, sin `@supabase/supabase-js` en el navegador. El cliente mínimo está en
  `04-frontend/febeca-admin.jsx` → función `crearApi(url, anon)`.
- **Parseo de xlsx:** en el navegador con SheetJS (`xlsx`), en un Web Worker. Nunca en servidor.
- **Pronósticos:** Holt-Winters en JS (ya implementado en `febeca-dashboard-inteligente.jsx`).
  Destino final: Edge Function disparada por webhook. Hoy corre en el cliente.
- **Despliegue:** Netlify (web estática). Persistencia en Supabase, no en IndexedDB.

## Mapa del repositorio

```
01-documentacion/
  contexto-dashboard-febeca.md   ← contexto completo: datos, trampas, arquitectura, permisos
  GUIA-SUPABASE.md               ← puesta en marcha del proyecto Supabase
  PASOS-SUPABASE.md              ← checklist de arranque + errores frecuentes
02-base-de-datos/
  febeca-supabase-consolidado.sql ← LA FUENTE DE VERDAD del esquema. Se aplica completo.
  migraciones/001..006            ← historia, solo referencia. NO aplicar por separado.
  pruebas/febeca-stub-local.sql   ← simula auth/storage para Postgres local
  pruebas/febeca-test-rls.sql     ← 22 comprobaciones de permisos con 7 usuarios
03-semilla/seed.mjs               ← usuarios, roles, jefes, catálogo, asignaciones (service role)
04-frontend/
  febeca-admin.jsx                ← módulo de administración CONECTADO a Supabase
  dashboard-compras-febeca.jsx    ← parser funcional de xlsx del SIM (datos en memoria)
  febeca-dashboard-inteligente.jsx← 7 pestañas, datos de PCP embebidos, Holt-Winters
  febeca-pcp-ejecutivo.jsx        ← versión anterior, ignorar
05-datos-referencia/marcas-maestro-referencia.csv ← 243 marcas, snapshot 2023, solo referencia
```

Archivos xlsx del SIM para pruebas: `data (23)` artículos USD 48m · `data (39)` unidades ·
`data (24)` geografía · `data (28)` vendedores · `data (38)` clientes · `data (34)/(35)` EPA ·
`data (22)` OC · `MARCAS_FEBECA_MASTER` infocompras.

## Estado actual

**Hecho y probado**
- Esquema consolidado: corre limpio en Postgres 16 con el stub. 22/22 pruebas de RLS pasan.
- Módulo de administración: usuarios, roles, marcas, clasificación, asignaciones con vigencia,
  suplencias, jefaturas, feed de actividad, equipo. Sintaxis validada, no probado contra un
  Supabase real todavía.
- Parser de xlsx del SIM: detecta tipo de archivo, descarta subtotales, normaliza a filas largas.
- Motor de pronósticos y pedido sugerido en el cliente.
- Semilla: invita solo al admin y carga el catálogo. La parte de marcas ya se ejecutó.

- **Consolidado aplicado en Supabase real** (21-sep-2026, proyecto `khiuxmkhiuxqmxpurkqv`,
  Postgres 17): 14 tablas, 16 vistas, 2 materializadas, 41 funciones, trigger sobre
  `auth.users`, RLS en las 14 tablas. Se aplicó vía Management API (mismo motor que el SQL
  Editor). Cerrado el hueco de `indicadores` (no tenía RLS y `authenticated` podía escribir);
  prueba 23 del test local lo cubre.

- `app` expuesto en PostgREST. Catálogo inicial cargado: 31 marcas clasificadas (20
  internacionales, 11 nacionales), equivalente a los pasos 2 y 3 de `seed.mjs`.

**Pendiente**
- Invitar al administrador (`seed.mjs` con `ADMIN_EMAIL`, o Authentication → Users → Invite
  en el panel y luego `update app.perfiles set rol='admin'`). Los demás usuarios los crea el
  administrador desde el módulo; la semilla ya no trae usuarios ni contraseñas fijas.

## Tareas siguientes, en orden

### 1. Verificar el esquema en Supabase real — HECHO
Aplicado sin errores. Si más adelante hay que cambiar algo, corregir **en el consolidado**, no
en las migraciones, y aplicar solo el delta en Supabase (el consolidado no es re-ejecutable:
los `create type` fallan la segunda vez). Verificación desde el SQL Editor:
```sql
select count(*) from app.indicadores;   -- 14
select count(*) from app.jefaturas;      -- 0 antes de la semilla
```
Las vistas `v_*` de administración filtran por rol del usuario autenticado: desde el SQL
Editor (sin usuario) devuelven vacío. No es un error; verificar con las tablas directas.

### 2. Probar `febeca-admin.jsx` contra Supabase real
Login → cada rol ve sus pestañas → clasificar marca → asignar → suplencia → feed. Anotar
cualquier diferencia entre PostgREST real y lo que el cliente espera (nombres de parámetros
de RPC, forma de los errores).

### 3. Conectar el parser con la ingesta
Tomar `leerHojaSim` y `clasificar` de `dashboard-compras-febeca.jsx` y enchufarlos a:
```
iniciar_carga(...) → [Storage upload] → ingerir_hechos(carga_id, lote) × N → finalizar_carga(carga_id)
```
- Lotes de **5.000 filas**. Cada lote es su propia transacción; reintentar solo el que falle.
- El `indicador` viaja con la **etiqueta del SIM** (`"Venta Neta"`); la base lo mapea y aplica
  `factor_escala`. El cliente NO convierte escalas.
- Los archivos filtrados a EPA van con `grano: "cliente_articulo"` y
  `clave: "RAZON SOCIAL|CODIGO_ARTICULO"`.
- El infocompras va por `ingerir_inventario`, no por `ingerir_hechos`.
- Mostrar los `avisos` que devuelve `finalizar_carga` (truncado, indicadores desconocidos).
- Hash SHA-256 del archivo antes de parsear; el aviso de duplicado **no bloquea**.

### 4. Dashboard leyendo de la base
Sustituir los datos embebidos de `febeca-dashboard-inteligente.jsx` por consultas a
`v_marca_mes`, `v_articulo_mes`, `v_articulo_mes_sin_excluidos`, `v_hechos`,
`v_pedido_sugerido`. El botón de EPA cambia entre `v_articulo_mes` y `..._sin_excluidos`.
Selector de marca: solo las de `marcas_visibles()` (la vista `v_marcas` ya filtra).

### 5. Pronósticos persistidos
Al terminar una carga, calcular Holt-Winters por artículo y marca (con y sin excluidos) y
escribir en `app.pronosticos` marcando los anteriores `vigente = false`. Primera versión en el
cliente; después mover a Edge Function con Database Webhook sobre `app.cargas` (`estado='ok'`).

### 6. Producción
- Edge Function `invitar-usuario` con `auth.admin.inviteUserByEmail` (hoy el módulo usa
  signup; la semilla ya invita). Requiere SMTP propio para correos fuera del equipo.
- `pg_cron` diario: cargas en `procesando` > 24 h → `error`.
- SSO Azure AD si Febeca usa Microsoft 365.
- `.pptx` nativo con pptxgenjs para el exportador de cierre.

## Reglas duras (romperlas produce números incorrectos en silencio)

1. **Ninguna columna de dimensión puede valer `"Total"`.** Verificar solo la última infla
   estados ×3 y supervisores ×2.
2. **`Presupuesto bruto` llega en dólares absolutos; el resto en miles.** La base normaliza
   todo a dólares con `indicadores.factor_escala`. El frontend nunca convierte.
3. **Los meses válidos son los que traen `Venta Neta`.** El archivo trae meses futuros solo con
   presupuesto. El último mes con venta es **parcial**: fuera de promedios, pronósticos y cobertura.
4. **Ratios se recalculan, nunca se suman.** Margen = contribución / venta. Es la única forma de
   que sigan correctos al excluir EPA.
5. **EPA por coincidencia exacta**, nunca `LIKE '%EPA%'` (atrapa FERREPACA, AREPA HOUSE, etc.).
   Y nunca hardcodear: es `entidades.excluir_de_analisis`.
6. **Pronóstico y pedido sugerido se calculan sin clientes excluidos.** EPA compra a saltos y
   destruye la estacionalidad.
7. **La app consulta `v_hechos`, nunca `hechos`.** Los ajustes manuales viven en `ajustes` y
   la vista los aplica encima. Escribir sobre `hechos` directamente pierde correcciones.
8. **No auditar `hechos` fila por fila.** Las cargas masivas ya quedan en `cargas`.
9. **Escritura usa `marcas_escribibles()`, lectura `marcas_visibles()`.** Gerencia ve todo y no
   escribe nada. No mezclar.
10. **Las funciones de seguridad son `STABLE security definer`.** Cambiarlas a `VOLATILE` hace
    que RLS se evalúe fila por fila.
11. **`service_role` key jamás en el frontend ni en el repo.** Solo `seed.mjs` desde local.
12. **El esquema `app` debe estar en Exposed schemas.** Si todo da 404, es esto.

## Cómo probar la base en local

```bash
createdb febeca_test
psql -d febeca_test -f 02-base-de-datos/pruebas/febeca-stub-local.sql
psql -d febeca_test -f 02-base-de-datos/febeca-supabase-consolidado.sql
psql -d febeca_test -f 02-base-de-datos/pruebas/febeca-test-rls.sql
```
Simular un usuario: `set role authenticated; set request.jwt.claim.sub = '<uuid>';`

## Cifras de control (agosto 2026, PCP)

Si el parser o la ingesta no dan esto, algo está roto:
venta neta **$145.696** (sin EPA **$117.020**) · unidades **87.863** · contribución **$38.175**
· margen **26,2%** · inventario **$118.727** · OC **$390.080** · presupuesto **$141.751**
· regiones suman exacto 145,70 · 93 artículos con movimiento.

## Convenciones

- Código, comentarios, nombres de tablas, funciones y UI en **español**.
- Cambios al esquema: editar `febeca-supabase-consolidado.sql` y volver a correr el test local.
  Las migraciones numeradas son historia congelada.
- Cada función SQL nueva que consulte tablas con RLS y necesite ver todo → `security definer`
  + `set search_path = app, public`.
- Mensajes de error de las funciones: decir qué hacer, no solo qué falló
  ("Pídele al administrador que la clasifique").
