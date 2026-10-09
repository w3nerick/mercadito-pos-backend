-- =====================================================================
-- Datos semilla de MercaditoPOS (dev / qa / staging)
-- Todos los datos son FICTICIOS: empresa, RTN, CAI, clientes y proveedores
-- se inventaron para pruebas. No usar en producción.
-- Se ejecuta con `supabase db reset` (después de las migraciones).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Organización
-- ---------------------------------------------------------------------
insert into public.empresa (id_empresa, razon_social, rtn, nombre_comercial, domicilio_casa_matriz) values
  (1, 'Supermercados Mercadito, S.A. de C.V.', '08019099000011', 'Mercadito', 'Col. Centro, Tegucigalpa, M.D.C.');

insert into public.sucursal (id_sucursal, id_empresa, codigo, nombre, direccion, telefono) values
  (1, 1, 'CEN', 'Centro', 'Av. Principal, Col. Centro, Tegucigalpa', '2200-0001'),
  (2, 1, 'NOR', 'Norte',  'Bulevar Norte, Col. Kennedy, Tegucigalpa', '2200-0002'),
  (3, 1, 'SUR', 'Sur',    'Salida al Sur, Col. Las Hadas, Tegucigalpa', '2200-0003');

insert into public.caja (id_caja, id_sucursal, codigo, serie_folio, id_dispositivo) values
  (1, 1, 'C01', 'C01', 'C01-CENTRO'),
  (2, 1, 'C02', 'C02', 'C02-CENTRO'),
  (3, 1, 'C03', 'C03', 'C03-CENTRO'),
  (4, 2, 'C04', 'C04', 'C04-NORTE'),
  (5, 2, 'C05', 'C05', 'C05-NORTE'),
  (6, 3, 'C06', 'C06', 'C06-SUR');

insert into public.almacen (id_almacen, id_sucursal, nombre, tipo) values
  (1, 1, 'Piso de venta', 'PISO'), (2, 1, 'Bodega', 'BODEGA'), (3, 1, 'Merma', 'MERMA'),
  (4, 2, 'Piso de venta', 'PISO'), (5, 2, 'Bodega', 'BODEGA'), (6, 2, 'Merma', 'MERMA'),
  (7, 3, 'Piso de venta', 'PISO'), (8, 3, 'Bodega', 'BODEGA'), (9, 3, 'Merma', 'MERMA');

