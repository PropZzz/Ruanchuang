// Retire the cache-first worker from the former Flutter Web entry.
// Only generated application caches are removed; account/local data is untouched.
self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    await Promise.all([
      'flutter-app-cache',
      'flutter-temp-cache',
      'flutter-app-manifest',
    ].map((name) => caches.delete(name)));
    await self.registration.unregister();
  })());
});
