// Service worker temporalmente desactivado para evitar bloqueos
self.addEventListener('install', () => {
    self.skipWaiting();
    });

    self.addEventListener('activate', (event) => {
        event.waitUntil(self.clients.claim());
        });
        