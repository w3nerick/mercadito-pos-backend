-- =====================================================================
-- 1100 · Row Level Security (doc 10 §9.1)
--
-- Principios (explicados uno por uno en docs/rls.md):
--  1. RLS activo en TODAS las tablas de public. Sin política = sin acceso.
--  2. anon (sin sesión) no ve nada.
--  3. Lectura por permiso y por sucursal con tiene_permiso(clave, sucursal).
--  4. Tablas hijas (líneas, pagos...) heredan la visibilidad del padre con
--     EXISTS sobre el padre, que a su vez pasa por su propio RLS.
--  5. Tablas transaccionales (ventas, caja, documentos, kardex, puntos) NO
--     se escriben directo: solo por funciones SECURITY DEFINER que validan
--     reglas de negocio y permisos. Así nadie se salta una regla con un
--     INSERT desde el navegador.
--  6. La llave service_role se salta el RLS: solo se usa en procesos del
--     servidor (cron, migraciones), nunca para atender a un usuario.
-- =====================================================================

-- Permiso con alcance de empresa (rol con alcance TODAS). Se usa para lo
-- que afecta a todas las sucursales, como el precio general.
create or replace function public.tiene_permiso_global(p_clave text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.usuario u
    join public.usuario_rol ur on ur.id_usuario = u.id_usuario
    join public.rol r          on r.id_rol = ur.id_rol and r.activo and r.alcance = 'TODAS'
    join public.rol_permiso rp on rp.id_rol = r.id_rol
    join public.permiso p      on p.id_permiso = rp.id_permiso
    where u.auth_user_id = auth.uid() and u.activo
      and (u.bloqueado_hasta is null or u.bloqueado_hasta < now())
      and p.clave = p_clave
      and ur.vigente_desde <= current_date
      and (ur.vigente_hasta is null or ur.vigente_hasta >= current_date)
  )
$$;

-- Sucursal de un almacén (atajo para políticas de inventario).
create or replace function public.sucursal_de_almacen(p_id_almacen bigint)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$ select id_sucursal from public.almacen where id_almacen = p_id_almacen $$;

create or replace function public.sucursal_de_caja(p_id_caja bigint)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$ select id_sucursal from public.caja where id_caja = p_id_caja $$;

-- ---------------------------------------------------------------------
-- 1 y 2. Activar RLS en todo y cerrar la puerta a anon
-- ---------------------------------------------------------------------
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    -- Sin FORCE: el dueño de las tablas (postgres) no queda sujeto al RLS,
    -- y es con quien corren los triggers y funciones SECURITY DEFINER.
    execute format('alter table public.%I enable row level security', t.tablename);
  end loop;
end $$;

revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;

-- Funciones internas: solo las ejecutan triggers, cron o funciones definer.
revoke execute on function public.sincronizar_alarma(text, bigint, bigint, bigint, boolean, numeric, text) from public, anon, authenticated;
revoke execute on function public.evaluar_alarmas_existencia(bigint, bigint, text) from public, anon, authenticated;
revoke execute on function public.evaluar_alarmas_caducidad(date) from public, anon, authenticated;

-- =====================================================================
-- Organización
-- =====================================================================
create policy empresa_leer on public.empresa for select to authenticated
  using (public.usuario_actual_id() is not null);
create policy empresa_editar on public.empresa for update to authenticated
  using (public.tiene_permiso_global('CONFIG_EDITAR'));

create policy sucursal_leer on public.sucursal for select to authenticated
  using (public.usuario_actual_id() is not null);
create policy sucursal_crear on public.sucursal for insert to authenticated
  with check (public.tiene_permiso_global('CONFIG_EDITAR'));
create policy sucursal_editar on public.sucursal for update to authenticated
  using (public.tiene_permiso('CONFIG_EDITAR', id_sucursal));

create policy caja_leer on public.caja for select to authenticated
  using (public.usuario_actual_id() is not null);
create policy caja_crear on public.caja for insert to authenticated
  with check (public.tiene_permiso('CONFIG_EDITAR', id_sucursal));
create policy caja_editar on public.caja for update to authenticated
  using (public.tiene_permiso('CONFIG_EDITAR', id_sucursal));

