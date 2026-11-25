# Sarrio

<img src="brand/sarrio-logo.png" alt="Sarrio" width="260">

Tu biblioteca de cumbres. Sarrio sincroniza tus salidas a la montaña y detecta los picos que has subido. Cada ascensión queda en tu biblioteca con:
- la ruta en 3D sobre satélite;
- un globo con todas tus cumbres;
- emblemas y retos;
- una red de amigos con likes y comentarios.

App nativa para iPhone (SwiftUI), con un backend gratuito en Cloudflare Workers y Turso.

## Estructura

```
ios/
  project.yml              Proyecto Xcode (XcodeGen)
  Config.example.xcconfig  Claves locales: cópialo a Config.xcconfig
  Sarrio/                  App SwiftUI (App, Core, Features)
  SarrioTests/
  Packages/SarrioKit/      Lógica pura y testeable: geometría, GPX, detección de cumbres
backend/                   API: Cloudflare Worker (Hono + Drizzle + Turso/libSQL)
  src/db/schema.ts         Esquema de la base de datos
  migrations/              SQL generado por drizzle-kit
tools/peaks/               Importador de picos de OpenStreetMap (Overpass → SQL)
brand/                     Logotipo, icono de la app y guía de marca
site/                      Web pública (soporte, privacidad, términos) → GitHub Pages
```

## Fuentes de datos

| Fuente | Estado |
|---|---|
| Apple Health (entrenos y rutas) | Fase 3. Sin aprobación previa |
| Importar GPX | ✅ Ya funciona (pantalla Cumbres → Importar) |
| Importar FIT/TCX | Fase 3 |
| Polar AccessLink | Fase 7. Alta propia gratuita |
| Garmin Connect, Suunto, COROS | Hay que solicitar acceso de partner ya, porque la aprobación tarda |

Strava queda descartado: su API Agreement (noviembre de 2024) no permite mostrar los datos de un usuario a otros usuarios, y eso es incompatible con la parte social.

## Puesta en marcha (todo gratuito)

### 1. Cuentas
- **Turso**: https://turso.tech. Ejecuta `turso db create sarrio` y luego `turso db tokens create sarrio`.
- **Cloudflare**: https://dash.cloudflare.com. Workers y R2. Crea el bucket con `npx wrangler r2 bucket create sarrio-files`.
- **Mapbox**: https://account.mapbox.com. Copia el token público (`pk.…`).
- **Apple Developer**: crea un App ID con HealthKit, Sign in with Apple y Push Notifications.
- **Polar AccessLink**: https://admin.polaraccesslink.com
- **Solicitudes de partner** (hazlo cuanto antes):
  - Garmin: https://developer.garmin.com/gc-developer-program/
  - Suunto: https://apizone.suunto.com
  - COROS: escribe a api@coros.com

### 2. Backend
```bash
cd backend
cp .dev.vars.example .dev.vars   # rellena los valores
npm ci
turso dev --db-file local.db     # en otra terminal: libSQL local en :8080
TURSO_DATABASE_URL=http://127.0.0.1:8080 npm run db:migrate
npm run dev                      # API en http://localhost:8787
npm test
```

Para producción:
```bash
npx wrangler secret put TURSO_DATABASE_URL
npx wrangler secret put TURSO_AUTH_TOKEN
npx wrangler secret put JWT_SECRET
npx wrangler secret put TOKEN_ENCRYPTION_KEY
npm run deploy
```

### 3. Picos (OpenStreetMap)
```bash
node tools/peaks/fetch-peaks.mjs pirineos > peaks-pirineos.sql
turso db shell sarrio < peaks-pirineos.sql
```
Las regiones están en `tools/peaks/regions.json`: Pirineos, Sierra Nevada, Picos de Europa, Sistema Central, España y Alpes.

### 4. App iOS
```bash
brew install xcodegen
cd ios
cp Config.example.xcconfig Config.xcconfig   # team, bundle id, token de Mapbox, URL de la API
xcodegen
open Sarrio.xcodeproj
```
Los tests de lógica se ejecutan sin Xcode: `cd ios/Packages/SarrioKit && swift test`.

El CI compila y testea la app en los runners macOS de GitHub en cada push (job `ios`).

## Hoja de ruta

- [x] **Fase 1**: esqueleto del repo. Incluye:
  - esquema y migración de Turso;
  - API con `/health` y `/v1/peaks/pack/:cell`;
  - importador de picos;
  - SarrioKit (geohash, Douglas-Peucker, GPX, detector de cumbres);
  - app con pestañas, importación de GPX y detección de cumbres;
  - CI.
- [x] **Fase 2**: Sign in with Apple → JWT propio (con nonce), perfil editable, borrado de cuenta, perfil público y sistema de diseño (`ios/Sarrio/Core/Design`).
- [ ] **Fase 3**: HealthKit (histórico y observer), FIT/TCX, Share Extension, y subida de actividades y ascensiones.
- [ ] **Fase 4**: detalle 3D con terreno y vuelo de cámara, perfil de elevación, y globo con clustering.
- [ ] **Fase 5**: emblemas y retos (oficiales y de usuarios).
- [ ] **Fase 6**: social. Incluye:
  - amigos y feed;
  - likes y comentarios;
  - notificaciones push;
  - visibilidad y zonas de privacidad;
  - bloquear y reportar.
- [ ] **Fase 7**: Polar; después Garmin, Suunto y COROS.
- [ ] **Fase 8**: App Store. Incluye:
  - privacy manifest;
  - política de privacidad;
  - TestFlight.

## Licencias de datos
- Picos: © OpenStreetMap contributors, bajo licencia [ODbL](https://opendatacommons.org/licenses/odbl/).
- Mapas: © Mapbox, © OpenStreetMap.