-- ---------------------------------------------------------------------
-- Roles y permisos (doc 10 §3–5)
-- ---------------------------------------------------------------------
insert into public.permiso (clave, modulo, descripcion) values
  ('VENTA_CREAR',                   'POS',          'Registrar y cobrar ventas'),
  ('VENTA_VER',                     'POS',          'Consultar ventas de la sucursal'),
  ('VENTA_CANCELAR_LINEA',          'POS',          'Cancelar línea después del subtotal'),
  ('VENTA_CANCELAR',                'POS',          'Cancelar venta completa'),
  ('VENTA_DESCUENTO_MANUAL',        'POS',          'Aplicar descuento manual (hasta el límite del rol)'),
  ('VENTA_PRECIO_MANUAL',           'POS',          'Cambiar precio en caja'),
  ('DOC_EMITIR_FACTURA',            'Documentos',   'Emitir factura (consumidor final o con RTN)'),
  ('DOC_EMITIR_TICKET',             'Documentos',   'Emitir solo ticket no fiscal'),
  ('DOC_CANJEAR_TICKET',            'Documentos',   'Canjear ticket por factura'),
  ('SAR_VER',                       'SAR',          'Ver datos del emisor, establecimientos y CAI'),
  ('SAR_CONFIGURAR',                'SAR',          'Registrar datos del emisor, establecimientos y CAI'),
  ('SAR_ANULAR',                    'SAR',          'Anular facturas'),
  ('SAR_NOTA_CREDITO',              'SAR',          'Emitir notas de crédito'),
  ('SAR_REPORTES',                  'SAR',          'Libro de ventas y reportes fiscales'),
  ('DEVOLUCION_CREAR',              'Devoluciones', 'Registrar devoluciones'),
  ('DEVOLUCION_AUTORIZAR',          'Devoluciones', 'Autorizar devoluciones'),
  ('CAJA_OPERAR',                   'Caja',         'Abrir turno y hacer retiros'),
  ('CAJA_CORTE',                    'Caja',         'Hacer cortes de caja'),
  ('CAJA_AUTORIZAR',                'Caja',         'Autorizar diferencias de caja'),
  ('CATALOGO_VER',                  'Catálogo',     'Ver productos y precios'),
  ('CATALOGO_EDITAR',               'Catálogo',     'Crear y editar productos'),
  ('PRECIO_EDITAR',                 'Catálogo',     'Programar precios'),
  ('CODIGOS_GENERAR',               'Catálogo',     'Generar códigos internos'),
  ('ETIQUETAS_IMPRIMIR',            'Catálogo',     'Imprimir etiquetas'),
  ('INVENTARIO_VER',                'Inventario',   'Ver existencias y kardex'),
  ('INVENTARIO_AJUSTAR',            'Inventario',   'Registrar ajustes y mermas'),
  ('INVENTARIO_APROBAR',            'Inventario',   'Aprobar ajustes'),
  ('INVENTARIO_TRANSFERIR',         'Inventario',   'Transferir entre sucursales'),
  ('INVENTARIO_AUTORIZAR_NEGATIVO', 'Inventario',   'Autorizar en caja la venta sin existencia'),
  ('ALARMAS_VER',                   'Inventario',   'Ver alarmas'),
  ('ALARMAS_GESTIONAR',             'Inventario',   'Atender alarmas'),
  ('ALARMAS_REGLAS',                'Inventario',   'Configurar reglas de alarma'),
  ('COMPRAS_VER',                   'Compras',      'Ver proveedores y órdenes de compra'),
  ('COMPRAS_CREAR',                 'Compras',      'Crear proveedores y órdenes de compra'),
  ('COMPRAS_APROBAR',               'Compras',      'Aprobar órdenes de compra'),
  ('RECEPCION_CREAR',               'Compras',      'Recibir mercancía'),
  ('PROMO_EDITAR',                  'Promociones',  'Crear y editar promociones'),
  ('CLIENTE_VER',                   'Clientes',     'Buscar clientes y ver puntos'),
  ('CLIENTE_CREAR',                 'Clientes',     'Registrar clientes'),
  ('CLIENTE_DATOS_PERSONALES',      'Clientes',     'Editar o anonimizar datos personales (ARCO)'),
  ('REPORTES_VER',                  'Reportes',     'Ver reportes'),
  ('REPORTES_EXPORTAR',             'Reportes',     'Exportar reportes'),
  ('CONFIG_EDITAR',                 'Configuración','Editar sucursales, cajas y parámetros'),
  ('USUARIOS_ADMIN',                'Seguridad',    'Administrar usuarios'),
  ('ROLES_ADMIN',                   'Seguridad',    'Administrar roles y permisos'),
  ('BITACORA_VER',                  'Seguridad',    'Consultar la bitácora de auditoría');

insert into public.rol (id_rol, nombre, descripcion, alcance, sistema) values
  (1, 'Administrador TI',     'Usuarios, roles y configuración técnica. No opera ventas ni inventario', 'TODAS',       true),
  (2, 'Gerente general',      'Consulta y aprueba todo; precios y promociones de la empresa',          'TODAS',       true),
  (3, 'Gerente de sucursal',  'Operación completa de su tienda; aprueba OC y ajustes',                  'ASIGNADAS',   true),
  (4, 'Supervisor de cajas',  'Autoriza cancelaciones, devoluciones, retiros y cortes',                 'ASIGNADAS',   true),
  (5, 'Cajero',               'Vende, cobra y emite factura',                                           'PROPIA_CAJA', true),
  (6, 'Almacén',              'Recepciones, ajustes (sin aprobar), transferencias y conteos',           'ASIGNADAS',   true),
  (7, 'Compras',              'Proveedores, productos y órdenes de compra',                             'TODAS',       true),
  (8, 'Contador',             'Configuración SAR, anulaciones, notas de crédito y libro de ventas',     'TODAS',       true),
  (9, 'Auditor',              'Solo lectura de todo y bitácora',                                        'TODAS',       true);

