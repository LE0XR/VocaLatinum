const CACHE_NAME = 'vocalatinum-shell-v1';
const APP_SHELL = ['./', './index.html', './manifest.webmanifest', './assets/icon.svg'];
const XLSX_URL = 'https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js';

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await Promise.allSettled(APP_SHELL.map(path => cache.add(path)));
    // Excel-Import-Bibliothek nach Möglichkeit für spätere Offline-Sitzungen zwischenspeichern.
    try {
      const response = await fetch(XLSX_URL, { mode: 'no-cors' });
      await cache.put(XLSX_URL, response);
    } catch (_) { /* Die App bleibt auch ohne Excel-Bibliothek offline nutzbar. */ }
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(key => key.startsWith('vocalatinum-shell-') && key !== CACHE_NAME).map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);

  if (url.origin !== self.location.origin) {
    if (url.href === XLSX_URL) {
      event.respondWith((async () => {
        const cache = await caches.open(CACHE_NAME);
        const cached = await cache.match(XLSX_URL);
        if (cached) return cached;
        try {
          const response = await fetch(request);
          cache.put(XLSX_URL, response.clone()).catch(() => {});
          return response;
        } catch (_) {
          return new Response('', { status: 503, statusText: 'Offline' });
        }
      })());
    }
    return;
  }

  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const cached = await cache.match(request) || (request.mode === 'navigate' ? await cache.match('./index.html') : null);
    if (cached) return cached;
    try {
      const response = await fetch(request);
      if (response.ok) cache.put(request, response.clone()).catch(() => {});
      return response;
    } catch (_) {
      if (request.mode === 'navigate') return (await cache.match('./index.html')) || new Response('Offline', { status: 503 });
      return new Response('', { status: 503 });
    }
  })());
});
