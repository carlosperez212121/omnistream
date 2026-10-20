# omnistream

## Autenticación

El proyecto usa `https://thnrfbomvckokqoyoehq.supabase.co` como URL predeterminada. Define `window.OMNISTREAM_SUPABASE_ANON_KEY` antes de cargar la aplicación con la clave anon/public de este proyecto. También puedes sobrescribir la URL mediante `window.OMNISTREAM_SUPABASE_URL`. No uses una clave `service_role` en el navegador. Sin la clave anon, el inicio de sesión con correo y contraseña usa cuentas locales en este navegador; las contraseñas se guardan como hashes PBKDF2 con sal.

Con la clave configurada y Google habilitado como proveedor de autenticación en Supabase, el botón inicia el flujo OAuth real. Supabase guarda la sesión en `localStorage` y la restaura al volver del proveedor. Añade `https://thnrfbomvckokqoyoehq.supabase.co/auth/v1/callback` como URI de redirección autorizada en Google Cloud y permite la URL del sitio en las URL de redirección de Supabase Auth. Sin la clave anon, el botón de Google informa que falta configuración; no simula una identidad.