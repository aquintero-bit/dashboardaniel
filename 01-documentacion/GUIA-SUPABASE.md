# Febeca · Puesta en marcha en Supabase

Todo lo que hay que hacer a mano son cinco pasos en el panel. El resto es copiar y pegar.

## 1. Crear el proyecto

En [supabase.com](https://supabase.com) → **New project**. Región: la más cercana a Venezuela
(`us-east-1`). Guarda la contraseña de la base de datos.

## 2. Aplicar el esquema

**SQL Editor → New query** → pegar `febeca-supabase-consolidado.sql` completo → **Run**.

Son ~3.200 líneas y tarda unos segundos. Está probado contra PostgreSQL 16 con los 22 casos de
`febeca-test-rls.sql`: roles, RLS, ingesta por lotes, ajustes manuales, suplencias y auditoría.

> El trigger sobre `auth.users` solo se puede crear desde el SQL Editor, porque ahí corres como
> `postgres`. Si algún día migras a un pipeline de migraciones automático, ese trigger tiene que
> aplicarse aparte con privilegios elevados.

## 3. Exponer el esquema `app`

**Settings → API → Exposed schemas** → agregar `app` junto a `public`.

Sin esto, todas las llamadas devuelven 404 aunque el esquema esté perfecto. Es el error más común.

## 4. Correr la semilla

```bash
npm install
SUPABASE_URL=https://xxxx.supabase.co \
SUPABASE_SERVICE_ROLE=eyJ... \
ADMIN_EMAIL=quien.administra@febeca.com \
node seed.mjs ruta/al/export-marcas-del-SIM.xlsx
```

La **service role key** está en Settings → API. Nunca va al frontend ni al repositorio.

La semilla invita al administrador por correo (él define su contraseña), registra el
catálogo de marcas y las clasifica. Los demás usuarios los crea el administrador desde el
módulo de administración. Antes de correrla, revisa en `seed.mjs` la lista `CLASIFICACION`:
las marcas que no estén quedan pendientes y se clasifican desde el módulo.

El argumento opcional es la exportación del SIM con `Parameter = Marca`, sin filtro, 12 meses,
`Venta Neta`. Si no lo pasas, solo registra las marcas de la clasificación.

## 5. Abrir el módulo de administración

La URL del proyecto y la anon key ya van fijas en `febeca-admin.jsx` (constantes `SUPABASE_URL`
y `SUPABASE_ANON`). La app abre directo en el login. Para correrla: `cd 04-frontend && npm
install && npm run dev`, o publicarla en Netlify (ver `LEEME.md`).

Lo que ve cada rol:

| Rol | Pestañas |
|---|---|
| admin, gerencia | Usuarios · Marcas · Asignaciones · Jefaturas · Actividad · Equipo |
| jefe_compras | Marcas (su ámbito) · Asignaciones (su ámbito) · Actividad · Equipo |
| comprador, lectura | Actividad · Equipo (solo lo propio) |

## Verificación rápida

Tras la semilla, en SQL Editor:

```sql
select codigo, origen, estado, responsables from app.v_marcas order by codigo;
select origen, count(*) from app.jefaturas where vigencia @> current_date group by 1;  -- 2 filas
```

> Las vistas de administración (`v_origenes_sin_jefe`, `v_jefaturas`, `v_asignaciones`,
> `v_equipo`...) filtran por el rol del usuario autenticado. En el SQL Editor no hay usuario,
> así que **devuelven vacío aunque tengan datos**. Para verificar desde el editor, consulta
> las tablas directamente; las vistas se comprueban desde el módulo de administración.

## Lo que falta para producción

- **Registro de usuarios.** El módulo usa `signup` desde el navegador del admin. Funciona, pero si
  el proyecto tiene confirmación de correo activada el usuario debe hacer clic en el enlace antes
  de entrar. La alternativa limpia es una Edge Function que llame a `auth.admin.inviteUserByEmail`.
- **Pronósticos.** Database Webhook sobre `app.cargas` (condición `estado = 'ok'`) → Edge Function
  que calcula Holt-Winters y escribe en `app.pronosticos`.
- **Cargas fantasma.** Un `pg_cron` diario que pase a `error` las cargas en `procesando` con más
  de 24 horas.
- **SSO.** Si Febeca usa Microsoft 365, Authentication → Providers → Azure.