create policy almacen_leer on public.almacen for select to authenticated
  using (public.usuario_actual_id() is not null);
create policy almacen_crear on public.almacen for insert to authenticated
  with check (public.tiene_permiso('CONFIG_EDITAR', id_sucursal));
create policy almacen_editar on public.almacen for update to authenticated
  using (public.tiene_permiso('CONFIG_EDITAR', id_sucursal));

-- =====================================================================
-- Seguridad
-- =====================================================================
create policy usuario_leer on public.usuario for select to authenticated
  using (auth_user_id = auth.uid() or public.tiene_permiso('USUARIOS_ADMIN'));
create policy usuario_crear on public.usuario for insert to authenticated
  with check (public.tiene_permiso('USUARIOS_ADMIN'));
create policy usuario_editar on public.usuario for update to authenticated
  using (public.tiene_permiso('USUARIOS_ADMIN'));

create policy rol_leer on public.rol for select to authenticated
  using (public.usuario_actual_id() is not null);
create policy rol_crear on public.rol for insert to authenticated
  with check (public.tiene_permiso('ROLES_ADMIN'));
create policy rol_editar on public.rol for update to authenticated
  using (public.tiene_permiso('ROLES_ADMIN'));

create policy permiso_leer on public.permiso for select to authenticated
  using (public.usuario_actual_id() is not null);

-- RN-ROL-02: nadie modifica la matriz de un rol que él mismo tiene.
create policy rol_permiso_leer on public.rol_permiso for select to authenticated
  using (public.usuario_actual_id() is not null);
create policy rol_permiso_crear on public.rol_permiso for insert to authenticated
  with check (public.tiene_permiso('ROLES_ADMIN')
              and not exists (select 1 from public.usuario_rol ur
                              where ur.id_rol = rol_permiso.id_rol and ur.id_usuario = public.usuario_actual_id()));
create policy rol_permiso_editar on public.rol_permiso for update to authenticated
  using (public.tiene_permiso('ROLES_ADMIN')
         and not exists (select 1 from public.usuario_rol ur
                         where ur.id_rol = rol_permiso.id_rol and ur.id_usuario = public.usuario_actual_id()));
create policy rol_permiso_borrar on public.rol_permiso for delete to authenticated
  using (public.tiene_permiso('ROLES_ADMIN')
         and not exists (select 1 from public.usuario_rol ur
                         where ur.id_rol = rol_permiso.id_rol and ur.id_usuario = public.usuario_actual_id()));

create policy rol_limite_leer on public.rol_limite for select to authenticated
  using (public.usuario_actual_id() is not null);
create policy rol_limite_escribir on public.rol_limite for all to authenticated
  using (public.tiene_permiso('ROLES_ADMIN')) with check (public.tiene_permiso('ROLES_ADMIN'));

-- RN-ROL-02: nadie se asigna ni se quita roles a sí mismo.
create policy usuario_rol_leer on public.usuario_rol for select to authenticated
  using (id_usuario = public.usuario_actual_id() or public.tiene_permiso('USUARIOS_ADMIN'));
create policy usuario_rol_escribir on public.usuario_rol for all to authenticated
  using (public.tiene_permiso('USUARIOS_ADMIN') and id_usuario <> public.usuario_actual_id())
  with check (public.tiene_permiso('USUARIOS_ADMIN') and id_usuario <> public.usuario_actual_id());

create policy usuario_sucursal_leer on public.usuario_sucursal for select to authenticated
  using (id_usuario = public.usuario_actual_id() or public.tiene_permiso('USUARIOS_ADMIN'));
create policy usuario_sucursal_escribir on public.usuario_sucursal for all to authenticated
  using (public.tiene_permiso('USUARIOS_ADMIN') and id_usuario <> public.usuario_actual_id())
  with check (public.tiene_permiso('USUARIOS_ADMIN') and id_usuario <> public.usuario_actual_id());

create policy regla_segregacion_leer on public.regla_segregacion for select to authenticated
  using (public.usuario_actual_id() is not null);
create policy regla_segregacion_escribir on public.regla_segregacion for all to authenticated
  using (public.tiene_permiso('ROLES_ADMIN')) with check (public.tiene_permiso('ROLES_ADMIN'));

