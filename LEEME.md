# Dashboard de Compras · Febeca

Empieza por `01-documentacion/GUIA-SUPABASE.md`: son cinco pasos para tener la base corriendo.
El contexto completo del proyecto está en `contexto-dashboard-febeca.md`.

```
01-documentacion/     Contexto del proyecto, guía de Supabase y especificación en Word
02-base-de-datos/     febeca-supabase-consolidado.sql → pegar completo en el SQL Editor
   migraciones/       Las seis migraciones originales, por referencia (la 002 tiene el
                      problema del enum, ya corregido en el consolidado)
   pruebas/           Test de RLS (24 puntos) con 7 usuarios y stub para correrlo en Postgres local
03-semilla/           seed.mjs: usuarios, roles, jefes, catálogo y asignaciones iniciales
04-frontend/          Proyecto Vite: npm install && npm run dev (ver abajo)
                      febeca-admin.jsx                 → administración (conectado a Supabase)
                      febeca-dashboard-inteligente.jsx → 7 pestañas con datos reales de PCP
                      dashboard-compras-febeca.jsx     → parser funcional de los xlsx del SIM
                      febeca-pcp-ejecutivo.jsx         → tablero ejecutivo, versión anterior
05-datos-referencia/  243 marcas del maestro de materiales (snapshot 2023, solo referencia)
```

## Correr la app

```bash
cd 04-frontend
npm install
npm run dev        # abre http://localhost:5173
npm run build      # genera dist/ para publicar
```

Publicación: conectar este repositorio en [Netlify](https://app.netlify.com) → "Import from Git".
`netlify.toml` ya trae la configuración. Después, en Supabase → Authentication → URL
Configuration, poner la dirección de Netlify como Site URL.

## Probar la base en local sin Supabase

```bash
createdb febeca_test
psql -d febeca_test -f 02-base-de-datos/pruebas/febeca-stub-local.sql
psql -d febeca_test -f 02-base-de-datos/febeca-supabase-consolidado.sql
psql -d febeca_test -f 02-base-de-datos/pruebas/febeca-test-rls.sql
```

Los 24 puntos deben salir como se describe en cada `\echo`.

## Orden de trabajo pendiente

1. Crear el proyecto en Supabase y aplicar el consolidado
2. Correr la semilla con los usuarios reales
3. Conectar `febeca-admin.jsx` y verificar roles
4. Unir el parser (`dashboard-compras-febeca.jsx`) con la ingesta
   (`iniciar_carga` → `ingerir_hechos` → `finalizar_carga`)
5. Edge Function de pronósticos disparada por webhook sobre `app.cargas`
