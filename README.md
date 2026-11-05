# RUNCTRL

Multi-workspace media operations for DOPE Sports Network, RecruitLook Hoops and DOPE VZN.

## Current release state

The feature branch builds and its Preview deployment is READY. **Production promotion is withheld:** Google OAuth is disabled in the shared Supabase project and has no client credentials configured. The real browser sign-in test returned `Unsupported provider: provider is not enabled`. Authenticated browser upload and review tests cannot pass that gate yet.

Preview: https://runctrl-git-feature-operations-v1-booking-3261s-projects.vercel.app/

Intended production URL after validation: https://runctrl-vert.vercel.app/

## Infrastructure

- Repository: `dopevzn/RUNCTRL`, branch `feature/operations-v1`
- Vercel: `runctrl`, `prj_JsIcZHw0Stz2nAq02E1LOph2gzxX`, team `booking-3261s-projects`
- Supabase: DSN Newsroom, `kelzecdcnkeojdohpziy` (shared interim backend)
- Eight RUNCTRL `rc_*` tables with RLS; private `runctrl-media` bucket
- Preview and Production now have `NEXT_PUBLIC_SUPABASE_URL` and the current publishable key under `NEXT_PUBLIC_SUPABASE_ANON_KEY`, configured through the authorized Vercel GUI
- No service-role/secret key is used by the application
- The duplicate Vercel project `runctrl-9u2g` has not been changed or removed

## Implemented workflows and protections

- Google OAuth interface with a useful message if the provider is unavailable
- Current workspace roles: owner, editor, contributor and viewer
- Contributor access requests load without membership; owner resolution grants the requested contributor/viewer role atomically, supports denial and blocks replay
- Assignment creation, contributor requests, member selection, briefs, deadlines and status tracking
- Assignees must be active contributors/editors/owners in the same workspace
- Credential drafts can be edited before authorization; owner approval is server recorded and protected from client edits
- Credential transitions cannot skip approval; authorization locks the approved request details; returning to draft clears approval
- Marking a credential request sent requires owner attestation and an HTTPS evidence link; RUNCTRL sends no email
- Credential status on assignments derives from the credential record
- Rights-attested submission packages, private media uploads and signed downloads
- Uploads limited to 50 MB per file; JPEG, PNG, WebP, TIFF, MP4 and QuickTime
- Metadata must match an existing uploaded storage object; failed metadata registration attempts orphan cleanup
- Asset clearance requires supporting rights notes; package approval requires at least one asset and all assets cleared
- Approved packages reject new uploads and asset changes until reopened for revision
- Workspace/record identities are immutable; the last owner cannot be demoted
- Audit records for assignment status and access, membership, credential, asset and package decisions
- Workspace changes clear previous records and forms; stale responses do not replace current workspace data

## Verified November 5, 2026

- Production build: PASS
- TypeScript: PASS
- Workflow unit tests: 3 PASS
- Hosted database role/RLS regression: 35 PASS, all fixtures rolled back
- Live anonymous REST/RPC isolation: 8 PASS
- Rollback cleanup: zero test users and zero test workspaces remain
- Dependency audit: zero known vulnerabilities at verification time; versions and lockfile are committed
- Security advisor: no RUNCTRL RLS/function warning; the existing shared-project warning is leaked-password protection disabled
- Browser: preview loads with environment configuration; Google sign-in reaches Supabase and is blocked by disabled provider
- Browser login, memberships, uploads, signed downloads, editorial review, responsive authenticated UI and production release: **NOT YET VERIFIED**

The database tests exercise real hosted Postgres permissions and triggers under `authenticated` with different user claims. Their storage rows are rollback-only fixtures; they do not establish that HTTP file uploads work. Do not represent database checks as completed browser end-to-end testing.

## Google OAuth handoff

The Supabase Google configuration panel is prepared at:
https://supabase.com/dashboard/project/kelzecdcnkeojdohpziy/auth/providers?provider=Google

The account owner must enter the Google OAuth Web client ID and client secret directly in that panel, enable Google and save. Do not put the secret in chat, Git or Vercel public variables.

Google Cloud client settings:

- Authorized origins: the Preview origin and intended production origin above
- Authorized redirect URI: `https://kelzecdcnkeojdohpziy.supabase.co/auth/v1/callback`
- Basic identity scopes only: `openid`, email and profile

The two exact RUNCTRL root redirects are saved in Supabase's allowlist. The existing DSN Newsroom redirect and default Site URL remain intact. No wildcard redirect was added.

**New signup remains disabled in the shared DSN project.** New contributors therefore need an invited/provisioned Supabase account before they can sign in and request workspace membership. Do not enable public signup for the shared project without reviewing DSN's existing invite-only boundary. Google setup alone does not change that onboarding restriction.

## Required release gate

1. Enable Google through the owner credential handoff and test the intended existing owner login on Preview.
2. Test no-member account request, owner approval/denial, contributor assignment request and editor assignment approval in the UI.
3. Verify a real small test-file upload, metadata, private signed download, uncleared package rejection, rights clearance, approval and upload lock.
4. Verify workspace switching, contributor/viewer restrictions, sign-out and fresh sign-in on desktop and mobile.
5. Stage the same reviewed commit as Production without domain assignment, verify it, then promote; keep deployment protection enabled.
6. Re-test the protected production URL and inspect runtime errors.

## Development and reproducibility

`npm ci`, `npm test`, `npm run typecheck`, `npm run build`.

Copy `.env.example` into an ignored `.env.local` and use the project's public URL and publishable key only. `node tests/anonymous-api.mjs` checks the live anonymous boundary using `.env.local` and prints no key values.

SQL source order matches hosted migrations: `supabase/operations_v1.sql`, `supabase/security_v2.sql`, `supabase/security_v3.sql`, `supabase/audit_v4.sql`. These target the existing shared DSN database, not a blank standalone database; do not rerun applied files. `supabase/schema.sql` is an older scaffold and is not the current operations schema.

`tests/rls-regression.sql` runs in one transaction and rolls back all fixtures. Run only against the specified project with authorization. It never emails users, contacts hosts or publishes content.

## Operational limits

RUNCTRL does not publish DSN content, send emails, process payments, license images or deliver RAW/large video. Rights notes record a human review; the application cannot independently establish legal ownership. Existing DSN Newsroom records are not imported. File cleanup is best effort if a network failure interrupts upload registration; administrators may need to reconcile unregistered storage objects. No production monitoring integration has been added.
