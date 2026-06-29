# Pipeline de medios de ejercicio (Forja)

Cada ejercicio muestra una animación corta en bucle que **funde el frame inicial y el frame final** del movimiento — efecto tipo GIF — para que se entienda el gesto de un vistazo.

## Pasos

1. **Frames (Google Flow vía `flow-bridge`)** — 2 imágenes por ejercicio (Text→Image):
   - `<slug>-start.png` — posición de inicio del movimiento.
   - `<slug>-end.png` — posición final (máxima contracción; en estiramientos, máxima elongación).
   - Los prompts ya están en [`db/exercise-library.json`](../../db/exercise-library.json) (`frame_start_prompt` / `frame_end_prompt`). Comparten un bloque de estilo fijo para que **lo único que cambie entre los dos frames sea la pose**, no el personaje ni el encuadre.

2. **Animación (ffmpeg)** — `make_anim.py` hace el fundido inicio→fin con **ping-pong** (inicio→fin→inicio) para un loop perfecto:

   ```bash
   # un ejercicio
   python make_anim.py --start flexiones-start.png --end flexiones-end.png --out flexiones.mp4 --webp

   # lote (todos los que tengan sus dos frames en ./frames)
   python make_anim.py --batch --frames ./frames --library ../../db/exercise-library.json --outdir ./anim
   ```

   Salida: **MP4 H.264** (1080×1350, ~5 s, ~30 KB) y, con `--webp`, un WebP animado. Parámetros: `--w/--h`, `--hold`, `--fade`, `--fps`, `--no-pingpong`.

3. **Subir** — sube el MP4 a Supabase Storage (bucket público) y guarda la URL en `trainer.exercises.demo_video_url` del ejercicio. La app lo reproduce con `<video muted loop autoplay playsinline>` (más ligero y suave que un GIF).

## Notas

- **"Haz uno de prueba y el resto iguales":** el motor y los parámetros son fijos; cada ejercicio nuevo es solo sus 2 frames + un `make_anim`. El modo `--batch` procesa toda la biblioteca de golpe en cuanto existan los frames.
- **Consistencia entre frames:** si Flow no mantiene el mismo personaje entre las dos generaciones, generar el frame final como **edición del inicial** (img2img: "la misma figura, ahora en [pose final]") en vez de dos Text→Image independientes.
- Motor: ffmpeg (el mismo que usa `auto-edit`/LUIS). El fundido es un `xfade` — no requiere el pipeline de cine.
