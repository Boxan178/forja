# Forja

App **PWA de entrenamiento personal** de Pablo. HTML/CSS/JS autocontenido (todo inline en `index.html`), instalable como PWA con service worker (`sw.js`) y modo offline.

## Qué es

Tracker de entrenos con modo guiado **manos libres** (auto-avance de series y descansos), aproximaciones, modo tiempo, penalización de descanso, gamificación (racha, check-in) y vista de progreso con gráfica + historial. Rediseño visual actual: **v3.0.0 "Symmetry"** (nav inferior, racha hero, popup check-in, player reskin).

## Despliegue

- **GitHub**: [`Boxan178/forja`](https://github.com/Boxan178/forja) — rama `main`.
- **GitHub Pages**: https://boxan178.github.io/forja/ — sirve `index.html` desde la raíz del repo. El deploy se dispara con cada push a `main`; mover el working copy no afecta al sitio.

## Backend

- **Supabase**, proyecto `dashboard-personal` (ref `gqoorsfyufktfnyqzudj`), **schema dedicado `trainer`**.
- La app conecta desde el cliente con la *publishable key*. Migración de esquema versionada en `db/migration-v2.sql`.

## Cerebro IA — Fase 2 (pendiente)

El cerebro IA (**Agents SDK**) que asistirá/programará los entrenos vivirá en el **VPS**, no en el cliente. Aún sin construir.

## Estructura

- `index.html` — app completa (CSS + JS inline).
- `sw.js` — service worker (cache offline / PWA).
- `manifest.webmanifest` — manifiesto PWA.
- `fonts/` — Sora + Manrope (woff2 self-host, sin CDN).
- `icon-*.png`, `apple-touch-icon.png`, `icon-source.svg` — iconos PWA.
- `db/migration-v2.sql` — migración de esquema Supabase (`trainer`).
- `_ref/symmetry/` — capturas de referencia del rediseño v3.

## Biblioteca de ejercicios y medios

- **Biblioteca**: `trainer.exercises` (153 ejercicios: fuerza + estiramientos + movilidad). Fuente curada con prompts en [`db/exercise-library.json`](db/exercise-library.json). Columna `kind` ('fuerza' | 'estiramiento' | 'movilidad' | 'cardio'), migración en `db/migration-v3.sql`.
- **Animación por ejercicio**: loop que funde frame inicial → frame final (efecto GIF). Pipeline: Flow (`flow-bridge`) genera los 2 frames → `tools/exercise-anim/make_anim.py` (ffmpeg `xfade` + ping-pong) → MP4 → `exercises.demo_video_url`. Ver [tools/exercise-anim/README.md](tools/exercise-anim/README.md).

## Sesiones: registrar / descartar

- Al terminar (fin natural o botón **Terminar**) NO se pregunta si completaste: se muestra el resumen y se **registra** al pulsar Hecho.
- Botón **Descartar** para sesiones de prueba o incompletas: revierte las series guardadas y marca `workouts.status='discarded'` → no cuenta como día entrenado (las queries de racha/semana filtran `status <> 'discarded'`). Migración en `db/migration-v3.sql`.

## Notas

- Migrado a `lab/` (workspace J.A.R.V.I.S.) desde `C:\dev\forja\` el 2026-06-25, conservando `.git` y el remoto. GitHub Pages sigue desplegando sin cambios.
- Destino futuro del workspace: `personal/` (cuando madure).
