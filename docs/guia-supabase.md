# Guía: aplicar el modelo en Supabase

Pasos para dejar el esquema en los proyectos `mercadito-dev`, `mercadito-qa` y `mercadito-staging` (doc 11 §3.1).
**Regla del equipo:** nadie crea ni cambia tablas a mano en el panel; todo cambio es una migración en un PR.

## 1. Requisitos

- [Supabase CLI](https://supabase.com/docs/guides/cli) (`brew install supabase/tap/supabase` en macOS).
- Acceso al proyecto en Supabase y su **contraseña de base de datos**.
- Node 20+ solo para correr las pruebas locales.

## 2. Habilitar extensiones (una vez por proyecto)

En el panel: **Database → Extensions** y activar `pg_cron`. (`btree_gist` y `pg_trgm` las crea la primera migración.)

## 3. Enlazar y subir las migraciones

```bash
supabase login
supabase link --project-ref <ref-del-proyecto>      # el ref está en Project Settings → General
supabase db push                                    # aplica supabase/migrations en orden
```

`db push` lleva el registro de qué migraciones ya se aplicaron: correrlo dos veces no repite nada.

## 4. Datos semilla (solo dev / qa / staging)

```bash
supabase db push --include-seed
```

o pegar el contenido de `supabase/seed.sql` en **SQL Editor**. Todos los datos son ficticios.

> - La semilla es para un proyecto **recién migrado**: usa ids fijos, así que correrla dos veces falla por llaves duplicadas.
> - Fallo conocido de la CLI: `--include-seed` no aplica la semilla si no hay migraciones pendientes
>   ([supabase/cli#4907](https://github.com/supabase/cli/issues/4907)). En ese caso, usar el SQL Editor.
> - Nunca usar `--include-seed` en producción.

## 5. Crear usuarios de prueba y enlazarlos

1. **Authentication → Users → Add user** (correo + contraseña), por ejemplo `cajero.centro@…`.
2. Copiar su `UID` y enlazarlo con el empleado de la semilla:

```sql
update public.usuario set auth_user_id = '<UID>' where usuario = 'cajero.centro';
```

## 6. Verificar el RLS desde el SQL Editor

El editor corre como dueño (se salta el RLS). Para ver lo que vería un usuario:

```sql
begin;
select set_config('request.jwt.claim.sub', '<UID del cajero>', true);
set local role authenticated;
select count(*) from public.producto;                         -- 16
select distinct id_sucursal from public.v_existencias;        -- solo la suya
insert into public.producto (sku, descripcion, id_categoria, id_unidad)
values ('X', 'X', 1, 1);                                       -- error: row-level security
rollback;
```

## 7. Pruebas locales sin Docker

```bash
npm ci
npm test
```

Las pruebas levantan Postgres en memoria con [PGlite](https://pglite.dev) (Postgres compilado a WASM), emulan lo
que Supabase trae de fábrica (`tests/db/supabase-stub.sql`: roles `anon`/`authenticated`, `auth.uid()`,
privilegios por defecto) y corren **todas** las migraciones y la semilla antes de cada archivo de pruebas.
GitHub Actions hace lo mismo en cada PR.

> **Versión de Postgres.** `@electric-sql/pglite` está fijado en `0.3.16` = **PostgreSQL 17.5**, la misma versión mayor
> que Supabase (`major_version = 17` en `supabase/config.toml`). Las versiones 0.5.x de PGlite traen Postgres 18:
> no actualizar sin revisar, o las pruebas podrían aceptar SQL que Supabase rechaza.

> Si alguien tiene Docker, `supabase start && supabase db reset` también funciona y además trae el panel local.

## 8. Agregar una migración nueva

```bash
supabase migration new nombre_corto      # crea supabase/migrations/<fecha>_nombre_corto.sql
```

1. Escribir el SQL (con `enable row level security` y sus políticas si es una tabla nueva: la prueba
   "todas las tablas tienen RLS" falla si se olvida).
2. Agregar pruebas en `tests/db/`.
3. `npm test` en verde → PR con la etiqueta `db` → revisión de la arquitectura de datos → `supabase db push` en `mercadito-qa`.
