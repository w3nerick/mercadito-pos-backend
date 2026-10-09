# Decisiones de diseño del modelo de datos

Los documentos del PRD se escribieron en momentos distintos y algunos se contradicen.
Aquí queda **qué se decidió y por qué**. Cada decisión va al comité técnico (líderes de
Front-end, Backend y QA) para su visto bueno, como pide el doc 11 §2.

| # | Tema | Conflicto en los documentos | Decisión | Por qué |
|---|---|---|---|---|
| D-01 | Usuarios | El doc 05 guarda `hash_contrasena` en `USUARIO`; el doc 10 usa `auth.users` | La contraseña la maneja **Supabase Auth**. `usuario.auth_user_id` apunta a `auth.users(id)` | No reinventar el manejo de contraseñas; Auth ya da JWT, expiración y recuperación |
| D-02 | CAI y factura | El doc 05 trae una versión vieja de `CAI` y una tabla `FACTURA` | Se usa el modelo del **doc 09** (`cai.ultimo_usado`, estados, `documento_fiscal`, `doc_fiscal_total`) | El doc 09 es el detallado y el doc 05 dice que lo reemplaza |
| D-03 | Impuestos | El doc 05 tiene `IMPUESTO` y `PRODUCTO_IMPUESTO` (traslado / retención) | Se reemplazan por `clasificacion_fiscal` (EXENTO, GRAVADO15, GRAVADO18) | En Honduras el ISV depende de la clasificación del producto (doc 09 §5) |
| D-04 | Existencia sin lote | El doc 05 usa `id_lote = 0` cuando el producto no controla lote | `id_lote` **nulo** + `unique nulls not distinct` | Un `0` rompe la llave foránea hacia `lote` |
| D-05 | Permisos | `ROL_PERMISO` trae banderas ver/crear/editar…, pero `tiene_permiso(clave, sucursal)` solo recibe la clave | Cada permiso es una **clave granular** (`VENTA_CREAR`, `VENTA_CANCELAR`…). Tener la fila = tener el permiso. Se conserva `puede_autorizar` (la "A" de la matriz) | Una sola forma de preguntar; la matriz del doc 10 §5 ya está en claves |
| D-06 | Emisión del documento | `POST /ventas` incluye el documento y además existe `POST /ventas/{id}/documento` | La venta y su factura/ticket se guardan **en la misma transacción** (función `registrar_venta`, módulo de negocio). La segunda ruta queda para canje de ticket y reimpresión | Si la venta se guarda y la factura falla, quedaría una venta sin respaldo o un correlativo perdido |
| D-07 | Transacciones | Supabase-js no permite transacciones de varias sentencias | Toda operación de varias tablas (venta, recepción, ajuste aplicado, cambio de precio) es **una función de Postgres** que la API llama por RPC | Es la única forma de que sea todo o nada |
| D-08 | Kardex y existencia | El doc 05 dice que la existencia "se concilia con un proceso nocturno" | La existencia la mantiene un **trigger** sobre `movimiento_inventario` en la misma transacción | Nunca se separan; la conciliación nocturna deja de ser necesaria |
| D-09 | Costo promedio | No se dice si es global o por almacén | **Global por producto** (`producto.costo_promedio`), como dice el doc 05 | Es lo que pide RN-14 y lo que valúa el inventario |
| D-10 | Partición mensual | El doc 05 §7 pide particionar `VENTA` por mes | **No se particiona** en esta versión | Postgres exige la columna de partición en la llave primaria (UUID); con ≈660 mil ventas/año los índices bastan |
| D-11 | Réplica de lectura | ADR-04 pide réplica para reportes | Se usan **vistas y funciones SQL** sobre la base principal | El plan gratuito de Supabase no tiene réplicas |
| D-12 | Totales de la venta | — | `total = subtotal − descuento`; el ISV **ya viene incluido** en el precio | El ejemplo del doc 06 §5.3.2 cuadra así (518.30 − 49.90 = 468.40) |
| D-13 | Escrituras transaccionales | — | Ventas, caja, documentos, kardex y puntos **no tienen política de INSERT/UPDATE**: solo se escriben por funciones `SECURITY DEFINER` que validan reglas y permisos | Nadie se salta una regla de negocio con un INSERT desde el navegador |
| D-14 | Permisos nuevos | El doc 06 usa `VENTA_VER` y la configuración no tiene permiso propio | Se agregan `VENTA_VER` y `CONFIG_EDITAR` al catálogo | El doc 10 §4 dice que su lista es un "extracto" |
| D-15 | Precio general | — | Un precio sin sucursal exige `PRECIO_EDITAR` en un rol con alcance **TODAS** (`tiene_permiso_global`) | Un gerente de sucursal no debe cambiar el precio de las demás |
| D-16 | Movimiento VENTA en negativo | — | El trigger **permite** que una venta deje existencia negativa (y genera alarma); ajustes, mermas, transferencias y devoluciones a proveedor **no** | RN-02 / RN-22: la venta sin existencia se autoriza en caja; lo demás debe validar (RF-EXI-05) |

## Pendiente de confirmar con el docente

- **Código SAR de la nota de crédito.** El doc 09 solo dice "01 = Factura, otros según SAR". La semilla solo trae `01`.
- **Tasas de ISV** (15 % y 18 %) y qué productos son exentos: se tomaron de los documentos; validarlas con fuente oficial (doc 11 §15.2 regla 6).