create policy autorizacion_leer on public.autorizacion for select to authenticated
  using (public.tiene_permiso('BITACORA_VER') or id_solicitante = public.usuario_actual_id());

-- RN-18: cualquiera registra SUS acciones; leer exige BITACORA_VER; nadie
-- actualiza ni borra (no hay política, y además el trigger lo impide).
create policy bitacora_insertar on public.bitacora_auditoria for insert to authenticated
  with check (id_usuario = public.usuario_actual_id());
create policy bitacora_leer on public.bitacora_auditoria for select to authenticated
  using (public.tiene_permiso('BITACORA_VER'));

-- =====================================================================
-- Catálogo y precios
-- =====================================================================
create policy clasificacion_fiscal_leer on public.clasificacion_fiscal for select to authenticated
  using (public.usuario_actual_id() is not null);
create policy clasificacion_fiscal_escribir on public.clasificacion_fiscal for update to authenticated
  using (public.tiene_permiso('SAR_CONFIGURAR'));

do $$
declare t text;
begin
  -- Tablas de catálogo global: se leen con CATALOGO_VER y se editan con CATALOGO_EDITAR.
  foreach t in array array['categoria', 'marca', 'unidad_medida', 'producto', 'codigo_barras'] loop
    execute format($f$
      create policy %1$s_leer on public.%1$I for select to authenticated
        using (public.tiene_permiso('CATALOGO_VER'));
      create policy %1$s_crear on public.%1$I for insert to authenticated
        with check (public.tiene_permiso('CATALOGO_EDITAR'));
      create policy %1$s_editar on public.%1$I for update to authenticated
        using (public.tiene_permiso('CATALOGO_EDITAR'));
    $f$, t);
  end loop;
end $$;

-- Precio de sucursal: PRECIO_EDITAR en esa sucursal. Precio general (sin
-- sucursal): PRECIO_EDITAR con alcance de empresa. El historial no se borra.
create policy precio_leer on public.precio for select to authenticated
  using (public.tiene_permiso('CATALOGO_VER'));
create policy precio_crear on public.precio for insert to authenticated
  with check (case when id_sucursal is null then public.tiene_permiso_global('PRECIO_EDITAR')
                   else public.tiene_permiso('PRECIO_EDITAR', id_sucursal) end
              and id_usuario_cambio = public.usuario_actual_id());
create policy precio_cerrar on public.precio for update to authenticated
  using (case when id_sucursal is null then public.tiene_permiso_global('PRECIO_EDITAR')
              else public.tiene_permiso('PRECIO_EDITAR', id_sucursal) end);

-- secuencia_codigo_interno: sin políticas; solo la usa generar_codigo_interno() (definer).

create policy categoria_rapida_leer on public.categoria_rapida for select to authenticated
  using (public.tiene_permiso('CATALOGO_VER', id_sucursal));
create policy categoria_rapida_escribir on public.categoria_rapida for all to authenticated
  using (public.tiene_permiso('CATALOGO_EDITAR', id_sucursal))
  with check (public.tiene_permiso('CATALOGO_EDITAR', id_sucursal));

create policy boton_rapido_leer on public.boton_rapido for select to authenticated
  using (exists (select 1 from public.categoria_rapida c where c.id_categoria_rapida = boton_rapido.id_categoria_rapida));
create policy boton_rapido_escribir on public.boton_rapido for all to authenticated
  using (exists (select 1 from public.categoria_rapida c
                 where c.id_categoria_rapida = boton_rapido.id_categoria_rapida
                   and public.tiene_permiso('CATALOGO_EDITAR', c.id_sucursal)))
  with check (exists (select 1 from public.categoria_rapida c
                      where c.id_categoria_rapida = boton_rapido.id_categoria_rapida
                        and public.tiene_permiso('CATALOGO_EDITAR', c.id_sucursal)));

create policy etiqueta_cola_leer on public.etiqueta_cola for select to authenticated
  using (public.tiene_permiso('CATALOGO_VER'));
create policy etiqueta_cola_crear on public.etiqueta_cola for insert to authenticated
  with check (public.tiene_permiso('ETIQUETAS_IMPRIMIR') or public.tiene_permiso('CATALOGO_EDITAR'));
