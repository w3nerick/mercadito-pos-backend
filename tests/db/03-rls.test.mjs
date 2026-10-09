// Pruebas de seguridad por filas (doc 10 §9.1). Cada prueba se ejecuta con
// el rol "authenticated" y el JWT del usuario, igual que una petición real.
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { crearBase, enlazarCuenta, como, fila, filas } from './db.mjs';
import { venderDemo } from './escenarios.mjs';

let db;
const u = {};
const RLS = /row-level security|seguridad de registros|violates/;

before(async () => {
  db = await crearBase();
  for (const n of ['admin.ti', 'gerente.general', 'gerente.centro', 'supervisor.centro', 'cajero.centro',
                   'cajero.norte', 'almacen.centro', 'compras', 'contador', 'auditor']) {
    u[n] = await enlazarCuenta(db, n);
  }
  await venderDemo(db, { idCaja: 1, idUsuario: 6, lineas: [{ idProducto: 1, cantidad: 1, precio: 32 }] });   // cajero.centro
  await venderDemo(db, { idCaja: 2, idUsuario: 5, lineas: [{ idProducto: 4, cantidad: 2, precio: 38 }] });   // supervisor.centro
  await venderDemo(db, { idCaja: 4, idUsuario: 7, lineas: [{ idProducto: 5, cantidad: 1, precio: 42 }] });   // cajero.norte
});

const cuenta = (n, sql, params) => como(db, u[n], async (tx) => (await tx.query(sql, params)).rows.length);

test('todas las tablas de public tienen RLS activo', async () => {
  const sin = await filas(db, `select relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
                               where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity`);
  assert.deepEqual(sin, []);
});

test('todas las vistas son security_invoker (no se saltan el RLS)', async () => {
  const malas = await filas(db, `select relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
                                 where n.nspname = 'public' and c.relkind = 'v'
                                   and not coalesce('security_invoker=true' = any(c.reloptions), false)`);
  assert.deepEqual(malas, []);
});

test('toda función SECURITY DEFINER fija search_path', async () => {
  const malas = await filas(db, `select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                                 where n.nspname = 'public' and p.prosecdef
                                   and not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')`);
  assert.deepEqual(malas, []);
});

test('anon (sin sesión) no puede leer nada', async () => {
  await assert.rejects(como(db, null, (tx) => tx.query('select * from public.producto')), /permission denied|permiso denegado/);
});

test('una cuenta de Auth sin empleado enlazado no ve datos', async () => {
  const uid = randomUUID();
  await db.query('insert into auth.users (id) values ($1)', [uid]);
  assert.equal(await como(db, uid, async (tx) => (await tx.query('select * from public.producto')).rows.length), 0);
  assert.equal(await como(db, uid, async (tx) => (await tx.query('select * from public.sucursal')).rows.length), 0);
});

test('catálogo: todo empleado con CATALOGO_VER lo ve; el Admin TI no (RN-ROL-06)', async () => {
  assert.equal(await cuenta('cajero.centro', 'select * from public.producto'), 16);
  assert.equal(await cuenta('admin.ti', 'select * from public.producto'), 0);
});

test('CP-RLS: el cajero del Norte solo ve existencias del Norte', async () => {
  const s = await como(db, u['cajero.norte'], async (tx) =>
    (await tx.query('select distinct id_sucursal from public.v_existencias')).rows.map((r) => r.id_sucursal));
  assert.deepEqual(s, [2]);
  assert.equal(await cuenta('cajero.norte', 'select * from public.movimiento_inventario'), 0);   // sin INVENTARIO_VER
});

test('el gerente de Centro ve el kardex de Centro pero no el del Norte', async () => {
  const s = await como(db, u['gerente.centro'], async (tx) =>
    (await tx.query('select distinct id_sucursal from public.movimiento_inventario')).rows.map((r) => r.id_sucursal));
  assert.deepEqual(s, [1]);
});

test('el gerente general (alcance TODAS) ve todas las sucursales', async () => {
  const s = await como(db, u['gerente.general'], async (tx) =>
    (await tx.query('select distinct id_sucursal from public.v_existencias order by 1')).rows.map((r) => r.id_sucursal));
  assert.deepEqual(s, [1, 2, 3]);
});

