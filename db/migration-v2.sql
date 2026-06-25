-- FORJA v2 — migracion CONSOLIDADA e IDEMPOTENTE sobre schema `trainer`
-- Aplicada a Supabase (proyecto gqoorsfyufktfnyqzudj) el 2026-06-25.
-- Re-ejecutable: IF NOT EXISTS / DO-guards / CREATE OR REPLACE.
-- Nombres canonicos: set_type, mode, work_seconds, target_rest_seconds,
-- actual_rest_seconds, rest_over_limit, set_order.

-- 1. profile: preferencias de timers
alter table trainer.profile add column if not exists prep_seconds         smallint not null default 10;
alter table trainer.profile add column if not exists default_rest_seconds  smallint not null default 120;
alter table trainer.profile add column if not exists rest_penalty_seconds  smallint not null default 300;
alter table trainer.profile add column if not exists default_work_seconds  smallint not null default 15;
alter table trainer.profile add column if not exists default_set_mode      text     not null default 'reps';
alter table trainer.profile add column if not exists prefs                 jsonb    not null default
  '{"sound_on":true,"vibrate_on":true,"wakelock_on":true,"penalty_type":"pushups"}'::jsonb;
do $$ begin
  if not exists (select 1 from pg_constraint where conname='profile_default_set_mode_chk') then
    alter table trainer.profile add constraint profile_default_set_mode_chk check (default_set_mode in ('reps','time'));
  end if;
end $$;

-- 2. workout_sets: tipo + modo + timing + orden
alter table trainer.workout_sets add column if not exists set_type            text     not null default 'working';
alter table trainer.workout_sets add column if not exists mode                text     not null default 'reps';
alter table trainer.workout_sets add column if not exists work_seconds        smallint;
alter table trainer.workout_sets add column if not exists target_rest_seconds smallint;
alter table trainer.workout_sets add column if not exists actual_rest_seconds smallint;
alter table trainer.workout_sets add column if not exists rest_over_limit     boolean  not null default false;
alter table trainer.workout_sets add column if not exists set_order           integer;
do $$ begin
  if not exists (select 1 from pg_constraint where conname='workout_sets_set_type_chk') then
    alter table trainer.workout_sets add constraint workout_sets_set_type_chk check (set_type in ('warmup','approach','working'));
  end if;
  if not exists (select 1 from pg_constraint where conname='workout_sets_mode_chk') then
    alter table trainer.workout_sets add constraint workout_sets_mode_chk check (mode in ('reps','time'));
  end if;
end $$;
update trainer.workout_sets set set_type = case when is_warmup then 'warmup' else 'working' end
 where set_type = 'working' and is_warmup is true;
update trainer.workout_sets ws set set_order = sub.rn
  from (select id, row_number() over (partition by workout_id order by id) as rn from trainer.workout_sets) sub
 where ws.id = sub.id and ws.set_order is null;
create or replace function trainer.sync_is_warmup() returns trigger language plpgsql as $$
begin
  new.is_warmup := (new.set_type in ('warmup','approach'));
  return new;
end $$;
drop trigger if exists trg_sync_is_warmup on trainer.workout_sets;
create trigger trg_sync_is_warmup before insert or update of set_type, is_warmup on trainer.workout_sets
  for each row execute function trainer.sync_is_warmup();
create index if not exists idx_workout_sets_order on trainer.workout_sets (workout_id, set_order);

-- 3. checkins: recuperacion activa
alter table trainer.checkins add column if not exists active_recovery text;

-- 4. exercises: defaults de motor por ejercicio
alter table trainer.exercises add column if not exists default_rest_seconds smallint default 120;
alter table trainer.exercises add column if not exists default_set_mode     text default 'reps';
alter table trainer.exercises add column if not exists default_work_seconds smallint;
do $$ begin
  if not exists (select 1 from pg_constraint where conname='exercises_default_set_mode_chk') then
    alter table trainer.exercises add constraint exercises_default_set_mode_chk check (default_set_mode in ('reps','time'));
  end if;
end $$;

-- 5. goals (recomposicion)
create table if not exists trainer.goals (
  id bigint generated always as identity primary key,
  metric text not null, direction text not null default 'down', label text not null,
  baseline_value numeric, current_value numeric, target_value numeric, unit text,
  is_active boolean not null default true, achieved_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
do $$ begin
  if not exists (select 1 from pg_constraint where conname='goals_direction_chk') then
    alter table trainer.goals add constraint goals_direction_chk check (direction in ('down','up'));
  end if;
end $$;

-- 6. achievements (code UNIQUE para upsert onConflict:code)
create table if not exists trainer.achievements (
  id bigint generated always as identity primary key,
  code text not null unique, title text, description text, icon text, category text,
  threshold numeric, context jsonb,
  unlocked_at timestamptz not null default now(), created_at timestamptz not null default now()
);

-- 7. streaks (singleton)
create table if not exists trainer.streaks (
  id smallint primary key default 1,
  current_streak integer not null default 0, longest_streak integer not null default 0,
  last_active_date date, updated_at timestamptz not null default now(),
  constraint streaks_singleton_chk check (id = 1)
);
insert into trainer.streaks (id) values (1) on conflict (id) do nothing;

-- 8. rest_penalty_events
create table if not exists trainer.rest_penalty_events (
  id bigint generated always as identity primary key,
  workout_id bigint references trainer.workouts(id),
  set_id bigint references trainer.workout_sets(id),
  actual_rest_seconds integer not null, limit_seconds integer not null,
  challenge_text text, completed boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists idx_rest_penalty_workout on trainer.rest_penalty_events (workout_id);

-- 9. RLS permisivo (app personal de un usuario)
do $$
declare t text;
begin
  foreach t in array array['goals','achievements','streaks','rest_penalty_events']
  loop
    execute format('alter table trainer.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname='trainer' and tablename=t and policyname='app full '||t) then
      execute format('create policy %I on trainer.%I for all to anon, authenticated using (true) with check (true)', 'app full '||t, t);
    end if;
  end loop;
end $$;

-- 10. GRANTs
grant usage on schema trainer to anon, authenticated;
grant all on trainer.goals, trainer.achievements, trainer.streaks, trainer.rest_penalty_events to anon, authenticated;
grant all on all sequences in schema trainer to anon, authenticated;

-- 11. Seeds de objetivos (recomposicion)
insert into trainer.goals (metric,direction,label,baseline_value,current_value,target_value,unit,is_active)
select v.metric, v.direction, v.label, null, null, v.target, v.unit, true
from (values
  ('bench_1rm_kg','up','Banca a 100 kg',100::numeric,'kg'),
  ('body_fat_pct','down','Bajar grasa (lumbar/abdomen/pecho) manteniendo peso',null::numeric,'%'),
  ('weekly_sessions','up','6 sesiones por semana',6::numeric,'ses/sem')
) as v(metric,direction,label,target,unit)
where not exists (select 1 from trainer.goals g where g.metric = v.metric);

-- 12. recargar PostgREST
notify pgrst, 'reload schema';