insert into public.rol_permiso (id_rol, id_permiso, puede_autorizar)
select m.id_rol, p.id_permiso, m.autoriza
from (values
  -- Administrador TI (RN-ROL-06: sin permisos operativos)
  (1, 'USUARIOS_ADMIN', false), (1, 'ROLES_ADMIN', false), (1, 'BITACORA_VER', false), (1, 'CONFIG_EDITAR', false),
  -- Gerente general
  (2, 'VENTA_VER', false), (2, 'VENTA_DESCUENTO_MANUAL', false), (2, 'PRECIO_EDITAR', false),
  (2, 'CATALOGO_VER', false), (2, 'CATALOGO_EDITAR', false), (2, 'INVENTARIO_VER', false),
  (2, 'INVENTARIO_APROBAR', false), (2, 'COMPRAS_VER', false), (2, 'COMPRAS_APROBAR', false),
  (2, 'PROMO_EDITAR', false), (2, 'CLIENTE_VER', false), (2, 'SAR_VER', false),
  (2, 'REPORTES_VER', false), (2, 'REPORTES_EXPORTAR', false), (2, 'BITACORA_VER', false),
  (2, 'ALARMAS_VER', false), (2, 'ALARMAS_GESTIONAR', false), (2, 'ALARMAS_REGLAS', false), (2, 'CONFIG_EDITAR', false),
  -- Gerente de sucursal
  (3, 'VENTA_CREAR', false), (3, 'VENTA_VER', false), (3, 'VENTA_CANCELAR_LINEA', true), (3, 'VENTA_CANCELAR', true),
  (3, 'VENTA_DESCUENTO_MANUAL', true), (3, 'VENTA_PRECIO_MANUAL', true),
  (3, 'DOC_EMITIR_FACTURA', false), (3, 'DOC_EMITIR_TICKET', false), (3, 'DOC_CANJEAR_TICKET', false),
  (3, 'SAR_ANULAR', true), (3, 'SAR_NOTA_CREDITO', false),
  (3, 'DEVOLUCION_CREAR', false), (3, 'DEVOLUCION_AUTORIZAR', true),
  (3, 'CAJA_OPERAR', false), (3, 'CAJA_CORTE', false), (3, 'CAJA_AUTORIZAR', true),
  (3, 'CATALOGO_VER', false), (3, 'PRECIO_EDITAR', false),
  (3, 'INVENTARIO_VER', false), (3, 'INVENTARIO_AJUSTAR', false), (3, 'INVENTARIO_APROBAR', false),
  (3, 'INVENTARIO_TRANSFERIR', false), (3, 'INVENTARIO_AUTORIZAR_NEGATIVO', true),
  (3, 'ALARMAS_VER', false), (3, 'ALARMAS_GESTIONAR', false), (3, 'ALARMAS_REGLAS', false),
  (3, 'COMPRAS_VER', false), (3, 'COMPRAS_CREAR', false), (3, 'COMPRAS_APROBAR', false),
  (3, 'CLIENTE_VER', false), (3, 'CLIENTE_CREAR', false), (3, 'CLIENTE_DATOS_PERSONALES', false),
  (3, 'REPORTES_VER', false), (3, 'REPORTES_EXPORTAR', false), (3, 'BITACORA_VER', false),
  -- Supervisor de cajas
  (4, 'VENTA_CREAR', false), (4, 'VENTA_VER', false), (4, 'VENTA_CANCELAR_LINEA', true), (4, 'VENTA_CANCELAR', true),
  (4, 'VENTA_DESCUENTO_MANUAL', true),
  (4, 'DOC_EMITIR_FACTURA', false), (4, 'DOC_EMITIR_TICKET', false), (4, 'DOC_CANJEAR_TICKET', false),
  (4, 'SAR_NOTA_CREDITO', false), (4, 'DEVOLUCION_CREAR', false), (4, 'DEVOLUCION_AUTORIZAR', true),
  (4, 'CAJA_OPERAR', false), (4, 'CAJA_CORTE', false), (4, 'CAJA_AUTORIZAR', true),
  (4, 'CATALOGO_VER', false), (4, 'INVENTARIO_VER', false), (4, 'INVENTARIO_AUTORIZAR_NEGATIVO', true),
  (4, 'ALARMAS_VER', false), (4, 'CLIENTE_VER', false), (4, 'CLIENTE_CREAR', false), (4, 'REPORTES_VER', false),
  -- Cajero (DOC_EMITIR_TICKET depende de la configuración: no se da por defecto)
  (5, 'VENTA_CREAR', false), (5, 'DOC_EMITIR_FACTURA', false), (5, 'DOC_CANJEAR_TICKET', false),
  (5, 'DEVOLUCION_CREAR', false), (5, 'CAJA_OPERAR', false), (5, 'CAJA_CORTE', false),
  (5, 'CATALOGO_VER', false), (5, 'CLIENTE_VER', false), (5, 'CLIENTE_CREAR', false),
  -- Almacén
  (6, 'CATALOGO_VER', false), (6, 'ETIQUETAS_IMPRIMIR', false), (6, 'INVENTARIO_VER', false),
  (6, 'INVENTARIO_AJUSTAR', false), (6, 'INVENTARIO_TRANSFERIR', false), (6, 'RECEPCION_CREAR', false),
  (6, 'COMPRAS_VER', false), (6, 'ALARMAS_VER', false), (6, 'ALARMAS_GESTIONAR', false),
  -- Compras
  (7, 'CATALOGO_VER', false), (7, 'CATALOGO_EDITAR', false), (7, 'CODIGOS_GENERAR', false),
  (7, 'ETIQUETAS_IMPRIMIR', false), (7, 'INVENTARIO_VER', false), (7, 'COMPRAS_VER', false),
  (7, 'COMPRAS_CREAR', false), (7, 'ALARMAS_VER', false), (7, 'ALARMAS_GESTIONAR', false), (7, 'REPORTES_VER', false),
  -- Contador (RN-ROL-05: SAR_CONFIGURAR sin VENTA_CREAR)
  (8, 'SAR_VER', false), (8, 'SAR_CONFIGURAR', false), (8, 'SAR_ANULAR', true), (8, 'SAR_NOTA_CREDITO', false),
  (8, 'SAR_REPORTES', false), (8, 'DOC_EMITIR_FACTURA', false), (8, 'DOC_CANJEAR_TICKET', false),
  (8, 'VENTA_VER', false), (8, 'CATALOGO_VER', false), (8, 'REPORTES_VER', false),
  (8, 'REPORTES_EXPORTAR', false), (8, 'BITACORA_VER', false),
  -- Auditor: solo lectura
  (9, 'VENTA_VER', false), (9, 'SAR_VER', false), (9, 'SAR_REPORTES', false), (9, 'CATALOGO_VER', false),
  (9, 'INVENTARIO_VER', false), (9, 'COMPRAS_VER', false), (9, 'CLIENTE_VER', false),
  (9, 'ALARMAS_VER', false), (9, 'REPORTES_VER', false), (9, 'BITACORA_VER', false)
) as m (id_rol, clave, autoriza)
join public.permiso p on p.clave = m.clave;

