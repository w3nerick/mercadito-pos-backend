// Arma escenarios de prueba directamente como dueño de la base (como lo
// haría la función registrar_venta del módulo de negocio, que aún no existe).
import { randomUUID } from 'node:crypto';

let folio = 900000;

// Abre (o reutiliza) un turno en la caja y registra una venta PAGADA con sus
// líneas, pago y salidas de inventario del piso de venta de la sucursal.
export async function venderDemo(db, { idCaja = 3, idUsuario = 6, lineas, documento = 'FACTURA_CF', estado = 'PAGADA', fecha = null, idCliente = null }) {
  const caja = (await db.query('select id_sucursal from public.caja where id_caja = $1', [idCaja])).rows[0];
  let turno = (await db.query("select id_turno from public.turno_caja where id_caja = $1 and estado = 'ABIERTO'", [idCaja])).rows[0];
  if (!turno) {
    turno = (await db.query(
      'insert into public.turno_caja (id_caja, id_usuario, fondo_inicial) values ($1, $2, 1000) returning id_turno',
      [idCaja, idUsuario])).rows[0];
  }
  const idVenta = randomUUID();
  let subtotal = 0, descuento = 0, impuestos = 0;
  const detalle = [];
  for (const [i, l] of lineas.entries()) {
    const p = (await db.query(
      `select p.clasificacion_fiscal, cf.tasa, p.costo_promedio
         from public.producto p join public.clasificacion_fiscal cf on cf.codigo = p.clasificacion_fiscal
        where p.id_producto = $1`, [l.idProducto])).rows[0];
    const bruto = Math.round(l.cantidad * l.precio * 100) / 100;
    const desc = l.descuento ?? 0;
    const importe = Math.round((bruto - desc) * 100) / 100;
    const tasa = Number(p.tasa);
    subtotal += bruto; descuento += desc;
    impuestos += tasa > 0 ? importe - Math.round((importe / (1 + tasa)) * 100) / 100 : 0;
    detalle.push({ ...l, n: i + 1, importe, desc, clas: p.clasificacion_fiscal, tasa, costo: p.costo_promedio });
  }
  const r2 = (x) => Math.round(x * 100) / 100;
  const total = r2(subtotal - descuento);
  await db.query(
    `insert into public.venta (id_venta, folio, id_turno, id_caja, id_sucursal, id_usuario, id_cliente, fecha,
                               subtotal, descuento, impuestos, total, estado, tipo_documento)
     values ($1, $2, $3, $4, $5, $6, $7, coalesce($8::timestamptz, now()), $9, $10, $11, $12, $13, $14)`,
    [idVenta, `C${String(idCaja).padStart(2, '0')}-${folio++}`, turno.id_turno, idCaja, caja.id_sucursal, idUsuario, idCliente, fecha,
     r2(subtotal), r2(descuento), r2(impuestos), total, estado, estado === 'PAGADA' ? documento : null]);
  for (const d of detalle) {
    await db.query(
      `insert into public.venta_linea (id_venta, numero_linea, id_producto, cantidad, precio_unitario, descuento,
                                       clasificacion_fiscal, tasa_impuesto, importe, costo_unitario)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
      [idVenta, d.n, d.idProducto, d.cantidad, d.precio, d.desc, d.clas, d.tasa, d.importe, d.costo]);
    if (estado === 'PAGADA') {
      const piso = (await db.query("select id_almacen from public.almacen where id_sucursal = $1 and tipo = 'PISO'", [caja.id_sucursal])).rows[0];
      await db.query(
        `insert into public.movimiento_inventario (id_producto, id_almacen, tipo, cantidad, documento_origen, id_usuario, fecha)
         values ($1, $2, 'VENTA', $3, $4, $5, coalesce($6::timestamptz, now()))`,
        [d.idProducto, piso.id_almacen, -d.cantidad, `venta:${idVenta}`, idUsuario, fecha]);
    }
  }
  if (estado === 'PAGADA') {
    await db.query('insert into public.pago (id_venta, id_forma_pago, importe) values ($1, 1, $2)', [idVenta, total]);
  }
  return { idVenta, total, detalle };
}

// Emite la factura de una venta tomando el siguiente correlativo del CAI
// (versión mínima de lo que hará el módulo SAR).
export async function facturarDemo(db, idVenta, idCai = 3) {
  const lineas = (await db.query('select clasificacion_fiscal, tasa_impuesto, importe from public.venta_linea where id_venta = $1', [idVenta])).rows;
  const r2 = (x) => Math.round(x * 100) / 100;
  const t = { exento: 0, g15: 0, g18: 0, i15: 0, i18: 0 };
  for (const l of lineas) {
    const imp = Number(l.importe);
    if (l.clasificacion_fiscal === 'EXENTO') t.exento += imp;
    if (l.clasificacion_fiscal === 'GRAVADO15') { const b = r2(imp / 1.15); t.g15 += b; t.i15 += r2(imp - b); }
    if (l.clasificacion_fiscal === 'GRAVADO18') { const b = r2(imp / 1.18); t.g18 += b; t.i18 += r2(imp - b); }
  }
  const total = r2(t.exento + t.g15 + t.g18 + t.i15 + t.i18);
  const c = (await db.query(
    `update public.cai set ultimo_usado = coalesce(ultimo_usado, correlativo_inicial - 1) + 1
      where id_cai = $1 returning ultimo_usado`, [idCai])).rows[0];
  const numero = (await db.query('select public.formato_numero_fiscal($1, $2) as n', [idCai, c.ultimo_usado])).rows[0].n;
  const d = (await db.query(
    `insert into public.documento_fiscal (id_cai, correlativo, numero, id_venta, importe_exento, importe_gravado_15,
       importe_gravado_18, isv_15, isv_18, total, total_letras)
     values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'TOTAL EN LETRAS') returning id_documento, numero, total`,
    [idCai, c.ultimo_usado, numero, idVenta, r2(t.exento), r2(t.g15), r2(t.g18), r2(t.i15), r2(t.i18), total])).rows[0];
  return d;
}
