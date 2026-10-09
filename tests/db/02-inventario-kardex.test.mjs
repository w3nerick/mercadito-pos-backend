import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { crearBase, enlazarCuenta, como, fila, filas } from './db.mjs';
import { venderDemo } from './escenarios.mjs';

let db, gerenteCentro, cajeroCentro, cajeroNorte;

const mov = (p, alm, tipo, cant, costo = null, fecha = null, lote = null) => db.query(
  `insert into public.movimiento_inventario (id_producto, id_almacen, id_lote, tipo, cantidad, costo_unitario, documento_origen, id_usuario, fecha)
   values ($1, $2, $3, $4, $5, $6, 'prueba', 1, coalesce($7::timestamptz, now()))`, [p, alm, lote, tipo, cant, costo, fecha]);

const nuevoProducto = async (sku, minimo = 0) => (await fila(db,
  `insert into public.producto (sku, descripcion, id_categoria, id_unidad, stock_minimo)
   values ($1, $1, 1, 1, $2) returning id_producto`, [sku, minimo])).id_producto;

const alarmas = (p, s = 1) => filas(db,
  "select tipo, estado, valor_actual from public.alarma where id_producto = $1 and id_sucursal = $2 order by id_alarma", [p, s]);

before(async () => {
  db = await crearBase();
  gerenteCentro = await enlazarCuenta(db, 'gerente.centro');
  cajeroCentro = await enlazarCuenta(db, 'cajero.centro');
  cajeroNorte = await enlazarCuenta(db, 'cajero.norte');
});

test('el trigger calcula saldo y actualiza la existencia', async () => {
  const p = await nuevoProducto('T-SALDO');
  await mov(p, 1, 'COMPRA', 10, 5);
  await mov(p, 1, 'VENTA', -3);
  const m = await fila(db, 'select existencia_resultante, costo_unitario from public.movimiento_inventario where id_producto = $1 order by id_movimiento desc limit 1', [p]);
  assert.equal(m.existencia_resultante, '7.000');
  assert.equal(m.costo_unitario, '5.0000');            // la salida sale al costo promedio
  assert.equal((await fila(db, 'select cantidad from public.existencia where id_producto = $1', [p])).cantidad, '7.000');
  assert.equal((await fila(db, 'select id_sucursal from public.movimiento_inventario where id_producto = $1 limit 1', [p])).id_sucursal, 1);
});

test('CP-KDX-02: recepción de 48 u a L 41.00 con 24 u a L 40.00 → costo promedio L 40.67 (RN-14)', async () => {
  const p = await nuevoProducto('T-PROM');
  await mov(p, 1, 'INICIAL', 24, 40);
  await mov(p, 1, 'COMPRA', 48, 41);
  const costo = (await fila(db, 'select costo_promedio from public.producto where id_producto = $1', [p])).costo_promedio;
  assert.equal(costo, '40.6667');
  assert.equal(Number(costo).toFixed(2), '40.67');
});

test('el costo promedio usa la existencia de todos los almacenes', async () => {
  const p = await nuevoProducto('T-PROM2');
  await mov(p, 1, 'INICIAL', 10, 10);      // Centro
  await mov(p, 4, 'INICIAL', 10, 10);      // Norte
  await mov(p, 1, 'COMPRA', 20, 13);       // (20×10 + 20×13) / 40 = 11.5
  assert.equal((await fila(db, 'select costo_promedio from public.producto where id_producto = $1', [p])).costo_promedio, '11.5000');
});

test('el signo de la cantidad debe corresponder al tipo de movimiento', async () => {
  await assert.rejects(mov(1, 1, 'VENTA', 5), /movimiento_inventario_check/);
  await assert.rejects(mov(1, 1, 'COMPRA', -5, 10), /movimiento_inventario_check/);
});

test('RF-EXI-05: una merma no puede sacar más de lo que hay', async () => {
  await assert.rejects(mov(1, 1, 'MERMA', -1000), /Existencia insuficiente/);
  await assert.rejects(mov(1, 1, 'AJUSTE', -1000), /Existencia insuficiente/);
});

test('RF-KDX-01: el kardex es de solo inserción', async () => {
  await assert.rejects(db.query('update public.movimiento_inventario set cantidad = 1 where id_movimiento = 1'), /solo inserción/);
  await assert.rejects(db.query('delete from public.movimiento_inventario where id_movimiento = 1'), /solo inserción/);
});