insert into public.rol_limite (id_rol, tipo_limite, valor) values
  (3, 'DESCUENTO_PCT', 20), (3, 'OC_MONTO', 50000),
  (4, 'DESCUENTO_PCT', 10), (4, 'DEVOLUCION_MONTO', 2000);

insert into public.regla_segregacion (id_permiso_a, id_permiso_b, accion)
select a.id_permiso, b.id_permiso, 'BLOQUEAR'
from public.permiso a, public.permiso b
where a.clave = 'SAR_CONFIGURAR' and b.clave = 'VENTA_CREAR';              -- RN-ROL-05

-- Empleados de demostración. Sin cuenta de Supabase Auth: se enlazan con
--   update public.usuario set auth_user_id = '<uuid de auth.users>' where usuario = '...';
insert into public.usuario (id_usuario, nombre_completo, usuario, activo) values
  (1, 'Proceso del sistema',     'sistema',           true),
  (2, 'Admin TI (demo)',         'admin.ti',          true),
  (3, 'Gerente general (demo)',  'gerente.general',   true),
  (4, 'Gerente Centro (demo)',   'gerente.centro',    true),
  (5, 'Supervisor Centro (demo)','supervisor.centro', true),
  (6, 'Cajero Centro (demo)',    'cajero.centro',     true),
  (7, 'Cajero Norte (demo)',     'cajero.norte',      true),
  (8, 'Almacén Centro (demo)',   'almacen.centro',    true),
  (9, 'Compras (demo)',          'compras',           true),
  (10,'Contador (demo)',         'contador',          true),
  (11,'Auditor (demo)',          'auditor',           true);

insert into public.usuario_rol (id_usuario, id_rol) values
  (2, 1), (3, 2), (4, 3), (5, 4), (6, 5), (7, 5), (8, 6), (9, 7), (10, 8), (11, 9);

insert into public.usuario_sucursal (id_usuario, id_sucursal) values
  (4, 1), (5, 1), (6, 1), (7, 2), (8, 1);

