# Febeca · Siguientes pasos con Supabase ya creado

Tres cosas, en orden. En cada una puede salir algo: si aparece un error, copiar el mensaje exacto.

## 1. Aplicar el esquema

SQL Editor → New query → pegar `febeca-supabase-consolidado.sql` completo → **Run**.

Está probado contra PostgreSQL 16 puro. El `auth` de Supabase puede tener alguna diferencia
menor; si sale un error, anotar el mensaje literal y la línea.

## 2. Exponer el esquema `app`

Settings → API → **Exposed schemas** → agregar `app` junto a `public` → Save.

Verificar en el SQL Editor:

```sql
select count(*) from app.indicadores;   -- debe dar 14
select count(*) from app.jefaturas;      -- debe dar 0 antes de la semilla
```

> Las vistas de administración (`v_origenes_sin_jefe`, `v_jefaturas`, `v_asignaciones`,
> `v_equipo`...) filtran por el rol del usuario autenticado. En el SQL Editor no hay usuario,
> así que **devuelven vacío aunque tengan datos**. Para verificar desde el editor, consulta
> las tablas directamente; las vistas se comprueban desde el módulo de administración.

## 3. Correr la semilla

La semilla hace tres cosas: invita al **administrador** (recibe un correo y elige su
contraseña), registra el catálogo inicial de marcas y las clasifica como nacionales o
internacionales. **No crea más usuarios**: gerencia, jefes y compradores los crea el
administrador desde el módulo, con sus roles, jefaturas y marcas.

Antes, revisar en `03-semilla/seed.mjs` la lista `CLASIFICACION`. Luego:

```bash
cd 03-semilla
npm install
SUPABASE_URL=https://TU-PROYECTO.supabase.co \
SUPABASE_SERVICE_ROLE=eyJ... \
ADMIN_EMAIL=quien.administra@febeca.com \
node seed.mjs [ruta/al/export-marcas-del-SIM.xlsx]
```

La **service role key** está en Settings → API, marcada como secreta.

> Esa clave no va al frontend, no va a ningún repositorio y no se comparte con nadie.
> Solo la usa `seed.mjs` desde tu máquina.

El argumento del xlsx es opcional: es la exportación del SIM con `Parameter = Marca`, sin
filtro, 12 meses, `Venta Neta`. Sin él, solo registra las marcas de `CLASIFICACION`.

> El correo de invitación sale por el SMTP por defecto de Supabase, que solo entrega a los
> correos del equipo del proyecto y con límite de pocos envíos por hora. Para invitar a
> gente fuera del equipo hay que configurar un SMTP propio en Authentication → SMTP.

**Estado (21-sep-2026):** el catálogo y la clasificación ya están cargados en el proyecto
(31 marcas). Falta solo invitar al administrador: correr la semilla igual, es idempotente
sobre las marcas.

## 4. Abrir el módulo de administración

La URL del proyecto y la anon key ya están fijas en `04-frontend/febeca-admin.jsx`. Para abrir
el módulo: `cd 04-frontend && npm install && npm run dev`, o la dirección de Netlify una vez
publicado.

Entrar con el correo del administrador y la contraseña que definió desde el correo de invitación.

## Verificación final

```sql
select codigo, origen, estado, responsables from app.v_marcas order by codigo;
select * from app.v_jefaturas;
select origen, count(*) from app.jefaturas where vigencia @> current_date group by 1;  -- 2 filas
select * from app.auditoria order by creado_en desc limit 20;
```

Las vistas `v_origenes_sin_jefe` y `v_actividad` se comprueban entrando como admin en el
módulo de administración (ver nota del paso 2).

## Errores frecuentes

| Síntoma | Causa | Arreglo |
|---|---|---|
| Todo devuelve 404 | `app` no está en Exposed schemas | Paso 2 |
| `permission denied for schema app` | Faltan los grants | Están al final del consolidado; reaplicar ese bloque |
| `Tu perfil no existe todavía` al entrar | El trigger sobre `auth.users` no se creó | Reaplicar la sección 1 de la migración 006 desde el SQL Editor |
| La semilla falla en `perfiles` | El usuario existe en Auth pero no tiene perfil | Mismo caso anterior |
| `No tienes alcance sobre esa marca` | El jefe intenta asignar una marca de otro origen | Correcto: lo hace admin, gerencia o el jefe del origen |
| `La marca no está clasificada` | Se intenta asignar antes de clasificar | Marcas → botón nacional / internacional |
