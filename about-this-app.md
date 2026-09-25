# LeadCatch SA — Single Source of Truth

**Purpose:** Never miss another WhatsApp lead. For independent South African service businesses.

## Stack
- TanStack Start v1 (React 19, Vite 7, file routes in `src/routes`), Tailwind v4 (`src/styles.css` tokens), shadcn/ui.
- Lovable Cloud (Supabase): Postgres + RLS, Auth (email/password + Google), Realtime.
- External WhatsApp Operator (Baileys) on Render: https://my-own-whatsapp-2z5h.onrender.com (repo: github.com/Naha1981/my-own-whatsapp). **This app never connects to WhatsApp directly.**

## Directory layout
- `src/routes/auth.tsx` — sign in / sign up, POPIA note
- `src/routes/_authenticated/route.tsx` — client-side auth gate (ssr:false)
- `src/routes/_authenticated/onboarding.tsx` — 3 steps: business → hours+greeting → WhatsApp
- `src/routes/_authenticated/_shell/*` — sidebar shell + `dashboard`, `inbox`, `auto-reply`, `settings`
- `src/routes/api/public/whatsapp/webhook.ts` — inbound Operator webhook (HMAC-verified)
- `src/lib/operator.server.ts` — server-only Operator HTTP client + signature verify
- `src/lib/whatsapp.functions.ts` — server fns: connect, status/QR, pairing code, disconnect, sendMessage
- `src/lib/autoreply.ts` — pure auto-reply decision logic (shared by webhook + preview)
- `src/lib/workspace.ts` — loads/creates tenant, profile, config on first sign-in

## Schema (all tables have `tenant_id`, RLS on)
- `tenants(id, owner_id unique)` — owner-only policies. `is_tenant_member(tenant_id)` security-definer helper.
- `business_profiles(tenant_id unique, business_name, industry, working_hours jsonb {days[0-6],start,end}, whatsapp_status, whatsapp_number, whatsapp_last_synced_at, wa_account_id, onboarded)`
- `leads(tenant_id, name, phone, status new|replied|qualified|closed)` unique (tenant_id, phone)
- `lead_events(tenant_id, lead_id, type, payload)` — append-only: lead_created, message_received, auto_reply_sent, reply_sent, status_changed
- `conversations(tenant_id, lead_id unique, last_message_preview, last_message_at, unread_count)`
- `conversation_messages(tenant_id, conversation_id, direction, body, is_auto, external_id, delivery_status)` unique (tenant_id, external_id)
- `auto_reply_configs(tenant_id unique, enabled, greeting, questions jsonb[], keyword_rules jsonb[{id,keywords[],reply,enabled}], after_hours, handoff)`
- `whatsapp_webhook_events(tenant_id, event, message_id, payload, processed_at, processing_error)` — durable inbox, service-role writes, tenant read.
- Policies: `tenant select/insert/update/delete` using `is_tenant_member(tenant_id)`.
- Realtime: conversations, conversation_messages, leads, business_profiles.

## Auth & onboarding
Sign-in → `/` redirects to `/dashboard` → shell loads workspace (creates tenant rows if missing) → redirects to `/onboarding` until `business_profiles.onboarded = true`.

## Auto-reply rules (`decideReplies`)
1. Disabled → nothing. 2. Keyword match → that reply. 3. First message: outside hours (SAST) → after-hours message; else greeting + question 1. 4. Message n (≤ #questions) → question n. 5. Next → handoff. Then silent.

## WhatsApp Operator integration
- Headers: `X-API-Key: OPERATOR_API_KEY`, `X-App-Id: leadcatch-sa`, `X-Tenant-Id: <tenant uuid>`.
- Connect: `POST /accounts/bootstrap {webhookUrl: <origin>/api/public/whatsapp/webhook}` → `POST /accounts/:id/connect` → poll `/accounts/:id/status` + `/accounts/:id/qr`; optional `POST /accounts/:id/pairing-code`.
- Send: `POST /send {waAccountId, to, text, type:"text"}`.
- Webhook: body `{schemaVersion, waAccountId, appId, tenantId, event, data, deliveredAt}`, header `X-Webhook-Signature` = hex HMAC-SHA256(raw body, WEBHOOK_SECRET). `event:"message"` creates/updates lead, conversation, message, then runs auto-reply. Stored idempotently by (event, messageId); non-2xx lets Operator retry.

## Environment variables (server secrets)
| Name | Purpose |
|---|---|
| OPERATOR_URL | Operator base URL (Render) |
| OPERATOR_API_KEY | Must equal Operator's API key |
| WEBHOOK_SECRET | Must equal Operator's webhook secret |
| SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY / SUPABASE_SERVICE_ROLE_KEY | Managed by Lovable Cloud |
Client: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY` (auto).

## Deployment
Publish from Lovable. The Operator must be able to reach `https://<published-domain>/api/public/whatsapp/webhook`; reconnect WhatsApp from Settings after changing domains so the webhook URL is re-bound.

## Design system
Dark default (bg oklch 0.145 ≈ #0F0F0F), single emerald accent (`--primary`), Geist font, radius 14px (`rounded-xl/2xl`), `shadow-soft` only. No glass/glow/illustrations. Semantic tokens only — no raw colour classes.

## Conventions
Server secrets only inside server fn handlers / server routes. Protected server fns use `requireSupabaseAuth`. Never edit `src/integrations/*` or `routeTree.gen.ts`.