test('CP-KDX-01: saldo inicial 42 + entradas 96 − salidas 130 = saldo final 8', async () => {
  const p = await nuevoProducto('T-KDX');
  await mov(p, 1, 'INICIAL', 42, 24, '2026-08-31 10:00-06');
  await mov(p, 1, 'COMPRA', 96, 24, '2026-09-05 10:00-06');
  for (const [d, c] of [['2026-09-02', 40], ['2026-09-10', 50], ['2026-09-20', 40]]) {
    await mov(p, 1, 'VENTA', -c, null, `${d} 12:00-06`);
  }
  await mov(p, 1, 'VENTA', -1, null, '2026-10-02 12:00-06');   // fuera del periodo
  const r = await como(db, gerenteCentro, async (tx) =>
    (await tx.query("select public.kardex_resumen($1, 1, '2026-09-01 00:00-06', '2026-09-30 23:59:59-06') as j", [p])).rows[0].j);
  assert.deepEqual(
    { i: r.saldoInicial, e: r.entradas, s: r.salidas, f: r.saldoFinal },
    { i: 42, e: 96, s: 130, f: 8 });
  assert.equal(r.valorFinal, 192);  // 8 × 24

  const k = await como(db, gerenteCentro, async (tx) =>
    (await tx.query("select * from public.kardex($1, 1, '2026-09-01 00:00-06', '2026-09-30 23:59:59-06')", [p])).rows);
  assert.equal(k.length, 4);
  assert.deepEqual(k.map((x) => x.saldo), ['2.000', '98.000', '48.000', '8.000']);
  assert.equal(k[0].usuario, 'Proceso del sistema');
});

test('kardex: ventas acumuladas por día', async () => {
  const p = await nuevoProducto('T-KDX-DIA');
  await mov(p, 1, 'INICIAL', 100, 10, '2026-09-01 08:00-06');
  await mov(p, 1, 'VENTA', -2, null, '2026-09-02 09:00-06');
  await mov(p, 1, 'VENTA', -3, null, '2026-09-02 15:00-06');
  await mov(p, 1, 'VENTA', -4, null, '2026-09-03 10:00-06');
  const k = await como(db, gerenteCentro, async (tx) =>
    (await tx.query("select tipo, salida, saldo from public.kardex($1, 1, p_ventas_por_dia => true)", [p])).rows);
  assert.deepEqual(k.map((x) => [x.tipo, x.salida, x.saldo]), [
    ['INICIAL', null, '100.000'], ['VENTA', '5.000', '95.000'], ['VENTA', '4.000', '91.000']]);
});

test('kardex: sin INVENTARIO_VER en la sucursal se rechaza', async () => {
  await assert.rejects(
    como(db, cajeroCentro, (tx) => tx.query('select * from public.kardex(1, 1)')),
    /Sin permiso INVENTARIO_VER/);
});

test('RF-KDX-06: existencia a una fecha pasada', async () => {
  const p = (await fila(db, "select id_producto from public.producto where sku = 'T-KDX'")).id_producto;
  assert.equal((await fila(db, "select public.existencia_a_fecha($1, 1, '2026-09-06') as e", [p])).e, '98.000');
});

test('CP-EXI-02: vender banano sin existencia (categoría permite negativo) crea alarma NEGATIVA', async () => {
  await mov(10, 1, 'VENTA', -70);          // había 60
  assert.deepEqual(await alarmas(10), [{ tipo: 'NEGATIVA', estado: 'NUEVA', valor_actual: '-10.000' }]);
});

test('RN-ALM-01: no se duplica la alarma abierta; se actualiza su valor', async () => {
  await mov(10, 1, 'VENTA', -5);
  assert.deepEqual(await alarmas(10), [{ tipo: 'NEGATIVA', estado: 'NUEVA', valor_actual: '-15.000' }]);
});

test('RF-ALM-06: la alarma se resuelve sola cuando llega mercancía', async () => {
  await mov(10, 1, 'COMPRA', 100, 10);
  const a = await alarmas(10);
  assert.equal(a[0].estado, 'RESUELTA');
  const h = await filas(db, "select accion from public.alarma_historial h join public.alarma a using (id_alarma) where a.id_producto = 10 order by id_historial");
  assert.deepEqual(h.map((x) => x.accion), ['CREADA', 'RESUELTA_AUTO']);
});

