# RUNCTRL
Production operations dashboard for DSN, RecruitLook Hoops, and DOPE VZN.

## Setup
1. Create a dedicated Supabase project and execute `supabase/schema.sql`.
2. Enable Google provider in Supabase Auth and configure authorized redirect URLs.
3. Add `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` in Vercel environment settings.
4. After the first Google login, add that user to `workspace_members` as admin for the relevant workspaces using the Supabase SQL editor.
5. Deploy with Vercel Git integration.

This is an initial operational foundation, not a production-ready media submission pipeline. Drive URLs are links, not a Google Drive API integration. Never commit secrets.
