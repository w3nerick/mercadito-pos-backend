# Bitácora de uso de IA — Arquitectura de datos

Registro exigido por el doc 11 §15.2 (regla 4). Una entrada por sesión.

## 2026-10-08 · Esquema inicial, RLS, reportes y pruebas

| Campo | Detalle |
|---|---|
| Herramienta | Claude (Claude Code) |
| Qué se pidió | Analizar el PRD y generar, para la parte de arquitectura de datos: migraciones de Supabase del modelo completo, políticas RLS, trigger de existencias y kardex, vistas y funciones de reportes, datos semilla, contrato OpenAPI y pruebas automáticas |
| Qué se aceptó | 13 migraciones, semilla, 81 pruebas, `api/openapi.yaml`, documentación (`docs/`) |
| Qué se corrigió | **Errores que encontraron las pruebas:** (1) `reporte_ventas` devolvía `varchar` donde la función declaraba `text`; (2) el libro de ventas mostraba `0` sin decimales en facturas anuladas; (3) el reporte por cajero salía sin nombre porque el RLS de `usuario` ocultaba a los demás empleados → se creó `nombre_empleado()`; (4) una prueba se colgaba por consultar la base dentro de una transacción abierta. **Decisiones de diseño** donde los documentos se contradicen → `docs/decisiones.md` |
| Cómo se verificó | `npm test`: migraciones + semilla + 81 pruebas en Postgres real (PGlite). **Prueba de mutación**: se quitaron a propósito dos políticas RLS y el `security_invoker` de una vista; las pruebas fallaron en los tres casos (las pruebas sí detectan una política rota). Contrato validado con `redocly lint`. Las pruebas se corrieron en PostgreSQL 18 y 17.5; quedaron fijadas en **17** (la versión de Supabase) con una verificación que falla si cambia |
| Pendiente de verificar | Tasas de ISV y código SAR de la nota de crédito con el docente; aplicar con `supabase db push` en `mercadito-dev` |

### Lo que debo poder explicar en la defensa
- [ ] Por qué la existencia solo cambia por un trigger del kardex (y qué pasa con dos cajas a la vez).
- [ ] La fórmula del costo promedio y el ejemplo CP-KDX-02 (40.67).
- [ ] Por qué `tiene_permiso` es `SECURITY DEFINER` y fija `search_path`.
- [ ] Por qué las vistas son `security_invoker`.
- [ ] Por qué una venta no se puede insertar directo aunque el cajero tenga `VENTA_CREAR`.
- [ ] Cómo una restricción de exclusión impide precios con vigencias traslapadas.
- [ ] Cómo se reconstruye el saldo del kardex con una suma acumulada (`sum() over`).
- [ ] Las preguntas de práctica de [`docs/rls.md`](../rls.md#6-preguntas-de-práctica-para-la-defensa).
