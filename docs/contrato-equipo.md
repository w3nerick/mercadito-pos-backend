# Contrato con el resto del equipo

Qué ofrece la base de datos y qué debe respetar cada integrante que la use.
Cualquier cambio a este contrato pasa por un PR con revisión de la arquitectura de datos (doc 11 §13).

## 1. Para el módulo de negocio y SAR (ventas, caja, inventario, compras, promociones, facturación)

### Reglas de oro
1. **Una operación de varias tablas = una función de Postgres.** Supabase-js no tiene transacciones; si la venta
   se guarda en una llamada y la factura en otra, un fallo intermedio deja datos a medias o un correlativo perdido.
2. **Las funciones que escriben en tablas transaccionales son `SECURITY DEFINER`** (esas tablas no tienen
   política de escritura). Por eso cada función debe:
   - empezar con `set search_path = ''` y nombres calificados (`public.venta`);
   - validar el permiso: `if not public.tiene_permiso('VENTA_CREAR', v_id_sucursal) then raise exception ... using errcode = '42501'; end if;`
   - tomar el usuario con `public.usuario_actual_id()` (nunca de un parámetro).
3. **Nunca actualizar `existencia` ni `producto.costo_promedio`.** Se inserta un renglón en
   `movimiento_inventario` y el trigger hace el resto:

```sql
insert into public.movimiento_inventario (id_producto, id_almacen, id_lote, tipo, cantidad, costo_unitario, documento_origen)
values (101, 1, null, 'VENTA', -3, null, 'venta:6f1c2a3e-...');   -- salida: cantidad negativa, costo lo pone el trigger
```

| Columna | Quién la llena |
|---|---|
| `cantidad` | Usted, con signo: **+ entrada, − salida** (el CHECK valida el signo según el tipo) |
| `costo_unitario` | Usted en entradas (`COMPRA`: costo de la factura del proveedor). En salidas déjelo nulo: el trigger usa el costo promedio |
| `id_sucursal`, `existencia_resultante`, `costo_promedio_resultante` | El trigger |
| `id_usuario` | El trigger, si no lo manda (toma `usuario_actual_id()`) |
| `documento_origen` | Usted: `venta:<uuid>`, `recepcion:<id>`, `ajuste:<id>`, `devolucion:<id>`, `transferencia:<id>` |

Tipos: `INICIAL`, `COMPRA`, `VENTA`, `CANCEL_VENTA`, `DEVOL_CLI`, `DEVOL_PROV`, `AJUSTE` (±), `MERMA`, `TRANSF_SAL`, `TRANSF_ENT`.

4. **Errores que lanza la base** (la API los traduce al formato del doc 06 §5.4):

| Señal en Postgres | Significa | HTTP sugerido |
|---|---|---|
| `HINT = 'EXISTENCIA_INSUFICIENTE'` | Ajuste/merma/transferencia/devolución a proveedor mayor a lo que hay | 422 |
| `HINT = 'SOLO_INSERCION'` | Se intentó modificar o borrar kardex, bitácora, puntos o un documento fiscal | 409 |
| `errcode 42501` o "row-level security" | Sin permiso | 403 |
| `errcode 23505` (unique) | Duplicado (folio, código de barras, correlativo, teléfono) | 409 |
| `errcode 23P01` (exclusion) | Vigencia de precio o rango de CAI traslapado | 409 |
| `errcode 23514` (check) | Dato fuera de regla (RTN, EAN-13, totales que no cuadran) | 422 |

### Lo que la base ya garantiza (no hace falta reprogramarlo)
- Venta: `total = subtotal − descuento`; `importe` de la línea = `round(cantidad × precio − descuento, 2)`; una venta cancelada exige autorizador ≠ cajero.
- Documento fiscal: el total cuadra con exento + exonerado + gravados + ISV; un correlativo no se repite por CAI; no se borra; anular exige motivo y usuario; un anulado no vuelve a vigente.
- CAI: formato válido, rango sin traslape por punto y tipo, un solo `ACTIVO` por punto y tipo, `ultimo_usado` dentro del rango.
- Turno: uno abierto por caja. Corte: con diferencia exige justificación; un solo corte Z por turno.
- Ticket: no puede tener formato de número fiscal; se canjea una sola vez.

