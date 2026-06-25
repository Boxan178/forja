/* Forja service worker — app-shell offline + network-first para datos.
   CRITICO subpath /forja/: todo se resuelve contra self.registration.scope,
   nunca contra "/". El SW se registra con scope "./" desde index.html. */

const VERSION = 'forja-v3.0.0';
const SHELL_CACHE = `${VERSION}-shell`;
const RUNTIME_CACHE = `${VERSION}-runtime`;

/* scope termina siempre en "/", p.ej. https://boxan178.github.io/forja/ */
const SCOPE = self.registration.scope;
const abs = (path) => new URL(path, SCOPE).toString();

/* App-shell: lo minimo para abrir la app offline.
   Los datos (Supabase REST) NO se precachean: requieren red. */
const SHELL_ASSETS = [
  abs('./'),
  abs('./index.html'),
  abs('./manifest.webmanifest'),
  abs('./icon-192.png'),
  abs('./icon-512.png'),
  abs('./icon-192-maskable.png'),
  abs('./icon-512-maskable.png'),
  abs('./apple-touch-icon.png'),
  // Tipografia self-host (mismo-origen, bajo /forja/) -> sobrevive offline
  abs('./fonts/sora-latin-var.woff2'),
  abs('./fonts/manrope-latin-var.woff2'),
  // CDN externo del app-shell (cross-origin, opaque-ok)
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2'
];

/* Hosts cuyas respuestas SON datos -> siempre network-first, nunca shell. */
const DATA_HOST = 'gqoorsfyufktfnyqzudj.supabase.co';
/* Hosts estaticos cacheables en runtime (fuentes servidas por gstatic). */
const STATIC_RUNTIME_HOSTS = ['fonts.gstatic.com', 'fonts.googleapis.com', 'cdn.jsdelivr.net'];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(SHELL_CACHE);
    // addAll falla entero si un recurso casca; los metemos uno a uno para ser robustos.
    await Promise.all(SHELL_ASSETS.map(async (url) => {
      try {
        const crossOrigin = url.startsWith('http') && !url.startsWith(SCOPE);
        const req = new Request(url, { cache: 'reload', mode: crossOrigin ? 'cors' : 'same-origin' });
        const res = await fetch(req);
        // NUNCA cachear opacas ni errores en assets criticos del shell (sobre todo
        // supabase-js): una opaca tiene body inaccesible/posible-vacio y dejaria la
        // app inservible al servir un bundle vacio. Exigimos res.ok && no-opaque.
        if (res && res.ok && res.type !== 'opaque') await cache.put(url, res.clone());
      } catch (_) { /* recurso opcional: seguimos */ }
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map((k) => {
      if (k !== SHELL_CACHE && k !== RUNTIME_CACHE) return caches.delete(k);
      return null;
    }));
    if (self.registration.navigationPreload) {
      try { await self.registration.navigationPreload.enable(); } catch (_) {}
    }
    await self.clients.claim();
  })());
});

/* Permite a la pagina forzar la activacion del SW nuevo. */
self.addEventListener('message', (event) => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return; // POST/PATCH a Supabase pasan directos a red

  const url = new URL(req.url);

  // 1) Navegaciones (abrir la app): network-first con fallback al index cacheado.
  if (req.mode === 'navigate') {
    event.respondWith(handleNavigate(event));
    return;
  }

  // 2) Datos Supabase: network-first, sin servir cache obsoleta de datos.
  if (url.hostname === DATA_HOST) {
    event.respondWith(networkFirstData(req));
    return;
  }

  // 3) Estaticos del shell mismo-origen (incluido bajo /forja/): cache-first.
  if (url.origin === self.location.origin) {
    event.respondWith(cacheFirst(req, SHELL_CACHE));
    return;
  }

  // 4) Fuentes / CDN estaticos cross-origin: stale-while-revalidate.
  if (STATIC_RUNTIME_HOSTS.includes(url.hostname)) {
    event.respondWith(staleWhileRevalidate(req, RUNTIME_CACHE));
    return;
  }

  // 5) Resto: intenta red, cae a cache si existe.
  event.respondWith(fetch(req).catch(() => caches.match(req)));
});

async function handleNavigate(event) {
  const req = event.request;
  try {
    // navigationPreload: aislamos su await en su propio try/catch. Si el preload
    // rechaza, o llega pero NO es ok (404/500 de GitHub Pages, redirect roto...),
    // NO lo devolvemos: caemos al fetch normal y, si falla, al index offline.
    let preload = null;
    try { preload = await event.preloadResponse; } catch (_) { preload = null; }
    if (preload && preload.ok) return preload;
    const net = await fetch(req);
    return net;
  } catch (_) {
    const cache = await caches.open(SHELL_CACHE);
    return (await cache.match(abs('./index.html'))) ||
           (await cache.match(abs('./'))) ||
           new Response('Offline', { status: 503, headers: { 'Content-Type': 'text/plain' } });
  }
}

async function networkFirstData(req) {
  /* Network-first PURO para Supabase: NO cacheamos por URL.
     PostgREST distingue "objeto unico" vs "array" por el header Accept
     (.maybeSingle()/.eq('id',1) -> application/vnd.pgrst.object+json;
     .select() normal -> array). La Cache API no discrimina por Accept salvo Vary,
     asi que una respuesta-array cacheada podria servirse a una llamada que espera
     objeto unico (y viceversa) -> bug de correctitud en modo avion.
     Offline devolvemos un 503 JSON limpio; el cliente ya degrada con elegancia. */
  try {
    return await fetch(req);
  } catch (_) {
    return new Response(JSON.stringify({ offline: true }), {
      status: 503, headers: { 'Content-Type': 'application/json' }
    });
  }
}

async function cacheFirst(req, cacheName) {
  const cache = await caches.open(cacheName);
  const cached = await cache.match(req);
  if (cached) return cached;
  try {
    const net = await fetch(req);
    if (net && (net.ok || net.type === 'opaque')) cache.put(req, net.clone());
    return net;
  } catch (_) {
    return cached || Response.error();
  }
}

async function staleWhileRevalidate(req, cacheName) {
  const cache = await caches.open(cacheName);
  const cached = await cache.match(req);
  const network = fetch(req).then((net) => {
    if (net && (net.ok || net.type === 'opaque')) cache.put(req, net.clone());
    return net;
  }).catch(() => null);
  return cached || (await network) || Response.error();
}