create policy etiqueta_cola_editar on public.etiqueta_cola for update to authenticated
  using (public.tiene_permiso('ETIQUETAS_IMPRIMIR'));

-- =====================================================================
-- Facturación SAR (estructura)
-- =====================================================================
create policy config_fiscal_leer on public.config_fiscal for select to authenticated
  using (public.usuario_actual_id() is not null);
create policy config_fiscal_escribir on public.config_fiscal for all to authenticated
  using (public.tiene_permiso('SAR_CONFIGURAR')) with check (public.tiene_permiso('SAR_CONFIGURAR'));

create policy tipo_documento_leer on public.tipo_documento_fiscal for select to authenticated
  using (public.usuario_actual_id() is not null);
create policy tipo_documento_escribir on public.tipo_documento_fiscal for all to authenticated
  using (public.tiene_permiso('SAR_CONFIGURAR')) with check (public.tiene_permiso('SAR_CONFIGURAR'));

create policy establecimiento_leer on public.establecimiento_sar for select to authenticated
  using (public.usuario_actual_id() is not null);
create policy establecimiento_escribir on public.establecimiento_sar for all to authenticated
  using (public.tiene_permiso('SAR_CONFIGURAR')) with check (public.tiene_permiso('SAR_CONFIGURAR'));

create policy punto_emision_leer on public.punto_emision for select to authenticated
  using (public.usuario_actual_id() is not null);
create policy punto_emision_escribir on public.punto_emision for all to authenticated
  using (public.tiene_permiso('SAR_CONFIGURAR')) with check (public.tiene_permiso('SAR_CONFIGURAR'));

-- CAI: lo ve contabilidad (SAR_VER) y la caja de esa sucursal; solo SAR_CONFIGURAR lo registra.
create policy cai_leer on public.cai for select to authenticated
  using (public.tiene_permiso('SAR_VER')
         or exists (select 1 from public.punto_emision pe
                    join public.establecimiento_sar e on e.id_establecimiento = pe.id_establecimiento
                    where pe.id_punto = cai.id_punto and public.tiene_permiso('VENTA_CREAR', e.id_sucursal)));
create policy cai_crear on public.cai for insert to authenticated
  with check (public.tiene_permiso('SAR_CONFIGURAR'));
create policy cai_editar on public.cai for update to authenticated
  using (public.tiene_permiso('SAR_CONFIGURAR'));

create policy bloque_correlativo_leer on public.bloque_correlativo for select to authenticated
  using (public.tiene_permiso('SAR_VER'));

-- =====================================================================
-- Inventario: lectura por sucursal; existencias y kardex solo por trigger
-- =====================================================================
create policy lote_leer on public.lote for select to authenticated
  using (public.tiene_permiso('INVENTARIO_VER') or public.tiene_permiso('VENTA_CREAR'));
create policy lote_crear on public.lote for insert to authenticated
  with check (public.tiene_permiso('RECEPCION_CREAR') or public.tiene_permiso('INVENTARIO_AJUSTAR'));

create policy existencia_leer on public.existencia for select to authenticated
  using (public.tiene_permiso('INVENTARIO_VER', public.sucursal_de_almacen(id_almacen))
         or public.tiene_permiso('VENTA_CREAR', public.sucursal_de_almacen(id_almacen)));

create policy movimiento_leer on public.movimiento_inventario for select to authenticated
  using (public.tiene_permiso('INVENTARIO_VER', id_sucursal));

create policy ajuste_leer on public.ajuste_inventario for select to authenticated
  using (public.tiene_permiso('INVENTARIO_VER', public.sucursal_de_almacen(id_almacen)));
create policy ajuste_crear on public.ajuste_inventario for insert to authenticated
  with check (public.tiene_permiso('INVENTARIO_AJUSTAR', public.sucursal_de_almacen(id_almacen))
              and id_usuario = public.usuario_actual_id() and estado = 'PENDIENTE');

create policy ajuste_detalle_leer on public.ajuste_detalle for select to authenticated
  using (exists (select 1 from public.ajuste_inventario a where a.id_ajuste = ajuste_detalle.id_ajuste));