### Funciones que faltan y le corresponden
| Función | Notas |
|---|---|
| `registrar_venta(jsonb)` | Contrato `POST /ventas` (doc 06 §5.3.2). Idempotente por `id_venta`. Dentro: venta, líneas, pagos, movimientos `VENTA`, documento (correlativo o ticket) y puntos (`calcular_puntos`) |
| `siguiente_correlativo(id_punto, tipo)` | `update public.cai set ultimo_usado = coalesce(ultimo_usado, correlativo_inicial - 1) + 1 where ... and estado = 'ACTIVO' and coalesce(ultimo_usado, correlativo_inicial - 1) < correlativo_final and fecha_limite_emision >= public.hoy_honduras() returning ultimo_usado` — el `UPDATE` bloquea la fila: dos cajas no obtienen el mismo número. Si no devuelve fila → `CAI_VENCIDO` / `CAI_AGOTADO` y activar el CAI `EN_ESPERA` |
| `generar_codigo_interno()` | `select ultimo_valor ... for update` en `secuencia_codigo_interno`, y `public.ean13_digito_verificador()` para el último dígito |
| Recepción, aplicar ajuste, devolución, corte | Insertan movimientos y registros; el kardex se encarga de existencias y costo |

## 2. Para seguridad, sincronización y DevOps

- Firma acordada: `public.tiene_permiso(p_clave text, p_id_sucursal bigint default null) returns boolean`. Si se cambia su lógica (horario de acceso, etc.), **no cambiar la firma**: la usan todas las políticas.
- Enlazar una cuenta de Auth con un empleado: `update public.usuario set auth_user_id = '<uuid>' where usuario = 'cajero.centro';`
- La API reenvía el JWT del usuario a Supabase. `service_role` solo para cron, migraciones y mantenimiento.
- `pg_cron` debe estar habilitado en cada proyecto (Database → Extensions) antes de `supabase db push`, o la migración 1300 solo avisará que no pudo programar la tarea.
- CI: `npm test` levanta Postgres en memoria (PGlite) y corre las migraciones, la semilla y las pruebas; no necesita Docker ni llaves.

## 3. Para Front-end (back-office, POS y dashboard)

Cada pantalla tiene su ruta en [`api/openapi.yaml`](../api/openapi.yaml). El campo `x-implementacion` dice qué
función o vista de Supabase la resuelve, por si se llama directo con `supabase.rpc(...)` / `supabase.from(...)`
mientras la API no está lista.

| Pantalla | Objeto en Supabase |
|---|---|
| Caja: escanear | `rpc('producto_por_codigo', { p_codigo, p_id_sucursal })` |
| Caja: buscar (F2) | `rpc('buscar_productos', { p_buscar, p_id_sucursal })` |
| Caja: validar existencia | `rpc('existencia_disponible', { p_id_producto, p_id_sucursal })` |
| Inventario | `from('v_existencias')`, `from('v_existencias_detalle')` |
| Kardex | `rpc('kardex', {...})` + `rpc('kardex_resumen', {...})` |
| Centro de alarmas | `from('v_alarmas')`, `rpc('atender_alarma', {...})` |
| Clientes | `from('v_clientes')`, `from('v_movimientos_puntos')` |
| Productos: margen | `from('v_margen_productos')` |
| Reportes | `rpc('reporte_ventas', {...})`, `from('v_ventas_por_dia')` |
| Dashboard | `rpc('kpis_dashboard', { p_id_sucursal })` |
| Libro de ventas | `rpc('libro_ventas', { p_mes })`, `rpc('resumen_isv', { p_mes })`, `from('v_ventas_sin_factura')` |

Para tiempo real: suscribirse a `alarma` y `venta` con Supabase Realtime (el RLS también filtra los eventos).

## 4. Para QA

- `npm test` corre **81 pruebas** contra una base real: PostgreSQL 17.5 en WASM, la misma versión mayor que Supabase (migraciones + semilla + reglas + RLS).
- Los nombres de las pruebas llevan el ID del caso cuando existe (`CP-KDX-01`, `CP-EXI-02`, `CP-ALM-01`, `CP-COD-02`…).
- Usuarios de demostración (sin contraseña; se enlazan con Auth): `admin.ti`, `gerente.general`, `gerente.centro`,
  `supervisor.centro`, `cajero.centro`, `cajero.norte`, `almacen.centro`, `compras`, `contador`, `auditor`.
