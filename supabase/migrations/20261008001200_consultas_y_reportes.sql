-- =====================================================================
-- 1200 · Consultas del catálogo, existencias, kardex y reportes
-- (doc 06 §5.3.1, doc 12 §3 y §6, doc 07 §3.1 "Reportes")
--
-- Todas las vistas son security_invoker: se evalúan con los permisos de
-- quien consulta, así el RLS de las tablas de abajo sigue aplicando.
-- (Una vista normal corre como su dueño y se saltaría el RLS.)
-- Las funciones SECURITY DEFINER validan el permiso al inicio.
-- =====================================================================

create or replace function public.hoy_honduras()
returns date
language sql
stable
set search_path = ''
as $$ select (now() at time zone 'America/Tegucigalpa')::date $$;

-- ---------------------------------------------------------------------
-- Catálogo
-- ---------------------------------------------------------------------

-- GET /api/v1/productos/codigo/{codigo}?sucursal= (doc 06 §5.3.1)
create or replace function public.producto_por_codigo(p_codigo text, p_id_sucursal bigint)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'idProducto',          p.id_producto,
    'sku',                 p.sku,
    'descripcion',         p.descripcion,
    'unidad',              u.clave,
    'esGranel',            p.es_granel,
    'factor',              cb.factor,
    'precio',              public.precio_vigente(p.id_producto, p_id_sucursal),
    'clasificacionFiscal', p.clasificacion_fiscal,
    'impuestos',           case when cf.tasa > 0
                             then jsonb_build_array(jsonb_build_object('nombre', 'ISV', 'tasa', cf.tasa))
                             else '[]'::jsonb end,
    'restringidoEdad',     p.restringido_edad,
    'promocionesVigentes', coalesce((
        select jsonb_agg(jsonb_build_object('idPromocion', pr.id_promocion, 'tipo', pr.tipo,
                                            'valor', pr.valor, 'n', pr.n_compra, 'm', pr.m_paga)
                         order by pr.prioridad desc)
        from public.promocion pr
        where pr.activa and now() >= pr.inicio and now() < pr.fin
          and exists (select 1 from public.promocion_alcance pa
                      where pa.id_promocion = pr.id_promocion
                        and (   (pa.tipo_objetivo = 'PRODUCTO'  and pa.id_objetivo = p.id_producto)
                             or (pa.tipo_objetivo = 'CATEGORIA' and pa.id_objetivo = p.id_categoria)))
          and (not exists (select 1 from public.promocion_alcance ps
                           where ps.id_promocion = pr.id_promocion and ps.tipo_objetivo = 'SUCURSAL')
               or exists (select 1 from public.promocion_alcance ps
                          where ps.id_promocion = pr.id_promocion and ps.tipo_objetivo = 'SUCURSAL'
                            and ps.id_objetivo = p_id_sucursal))), '[]'::jsonb),
    'existenciaSucursal',  coalesce((
        select sum(e.cantidad)
        from public.existencia e
        join public.almacen a on a.id_almacen = e.id_almacen
        where e.id_producto = p.id_producto and a.id_sucursal = p_id_sucursal and a.tipo <> 'MERMA'), 0)
  )
  from public.codigo_barras cb
  join public.producto p             on p.id_producto = cb.id_producto and p.activo
  join public.unidad_medida u        on u.id_unidad = p.id_unidad
  join public.clasificacion_fiscal cf on cf.codigo = p.clasificacion_fiscal
  where cb.codigo = p_codigo
$$;

