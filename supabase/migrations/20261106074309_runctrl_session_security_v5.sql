-- A revoked session must not retain RUNCTRL access until its JWT expires.
-- This private lookup needs definer privileges to read the protected auth schema.
create or replace function runctrl_private.active_session()
returns boolean language sql stable security definer set search_path = ''
as $$
 select exists (
  select 1 from auth.sessions s
  where s.id::text = (select auth.jwt()->>'session_id')
    and s.user_id = (select auth.uid())
    and (s.not_after is null or s.not_after > now())
 )
$$;
revoke all on function runctrl_private.active_session() from public,anon;
grant execute on function runctrl_private.active_session() to authenticated;

create or replace function runctrl_private.has_role(w uuid, roles text[])
returns boolean language sql stable security definer set search_path = ''
as $$ select runctrl_private.active_session() and exists (
 select 1 from public.rc_members m
 where m.workspace_id=w and m.user_id=(select auth.uid()) and m.role=any(roles)
) $$;

-- Restrictive policies also cover directory, self-membership, and access requests.
do $$ declare t text; begin
 foreach t in array array['rc_workspaces','rc_members','rc_access_requests','rc_assignments','rc_credentials','rc_submissions','rc_assets','rc_audit'] loop
  execute format('create policy "RUNCTRL requires active session" on public.%I as restrictive for all to authenticated using ((select runctrl_private.active_session())) with check ((select runctrl_private.active_session()))',t);
 end loop;
end $$;

-- Other applications sharing this project retain their existing storage behavior.
create policy "RUNCTRL storage requires active session" on storage.objects
as restrictive for all to authenticated
using (bucket_id <> 'runctrl-media' or (select runctrl_private.active_session()))
with check (bucket_id <> 'runctrl-media' or (select runctrl_private.active_session()));