test('ventas: el cajero ve solo las suyas; el supervisor todas las de su sucursal; nadie las de otra', async () => {
  assert.equal(await cuenta('cajero.centro', 'select * from public.venta'), 1);
  assert.equal(await cuenta('cajero.centro', 'select * from public.venta_linea'), 1);   // hereda del padre
  assert.equal(await cuenta('supervisor.centro', 'select * from public.venta'), 2);
  assert.equal(await cuenta('cajero.norte', 'select * from public.venta where id_sucursal = 1'), 0);
});

test('ventas: nadie las inserta directo (solo por la función de negocio)', async () => {
  await assert.rejects(como(db, u['cajero.centro'], (tx) => tx.query(
    `insert into public.venta (folio, id_turno, id_caja, id_sucursal, id_usuario, subtotal, total)
     values ('X-1', 1, 1, 1, 6, 10, 10)`)), RLS);
});

test('existencias: nadie las modifica directo, solo el trigger del kardex', async () => {
  assert.equal(await como(db, u['gerente.centro'], async (tx) =>
    (await tx.query('update public.existencia set cantidad = 999 where id_almacen = 1')).affectedRows), 0);
  await assert.rejects(como(db, u['gerente.centro'], (tx) => tx.query(
    "insert into public.movimiento_inventario (id_producto, id_almacen, tipo, cantidad, documento_origen) values (1, 1, 'AJUSTE', 5, 'x')")), RLS);
});

test('producto: el cajero no puede crearlo; Compras sí', async () => {
  const sql = "insert into public.producto (sku, descripcion, id_categoria, id_unidad) values ('NUEVO-1', 'Nuevo', 2, 1)";
  await assert.rejects(como(db, u['cajero.centro'], (tx) => tx.query(sql)), RLS);
  assert.equal(await como(db, u['compras'], async (tx) => (await tx.query(sql)).affectedRows), 1);
});

test('precio: el gerente de Centro programa precio en Centro, no en Norte ni el general', async () => {
  await como(db, u['gerente.centro'], async (tx) => {
    await tx.query('select public.programar_precio(1, 1, 35)');
    assert.equal((await tx.query('select public.precio_vigente(1, 1) as p')).rows[0].p, '35.00');
  });
  await assert.rejects(como(db, u['gerente.centro'], (tx) => tx.query('select public.programar_precio(1, 2, 35)')), RLS);
  await assert.rejects(como(db, u['gerente.centro'], (tx) => tx.query('select public.programar_precio(1, null, 35)')), RLS);
});

test('precio general: el gerente general lo cambia y el anterior queda en el historial', async () => {
  await como(db, u['gerente.general'], async (tx) => {
    await tx.query('select public.programar_precio(4, null, 40)');
    assert.equal((await tx.query('select public.precio_vigente(4, 1) as p')).rows[0].p, '40.00');
    const h = (await tx.query('select precio_venta, vigente_hasta is null as abierto from public.precio where id_producto = 4 and id_sucursal is null order by vigente_desde')).rows;
    assert.deepEqual(h, [{ precio_venta: '38.00', abierto: false }, { precio_venta: '40.00', abierto: true }]);
  });
});

test('RN-ROL-02: nadie se asigna roles ni edita la matriz de un rol propio', async () => {
  await assert.rejects(como(db, u['admin.ti'], (tx) => tx.query('insert into public.usuario_rol (id_usuario, id_rol) values (2, 2)')), RLS);
  await assert.rejects(como(db, u['admin.ti'], (tx) => tx.query(
    "insert into public.rol_permiso (id_rol, id_permiso) select 1, id_permiso from public.permiso where clave = 'VENTA_CREAR'")), RLS);
  // A otro usuario y a otro rol, sí.
  assert.equal(await como(db, u['admin.ti'], async (tx) =>
    (await tx.query('insert into public.usuario_rol (id_usuario, id_rol) values (6, 9)')).affectedRows), 1);
  assert.equal(await como(db, u['admin.ti'], async (tx) =>
    (await tx.query("insert into public.rol_permiso (id_rol, id_permiso) select 5, id_permiso from public.permiso where clave = 'DOC_EMITIR_TICKET'")).affectedRows), 1);
});