-- GET /api/v1/productos?buscar=&categoria=&pagina=&tamano= (búsqueda F2)
create or replace function public.buscar_productos(
  p_buscar        text    default null,
  p_id_categoria  bigint  default null,
  p_id_sucursal   bigint  default null,
  p_pagina        int     default 1,
  p_tamano        int     default 50
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with filtrados as (
    select p.*
    from public.producto p
    where p.activo
      and (p_id_categoria is null or p.id_categoria = p_id_categoria)
      and (p_buscar is null
           or p.descripcion ilike '%' || p_buscar || '%'
           or p.sku ilike p_buscar || '%'
           or exists (select 1 from public.codigo_barras cb
                      where cb.id_producto = p.id_producto and cb.codigo = p_buscar))
  )
  select jsonb_build_object(
    'total',  (select count(*) from filtrados),
    'pagina', greatest(p_pagina, 1),
    'tamano', least(greatest(p_tamano, 1), 200),
    'datos',  coalesce((
      select jsonb_agg(fila order by fila->>'descripcion')
      from (
        select jsonb_build_object(
                 'idProducto', f.id_producto, 'sku', f.sku, 'descripcion', f.descripcion,
                 'idCategoria', f.id_categoria, 'clasificacionFiscal', f.clasificacion_fiscal,
                 'costoPromedio', f.costo_promedio,
                 'precio', case when p_id_sucursal is not null
                                then public.precio_vigente(f.id_producto, p_id_sucursal) end) as fila
        from filtrados f
        order by f.descripcion
        limit least(greatest(p_tamano, 1), 200)
        offset (greatest(p_pagina, 1) - 1) * least(greatest(p_tamano, 1), 200)
      ) pagina), '[]'::jsonb)
  )
$$;

-- RF-CAT-04: margen sobre el precio vigente (precio sin ISV vs costo promedio)
-- y precio sugerido según el margen objetivo de la categoría.
create or replace view public.v_margen_productos
with (security_invoker = true) as
select p.id_producto, p.sku, p.descripcion, s.id_sucursal, s.nombre as sucursal,
       p.costo_promedio,
       pv.precio as precio_venta,
       round(pv.precio / (1 + cf.tasa), 2) as precio_sin_isv,
       case when pv.precio > 0
            then round(1 - p.costo_promedio / (pv.precio / (1 + cf.tasa)), 4) end as margen,
       c.margen_objetivo,
       case when c.margen_objetivo is not null and c.margen_objetivo < 1
            then round(p.costo_promedio / (1 - c.margen_objetivo) * (1 + cf.tasa), 2) end as precio_sugerido
from public.producto p
join public.categoria c             on c.id_categoria = p.id_categoria
join public.clasificacion_fiscal cf on cf.codigo = p.clasificacion_fiscal
cross join public.sucursal s
cross join lateral (select public.precio_vigente(p.id_producto, s.id_sucursal) as precio) pv
where p.activo and s.activa and pv.precio is not null;

-- ---------------------------------------------------------------------
-- Existencias
-- ---------------------------------------------------------------------

-- Existencia por producto y sucursal (sin el almacén de merma) con su estado.
create or replace view public.v_existencias
with (security_invoker = true) as
select p.id_producto, p.sku, p.descripcion,
       c.id_categoria, c.nombre as categoria,
       a.id_sucursal, s.nombre as sucursal,
       sum(e.cantidad)                          as cantidad,
       p.stock_minimo, p.stock_maximo,
       p.costo_promedio,
       round(sum(e.cantidad) * p.costo_promedio, 2) as valor,
       case
         when sum(e.cantidad) < 0                                 then 'NEGATIVA'
         when sum(e.cantidad) = 0                                 then 'SIN_EXISTENCIA'
         when sum(e.cantidad) < p.stock_minimo                    then 'BAJO_MINIMO'
         when p.stock_maximo is not null and sum(e.cantidad) > p.stock_maximo then 'SOBRE_MAXIMO'
         else 'OK'
       end as estado,
       max(e.actualizado) as actualizado
from public.existencia e
join public.almacen a   on a.id_almacen = e.id_almacen and a.tipo <> 'MERMA'
join public.sucursal s  on s.id_sucursal = a.id_sucursal
join public.producto p  on p.id_producto = e.id_producto
join public.categoria c on c.id_categoria = p.id_categoria
group by p.id_producto, c.id_categoria, a.id_sucursal, s.nombre;

-- Existencia por almacén y lote (detalle de la pantalla de Inventario).
create or replace view public.v_existencias_detalle
with (security_invoker = true) as
select e.id_existencia, e.id_producto, p.sku, p.descripcion,
       a.id_sucursal, e.id_almacen, a.nombre as almacen, a.tipo as tipo_almacen,
       e.id_lote, l.numero_lote, l.fecha_caducidad, coalesce(l.bloqueado, false) as lote_bloqueado,
       e.cantidad, e.actualizado
from public.existencia e
join public.almacen a  on a.id_almacen = e.id_almacen
join public.producto p on p.id_producto = e.id_producto
left join public.lote l on l.id_lote = e.id_lote;

-- GET /api/v1/existencias/disponible?producto=&sucursal= (doc 12 §6)
-- RN-EXI-01: disponible = existencia − lo apartado en ventas abiertas o
-- suspendidas de la sucursal. No cuenta lotes caducados ni bloqueados.
-- SECURITY DEFINER para poder informar la existencia de OTRAS sucursales
-- (RF-EXI-04) sin abrirle al cajero el detalle de su inventario.
create or replace function public.existencia_disponible(p_id_producto bigint, p_id_sucursal bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_resultado jsonb;
begin
  if not (public.tiene_permiso('VENTA_CREAR', p_id_sucursal) or public.tiene_permiso('INVENTARIO_VER', p_id_sucursal)) then
    raise exception 'Sin permiso para consultar existencias de la sucursal %', p_id_sucursal using errcode = '42501';
  end if;

  with disponible as (
    select s.id_sucursal, s.nombre,
           coalesce((select sum(e.cantidad)
                     from public.existencia e
                     join public.almacen a on a.id_almacen = e.id_almacen and a.tipo <> 'MERMA'
                     left join public.lote l on l.id_lote = e.id_lote
                     where e.id_producto = p_id_producto and a.id_sucursal = s.id_sucursal
                       and not coalesce(l.bloqueado, false)
                       and (l.fecha_caducidad is null or l.fecha_caducidad >= public.hoy_honduras())), 0)
         - coalesce((select sum(vl.cantidad)
                     from public.venta v
                     join public.venta_linea vl on vl.id_venta = v.id_venta and not vl.cancelada
                     where v.id_sucursal = s.id_sucursal and v.estado in ('ABIERTA', 'SUSPENDIDA')
                       and vl.id_producto = p_id_producto), 0) as disponible
    from public.sucursal s
    where s.activa
  )
  select jsonb_build_object(
           'idProducto',      p.id_producto,
           'producto',        p.descripcion,
           'disponible',      (select d.disponible from disponible d where d.id_sucursal = p_id_sucursal),
           'minimo',          p.stock_minimo,
           'permiteNegativo', c.permite_negativo,
           'otrasSucursales', coalesce((select jsonb_agg(jsonb_build_object('idSucursal', d.id_sucursal,
                                                                            'sucursal', d.nombre,
                                                                            'disponible', d.disponible)
                                                         order by d.nombre)
                                        from disponible d
                                        where d.id_sucursal <> p_id_sucursal and d.disponible > 0), '[]'::jsonb))
    into v_resultado
  from public.producto p
  join public.categoria c on c.id_categoria = p.id_categoria
  where p.id_producto = p_id_producto;

  return v_resultado;
end;
$$;

-- ---------------------------------------------------------------------
-- Kardex (RF-KDX-02, RF-KDX-03, RF-KDX-06)
-- El saldo se reconstruye con una suma acumulada de los movimientos, así
-- funciona igual para un almacén o para toda la sucursal y a cualquier fecha.
-- ---------------------------------------------------------------------
create or replace function public.kardex(
  p_id_producto     bigint,
  p_id_sucursal     bigint,
  p_desde           timestamptz default '-infinity',
  p_hasta           timestamptz default 'infinity',
  p_tipo            text        default null,
  p_id_almacen      bigint      default null,
  p_ventas_por_dia  boolean     default false
)
returns table (
  fecha              timestamptz,
  tipo               varchar,
  documento_origen   varchar,
  numero_lote        varchar,
  usuario            varchar,
  entrada            numeric,
  salida             numeric,
  saldo              numeric,
  costo_unitario     numeric,
  costo_promedio     numeric,
  valor_saldo        numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.tiene_permiso('INVENTARIO_VER', p_id_sucursal) then
    raise exception 'Sin permiso INVENTARIO_VER en la sucursal %', p_id_sucursal using errcode = '42501';
  end if;

  return query
  with movs as (
    select m.id_movimiento, m.fecha, m.tipo, m.documento_origen, m.id_lote, m.id_usuario,
           m.cantidad, m.costo_unitario, m.costo_promedio_resultante,
           sum(m.cantidad) over (order by m.fecha, m.id_movimiento) as saldo_acum
    from public.movimiento_inventario m
    join public.almacen a on a.id_almacen = m.id_almacen
    where m.id_producto = p_id_producto
      and m.id_sucursal = p_id_sucursal
      and a.tipo <> 'MERMA'
      and (p_id_almacen is null or m.id_almacen = p_id_almacen)
      and m.fecha <= p_hasta
  ),
  periodo as (
    select * from movs
    where movs.fecha >= p_desde and (p_tipo is null or movs.tipo = p_tipo)
  ),
  detalle as (
    select pe.fecha, pe.tipo, pe.documento_origen, l.numero_lote, u.nombre_completo as usuario,
           case when pe.cantidad > 0 then pe.cantidad end as entrada,
           case when pe.cantidad < 0 then -pe.cantidad end as salida,
           pe.saldo_acum as saldo, pe.costo_unitario, pe.costo_promedio_resultante as costo_promedio,
           pe.id_movimiento
    from periodo pe
    left join public.lote l    on l.id_lote = pe.id_lote
    left join public.usuario u on u.id_usuario = pe.id_usuario
    where not (p_ventas_por_dia and pe.tipo = 'VENTA')
  ),
  -- Opcional: ventas acumuladas por día para que el kardex sea legible (doc 12 §3.1).
  ventas_dia as (
    select max(pe.fecha) as fecha, 'VENTA'::varchar as tipo,
           ('ventas del ' || to_char((pe.fecha at time zone 'America/Tegucigalpa')::date, 'DD/MM/YYYY'))::varchar as documento_origen,
           null::varchar as numero_lote, null::varchar as usuario,
           null::numeric as entrada, -sum(pe.cantidad) as salida,
           (array_agg(pe.saldo_acum order by pe.fecha desc, pe.id_movimiento desc))[1] as saldo,
           round(avg(pe.costo_unitario), 4) as costo_unitario,
           (array_agg(pe.costo_promedio_resultante order by pe.fecha desc, pe.id_movimiento desc))[1] as costo_promedio,
           max(pe.id_movimiento) as id_movimiento
    from periodo pe
    where p_ventas_por_dia and pe.tipo = 'VENTA'
    group by (pe.fecha at time zone 'America/Tegucigalpa')::date
  )
  select x.fecha, x.tipo, x.documento_origen, x.numero_lote, x.usuario,
         x.entrada, x.salida, x.saldo, x.costo_unitario, x.costo_promedio,
         round(x.saldo * x.costo_promedio, 2) as valor_saldo
  from (select * from detalle union all select * from ventas_dia) x
  order by x.fecha, x.id_movimiento;
end;
$$;

-- Resumen del periodo: saldo inicial + entradas − salidas = saldo final (RF-KDX-03).
create or replace function public.kardex_resumen(
  p_id_producto  bigint,
  p_id_sucursal  bigint,
  p_desde        timestamptz default '-infinity',
  p_hasta        timestamptz default 'infinity',
  p_id_almacen   bigint      default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  if not public.tiene_permiso('INVENTARIO_VER', p_id_sucursal) then
    raise exception 'Sin permiso INVENTARIO_VER en la sucursal %', p_id_sucursal using errcode = '42501';
  end if;

  with movs as (
    select m.*
    from public.movimiento_inventario m
    join public.almacen a on a.id_almacen = m.id_almacen and a.tipo <> 'MERMA'
    where m.id_producto = p_id_producto and m.id_sucursal = p_id_sucursal
      and (p_id_almacen is null or m.id_almacen = p_id_almacen)
      and m.fecha <= p_hasta
  ),
  t as (
    select coalesce(sum(cantidad) filter (where fecha < p_desde), 0)                     as saldo_inicial,
           coalesce(sum(cantidad) filter (where fecha >= p_desde and cantidad > 0), 0)   as entradas,
           coalesce(-sum(cantidad) filter (where fecha >= p_desde and cantidad < 0), 0)  as salidas,
           (select m2.costo_promedio_resultante from movs m2 order by m2.fecha desc, m2.id_movimiento desc limit 1) as costo_promedio
    from movs
  )
  select jsonb_build_object(
           'saldoInicial',  t.saldo_inicial,
           'entradas',      t.entradas,
           'salidas',       t.salidas,
           'saldoFinal',    t.saldo_inicial + t.entradas - t.salidas,
           'costoPromedio', coalesce(t.costo_promedio, 0),
           'valorFinal',    round((t.saldo_inicial + t.entradas - t.salidas) * coalesce(t.costo_promedio, 0), 2))
    into v
  from t;
  return v;
end;
$$;

-- RF-KDX-06: existencia de un producto en una sucursal a cualquier fecha.
create or replace function public.existencia_a_fecha(p_id_producto bigint, p_id_sucursal bigint, p_fecha timestamptz)
returns numeric
language sql
stable
set search_path = ''
as $$
  select coalesce(sum(m.cantidad), 0)
  from public.movimiento_inventario m
  join public.almacen a on a.id_almacen = m.id_almacen and a.tipo <> 'MERMA'
  where m.id_producto = p_id_producto and m.id_sucursal = p_id_sucursal and m.fecha <= p_fecha
$$;

-- ---------------------------------------------------------------------
-- Reportes de ventas (RF-REP-01, RF-REP-02)
-- Cuentan ventas cobradas: PAGADA y con devolución parcial/total (la
-- devolución se descuenta por su lado con la nota de crédito).
-- ---------------------------------------------------------------------
create or replace view public.v_ventas_por_dia
with (security_invoker = true) as
select (v.fecha at time zone 'America/Tegucigalpa')::date as dia,
       v.id_sucursal, s.nombre as sucursal,
       count(*)                                  as ventas,
       sum(v.subtotal)                           as subtotal,
       sum(v.descuento)                          as descuento,
       sum(v.impuestos)                          as impuestos,
       sum(v.total)                              as total,
       round(avg(v.total), 2)                    as ticket_promedio,
       count(*) filter (where v.tipo_documento = 'TICKET') as ventas_sin_factura
from public.venta v
join public.sucursal s on s.id_sucursal = v.id_sucursal
where v.estado in ('PAGADA', 'DEV_PARCIAL', 'DEV_TOTAL')
group by 1, v.id_sucursal, s.nombre;

-- Nombre de un empleado para reportes. La tabla usuario solo deja ver la
-- fila propia (RLS); esta función expone únicamente el nombre, y solo a
-- empleados con sesión.
create or replace function public.nombre_empleado(p_id_usuario bigint)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select u.nombre_completo::text
  from public.usuario u
  where u.id_usuario = p_id_usuario and public.usuario_actual_id() is not null
$$;

-- GET /api/v1/reportes/ventas?desde=&hasta=&agrupar=
create or replace function public.reporte_ventas(
  p_desde        date,
  p_hasta        date,
  p_agrupar      text   default 'dia',
  p_id_sucursal  bigint default null
)
returns table (clave text, etiqueta text, ventas bigint, unidades numeric, total numeric, margen numeric)
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_agrupar not in ('dia', 'sucursal', 'caja', 'cajero', 'hora', 'categoria', 'producto', 'forma_pago') then
    raise exception 'agrupar debe ser dia, sucursal, caja, cajero, hora, categoria, producto o forma_pago'
      using errcode = '22023';
  end if;

  return query
  with v as (
    select x.*
    from public.venta x
    where x.estado in ('PAGADA', 'DEV_PARCIAL', 'DEV_TOTAL')
      and (x.fecha at time zone 'America/Tegucigalpa')::date between p_desde and p_hasta
      and (p_id_sucursal is null or x.id_sucursal = p_id_sucursal)
  ),
  l as (
    select vl.*, v.fecha
    from public.venta_linea vl join v on v.id_venta = vl.id_venta
    where not vl.cancelada
  )
  -- Por línea de venta: categoría y producto (dan unidades y margen).
  select g.clave, g.etiqueta, count(distinct g.id_venta), sum(g.cantidad), sum(g.importe),
         sum(round(g.importe / (1 + g.tasa_impuesto), 2) - round(g.cantidad * g.costo_unitario, 2))
  from (
    select case p_agrupar when 'categoria' then c.id_categoria::text else p.id_producto::text end as clave,
           (case p_agrupar when 'categoria' then c.nombre else p.descripcion end)::text as etiqueta,
           l.id_venta, l.cantidad, l.importe, l.costo_unitario, l.tasa_impuesto
    from l
    join public.producto p  on p.id_producto = l.id_producto
    join public.categoria c on c.id_categoria = p.id_categoria
    where p_agrupar in ('categoria', 'producto')
  ) g
  group by g.clave, g.etiqueta

  union all
  -- Por forma de pago (lo cobrado menos el cambio).
  select fp.clave::text, fp.nombre::text, count(distinct pg.id_venta), null::numeric,
         sum(pg.importe - pg.cambio), null::numeric
  from public.pago pg
  join v on v.id_venta = pg.id_venta
  join public.forma_pago fp on fp.id_forma_pago = pg.id_forma_pago
  where p_agrupar = 'forma_pago'
  group by fp.clave, fp.nombre

  union all
  -- Por encabezado de venta.
  select g.clave, g.etiqueta, count(*), null::numeric, sum(g.total), null::numeric
  from (
    select case p_agrupar
             when 'dia'      then to_char((v.fecha at time zone 'America/Tegucigalpa')::date, 'YYYY-MM-DD')
             when 'hora'     then to_char(v.fecha at time zone 'America/Tegucigalpa', 'HH24')
             when 'sucursal' then v.id_sucursal::text
             when 'caja'     then v.id_caja::text
             when 'cajero'   then v.id_usuario::text
           end as clave,
           case p_agrupar
             when 'dia'      then to_char((v.fecha at time zone 'America/Tegucigalpa')::date, 'DD/MM/YYYY')
             when 'hora'     then to_char(v.fecha at time zone 'America/Tegucigalpa', 'HH24') || ':00'
             when 'sucursal' then (select s.nombre::text from public.sucursal s where s.id_sucursal = v.id_sucursal)
             when 'caja'     then (select cj.codigo::text from public.caja cj where cj.id_caja = v.id_caja)
             when 'cajero'   then public.nombre_empleado(v.id_usuario)
           end as etiqueta,
           v.total
    from v
    where p_agrupar in ('dia', 'hora', 'sucursal', 'caja', 'cajero')
  ) g
  group by g.clave, g.etiqueta
  order by 1;
end;
$$;

-- Tablero: KPIs del día y alertas (RF-REP-01, doc 07 §3.1 "Dashboard").
create or replace function public.kpis_dashboard(p_id_sucursal bigint default null, p_dia date default null)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with dia as (select coalesce(p_dia, public.hoy_honduras()) as d),
  v as (
    select x.* from public.venta x, dia
    where x.estado in ('PAGADA', 'DEV_PARCIAL', 'DEV_TOTAL')
      and (x.fecha at time zone 'America/Tegucigalpa')::date = dia.d
      and (p_id_sucursal is null or x.id_sucursal = p_id_sucursal)
  ),
  l as (
    select vl.* from public.venta_linea vl join v on v.id_venta = vl.id_venta where not vl.cancelada
  )
  select jsonb_build_object(
    'dia',             (select d from dia),
    'ventas',          (select count(*) from v),
    'total',           (select coalesce(sum(total), 0) from v),
    'ticketPromedio',  (select coalesce(round(avg(total), 2), 0) from v),
    'impuestos',       (select coalesce(sum(impuestos), 0) from v),
    'ventasSinFactura',(select count(*) from v where tipo_documento = 'TICKET'),
    'margenBruto',     (select coalesce(sum(round(importe / (1 + tasa_impuesto), 2) - round(cantidad * costo_unitario, 2)), 0) from l),
    'alarmas', jsonb_build_object(
       'criticas',    (select count(*) from public.alarma a where a.estado <> 'RESUELTA' and a.nivel = 'CRITICA'
                         and (p_id_sucursal is null or a.id_sucursal = p_id_sucursal)),
       'advertencias',(select count(*) from public.alarma a where a.estado <> 'RESUELTA' and a.nivel = 'ADVERTENCIA'
                         and (p_id_sucursal is null or a.id_sucursal = p_id_sucursal))),
    'topProductos', coalesce((
       select jsonb_agg(t order by t.total desc)
       from (select p.descripcion, sum(l.cantidad) as unidades, sum(l.importe) as total
             from l join public.producto p on p.id_producto = l.id_producto
             group by p.descripcion order by sum(l.importe) desc limit 5) t), '[]'::jsonb)
  )
$$;

-- ---------------------------------------------------------------------
-- Reportes fiscales (doc 09 §3.8, RF-SAR-12, RF-DOC-06)
-- ---------------------------------------------------------------------

-- Libro de ventas: un renglón por documento. Las facturas anuladas se
-- listan con montos en cero para que no haya huecos en la numeración;
-- las notas de crédito restan.
create or replace view public.v_libro_ventas
with (security_invoker = true) as
select d.id_documento,
       (d.fecha_emision at time zone 'America/Tegucigalpa')::date as fecha,
       to_char(d.fecha_emision at time zone 'America/Tegucigalpa', 'YYYY-MM') as mes,
       c.tipo_documento, td.nombre as tipo_documento_nombre,
       d.numero, c.cai, d.correlativo,
       e.id_sucursal,
       coalesce(d.rtn_comprador, '') as rtn_comprador,
       d.nombre_comprador,
       d.estado,
       (s.signo * case when d.estado = 'ANULADO' then 0 else d.importe_exento end)::numeric(12,2) as importe_exento,
       (s.signo * case when d.estado = 'ANULADO' then 0 else d.importe_exonerado end)::numeric(12,2) as importe_exonerado,
       (s.signo * case when d.estado = 'ANULADO' then 0 else d.importe_gravado_15 end)::numeric(12,2) as importe_gravado_15,
       (s.signo * case when d.estado = 'ANULADO' then 0 else d.importe_gravado_18 end)::numeric(12,2) as importe_gravado_18,
       (s.signo * case when d.estado = 'ANULADO' then 0 else d.isv_15 end)::numeric(12,2) as isv_15,
       (s.signo * case when d.estado = 'ANULADO' then 0 else d.isv_18 end)::numeric(12,2) as isv_18,
       (s.signo * case when d.estado = 'ANULADO' then 0 else d.total end)::numeric(12,2) as total
from public.documento_fiscal d
join public.cai c                    on c.id_cai = d.id_cai
join public.tipo_documento_fiscal td on td.codigo = c.tipo_documento and td.afecta_libro_ventas
join public.punto_emision pe         on pe.id_punto = c.id_punto
join public.establecimiento_sar e    on e.id_establecimiento = pe.id_establecimiento
cross join lateral (select case when d.id_documento_origen is null then 1 else -1 end as signo) s;

-- GET /api/v1/sar/libro-ventas?mes=2026-09
create or replace function public.libro_ventas(p_mes text, p_id_sucursal bigint default null)
returns setof public.v_libro_ventas
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_mes !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'El mes debe tener formato AAAA-MM' using errcode = '22023';
  end if;
  if not public.tiene_permiso('SAR_REPORTES') then
    raise exception 'Sin permiso SAR_REPORTES' using errcode = '42501';
  end if;

  return query
  select * from public.v_libro_ventas lv
  where lv.mes = p_mes and (p_id_sucursal is null or lv.id_sucursal = p_id_sucursal)
  order by lv.tipo_documento, lv.numero;
end;
$$;

-- Resumen para la declaración mensual del ISV.
create or replace function public.resumen_isv(p_mes text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'mes',              p_mes,
    'documentos',       count(*),
    'anulados',         count(*) filter (where estado = 'ANULADO'),
    'importeExento',    coalesce(sum(importe_exento), 0),
    'importeExonerado', coalesce(sum(importe_exonerado), 0),
    'gravado15',        coalesce(sum(importe_gravado_15), 0),
    'gravado18',        coalesce(sum(importe_gravado_18), 0),
    'isv15',            coalesce(sum(isv_15), 0),
    'isv18',            coalesce(sum(isv_18), 0),
    'total',            coalesce(sum(total), 0))
  from public.libro_ventas(p_mes)
$$;

-- RF-DOC-06: ventas respaldadas solo con ticket (emitidos, canjeados, vencidos).
create or replace view public.v_ventas_sin_factura
with (security_invoker = true) as
select t.id_ticket, t.numero, t.codigo_canje,
       (t.fecha at time zone 'America/Tegucigalpa')::date as fecha,
       v.id_sucursal, s.nombre as sucursal, v.folio, v.total,
       case when t.estado = 'EMITIDO' and t.fecha_limite_canje < public.hoy_honduras()
            then 'VENCIDO' else t.estado end as estado,
       t.fecha_limite_canje,
       d.numero as factura_canje
from public.ticket t
join public.venta v    on v.id_venta = t.id_venta
join public.sucursal s on s.id_sucursal = v.id_sucursal
left join public.documento_fiscal d on d.id_documento = t.id_documento_canje;

-- ---------------------------------------------------------------------
-- Clientes y lealtad
-- ---------------------------------------------------------------------

-- GET /api/v1/clientes?telefono= : identificación en caja con saldo de puntos.
create or replace view public.v_clientes
with (security_invoker = true) as
select c.id_cliente, c.nombre, c.telefono, c.correo, c.rtn, c.razon_social, c.activo,
       cl.numero_tarjeta, cl.saldo_puntos, cl.nivel,
       (select max(v.fecha) from public.venta v where v.id_cliente = c.id_cliente) as ultima_compra
from public.cliente c
left join public.cuenta_lealtad cl on cl.id_cliente = c.id_cliente
where not c.anonimizado;

-- Historial de puntos con caducidad (RF-CLI-04).
create or replace view public.v_movimientos_puntos
with (security_invoker = true) as
select cl.id_cliente, mp.id_mov, mp.tipo, mp.puntos, mp.caduca_el, mp.fecha, v.folio
from public.movimiento_puntos mp
join public.cuenta_lealtad cl on cl.id_cuenta = mp.id_cuenta
left join public.venta v on v.id_venta = mp.id_venta;

-- ---------------------------------------------------------------------
-- Centro de alarmas
-- ---------------------------------------------------------------------
create or replace view public.v_alarmas
with (security_invoker = true) as
select a.id_alarma, a.tipo, a.nivel, a.estado, a.valor_actual, a.origen,
       a.id_producto, p.sku, p.descripcion as producto,
       a.id_sucursal, s.nombre as sucursal,
       a.id_lote, l.numero_lote, l.fecha_caducidad,
       r.id_rol_responsable, ro.nombre as rol_responsable,
       a.id_asignado, a.creada, a.actualizada, a.resuelta,
       p.stock_minimo
from public.alarma a
join public.producto p      on p.id_producto = a.id_producto
join public.sucursal s      on s.id_sucursal = a.id_sucursal
join public.regla_alarma r  on r.id_regla = a.id_regla
left join public.rol ro     on ro.id_rol = r.id_rol_responsable
left join public.lote l     on l.id_lote = a.id_lote;
