# Sarrio: notas para Claude

App iOS nativa (SwiftUI) que funciona como biblioteca de las cumbres que ha subido el usuario, con red social de amigos.
El plan completo por fases está en el README.

## Decisiones tomadas
- **Sin Strava.** Su API Agreement prohíbe mostrar los datos de un usuario a otros. Fuentes: Apple Health, importar GPX/FIT, Polar AccessLink, y Garmin/Suunto/COROS cuando aprueben el acceso.
- **Todo en planes gratuitos:**
  - Turso (libSQL) como base de datos;
  - Cloudflare Workers (Hono + Drizzle) como API, desplegada con Workers Builds en cada push (raíz `backend`);
  - sin R2: las rutas se guardarán comprimidas en Turso;
  - Mapbox para mapas.
- **La app nunca accede a Turso directamente:** todo pasa por la API, que aplica la visibilidad (`backend/src/services/visibility.ts`) y las zonas de privacidad (`applyPrivacyZones`).
- **La detección de cumbres se hace en el iPhone** (`SarrioKit.PeakDetector`), con paquetes de picos por celda geohash de 4 caracteres (`GET /v1/peaks/pack/:cell`).
- **Geohash:** la implementación de Swift (`Geo.geohash`), la del backend (`lib/geo.ts`) y la del script de picos tienen que dar el mismo resultado. Los tests fijan el valor de referencia `sp86w` para el Aneto.

## Comandos
- Backend: `cd backend && npm ci && npm run typecheck && npm test`
- Migraciones: edita `backend/src/db/schema.ts` y luego `npm run db:generate`. Revisa el SQL generado en `backend/migrations/`.
- SarrioKit: `cd ios/Packages/SarrioKit && swift test` (funciona también en Linux).
- Proyecto Xcode: `cd ios && xcodegen`. El `.xcodeproj` no se versiona.
- Picos: `node tools/peaks/fetch-peaks.mjs <región> > peaks-<región>.sql`

## Convenciones
- Estética clara, minimalista y profesional: usa siempre `Theme` y los componentes de `ios/Sarrio/Core/Design` (Card, StatRow, PrimaryButtonStyle, EmptyStateView…). Fondos blancos o gris muy suave, un único color de acento y cifras grandes en negrita.
- Rutas del backend: dependencias inyectables con `createApp(deps)`. Los tests usan libSQL en memoria (`backend/test/helpers.ts`).
- Los textos de la interfaz van en español.
- La lógica pura (sin UIKit, HealthKit ni Mapbox) va en `SarrioKit` y lleva tests.
