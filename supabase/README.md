# Supabase backend (free tier)

| Path | What it is |
|---|---|
| `migrations/20260928000001_init.sql` | `flowmoney` schema: tables, Row Level Security, server timestamps, profile trigger, `delete_my_account()` |
| `tests/rls_test.sql` | pgTAP tests: users can't see, change or reference each other's data (run in CI) |
| `config.toml` | Local stack config for `supabase db start` / `supabase test db` |

## Set up your project (~5 minutes, no credit card)

1. [supabase.com](https://supabase.com) → **New project** (Free plan). Pick a strong DB password and a region near you.
2. **SQL Editor → New query** → paste all of `migrations/20260928000001_init.sql` → **Run**.
   Everything is created in its own `flowmoney` schema, so it can share a project with other apps
   (this demo shares one with NovaShop) without touching their tables.
3. **Integrations → Data API → Settings → Exposed schemas**: add `flowmoney`. Leave its tables' "custom grants"
   as they are — the migration deliberately grants signed-in users only (no anonymous access).
4. **Authentication → URL Configuration → Redirect URLs**: add `flowmoney://auth/confirm` and `flowmoney://auth/reset`
   (the sign-up confirmation and password-reset emails open the app through these).
5. **Authentication → Sign In / Providers → Email**:
   - For demos, turn **Confirm email** off (the app also supports it on: it shows "check your inbox").
   - Set the minimum password length to **8** (matches the in-app checklist).
6. **Project Settings → API Keys**: copy the project URL's host and the **publishable** key into
   `Config/Supabase.local.xcconfig` (copy it from `Config/Supabase.local.example.xcconfig`):

   ```
   SUPABASE_HOST = abcdefghijkl.supabase.co
   SUPABASE_PUBLISHABLE_KEY = sb_publishable_…
   ```

   **Never** use the secret / `service_role` key in the app.
7. `make run`. Settings → *Data & Sync* shows `Supabase · <host>`; sign up and your data syncs.

With the CLI instead: `supabase link --project-ref <ref> && supabase db push`.

## Run the database tests locally (needs Docker)

```bash
supabase db start      # local Postgres with the migration applied
supabase test db       # pgTAP: 14 RLS / constraint assertions
```

## Free-tier notes
- Projects pause after 7 days without activity — resume from the dashboard in one click.
- Built-in email sending is rate-limited; keep "Confirm email" off for demos or add a free SMTP provider.

## Sharing a project with another app

FlowMoney lives entirely in the `flowmoney` schema. The only shared object is the Supabase Auth user list, so one
login works in both apps. `flowmoney.delete_my_account()` therefore deletes the user's FlowMoney data but **not** the
shared login (that would cascade into the other app's data). In a dedicated project, deleting `auth.users` is fine.
