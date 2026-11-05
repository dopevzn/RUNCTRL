# RUNCTRL

RUNCTRL is a multi-workspace production operations interface for DOPE Sports Network, RecruitLook Hoops, and DOPE VZN.

## What is implemented in the operations-v1 branch

- Google OAuth sign-in through Supabase Auth
- Workspace-specific roles: owner, editor, contributor, viewer
- Contributor access request and owner approval
- Assignments, briefs, due dates, and workflow statuses
- Credential drafts, authorization tracking, and documentary approval links
- Rights-attested media submission packages with restricted uploads (50 MB per file)
- Asset rights review, restricted signed URL downloads, and submission approval gates
- Audit records on assignment status changes
- Responsive dashboard and workspace navigation

**This is not yet a production-approved release.** GitHub/Vercel builds passing does not verify OAuth or media upload workflows.

## Existing infrastructure

- GitHub: `dopevzn/RUNCTRL`
- Vercel project: `runctrl` (use this as the primary project; the duplicate `runctrl-9u2g` has not been removed)
- Supabase project: DSN Newsroom (`kelzecdcnkeojdohpziy`), an interim shared database
- RUNCTRL public tables use the `rc_` prefix and enforce RLS
- Media bucket: `runctrl-media`, private, 50 MB per file
- SQL base file: `supabase/operations_v1.sql`
- Applied Supabase migrations: `runctrl_operations_v1` and `runctrl_security_hardening_v2`

## Deployment blocker

The connected Vercel identity returns HTTP 403 when trying to list **or create** environment variables on project `runctrl`. An administrator must grant project environment-variable management access or configure these two public client variables in Vercel Project Settings > Environment Variables:

- `NEXT_PUBLIC_SUPABASE_URL` = `https://kelzecdcnkeojdohpziy.supabase.co`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` = Supabase project's enabled **publishable** API key (retrieve from Supabase Dashboard > Project Settings > API Keys; never use the service-role/secret key)

Add both variables to Preview and Production environments, then redeploy the preview. Verify Google OAuth callback URL is authorized for the deployed preview and intended production domain.

## Release acceptance checklist

- [ ] Confirm the OAuth flow succeeds on preview and the expected owner account is assigned
- [ ] Confirm different workspaces never expose one another's assignments or files
- [ ] Confirm pending contributor has no member access until explicitly approved
- [ ] Confirm contributor cannot create owner/editor memberships or approve credentials
- [ ] Confirm owner can approve credential outreach and no email is sent automatically
- [ ] Confirm upload, private signed preview, rights clearance and package approval
- [ ] Confirm a submission with unapproved assets cannot be approved or published
- [ ] Confirm upload error reconciliation; orphaned files are manually recoverable
- [ ] Confirm a protected production URL, audit logs and rollback plan
- [ ] Test on desktop and mobile before promoting to production

## Important boundaries

RUNCTRL currently **does not automatically email credential contacts, publish DSN articles, process payments, license images, or deliver large RAW/video files**. Keep those operations separate until approved integrations are built and validated. Existing DSN Newsroom records are not imported into RUNCTRL.

The Google OAuth and media-upload interfaces are implemented but not yet end-to-end tested. Do not advertise the application as complete until all acceptance checks pass.