-- ---------------------------------------------------------------------
-- Catálogo
-- ---------------------------------------------------------------------
-- Tasas de ISV vigentes en Honduras: 15 % general y 18 % (bebidas
-- alcohólicas y tabaco). Confirmar con el docente (doc 11 §15.2 regla 6).
insert into public.clasificacion_fiscal (codigo, tasa, descripcion) values
  ('EXENTO',    0.0000, 'Exento de ISV (canasta básica)'),
  ('GRAVADO15', 0.1500, 'Gravado con ISV 15 %'),
  ('GRAVADO18', 0.1800, 'Gravado con ISV 18 % (bebidas alcohólicas y tabaco)');

insert into public.unidad_medida (id_unidad, clave, nombre, decimales) values
  (1, 'PZA', 'Pieza', 0), (2, 'KG', 'Kilogramo', 3), (3, 'LT', 'Litro', 3);

insert into public.categoria (id_categoria, nombre, margen_objetivo, permite_negativo) values
  (1, 'Lácteos',            0.18, false),
  (2, 'Abarrotes',          0.15, false),
  (3, 'Panadería',          0.30, false),
  (4, 'Frutas y verduras',  0.35, true),     -- RN-02: se permite vender en negativo
  (5, 'Bebidas',            0.22, false),
  (6, 'Licores y tabaco',   0.25, false),
  (7, 'Limpieza',           0.25, false);

insert into public.marca (id_marca, nombre) values
  (1, 'Marca Mercadito'), (2, 'Lácteos del Valle'), (3, 'Granos Copán'),
  (4, 'Refrescos Tropical'), (5, 'Cervecera Montaña'), (6, 'Limpio Hogar');

insert into public.producto
  (id_producto, sku, descripcion, id_categoria, id_marca, id_unidad, clasificacion_fiscal, contenido,
   es_granel, controla_lote, restringido_edad, excluido_puntos, stock_minimo, punto_reorden, stock_maximo) values
  (1,  'LAC-0014', 'Leche entera 1 L',              1, 2, 1, 'EXENTO',    '1 L',   false, false, false, false, 24, 36, 300),
  (2,  'LAC-0020', 'Yogur de fresa 1 L',            1, 2, 1, 'GRAVADO15', '1 L',   false, true,  false, false, 12, 18, 120),
  (3,  'LAC-0031', 'Queso fresco 1 lb',             1, 2, 1, 'EXENTO',    '1 lb',  false, false, false, false, 10, 15, 80),
  (4,  'ABA-0101', 'Arroz blanco 2 lb',             2, 3, 1, 'EXENTO',    '2 lb',  false, false, false, false, 30, 45, 400),
  (5,  'ABA-0102', 'Frijoles rojos 2 lb',           2, 3, 1, 'EXENTO',    '2 lb',  false, false, false, false, 30, 45, 400),
  (6,  'ABA-0150', 'Aceite vegetal 1 L',            2, 1, 1, 'GRAVADO15', '1 L',   false, false, false, false, 20, 30, 200),
  (7,  'ABA-0160', 'Huevos cartón 30 u',            2, 1, 1, 'EXENTO',    '30 u',  false, false, false, false, 15, 20, 120),
  (8,  'PAN-0001', 'Pan francés',                   3, 1, 1, 'EXENTO',    null,    false, false, false, false, 40, 60, 500),
  (9,  'PAN-0010', 'Pan integral',                  3, 1, 1, 'EXENTO',    null,    false, false, false, false, 12, 18, 100),
  (10, 'FRU-0001', 'Banano',                        4, null, 2, 'EXENTO', null,    true,  false, false, false, 20, 30, 200),
  (11, 'FRU-0002', 'Tomate',                        4, null, 2, 'EXENTO', null,    true,  false, false, false, 15, 25, 150),
  (12, 'BEB-0102', 'Refresco cola 2 L',             5, 4, 1, 'GRAVADO15', '2 L',   false, false, false, false, 24, 36, 300),
  (13, 'BEB-0110', 'Agua purificada 1 galón',       5, 4, 1, 'GRAVADO15', '1 gal', false, false, false, false, 20, 30, 200),
  (14, 'LIC-0001', 'Cerveza lata 355 ml',           6, 5, 1, 'GRAVADO18', '355 ml',false, false, true,  true,  48, 72, 600),
  (15, 'LIM-0001', 'Detergente en polvo 1 kg',      7, 6, 1, 'GRAVADO15', '1 kg',  false, false, false, false, 15, 20, 150),
  (16, 'LIM-0002', 'Papel higiénico 4 rollos',      7, 6, 1, 'GRAVADO15', '4 u',   false, false, false, false, 20, 30, 200);

