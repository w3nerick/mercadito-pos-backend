import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { crearBase, enlazarCuenta, como, fila, filas } from './db.mjs';
import { venderDemo, facturarDemo } from './escenarios.mjs';

let db, contador, cajero, gerente;
let venta1, venta2, venta3, fac1, fac2;
const mes = async () => (await fila(db, "select to_char(public.hoy_honduras(), 'YYYY-MM') as m")).m;

before(async () => {
  db = await crearBase();
  contador = await enlazarCuenta(db, 'contador');
  cajero = await enlazarCuenta(db, 'cajero.centro');
  gerente = await enlazarCuenta(db, 'gerente.centro');
  // 3 leches (exentas) + 2 refrescos con 2×1 (gravados 15 %): total 96 + 38 = 134
  venta1 = await venderDemo(db, { idCaja: 3, lineas: [
    { idProducto: 1, cantidad: 3, precio: 32 },
    { idProducto: 12, cantidad: 2, precio: 38, descuento: 38 }], idCliente: 3 });
  fac1 = await facturarDemo(db, venta1.idVenta);
  // Cerveza (18 %)
  venta2 = await venderDemo(db, { idCaja: 3, lineas: [{ idProducto: 14, cantidad: 6, precio: 30 }] });
  fac2 = await facturarDemo(db, venta2.idVenta);
  // Venta con ticket
  venta3 = await venderDemo(db, { idCaja: 3, lineas: [{ idProducto: 8, cantidad: 10, precio: 3 }], documento: 'TICKET' });
  await db.query(
    "insert into public.ticket (numero, id_venta, codigo_canje, fecha_limite_canje) values ('T03-000482', $1, 'T03-000482-7F2A', current_date + 30)",
    [venta3.idVenta]);
});

// ------------------------------- CAI --------------------------------

test('CAI: formato inválido se rechaza', async () => {
  await assert.rejects(db.query(
    `insert into public.cai (cai, id_punto, tipo_documento, fecha_autorizacion, correlativo_inicial, correlativo_final, fecha_limite_emision)
     values ('35BD6A-0195F4', 1, '01', '2026-10-01', 50001, 60000, '2027-01-01')`), /cai_cai_check/);
});

test('RN-SAR-04: rangos traslapados en el mismo punto y tipo se rechazan', async () => {
  await assert.rejects(db.query(
    `insert into public.cai (cai, id_punto, tipo_documento, fecha_autorizacion, correlativo_inicial, correlativo_final, fecha_limite_emision)
     values ('AAAAAA-BBBBBB-CCCCCC-DDDDDD-EEEEEE-01', 3, '01', '2026-10-01', 19000, 25000, '2027-01-01')`), /cai_rango_sin_traslape/);
});

test('RN-SAR-03: solo un CAI activo por punto y tipo', async () => {
  await assert.rejects(db.query("update public.cai set estado = 'ACTIVO' where id_cai = 4"), /cai_un_activo_idx/);
});

test('el último correlativo usado no puede salirse del rango', async () => {
  await assert.rejects(db.query('update public.cai set ultimo_usado = 20001 where id_cai = 3'), /cai_check/);
});

test('número fiscal con formato EEE-PPP-TT-NNNNNNNN', async () => {
  assert.equal((await fila(db, 'select public.formato_numero_fiscal(3, 12520) as n')).n, '000-003-01-00012520');
});

// ------------------------- Documento fiscal -------------------------

test('la factura de ejemplo toma el siguiente correlativo y desglosa exento / gravado / ISV', async () => {
  assert.equal(fac1.numero, '000-003-01-00012520');
  const d = await fila(db, 'select importe_exento, importe_gravado_15, isv_15, total from public.documento_fiscal where id_documento = $1', [fac1.id_documento]);
  assert.deepEqual(d, { importe_exento: '96.00', importe_gravado_15: '33.04', isv_15: '4.96', total: '134.00' });
  assert.equal(fac2.numero, '000-003-01-00012521');
});

test('el total de la factura debe cuadrar con su desglose', async () => {
  await assert.rejects(db.query(
    `insert into public.documento_fiscal (id_cai, correlativo, numero, id_venta, importe_exento, total, total_letras)
     values (3, 12600, '000-003-01-00012600', $1, 10, 11, 'x')`, [venta3.idVenta]), /documento_fiscal_check/);
});

test('RN-SAR-01: un correlativo no se repite', async () => {
  await assert.rejects(db.query(
    `insert into public.documento_fiscal (id_cai, correlativo, numero, id_venta, importe_exento, total, total_letras)
     values (3, 12520, '000-003-01-00012599', $1, 30, 30, 'x')`, [venta3.idVenta]), /duplicate key|llave duplicada/);
});

