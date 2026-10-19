# omnistream

## Autenticación

Si no se definen `window.OMNISTREAM_SUPABASE_URL` y `window.OMNISTREAM_SUPABASE_ANON_KEY` antes de cargar la aplicación, el registro y el inicio de sesión usan cuentas locales guardadas en el navegador. Las contraseñas locales se almacenan como hashes PBKDF2 con sal; cada navegador conserva sus propias cuentas y sesión.

Con Supabase configurado y Google habilitado como proveedor de autenticación, el botón inicia el flujo OAuth real y la aplicación restaura la sesión al regresar. Sin configuración de Supabase, el botón ofrece un modo de demostración que acepta un correo de prueba y guarda una sesión local; no verifica la identidad de Google.