insert into public.codigo_barras (codigo, id_producto, tipo, factor) values
  ('7421000000013', 1,  'EAN13', 1),
  ('7421000000020', 2,  'EAN13', 1),
  ('7421000000037', 3,  'EAN13', 1),
  ('7421000000044', 4,  'EAN13', 1),
  ('7421000000051', 5,  'EAN13', 1),
  ('7421000000068', 6,  'EAN13', 1),
  ('7421000000075', 7,  'EAN13', 1),
  ('7421000000082', 12, 'EAN13', 1),
  ('7421000000099', 13, 'EAN13', 1),
  ('7421000000105', 14, 'EAN13', 1),
  ('7421000000112', 14, 'EAN13', 12),      -- caja de 12 latas
  ('7421000000129', 15, 'EAN13', 1),
  ('7421000000136', 16, 'EAN13', 1),
  ('2000000000442', 8,  'INTERNO', 1),     -- pan sin código del fabricante
  ('201230',        10, 'PESO_VARIABLE', 1),
  ('201240',        11, 'PESO_VARIABLE', 1);

insert into public.codigo_barras (codigo, id_producto, tipo, factor, generado_por_sistema) values
  ('2000000000435', 9, 'INTERNO', 1, true);

insert into public.secuencia_codigo_interno (prefijo, ultimo_valor) values ('200', 44);

-- Precios generales (incluyen ISV) vigentes desde el 1 de septiembre.
insert into public.precio (id_producto, id_sucursal, precio_venta, vigente_desde, id_usuario_cambio) values
  (1, null, 32.00, '2026-09-01', 1), (2, null, 58.00, '2026-09-01', 1), (3, null, 75.00, '2026-09-01', 1),
  (4, null, 38.00, '2026-09-01', 1), (5, null, 42.00, '2026-09-01', 1), (6, null, 85.00, '2026-09-01', 1),
  (7, null, 110.00,'2026-09-01', 1), (8, null, 3.00,  '2026-09-01', 1), (9, null, 45.00, '2026-09-01', 1),
  (10,null, 18.00, '2026-09-01', 1), (11,null, 30.00, '2026-09-01', 1), (12,null, 38.00, '2026-09-01', 1),
  (13,null, 40.00, '2026-09-01', 1), (14,null, 30.00, '2026-09-01', 1), (15,null, 95.00, '2026-09-01', 1),
  (16,null, 72.00, '2026-09-01', 1);
-- Precio propio de la sucursal Sur para la leche (RF-CAT-03).
insert into public.precio (id_producto, id_sucursal, precio_venta, vigente_desde, id_usuario_cambio) values
  (1, 3, 31.00, '2026-09-01', 1);

insert into public.categoria_rapida (id_categoria_rapida, id_sucursal, nombre, color, icono, orden) values
  (1, 1, 'Panadería', '#F2A541', 'pan',    1),
  (2, 1, 'Frutas',    '#6BBF59', 'fruta',  2),
  (3, 1, 'Bebidas',   '#3B82F6', 'bebida', 3);

insert into public.boton_rapido (id_categoria_rapida, id_producto, orden) values
  (1, 8, 1), (1, 9, 2), (2, 10, 1), (2, 11, 2), (3, 12, 1), (3, 13, 2);

-- ---------------------------------------------------------------------
-- Facturación SAR (CAI FICTICIOS para pruebas)
-- ---------------------------------------------------------------------
insert into public.config_fiscal (id_empresa, rtn, razon_social, nombre_comercial, direccion_casa_matriz,
                                  telefono, correo, resolucion_autoimpresor, fecha_resolucion,
                                  permitir_ticket_no_fiscal, dias_canje_ticket, documento_por_defecto) values
  (1, '08019099000011', 'Supermercados Mercadito, S.A. de C.V.', 'Mercadito', 'Col. Centro, Tegucigalpa, M.D.C.',
   '2200-0000', 'facturacion@mercadito.example', 'RES-AUTO-0000-2026', '2026-01-15', true, 30, 'FACTURA_CF');

insert into public.tipo_documento_fiscal (codigo, nombre, afecta_libro_ventas) values
  ('01', 'Factura', true);