test('CP-ALM-01: venta deja existencia en 8 con mínimo 24 → alarma "Bajo el mínimo"', async () => {
  await mov(1, 1, 'VENTA', -64);           // leche Centro: 72 → 8
  const a = await alarmas(1);
  assert.ok(a.some((x) => x.tipo === 'BAJO_MINIMO' && x.estado === 'NUEVA' && x.valor_actual === '8.000'));
  const v = await fila(db, "select r.nivel, ro.nombre from public.alarma a join public.regla_alarma r using (id_regla) join public.rol ro on ro.id_rol = r.id_rol_responsable where a.id_producto = 1 and a.tipo = 'BAJO_MINIMO'");
  assert.deepEqual(v, { nivel: 'ADVERTENCIA', nombre: 'Compras' });
});

test('existencia en cero genera alarma crítica SIN_EXISTENCIA', async () => {
  await mov(1, 1, 'VENTA', -8);
  const a = await alarmas(1);
  assert.ok(a.some((x) => x.tipo === 'SIN_EXISTENCIA' && x.estado === 'NUEVA'));
  assert.ok(a.some((x) => x.tipo === 'BAJO_MINIMO' && x.estado === 'RESUELTA'));
});

test('caducidad: proceso nocturno alarma lote por caducar y luego lo bloquea como caducado', async () => {
  await db.query("select public.evaluar_alarmas_caducidad('2026-10-08')");
  let a = await filas(db, "select tipo, estado, id_lote from public.alarma where id_producto = 2 order by id_alarma");
  assert.deepEqual(a, [{ tipo: 'POR_CADUCAR', estado: 'NUEVA', id_lote: 1 }]);

  await db.query("select public.evaluar_alarmas_caducidad('2026-10-13')");
  a = await filas(db, "select tipo, estado, id_lote from public.alarma where id_producto = 2 order by id_alarma");
  assert.deepEqual(a, [
    { tipo: 'POR_CADUCAR', estado: 'RESUELTA', id_lote: 1 },
    { tipo: 'CADUCADO', estado: 'NUEVA', id_lote: 1 }]);
  assert.equal((await fila(db, 'select bloqueado from public.lote where id_lote = 1')).bloqueado, true);
});

test('RN-EXI-01: disponible = existencia − ventas abiertas, sin lotes caducados; muestra otras sucursales', async () => {
  // Yogur: lote 1 (10 u) quedó bloqueado; solo cuenta el lote 2 (30 u).
  const y = await como(db, cajeroCentro, async (tx) => (await tx.query('select public.existencia_disponible(2, 1) as j')).rows[0].j);
  assert.equal(y.disponible, 30);

  // Pan integral: 8 en Centro, 3 apartados en una venta abierta.
  await venderDemo(db, { idCaja: 1, lineas: [{ idProducto: 9, cantidad: 3, precio: 45 }], estado: 'ABIERTA' });
  const j = await como(db, cajeroCentro, async (tx) => (await tx.query('select public.existencia_disponible(9, 1) as j')).rows[0].j);
  assert.equal(j.disponible, 5);
  assert.equal(j.minimo, 12);
  assert.equal(j.permiteNegativo, false);
  assert.deepEqual(j.otrasSucursales.map((s) => [s.sucursal, s.disponible]), [['Norte', 36], ['Sur', 36]]);
});

test('existencia_disponible: un cajero de otra sucursal no puede consultarla', async () => {
  await assert.rejects(
    como(db, cajeroNorte, (tx) => tx.query('select public.existencia_disponible(9, 1)')),
    /Sin permiso/);
});

test('atender_alarma: cambia estado con historial; resolver a mano exige comentario', async () => {
  const id = (await fila(db, "select id_alarma from public.alarma where tipo = 'SIN_EXISTENCIA' and id_producto = 1")).id_alarma;
  const r = await como(db, gerenteCentro, async (tx) => {
    await tx.query("select public.atender_alarma($1, 'EN_ATENCION', 'Se pidió OC')", [id]);
    return (await tx.query(
      "select a.estado, (select count(*) from public.alarma_historial h where h.id_alarma = a.id_alarma and h.accion = 'EN_ATENCION') as hist from public.alarma a where id_alarma = $1", [id])).rows[0];
  });
  assert.deepEqual(r, { estado: 'EN_ATENCION', hist: 1 });
  await assert.rejects(como(db, gerenteCentro, (tx) => tx.query("select public.atender_alarma($1, 'RESUELTA')", [id])), /comentario/);
  await assert.rejects(como(db, cajeroCentro, (tx) => tx.query("select public.atender_alarma($1, 'VISTA')", [id])), /ALARMAS_GESTIONAR/);
});
