// Crea una base PGlite con el esquema de Supabase emulado, todas las
// migraciones en orden y (opcionalmente) los datos semilla.
import { PGlite } from '@electric-sql/pglite';
import { btree_gist } from '@electric-sql/pglite/contrib/btree_gist';
import { pg_trgm } from '@electric-sql/pglite/contrib/pg_trgm';
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const carpetaMigraciones = join(raiz, 'supabase', 'migrations');

export function migraciones() {
  return readdirSync(carpetaMigraciones).filter((f) => f.endsWith('.sql')).sort();
}

export async function crearBase({ semilla = true } = {}) {
  const db = new PGlite({ extensions: { btree_gist, pg_trgm } });
  // Las pruebas deben correr en la misma versión mayor que Supabase (17).
  const version = (await db.query('show server_version_num')).rows[0].server_version_num;
  if (!String(version).startsWith('17')) {
    throw new Error(`Las pruebas esperan PostgreSQL 17 (como Supabase) y PGlite trae ${version}. Ver docs/guia-supabase.md §7.`);
  }
  await db.exec(readFileSync(join(raiz, 'tests', 'db', 'supabase-stub.sql'), 'utf8'));
  for (const archivo of migraciones()) {
    try {
      await db.exec(readFileSync(join(carpetaMigraciones, archivo), 'utf8'));
    } catch (e) {
      throw new Error(`Falló la migración ${archivo}: ${e.message}`);
    }
  }
  if (semilla) {
    await db.exec(readFileSync(join(raiz, 'supabase', 'seed.sql'), 'utf8'));
  }
  return db;
}

// Crea una cuenta en auth.users, la enlaza al empleado y devuelve su uuid.
export async function enlazarCuenta(db, usuario) {
  const uid = randomUUID();
  await db.query('insert into auth.users (id, email) values ($1, $2)', [uid, `${usuario}@demo.test`]);
  const r = await db.query('update public.usuario set auth_user_id = $1 where usuario = $2 returning id_usuario', [uid, usuario]);
  if (r.rows.length !== 1) throw new Error(`No existe el usuario ${usuario}`);
  return uid;
}

// Ejecuta fn como si fuera una petición de la API con el JWT de ese usuario:
// rol "authenticated" (sujeto a RLS) y auth.uid() = uid. Todo se revierte.
export async function como(db, uid, fn) {
  let resultado;
  let error;
  await db.transaction(async (tx) => {
    await tx.query("select set_config('request.jwt.claim.sub', $1, true)", [uid ?? '']);
    await tx.exec(uid ? 'set local role authenticated' : 'set local role anon');
    try {
      resultado = await fn(tx);
    } catch (e) {
      error = e;
    }
    await tx.rollback();
  });
  if (error) throw error;
  return resultado;
}

// Igual que "como" pero confirma la transacción (para preparar escenarios).
export async function comoConfirmado(db, uid, fn) {
  return db.transaction(async (tx) => {
    await tx.query("select set_config('request.jwt.claim.sub', $1, true)", [uid ?? '']);
    await tx.exec('set local role authenticated');
    return fn(tx);
  });
}

export const filas = async (db, sql, params) => (await db.query(sql, params)).rows;
export const fila = async (db, sql, params) => (await db.query(sql, params)).rows[0];