insert into public.establecimiento_sar (id_establecimiento, id_sucursal, codigo, direccion) values
  (1, 1, '000', 'Av. Principal, Col. Centro, Tegucigalpa'),
  (2, 2, '001', 'Bulevar Norte, Col. Kennedy, Tegucigalpa'),
  (3, 3, '002', 'Salida al Sur, Col. Las Hadas, Tegucigalpa');

insert into public.punto_emision (id_punto, id_establecimiento, id_caja, codigo) values
  (1, 1, 1, '001'), (2, 1, 2, '002'), (3, 1, 3, '003'),
  (4, 2, 4, '001'), (5, 2, 5, '002'),
  (6, 3, 6, '001');

insert into public.cai (id_cai, cai, id_punto, tipo_documento, fecha_autorizacion, correlativo_inicial, correlativo_final,
                        ultimo_usado, fecha_limite_emision, estado, id_usuario_registro) values
  (1, 'A1B2C3-000001-D4E5F6-000001-ABCDEF-01', 1, '01', '2026-09-15', 1,     10000, null,  '2026-12-31', 'ACTIVO',    1),
  (2, 'A1B2C3-000002-D4E5F6-000002-ABCDEF-02', 2, '01', '2026-09-15', 1,     10000, null,  '2026-12-31', 'ACTIVO',    1),
  -- El del ejemplo de los documentos: el siguiente número será 000-003-01-00012520.
  (3, '35BD6A-0195F4-B34BAA-8B7D6B-2E3A87-C3', 3, '01', '2026-09-15', 10001, 20000, 12519, '2026-12-31', 'ACTIVO',    1),
  (4, 'A1B2C3-000004-D4E5F6-000004-ABCDEF-04', 3, '01', '2026-10-01', 20001, 30000, null,  '2027-03-31', 'EN_ESPERA', 1),
  (5, 'A1B2C3-000005-D4E5F6-000005-ABCDEF-05', 4, '01', '2026-09-15', 1,     10000, null,  '2026-12-31', 'ACTIVO',    1),
  (6, 'A1B2C3-000006-D4E5F6-000006-ABCDEF-06', 5, '01', '2026-09-15', 1,     10000, null,  '2026-12-31', 'ACTIVO',    1),
  (7, 'A1B2C3-000007-D4E5F6-000007-ABCDEF-07', 6, '01', '2026-09-15', 1,     10000, null,  '2026-12-31', 'ACTIVO',    1);

-- ---------------------------------------------------------------------
-- Formas de pago, lealtad, clientes y proveedores
-- ---------------------------------------------------------------------
insert into public.forma_pago (id_forma_pago, clave, nombre) values
  (1, 'EFE', 'Efectivo'), (2, 'TDD', 'Tarjeta de débito'), (3, 'TDC', 'Tarjeta de crédito'),
  (4, 'QR', 'Pago con QR'), (5, 'VALE', 'Vale'), (6, 'PUNTOS', 'Puntos Mercadito');

insert into public.config_lealtad (id_empresa, lempiras_por_punto, meses_caducidad) values (1, 10, 12);

insert into public.cliente (id_cliente, nombre, telefono, correo, rtn, razon_social, consentimiento_datos) values
  (1, 'Cliente Demo Uno',    '99990001', 'cliente1@example.com', null,             null,                               true),
  (2, 'Cliente Demo Dos',    '99990002', null,                   null,             null,                               true),
  (3, 'Comercial Los Pinos', '99990003', 'compras@lospinos.example', '08019099887766', 'Comercial Los Pinos, S. de R.L.', true);

insert into public.proveedor (id_proveedor, razon_social, rtn, contacto, correo, telefono, dias_credito, tiempo_entrega_dias) values
  (1, 'Distribuidora Lácteos del Valle, S.A.', '08019088000011', 'Ventas', 'ventas@lacteosvalle.example', '2230-1000', 15, 2),
  (2, 'Granos y Abarrotes Copán, S.A.',        '08019088000022', 'Ventas', 'ventas@granoscopan.example',  '2230-2000', 30, 3),
  (3, 'Bebidas Tropical, S.A.',                '08019088000033', 'Ventas', 'ventas@tropical.example',     '2230-3000', 30, 2);

