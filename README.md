# RUNCTRL

Multi-workspace media operations for DOPE Sports Network, RecruitLook Hoops and DOPE VZN.

## Current release state

RUNCTRL is deployed to Production at https://runctrl-vert.vercel.app/.

Release commit: `86afda699b146a185e9d0a70fd3ccf9d3948a4ba`.
Production deployment: `dpl_6eGG8hnDD8XUqN1SpWj4s2rwnNLT`.
The exact commit was exported from Git, built with Production settings using `--skip-domain`, tested through the approved branch alias, then promoted without rebuilding. Domain assignment completed and live owner/contributor sign-in and private download were re-tested.

Preview: https://runctrl-git-feature-operations-v1-booking-3261s-projects.vercel.app/

Google OAuth remains in **Testing** mode. Google requires completion of Branding before its app can be published; unrestricted onboarding has not been verified. The tested owner and contributor identities both work. RUNCTRL membership remains independently owner-approved.

## Infrastructure

- Repository: `dopevzn/RUNCTRL`, branch `feature/operations-v1`
- Vercel: `runctrl`, `prj_JsIcZHw0Stz2nAq02E1LOph2gzxX`, team `booking-3261s-projects`
- Supabase: DSN Newsroom, `kelzecdcnkeojdohpziy` (shared interim backend)
- Eight RUNCTRL `rc_*` tables with RLS; private `runctrl-media` bucket
- Preview and Production now have `NEXT_PUBLIC_SUPABASE_URL` and the current publishable key under `NEXT_PUBLIC_SUPABASE_ANON_KEY`, configured through the authorized Vercel GUI
- No service-role/secret key is used by the application
- The duplicate Vercel project `runctrl-9u2g` has not been changed or removed

## Implemented workflows and protections

- Google OAuth using PKCE, with a useful message if the provider is unavailable
- Active-session verification in RUNCTRL table and storage policies denies revoked sessions before JWT expiry
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

## Verified November 6, 2026

- Production build: PASS
- TypeScript: PASS
- Workflow unit tests: 3 PASS
- Hosted database role/RLS regression: 39 PASS, all fixtures rolled back
- Live anonymous REST/RPC isolation: 8 PASS
- Rollback cleanup: zero test users and zero test workspaces remain
- Dependency audit: zero known vulnerabilities at verification time; versions and lockfile are committed
- Security advisor: no RUNCTRL RLS/function warning; the existing shared-project warning is leaked-password protection disabled
- Browser: owner Google login, assignments, protected credential approval, private upload and signed download, rights clearance, package approval/upload lock, and workspace switching: PASS
- PKCE sign-in/sign-out with clean callback: PASS for owner and contributor
- No-member request, owner approval, contributor assignment request/owner approval, and another workspace request/denial: PASS in browser
- Contributor can see only DSN and its own assignment/package; owner private fixture remains hidden: PASS
- Contributor real file upload, metadata registration, owner rights review, package approval and upload lock: PASS
- Protected image download: PASS (320 × 180 synthetic PNG)
- Authenticated phone layout: PASS at 390 × 844, no horizontal overflow for tested owner/contributor screens
- Production staged/validated/promoted: PASS; production owner/contributor login, data, restrictions and download re-tested
- Browser console: zero captured errors during staged/live checks
- Vercel error/fatal runtime scan: no matching logs; this static client talks directly to Supabase, so this is not comprehensive monitoring

The database tests exercise real hosted Postgres permissions and triggers under `authenticated` with different user claims. Their storage rows are rollback-only fixtures; they do not establish that HTTP file uploads work. Do not represent database checks as completed browser end-to-end testing.

## Google OAuth configuration

Google is enabled in the intended Supabase project. Client credentials were entered by the account owner. Never put OAuth secrets in chat, Git, public environment variables, or screenshots.

Google Cloud client settings:

- Authorized origins: the Preview origin and intended production origin above
- Authorized redirect URI: `https://kelzecdcnkeojdohpziy.supabase.co/auth/v1/callback`
- Basic identity scopes only: `openid`, email and profile

The two exact RUNCTRL root redirects are saved in Supabase's allowlist. The existing DSN Newsroom redirect and default Site URL remain intact. No wildcard redirect was added.

Google and public signup are enabled in the shared project following the owner setup. A new Google identity still has no RUNCTRL membership until a workspace owner approves its request. Google OAuth currently uses testing mode; authorized test accounts may be required until its Google audience is published.

## Release validation

Owner and contributor workflows passed on the Preview build. The same source was staged with Production environment settings, then fresh login, contributor restrictions, package lock and protected download passed on that exact staged build. The build was promoted without rebuilding. Production domain assignment, fresh owner and contributor login, clean callbacks, data rendering and protected download passed afterward. Deployment protection remains enabled (`all_except_custom_domains`). No external credential emails or content publication occurred.

The database regression uses five temporary identities plus temporary workspaces/sessions inside one rolled-back transaction. Browser tests used the real owner and owner-approved `booking@dopevzn.com` contributor, with two clearly labeled QA assignments/packages and two synthetic images. Those browser fixtures remain for inspection; the contributor membership remains active in DSN only. Its DOPE VZN access request was denied. Its shared DSN Newsroom profile remains inactive.

## Development and reproducibility

`npm ci`, `npm test`, `npm run typecheck`, `npm run build`.

Copy `.env.example` into an ignored `.env.local` and use the project's public URL and publishable key only. `node tests/anonymous-api.mjs` checks the live anonymous boundary using `.env.local` and prints no key values.

SQL source order matches hosted migrations: `supabase/operations_v1.sql`, `supabase/security_v2.sql`, `supabase/security_v3.sql`, `supabase/audit_v4.sql`, then `supabase/migrations/20261106074309_runctrl_session_security_v5.sql`. These target the existing shared DSN database, not a blank standalone database; do not rerun applied files. `supabase/schema.sql` is an older scaffold and is not the current operations schema.

`tests/rls-regression.sql` runs in one transaction and rolls back all fixtures. Run only against the specified project with authorization. It never emails users, contacts hosts or publishes content.

## Operational limits

RUNCTRL does not publish DSN content, send emails, process payments, license images or deliver RAW/large video. Rights notes record a human review; the application cannot independently establish legal ownership. Existing DSN Newsroom records are not imported. File cleanup is best effort if a network failure interrupts upload registration; administrators may need to reconcile unregistered storage objects. No production monitoring integration has been added.
