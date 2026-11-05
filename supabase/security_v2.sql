
-- RUNCTRL security hardening: limit all grants to explicit workspace membership.
-- The existing DSN "unfinished package" policy previously matched *other buckets*.
drop policy if exists "DSN uploads require an unfinished package" on storage.objects;
create policy "DSN uploads require an unfinished package" on storage.objects for insert to authenticated
with check (
 bucket_id='dsn-submissions'
 and exists(select 1 from public.submissions s
   where s.id::text=(storage.foldername(name))[2]
   and s.contributor_id=(select auth.uid())
   and not s.upload_complete)
);
drop policy if exists "RUNCTRL uploader may upload to own submission" on storage.objects;
create policy "RUNCTRL uploader may upload to own submission" on storage.objects for insert to authenticated
with check(
 bucket_id='runctrl-media'
 and exists(
  select 1 from public.rc_submissions s
  where s.id::text=(storage.foldername(name))[3]
   and s.workspace_id::text=(storage.foldername(name))[1]
   and s.uploaded_by=(select auth.uid())
   and (storage.foldername(name))[2]=(select auth.uid())::text
   and runctrl_private.has_role(s.workspace_id,array['owner','editor','contributor'])
 )
);
drop policy if exists "RUNCTRL uploader and editors can download" on storage.objects;
create policy "RUNCTRL uploader and editors can download" on storage.objects for select to authenticated
using(
 bucket_id='runctrl-media'
 and exists(
  select 1 from public.rc_members m where m.workspace_id::text=(storage.foldername(name))[1]
   and m.user_id=(select auth.uid())
   and (m.role in ('owner','editor') or (m.role='contributor' and
    (storage.foldername(name))[2]=(select auth.uid())::text))
 )
);
drop policy if exists "Member reads relevant assignments" on public.rc_assignments;
create policy "Member reads relevant assignments" on public.rc_assignments for select to authenticated
using(
 runctrl_private.has_role(workspace_id,array['owner','editor'])
 or (runctrl_private.has_role(workspace_id,array['contributor']) and
   (assigned_to=(select auth.uid()) or created_by=(select auth.uid())))
);
drop policy if exists "Credential access by editors and assignee" on public.rc_credentials;
create policy "Credential access by editors and assignee" on public.rc_credentials for select to authenticated
using(
 runctrl_private.has_role(workspace_id,array['owner','editor'])
 or (runctrl_private.has_role(workspace_id,array['contributor']) and exists(
   select 1 from public.rc_assignments a where a.id=assignment_id
    and a.workspace_id=rc_credentials.workspace_id and a.assigned_to=(select auth.uid())
 ))
);
drop policy if exists "Members read authorized submissions" on public.rc_submissions;
create policy "Members read authorized submissions" on public.rc_submissions for select to authenticated
using(runctrl_private.has_role(workspace_id,array['owner','editor']) or
 (runctrl_private.has_role(workspace_id,array['contributor']) and uploaded_by=(select auth.uid())));
drop policy if exists "Owner/editor or uploader reads assets" on public.rc_assets;
create policy "Owner/editor or uploader reads assets" on public.rc_assets for select to authenticated
using(runctrl_private.has_role(workspace_id,array['owner','editor']) or
 (runctrl_private.has_role(workspace_id,array['contributor']) and uploader_id=(select auth.uid())));
drop policy if exists "Uploader adds own assets" on public.rc_assets;
create policy "Uploader adds own assets" on public.rc_assets for insert to authenticated
with check(
 uploader_id=(select auth.uid()) and review_status='pending' and rights_status='unreviewed'
 and runctrl_private.has_role(workspace_id,array['owner','editor','contributor'])
 and storage_path like workspace_id::text||'/'||(select auth.uid())::text||'/'||submission_id::text||'/%'
 and exists(select 1 from public.rc_submissions s where s.id=submission_id
   and s.workspace_id=rc_assets.workspace_id and s.uploaded_by=(select auth.uid()))
);
drop policy if exists "Assigned contributor submits with rights attestation" on public.rc_submissions;
create policy "Assigned contributor submits with rights attestation" on public.rc_submissions for insert to authenticated
with check(
 uploaded_by=(select auth.uid()) and rights_attested and status='submitted'
 and runctrl_private.has_role(workspace_id,array['owner','editor','contributor'])
 and exists(select 1 from public.rc_assignments a where a.id=assignment_id
  and a.workspace_id=rc_submissions.workspace_id
  and a.status in ('approved','assigned','in_progress','review','completed')
  and (a.assigned_to=(select auth.uid()) or runctrl_private.has_role(a.workspace_id,array['owner','editor'])))
);

