/* Cappybara — minimal service worker for PWA installability.
   Network-first for pages (mint data must stay fresh), cache-first
   for the app icons and other static assets, with an offline
   fallback to the cached home page. */
var CACHE_NAME = "cappybara-pwa-v1";
var CORE_ASSETS = [
  "../index.html",
  "./manifest.webmanifest",
  "./icon-192.png",
  "./icon-512.png",
  "./icon-maskable-192.png",
  "./icon-maskable-512.png",
  "./apple-touch-icon.png"
];

self.addEventListener("install", function (event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function (cache) {
      /* Cache files one by one so a single miss never blocks install. */
      return Promise.all(
        CORE_ASSETS.map(function (url) {
          return cache.add(url).catch(function () { /* non-fatal */ });
        })
      );
    }).then(function () {
      return self.skipWaiting();
    })
  );
});

self.addEventListener("activate", function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(
        keys.map(function (key) {
          if (key !== CACHE_NAME) return caches.delete(key);
        })
      );
    }).then(function () {
      return self.clients.claim();
    })
  );
});

self.addEventListener("fetch", function (event) {
  var req = event.request;
  if (req.method !== "GET") return;

  /* Pages: network first, fall back to the cached page when offline. */
  if (req.mode === "navigate") {
    event.respondWith(
      fetch(req).then(function (res) {
        var copy = res.clone();
        caches.open(CACHE_NAME).then(function (cache) {
          cache.put("../index.html", copy);
        });
        return res;
      }).catch(function () {
        return caches.match("../index.html", { ignoreSearch: true });
      })
    );
    return;
  }

  /* Static assets (icons, manifest, fonts): cache first, then network. */
  event.respondWith(
    caches.match(req, { ignoreSearch: true }).then(function (cached) {
      if (cached) return cached;
      return fetch(req).then(function (res) {
        if (res && res.status === 200) {
          var copy = res.clone();
          caches.open(CACHE_NAME).then(function (cache) {
            cache.put(req, copy);
          });
        }
        return res;
      });
    })
  );
});
