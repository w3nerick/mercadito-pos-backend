-- =====================================================================
-- 1300 · Tareas programadas con pg_cron (doc 05 §2.5)
-- En Supabase pg_cron se habilita desde Database → Extensions. Si la
-- extensión no está disponible (p. ej. en las pruebas locales), esta
-- migración solo avisa y no falla.
-- =====================================================================
do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron no disponible: las tareas programadas no se registran (%).', sqlerrm;
    return;
  end;

  -- 00:05 hora de Honduras (06:05 UTC): bloquea lotes caducados y genera
  -- alarmas de caducidad (RN-EXI-03, alarmas CADUCADO / POR_CADUCAR).
  perform cron.schedule('alarmas-caducidad', '5 6 * * *', 'select public.evaluar_alarmas_caducidad()');
end $$;
