#!/usr/bin/env python3
"""
make_anim.py — Genera la animacion "GIF" de un ejercicio a partir de dos frames.

Pipeline Forja (hilo de videos de ejercicio):
  Flow (flow-bridge) -> frame INICIAL + frame FINAL  ->  ESTE script  ->  loop MP4/WebP  ->  subir a la app

El efecto es un fundido (xfade) entre el frame inicial y el final del movimiento,
con ping-pong (inicio -> fin -> inicio) para que el bucle lea como la repeticion
bajando y subiendo. Motor: ffmpeg (el mismo que usa auto-edit/LUIS), trabajo simple.

Uso (un ejercicio):
  python make_anim.py --start flexiones-start.png --end flexiones-end.png --out flexiones.mp4

Uso (lote, desde la biblioteca):
  python make_anim.py --batch --frames ./frames --library biblioteca.json --outdir ./anim
  # espera ./frames/<slug>-start.png y ./frames/<slug>-end.png por ejercicio

Salidas: MP4 (H.264, yuv420p, faststart) y, si --webp, ademas un WebP animado.
"""
import argparse, json, os, subprocess, sys, tempfile
from pathlib import Path

def run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        sys.stderr.write("\n[ffmpeg ERROR]\n" + " ".join(cmd) + "\n" + p.stderr[-2000:] + "\n")
        raise SystemExit(1)
    return p

def scale_crop(w, h):
    # cubrir y recortar al centro al lienzo destino, SAR 1:1
    return f"scale={w}:{h}:force_original_aspect_ratio=increase,crop={w}:{h},setsar=1"

def make_one(start, end, out, w=1080, h=1350, hold=0.85, fade=0.75, fps=30,
             pingpong=True, webp=False):
    start, end, out = Path(start), Path(end), Path(out)
    if not start.exists(): raise SystemExit(f"No existe frame inicial: {start}")
    if not end.exists():   raise SystemExit(f"No existe frame final: {end}")
    out.parent.mkdir(parents=True, exist_ok=True)
    seg = round(hold + fade, 3)          # duracion de cada still (hold + solape del fundido)
    sc = scale_crop(w, h)

    with tempfile.TemporaryDirectory() as td:
        fwd = Path(td) / "forward.mp4"
        # forward: A se mantiene `hold`, funde a B en `fade`, B se mantiene `hold`
        fc = (f"[0:v]{sc},fps={fps}[a];"
              f"[1:v]{sc},fps={fps}[b];"
              f"[a][b]xfade=transition=fade:duration={fade}:offset={hold},format=yuv420p[v]")
        run(["ffmpeg","-y","-loop","1","-t",str(seg),"-i",str(start),
             "-loop","1","-t",str(seg),"-i",str(end),
             "-filter_complex",fc,"-map","[v]","-r",str(fps),"-an",str(fwd)])

        if pingpong:
            # ping-pong: forward + su reverso -> inicio->fin->inicio, bucle perfecto
            run(["ffmpeg","-y","-i",str(fwd),
                 "-filter_complex","[0:v]reverse[r];[0:v][r]concat=n=2:v=1[v]",
                 "-map","[v]","-r",str(fps),"-pix_fmt","yuv420p",
                 "-movflags","+faststart",str(out)])
        else:
            run(["ffmpeg","-y","-i",str(fwd),"-c","copy","-movflags","+faststart",str(out)])

    if webp:
        wp = out.with_suffix(".webp")
        run(["ffmpeg","-y","-i",str(out),"-vcodec","libwebp","-lossless","0",
             "-q:v","70","-loop","0","-preset","default","-an","-vsync","0",str(wp)])
        print(f"  + {wp.name} ({wp.stat().st_size//1024} KB)")

    print(f"OK -> {out} ({out.stat().st_size//1024} KB)")
    return out

def batch(frames, library, outdir, **kw):
    frames, outdir = Path(frames), Path(outdir)
    lib = json.loads(Path(library).read_text(encoding="utf-8"))
    exs = lib.get("exercises", lib) if isinstance(lib, dict) else lib
    done, missing = 0, []
    for ex in exs:
        slug = ex.get("slug") or ex["name"].lower()
        s = frames / f"{slug}-start.png"
        e = frames / f"{slug}-end.png"
        if not (s.exists() and e.exists()):
            missing.append(slug); continue
        make_one(s, e, outdir / f"{slug}.mp4", **kw)
        done += 1
    print(f"\nLote: {done} animaciones generadas. {len(missing)} sin frames todavia.")
    if missing:
        print("Pendientes de frames (Flow):", ", ".join(missing[:30]) + (" ..." if len(missing) > 30 else ""))

def main():
    ap = argparse.ArgumentParser(description="Animacion de ejercicio: fundido frame inicial -> frame final")
    ap.add_argument("--start"); ap.add_argument("--end"); ap.add_argument("--out")
    ap.add_argument("--batch", action="store_true")
    ap.add_argument("--frames"); ap.add_argument("--library"); ap.add_argument("--outdir", default="./anim")
    ap.add_argument("--w", type=int, default=1080); ap.add_argument("--h", type=int, default=1350)
    ap.add_argument("--hold", type=float, default=0.85); ap.add_argument("--fade", type=float, default=0.75)
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--no-pingpong", dest="pingpong", action="store_false")
    ap.add_argument("--webp", action="store_true")
    a = ap.parse_args()
    kw = dict(w=a.w, h=a.h, hold=a.hold, fade=a.fade, fps=a.fps, pingpong=a.pingpong, webp=a.webp)
    if a.batch:
        if not (a.frames and a.library): raise SystemExit("--batch requiere --frames y --library")
        batch(a.frames, a.library, a.outdir, **kw)
    else:
        if not (a.start and a.end and a.out): raise SystemExit("Modo simple requiere --start --end --out")
        make_one(a.start, a.end, a.out, **kw)

if __name__ == "__main__":
    main()
