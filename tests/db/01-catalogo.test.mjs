import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { crearBase, fila, filas } from './db.mjs';

let db;
before(async () => { db = await crearBase(); });

test('EAN-13: calcula el dígito verificador (RN-21)', async () => {
  assert.equal((await fila(db, "select public.ean13_valido('2000000000459') as v")).v, true);   // ejemplo del doc 12
  assert.equal((await fila(db, "select public.ean13_valido('2000000000458') as v")).v, false);
  assert.equal((await fila(db, "select public.ean13_digito_verificador('750105530007') as d")).d, 5);
});

test('CP-COD-03: rechaza un código con dígito verificador inválido', async () => {
  await assert.rejects(
    db.query("insert into public.codigo_barras (codigo, id_producto) values ('7421000000014', 1)"),
    /codigo_barras_check/);
});

test('CP-COD-02: rechaza un código ya asignado a otro producto', async () => {
  await assert.rejects(
    db.query("insert into public.codigo_barras (codigo, id_producto) values ('7421000000013', 2)"),
    /duplicate key|llave duplicada/);
});

test('código interno debe usar prefijo 200', async () => {
  await assert.rejects(
    db.query("insert into public.codigo_barras (codigo, id_producto, tipo) values ('7421000000143', 2, 'INTERNO')"),
    /codigo_barras_check/);
});

test('precio: no se permiten vigencias traslapadas para el mismo producto y sucursal', async () => {
  await assert.rejects(
    db.query("insert into public.precio (id_producto, id_sucursal, precio_venta, vigente_desde, id_usuario_cambio) values (1, null, 33, '2026-10-01', 1)"),
    /precio_sin_traslape/);
  // En otra sucursal sí se puede (precio propio)
  await db.query("insert into public.precio (id_producto, id_sucursal, precio_venta, vigente_desde, id_usuario_cambio) values (1, 2, 33, '2026-10-01', 1)");
});

test('precio_vigente: el de la sucursal gana sobre el general', async () => {
  assert.equal((await fila(db, 'select public.precio_vigente(1, 3) as p')).p, '31.00');   // Sur tiene precio propio
  assert.equal((await fila(db, 'select public.precio_vigente(1, 1) as p')).p, '32.00');   // Centro usa el general
  assert.equal((await fila(db, "select public.precio_vigente(1, 1, '2026-08-01') as p")).p, null); // antes de la vigencia
});

test('precio: el valor debe ser mayor que cero', async () => {
  await assert.rejects(
    db.query("insert into public.precio (id_producto, precio_venta, vigente_desde, id_usuario_cambio) values (2, 0, '2030-01-01', 1)"),
    /precio_precio_venta_check/);
});

test('producto_por_codigo responde con el contrato de doc 06 §5.3.1', async () => {
  const p = (await fila(db, "select public.producto_por_codigo('7421000000082', 1) as j")).j;
  assert.equal(p.sku, 'BEB-0102');
  assert.equal(p.descripcion, 'Refresco cola 2 L');
  assert.equal(p.precio, 38);
  assert.equal(p.clasificacionFiscal, 'GRAVADO15');
  assert.deepEqual(p.impuestos, [{ nombre: 'ISV', tasa: 0.15 }]);
  assert.equal(p.existenciaSucursal, 72);
  assert.equal(p.factor, 1);
  // La promoción 2×1 solo cuenta si está vigente hoy.
  const vigente = (await fila(db, "select now() between '2026-10-01' and '2026-10-31' as v")).v;
  assert.equal(p.promocionesVigentes.length, vigente ? 1 : 0);
});

test('producto_por_codigo: código de caja devuelve factor 12; código inexistente devuelve nulo', async () => {
  assert.equal((await fila(db, "select public.producto_por_codigo('7421000000112', 1) as j")).j.factor, 12);
  assert.equal((await fila(db, "select public.producto_por_codigo('0000000000000', 1) as j")).j, null);
});

test('producto exento no lleva impuestos', async () => {
  const p = (await fila(db, "select public.producto_por_codigo('7421000000013', 1) as j")).j;
  assert.deepEqual(p.impuestos, []);
});

test('buscar_productos: búsqueda parcial por nombre con paginación', async () => {
  const r = (await fila(db, "select public.buscar_productos('pan', null, 1, 1, 50) as j")).j;
  assert.equal(r.total, 2);
  assert.deepEqual(r.datos.map((d) => d.sku).sort(), ['PAN-0001', 'PAN-0010']);
  const pag = (await fila(db, 'select public.buscar_productos(null, null, null, 2, 5) as j')).j;
  assert.equal(pag.total, 16);
  assert.equal(pag.datos.length, 5);
  assert.equal(pag.pagina, 2);
});

test('margen: precio sugerido según margen objetivo de la categoría (RF-CAT-04)', async () => {
  const m = await fila(db, 'select * from public.v_margen_productos where id_producto = 1 and id_sucursal = 1');
  // Leche exenta: costo 24, precio 32 → margen 25 %
  assert.equal(m.margen, '0.2500');
  // Margen objetivo de lácteos 18 % → 24 / 0.82 = 29.27
  assert.equal(m.precio_sugerido, '29.27');
});

test('producto: stock máximo no puede ser menor al mínimo', async () => {
  await assert.rejects(
    db.query("update public.producto set stock_maximo = 1 where id_producto = 1"),
    /producto_check/);
});
