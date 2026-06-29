-- FORJA v3 — migracion sobre schema `trainer`
-- Idempotente (IF NOT EXISTS / DO-guards). Aplicada a Supabase (gqoorsfyufktfnyqzudj).
--
-- Objetivo:
--   1. exercises.kind        -> distingue fuerza / estiramiento / movilidad (biblioteca extensa)
--   2. exercises.demo_video_url ya existe (animacion del ejercicio: loop MP4 Flow->xfade)
--   3. workouts.status        -> 'active' | 'completed' | 'discarded'
--      Permite DESCARTAR una sesion (prueba / incompleta) sin que cuente como dia entrenado.
--      Las queries de racha/semana filtran status <> 'discarded'.

-- 1. exercises.kind (tipo de ejercicio)
alter table trainer.exercises add column if not exists kind text not null default 'fuerza';
do $$ begin
  if not exists (select 1 from pg_constraint where conname='exercises_kind_chk') then
    alter table trainer.exercises add constraint exercises_kind_chk
      check (kind in ('fuerza','estiramiento','movilidad','cardio'));
  end if;
end $$;

-- 2. workouts.status (registrar / descartar)
alter table trainer.workouts add column if not exists status text not null default 'active';
do $$ begin
  if not exists (select 1 from pg_constraint where conname='workouts_status_chk') then
    alter table trainer.workouts add constraint workouts_status_chk
      check (status in ('active','completed','discarded'));
  end if;
end $$;
create index if not exists idx_workouts_status_date on trainer.workouts (status, date);

-- 3. recargar PostgREST
notify pgrst, 'reload schema';