create policy ajuste_detalle_crear on public.ajuste_detalle for insert to authenticated
  with check (exists (select 1 from public.ajuste_inventario a
                      where a.id_ajuste = ajuste_detalle.id_ajuste and a.estado = 'PENDIENTE'
                        and a.id_usuario = public.usuario_actual_id()));

create policy transferencia_leer on public.transferencia for select to authenticated
  using (public.tiene_permiso('INVENTARIO_VER', public.sucursal_de_almacen(id_almacen_origen))
         or public.tiene_permiso('INVENTARIO_VER', public.sucursal_de_almacen(id_almacen_destino)));
create policy transferencia_detalle_leer on public.transferencia_detalle for select to authenticated
  using (exists (select 1 from public.transferencia t where t.id_transferencia = transferencia_detalle.id_transferencia));

create policy conteo_leer on public.conteo_fisico for select to authenticated
  using (public.tiene_permiso('INVENTARIO_VER', public.sucursal_de_almacen(id_almacen)));
create policy conteo_detalle_leer on public.conteo_detalle for select to authenticated
  using (exists (select 1 from public.conteo_fisico c where c.id_conteo = conteo_detalle.id_conteo));

-- =====================================================================
-- Compras y proveedores
-- =====================================================================
create policy proveedor_leer on public.proveedor for select to authenticated
  using (public.tiene_permiso('COMPRAS_VER'));
create policy proveedor_crear on public.proveedor for insert to authenticated
  with check (public.tiene_permiso('COMPRAS_CREAR'));
create policy proveedor_editar on public.proveedor for update to authenticated
  using (public.tiene_permiso('COMPRAS_CREAR'));

create policy producto_proveedor_leer on public.producto_proveedor for select to authenticated
  using (public.tiene_permiso('COMPRAS_VER'));
create policy producto_proveedor_escribir on public.producto_proveedor for all to authenticated
  using (public.tiene_permiso('COMPRAS_CREAR')) with check (public.tiene_permiso('COMPRAS_CREAR'));

create policy orden_compra_leer on public.orden_compra for select to authenticated
  using (public.tiene_permiso('COMPRAS_VER', id_sucursal));
create policy oc_detalle_leer on public.oc_detalle for select to authenticated
  using (exists (select 1 from public.orden_compra o where o.id_oc = oc_detalle.id_oc));

create policy recepcion_leer on public.recepcion for select to authenticated
  using (public.tiene_permiso('COMPRAS_VER', public.sucursal_de_almacen(id_almacen))
         or public.tiene_permiso('RECEPCION_CREAR', public.sucursal_de_almacen(id_almacen)));
create policy recepcion_detalle_leer on public.recepcion_detalle for select to authenticated
  using (exists (select 1 from public.recepcion r where r.id_recepcion = recepcion_detalle.id_recepcion));

create policy cxp_leer on public.cuenta_por_pagar for select to authenticated
  using (public.tiene_permiso('COMPRAS_VER'));
create policy pago_proveedor_leer on public.pago_proveedor for select to authenticated
  using (public.tiene_permiso('COMPRAS_VER'));

-- =====================================================================
-- Clientes y lealtad
-- =====================================================================
create policy cliente_leer on public.cliente for select to authenticated
  using (public.tiene_permiso('CLIENTE_VER'));
create policy cliente_crear on public.cliente for insert to authenticated
  with check (public.tiene_permiso('CLIENTE_CREAR'));
-- Cambiar o borrar datos personales (ARCO) exige un permiso aparte.
create policy cliente_editar on public.cliente for update to authenticated
  using (public.tiene_permiso('CLIENTE_DATOS_PERSONALES'));

create policy config_lealtad_leer on public.config_lealtad for select to authenticated
  using (public.usuario_actual_id() is not null);
create policy config_lealtad_editar on public.config_lealtad for update to authenticated
  using (public.tiene_permiso_global('CONFIG_EDITAR'));

create policy cuenta_lealtad_leer on public.cuenta_lealtad for select to authenticated
  using (public.tiene_permiso('CLIENTE_VER'));
create policy movimiento_puntos_leer on public.movimiento_puntos for select to authenticated
  using (public.tiene_permiso('CLIENTE_VER'));