test('la factura no se borra ni se le cambian montos; se anula con motivo', async () => {
  await assert.rejects(db.query('delete from public.documento_fiscal where id_documento = $1', [fac2.id_documento]), /se anulan/);
  await assert.rejects(db.query('update public.documento_fiscal set total = 1 where id_documento = $1', [fac2.id_documento]), /no se modifican/);
  await assert.rejects(db.query("update public.documento_fiscal set estado = 'ANULADO' where id_documento = $1", [fac2.id_documento]), /documento_fiscal_check/);
  await db.query(
    "update public.documento_fiscal set estado = 'ANULADO', motivo_anulacion = 'Error de cobro', id_usuario_anula = 10, fecha_anulacion = now() where id_documento = $1",
    [fac2.id_documento]);
  await assert.rejects(db.query("update public.documento_fiscal set estado = 'VIGENTE' where id_documento = $1", [fac2.id_documento]), /no puede volver/);
});

test('RN-DOC-02: el ticket no puede llevar formato de número fiscal', async () => {
  await assert.rejects(db.query(
    "insert into public.ticket (numero, id_venta, codigo_canje, fecha_limite_canje) values ('000-003-01-0001', $1, 'X', current_date)",
    [venta1.idVenta]), /ticket_numero_check/);
});

// ----------------------------- Reportes -----------------------------

test('libro de ventas: un renglón por factura; la anulada aparece en cero', async () => {
  const m = await mes();
  const l = await como(db, contador, async (tx) => (await tx.query('select numero, estado, total from public.libro_ventas($1)', [m])).rows);
  assert.deepEqual(l, [
    { numero: '000-003-01-00012520', estado: 'VIGENTE', total: '134.00' },
    { numero: '000-003-01-00012521', estado: 'ANULADO', total: '0.00' }]);
});

test('resumen para la declaración de ISV', async () => {
  const m = await mes();
  const r = await como(db, contador, async (tx) => (await tx.query('select public.resumen_isv($1) as j', [m])).rows[0].j);
  assert.deepEqual(
    { d: r.documentos, a: r.anulados, ex: r.importeExento, g: r.gravado15, i: r.isv15, t: r.total },
    { d: 2, a: 1, ex: 96, g: 33.04, i: 4.96, t: 134 });
});

test('libro de ventas: sin SAR_REPORTES se rechaza; mes mal escrito también', async () => {
  const m = await mes();
  await assert.rejects(como(db, cajero, (tx) => tx.query('select * from public.libro_ventas($1)', [m])), /SAR_REPORTES/);
  await assert.rejects(como(db, contador, (tx) => tx.query("select * from public.libro_ventas('2026-13')")), /AAAA-MM/);
});

test('ventas sin factura (RF-DOC-06)', async () => {
  const t = await como(db, contador, async (tx) => (await tx.query('select numero, estado, total from public.v_ventas_sin_factura')).rows);
  assert.deepEqual(t, [{ numero: 'T03-000482', estado: 'EMITIDO', total: '30.00' }]);
});

test('reporte de ventas agrupado por producto, forma de pago, día y cajero', async () => {
  const hoy = (await fila(db, 'select public.hoy_honduras() as d')).d;
  const r = (agrupar) => como(db, gerente, async (tx) =>
    (await tx.query('select clave, etiqueta, ventas, unidades, total from public.reporte_ventas($1, $1, $2)', [hoy, agrupar])).rows);

  const prod = await r('producto');
  assert.deepEqual(prod.find((x) => x.etiqueta === 'Refresco cola 2 L'), { clave: '12', etiqueta: 'Refresco cola 2 L', ventas: 1, unidades: '2.000', total: '38.00' });
  assert.deepEqual((await r('forma_pago')).map((x) => [x.clave, x.total]), [['EFE', '344.00']]);
  assert.deepEqual((await r('dia')).map((x) => [x.ventas, x.total]), [[3, '344.00']]);
  assert.deepEqual((await r('cajero')).map((x) => x.etiqueta), ['Cajero Centro (demo)']);
  await assert.rejects(r('color'), /agrupar debe ser/);
});

test('margen del reporte: precio sin ISV menos costo', async () => {
  const hoy = (await fila(db, 'select public.hoy_honduras() as d')).d;
  const m = await como(db, gerente, async (tx) =>
    (await tx.query("select margen from public.reporte_ventas($1, $1, 'producto') where clave = '1'", [hoy])).rows[0].margen);
  assert.equal(m, '24.00');   // 3 leches exentas: 96 − 3 × 24
});