insert into public.producto_proveedor (id_producto, id_proveedor, codigo_proveedor, costo_pactado, empaque, principal) values
  (1, 1, 'LV-LE1', 24.00, 12, true), (2, 1, 'LV-YF1', 40.00, 6, true), (3, 1, 'LV-QF1', 55.00, 10, true),
  (4, 2, 'GC-AB2', 29.00, 25, true), (5, 2, 'GC-FR2', 32.00, 25, true),
  (12, 3, 'BT-CO2', 26.00, 8, true), (13, 3, 'BT-AG1', 28.00, 6, true);

-- Promociones de ejemplo: 2×1 en refresco y 10 % en lácteos.
insert into public.promocion (id_promocion, nombre, tipo, valor, n_compra, m_paga, inicio, fin, prioridad) values
  (1, '2×1 refresco cola 2 L', 'NxM',  null, 2, 1, '2026-10-01', '2026-10-31', 10),
  (2, '10 % en lácteos',       'PORC', 10,   null, null, '2026-10-01', '2026-10-31', 5);
insert into public.promocion_alcance (id_promocion, tipo_objetivo, id_objetivo) values
  (1, 'PRODUCTO', 12), (2, 'CATEGORIA', 1);

-- ---------------------------------------------------------------------
-- Reglas de alarma generales (doc 12 §4.2)
-- ---------------------------------------------------------------------
insert into public.regla_alarma (tipo, alcance, nivel, id_rol_responsable, dias) values
  ('SIN_EXISTENCIA', 'GENERAL', 'CRITICA',     7, null),
  ('NEGATIVA',       'GENERAL', 'CRITICA',     6, null),
  ('CADUCADO',       'GENERAL', 'CRITICA',     6, null),
  ('BAJO_MINIMO',    'GENERAL', 'ADVERTENCIA', 7, null),
  ('REORDEN',        'GENERAL', 'ADVERTENCIA', 7, null),
  ('POR_CADUCAR',    'GENERAL', 'ADVERTENCIA', 3, 7),
  ('SOBRE_MAXIMO',   'GENERAL', 'INFO',        7, null);

-- ---------------------------------------------------------------------
-- Inventario inicial: TODO entra por movimientos (así nace el kardex).
-- ---------------------------------------------------------------------
insert into public.lote (id_lote, id_producto, numero_lote, fecha_caducidad, fecha_recepcion) values
  (1, 2, 'YF-2609', '2026-10-12', '2026-09-20'),   -- por caducar: el proceso nocturno lo alarma
  (2, 2, 'YF-2610', '2026-11-15', '2026-10-01');

insert into public.movimiento_inventario (id_producto, id_almacen, id_lote, tipo, cantidad, costo_unitario, documento_origen, id_usuario, fecha)
select p.id_producto, a.id_almacen, null, 'INICIAL',
       case when p.id_producto = 9 and a.id_sucursal = 1 then 8          -- pan integral bajo el mínimo en Centro
            else round(p.stock_minimo * 3) end,
       pp.costo, 'carga-inicial', 1, '2026-09-01 07:00-06'
from public.producto p
join public.almacen a on a.tipo = 'PISO'
cross join lateral (values (case p.id_producto
    when 1 then 24.00 when 3 then 55.00 when 4 then 29.00 when 5 then 32.00 when 6 then 65.00
    when 7 then 85.00 when 8 then 1.60 when 9 then 28.00 when 10 then 10.00 when 11 then 17.00
    when 12 then 26.00 when 13 then 28.00 when 14 then 19.00 when 15 then 62.00 when 16 then 48.00 end)) as pp (costo)
where p.id_producto <> 2
order by p.id_producto, a.id_almacen;

insert into public.movimiento_inventario (id_producto, id_almacen, id_lote, tipo, cantidad, costo_unitario, documento_origen, id_usuario, fecha) values
  (2, 1, 1, 'INICIAL', 10, 40.00, 'carga-inicial', 1, '2026-09-20 07:00-06'),
  (2, 1, 2, 'INICIAL', 30, 40.00, 'carga-inicial', 1, '2026-10-01 07:00-06');

-- ---------------------------------------------------------------------
-- Las tablas con identidad recibieron ids explícitos: se mueven sus
-- secuencias para que el siguiente INSERT no choque.
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select c.table_name, c.column_name
    from information_schema.columns c
    where c.table_schema = 'public' and c.is_identity = 'YES'
  loop
    execute format(
      'select setval(pg_get_serial_sequence(%L, %L), coalesce((select max(%I) from public.%I), 0) + 1, false)',
      'public.' || r.table_name, r.column_name, r.column_name, r.table_name);
  end loop;
end $$;