test('RN-ROL-08: un usuario dado de baja pierde el acceso de inmediato', async () => {
  await db.query("update public.usuario set activo = false where usuario = 'cajero.norte'");
  assert.equal(await cuenta('cajero.norte', 'select * from public.producto'), 0);
  await db.query("update public.usuario set activo = true where usuario = 'cajero.norte'");
});

test('delegación vencida (vigente_hasta en el pasado) ya no da permisos', async () => {
  await db.query("update public.usuario_rol set vigente_desde = '2026-01-01', vigente_hasta = '2026-01-31' where id_usuario = 11");
  assert.equal(await cuenta('auditor', 'select * from public.producto'), 0);
  await db.query('update public.usuario_rol set vigente_hasta = null where id_usuario = 11');
  assert.equal(await cuenta('auditor', 'select * from public.producto'), 16);
});

test('bitácora (RN-18): cada quien registra lo suyo, solo BITACORA_VER la lee, nadie la borra', async () => {
  await como(db, u['cajero.centro'], async (tx) => {
    await tx.query("insert into public.bitacora_auditoria (id_usuario, accion, entidad) values (6, 'LOGIN', 'usuario')");
    assert.equal((await tx.query('select * from public.bitacora_auditoria')).rows.length, 0);   // no la puede leer
  });
  await assert.rejects(como(db, u['cajero.centro'], (tx) => tx.query(
    "insert into public.bitacora_auditoria (id_usuario, accion, entidad) values (5, 'LOGIN', 'usuario')")), RLS);
  await db.query("insert into public.bitacora_auditoria (id_usuario, accion, entidad) values (6, 'LOGIN', 'usuario')");
  assert.equal(await como(db, u['auditor'], async (tx) =>
    (await tx.query('delete from public.bitacora_auditoria')).affectedRows), 0);
  await assert.rejects(db.query('delete from public.bitacora_auditoria'), /solo inserción/);   // ni el dueño
});

test('clientes: el cajero registra pero no edita datos personales ni anonimiza', async () => {
  assert.equal(await como(db, u['cajero.centro'], async (tx) => (await tx.query(
    "insert into public.cliente (nombre, telefono, consentimiento_datos) values ('Nuevo', '99991111', true)")).affectedRows), 1);
  assert.equal(await como(db, u['cajero.centro'], async (tx) =>
    (await tx.query("update public.cliente set nombre = 'X' where id_cliente = 1")).affectedRows), 0);
  await assert.rejects(como(db, u['cajero.centro'], (tx) => tx.query('select public.anonimizar_cliente(1)')), /sin permiso/);
});

test('clientes ARCO: el gerente anonimiza y el cliente desaparece de la búsqueda', async () => {
  await como(db, u['gerente.centro'], async (tx) => {
    await tx.query('select public.anonimizar_cliente(2)');
    const c = (await tx.query('select nombre, telefono, anonimizado from public.cliente where id_cliente = 2')).rows[0];
    assert.deepEqual(c, { nombre: 'Cliente anonimizado #2', telefono: null, anonimizado: true });
    assert.equal((await tx.query('select * from public.v_clientes where id_cliente = 2')).rows.length, 0);
  });
});

test('CAI: lo registra el contador; el cajero no', async () => {
  const sql = `insert into public.cai (cai, id_punto, tipo_documento, fecha_autorizacion, correlativo_inicial, correlativo_final, fecha_limite_emision)
               values ('FFFFFF-000009-D4E5F6-000009-ABCDEF-09', 1, '01', '2026-10-01', 10001, 20000, '2027-06-30')`;
  await assert.rejects(como(db, u['cajero.centro'], (tx) => tx.query(sql)), RLS);
  assert.equal(await como(db, u['contador'], async (tx) => (await tx.query(sql)).affectedRows), 1);
});

test('funciones internas no se pueden llamar desde la API', async () => {
  await assert.rejects(como(db, u['gerente.general'], (tx) => tx.query('select public.evaluar_alarmas_caducidad()')),
    /permission denied|permiso denegado/);
});
