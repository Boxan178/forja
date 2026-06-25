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

## Notas

- Migrado a `lab/` (workspace J.A.R.V.I.S.) desde `C:\dev\forja\` el 2026-06-25, conservando `.git` y el remoto. GitHub Pages sigue desplegando sin cambios.
- Destino futuro del workspace: `personal/` (cuando madure).
