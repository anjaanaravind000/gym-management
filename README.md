# Gym Management

A modern, mobile-first gym management SaaS UI designed for 2026 workflows. The frontend is React + TypeScript + Vite and is prepared to connect to the Supabase project already provisioned for this product.

## Included

- Premium dark-first responsive dashboard
- Mobile Members directory with search, filters and bottom-sheet actions
- Touch-friendly quick actions and fixed mobile navigation
- Revenue, membership health, attendance and activity dashboard modules
- Empty, loading-ready and error-friendly UI patterns
- Supabase client bootstrap using publishable credentials only
- Environment template and Git hygiene

## Supabase

The backend project already exists separately. Set:

```bash
cp .env.example .env.local
```

Then add the project URL and publishable key. Never put a service-role or secret key in frontend environment variables.

## Local development

```bash
npm install
npm run dev
```

## Production build

```bash
npm run build
```

## Product direction

The app follows the agreed design standard: modern premium fitness SaaS, dark-first, large readable metrics, one-handed mobile workflows, bottom sheets for contextual actions, predictable navigation, and minimal decorative UI.
