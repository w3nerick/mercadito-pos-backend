-- =====================================================================
-- 0100 · Extensiones y funciones de validación compartidas
-- Responsable: Líder Backend / arquitectura de datos
-- =====================================================================

-- btree_gist permite restricciones de exclusión que mezclan "=" con
-- traslapes de rangos (vigencias de precios, rangos de CAI).
create schema if not exists extensions;
create extension if not exists btree_gist with schema extensions;

-- ---------------------------------------------------------------------
-- Dígito verificador EAN-13 (doc 05 §7, RN-21).
-- Suma los 12 primeros dígitos con pesos 1,3,1,3...; el verificador es
-- lo que falta para llegar a la siguiente decena.
-- ---------------------------------------------------------------------
create or replace function public.ean13_digito_verificador(p_doce text)
returns int
language sql
immutable
set search_path = ''
as $$
  select (10 - (sum(substr(p_doce, i, 1)::int * case when i % 2 = 0 then 3 else 1 end) % 10)) % 10
  from generate_series(1, 12) as i
$$;

create or replace function public.ean13_valido(p_codigo text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_codigo ~ '^[0-9]{13}$'
     and public.ean13_digito_verificador(left(p_codigo, 12)) = right(p_codigo, 1)::int
$$;

-- RTN hondureño: 14 dígitos numéricos (RF-SAR-15, RF-CLI-05).
create or replace function public.rtn_valido(p_rtn text)
returns boolean
language sql
immutable
set search_path = ''
as $$ select p_rtn ~ '^[0-9]{14}$' $$;

-- Mantiene la columna "actualizado" en tablas que la tienen.
create or replace function public.tg_marcar_actualizado()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.actualizado := now();
  return new;
end;
$$;

-- Bloquea UPDATE y DELETE en tablas de solo inserción (kardex, bitácora,
-- puntos). Las correcciones se hacen con un registro contrario.
create or replace function public.tg_solo_insercion()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'La tabla % es de solo inserción; registre un movimiento contrario', tg_table_name
    using errcode = 'P0001', hint = 'SOLO_INSERCION';
end;
$$;