test('dashboard: KPIs del día y alarmas', async () => {
  const k = await como(db, gerente, async (tx) => (await tx.query('select public.kpis_dashboard(1) as j')).rows[0].j);
  assert.equal(k.ventas, 3);
  assert.equal(k.total, 344);
  assert.equal(k.ventasSinFactura, 1);
  assert.equal(k.alarmas.advertencias, 2);    // pan integral bajo mínimo y reorden (semilla)
  assert.equal(k.topProductos[0].descripcion, 'Cerveza lata 355 ml');
});

// ----------------------------- Clientes -----------------------------

test('RF-CLI-01: sin consentimiento no se registra', async () => {
  await assert.rejects(db.query("insert into public.cliente (nombre, telefono, consentimiento_datos) values ('Sin', '99998888', false)"), /cliente_consentimiento_datos_check/);
});

test('RF-CLI-05: RTN de 14 dígitos y con razón social', async () => {
  await assert.rejects(db.query("insert into public.cliente (nombre, telefono, consentimiento_datos, rtn, razon_social) values ('A', '99997777', true, '0801', 'X')"), /cliente_rtn_check/);
  await assert.rejects(db.query("insert into public.cliente (nombre, telefono, consentimiento_datos, rtn) values ('A', '99997777', true, '08011999000011')"), /cliente_check/);
});

test('el teléfono identifica al cliente: no se repite', async () => {
  await assert.rejects(db.query("insert into public.cliente (nombre, telefono, consentimiento_datos) values ('Otro', '99990001', true)"), /duplicate key|llave duplicada/);
});

test('cada cliente nuevo recibe su tarjeta de lealtad', async () => {
  const c = await fila(db, "insert into public.cliente (nombre, telefono, consentimiento_datos) values ('Nuevo', '99996666', true) returning id_cliente");
  const t = await fila(db, 'select numero_tarjeta, saldo_puntos from public.cuenta_lealtad where id_cliente = $1', [c.id_cliente]);
  assert.equal(t.numero_tarjeta, 'MC' + String(c.id_cliente).padStart(10, '0'));
  assert.equal(t.saldo_puntos, 0);
});

test('puntos: 1 por cada L 10 (468.40 → 46, ejemplo del doc 06)', async () => {
  assert.equal((await fila(db, 'select public.calcular_puntos(468.40) as p')).p, 46);
});

test('puntos: el saldo se mueve solo por movimientos y no queda negativo', async () => {
  const cuenta = (await fila(db, 'select id_cuenta from public.cuenta_lealtad where id_cliente = 3')).id_cuenta;
  await db.query("insert into public.movimiento_puntos (id_cuenta, id_venta, tipo, puntos, caduca_el) values ($1, $2, 'ACUMULA', 13, current_date + 365)", [cuenta, venta1.idVenta]);
  assert.equal((await fila(db, 'select saldo_puntos from public.cuenta_lealtad where id_cuenta = $1', [cuenta])).saldo_puntos, 13);
  await assert.rejects(db.query("insert into public.movimiento_puntos (id_cuenta, tipo, puntos) values ($1, 'CANJE', -20)", [cuenta]), /cuenta_lealtad_saldo_puntos_check/);
  await assert.rejects(db.query('delete from public.movimiento_puntos'), /solo inserción/);
});

test('turno: solo uno abierto por caja', async () => {
  await assert.rejects(db.query('insert into public.turno_caja (id_caja, id_usuario, fondo_inicial) values (3, 6, 500)'), /turno_un_abierto_por_caja_idx/);
});

test('corte con diferencia exige justificación', async () => {
  const t = (await fila(db, "select id_turno from public.turno_caja where id_caja = 3 and estado = 'ABIERTO'")).id_turno;
  await assert.rejects(db.query("insert into public.corte_caja (id_turno, tipo, esperado_efectivo, contado_efectivo) values ($1, 'Z', 8020, 8000)", [t]), /corte_caja_check/);
  const c = await fila(db, "insert into public.corte_caja (id_turno, tipo, esperado_efectivo, contado_efectivo, justificacion) values ($1, 'Z', 8020, 8000, 'Error al dar cambio') returning diferencia", [t]);
  assert.equal(c.diferencia, '-20.00');
});

test('venta: el total debe ser subtotal − descuento y el importe de la línea cuadrar', async () => {
  await assert.rejects(db.query(
    `insert into public.venta (folio, id_turno, id_caja, id_sucursal, id_usuario, subtotal, descuento, total)
     values ('C03-X1', 1, 3, 1, 6, 100, 10, 95)`), /venta_check/);
  await assert.rejects(db.query(
    `insert into public.venta_linea (id_venta, numero_linea, id_producto, cantidad, precio_unitario, clasificacion_fiscal, tasa_impuesto, importe)
     values ($1, 9, 1, 3, 32, 'EXENTO', 0, 95)`, [venta1.idVenta]), /venta_linea_check/);
});