create policy promocion_leer on public.promocion for select to authenticated
  using (public.tiene_permiso('CATALOGO_VER'));
create policy promocion_escribir on public.promocion for all to authenticated
  using (public.tiene_permiso('PROMO_EDITAR')) with check (public.tiene_permiso('PROMO_EDITAR'));
create policy promocion_alcance_leer on public.promocion_alcance for select to authenticated
  using (public.tiene_permiso('CATALOGO_VER'));
create policy promocion_alcance_escribir on public.promocion_alcance for all to authenticated
  using (public.tiene_permiso('PROMO_EDITAR')) with check (public.tiene_permiso('PROMO_EDITAR'));

-- =====================================================================
-- Caja, ventas y documentos: solo lectura (las escrituras son por funciones)
-- =====================================================================
create policy forma_pago_leer on public.forma_pago for select to authenticated
  using (public.usuario_actual_id() is not null);

create policy turno_leer on public.turno_caja for select to authenticated
  using (id_usuario = public.usuario_actual_id()
         or public.tiene_permiso('CAJA_CORTE', public.sucursal_de_caja(id_caja))
         or public.tiene_permiso('REPORTES_VER', public.sucursal_de_caja(id_caja)));
create policy movimiento_caja_leer on public.movimiento_caja for select to authenticated
  using (exists (select 1 from public.turno_caja t where t.id_turno = movimiento_caja.id_turno));
create policy corte_leer on public.corte_caja for select to authenticated
  using (exists (select 1 from public.turno_caja t where t.id_turno = corte_caja.id_turno));
create policy corte_denominacion_leer on public.corte_denominacion for select to authenticated
  using (exists (select 1 from public.corte_caja c where c.id_corte = corte_denominacion.id_corte));

-- Ventas: el cajero ve las suyas; con VENTA_VER, las de sus sucursales.
create policy venta_leer on public.venta for select to authenticated
  using (id_usuario = public.usuario_actual_id()
         or public.tiene_permiso('VENTA_VER', id_sucursal)
         or public.tiene_permiso('REPORTES_VER', id_sucursal));
create policy venta_linea_leer on public.venta_linea for select to authenticated
  using (exists (select 1 from public.venta v where v.id_venta = venta_linea.id_venta));
create policy pago_leer on public.pago for select to authenticated
  using (exists (select 1 from public.venta v where v.id_venta = pago.id_venta));
create policy devolucion_leer on public.devolucion for select to authenticated
  using (exists (select 1 from public.venta v where v.id_venta = devolucion.id_venta));
create policy devolucion_linea_leer on public.devolucion_linea for select to authenticated
  using (exists (select 1 from public.devolucion d where d.id_devolucion = devolucion_linea.id_devolucion));

create policy documento_fiscal_leer on public.documento_fiscal for select to authenticated
  using (public.tiene_permiso('SAR_REPORTES')
         or exists (select 1 from public.venta v where v.id_venta = documento_fiscal.id_venta));
create policy doc_fiscal_total_leer on public.doc_fiscal_total for select to authenticated
  using (exists (select 1 from public.documento_fiscal d where d.id_documento = doc_fiscal_total.id_documento));
create policy ticket_leer on public.ticket for select to authenticated
  using (public.tiene_permiso('SAR_REPORTES')
         or exists (select 1 from public.venta v where v.id_venta = ticket.id_venta));

-- =====================================================================
-- Alarmas
-- =====================================================================
create policy regla_alarma_leer on public.regla_alarma for select to authenticated
  using (public.tiene_permiso('ALARMAS_VER'));
create policy regla_alarma_escribir on public.regla_alarma for all to authenticated
  using (public.tiene_permiso('ALARMAS_REGLAS')) with check (public.tiene_permiso('ALARMAS_REGLAS'));

-- Las alarmas se crean por trigger y se atienden con atender_alarma().
create policy alarma_leer on public.alarma for select to authenticated
  using (public.tiene_permiso('ALARMAS_VER', id_sucursal));
create policy alarma_historial_leer on public.alarma_historial for select to authenticated
  using (exists (select 1 from public.alarma a where a.id_alarma = alarma_historial.id_alarma));
