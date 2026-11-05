-- Apply after runctrl_security_hardening_v2. Only RUNCTRL objects are changed.
begin;
-- Generic JSON comparison avoids referencing fields absent from a trigger's row type.
create or replace function runctrl_private.prevent_reparent()
returns trigger language plpgsql set search_path='' as $$
declare fields text[]; k text;
begin
 fields := case tg_table_name
 when 'rc_assignments' then array['id','workspace_id','created_by']
 when 'rc_credentials' then array['id','workspace_id','assignment_id']
 when 'rc_submissions' then array['id','workspace_id','assignment_id','uploaded_by']
 when 'rc_assets' then array['id','workspace_id','submission_id','uploader_id','storage_path','bytes','mime_type','original_name']
 when 'rc_members' then array['workspace_id','user_id']
 when 'rc_access_requests' then array['id','workspace_id','user_id','email','requested_role'] end;
 foreach k in array fields loop
  if to_jsonb(new)->k is distinct from to_jsonb(old)->k then raise exception 'Record identity is immutable: %',k; end if;
 end loop;
 return new;
end $$;

-- Owner-only resolution remains subject to the existing member and request RLS.
create or replace function public.rc_resolve_access(request_id uuid, decision text)
returns void language plpgsql security invoker set search_path='' as $$
declare r public.rc_access_requests;
begin
 if decision not in ('approved','denied') then raise exception 'Invalid decision'; end if;
 select * into r from public.rc_access_requests where id=request_id for update;
 if not found or not runctrl_private.has_role(r.workspace_id,array['owner']) then raise exception 'Owner access required'; end if;
 if r.status <> 'pending' then raise exception 'Request already resolved'; end if;
 if decision='approved' then
  insert into public.rc_members(workspace_id,user_id,role) values(r.workspace_id,r.user_id,r.requested_role)
  on conflict(workspace_id,user_id) do nothing;
 end if;
 update public.rc_access_requests set status=decision,resolved_at=now() where id=r.id;
end $$;
revoke all on function public.rc_resolve_access(uuid,text) from public,anon;
grant execute on function public.rc_resolve_access(uuid,text) to authenticated;

create or replace function runctrl_private.guard_credential_change()
returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='INSERT' then
  if new.status <> 'draft' or new.approval_by is not null or new.approval_at is not null or new.proof_url<>'' then
   raise exception 'Credentials must begin as unapproved drafts';
  end if;
 else
  if new.approval_by is distinct from old.approval_by or new.approval_at is distinct from old.approval_at then
   raise exception 'Approval evidence is server controlled';
  end if;
  if old.status not in ('draft','approval_required') and
   (new.contact_email,new.contact_name,new.request_notes) is distinct from (old.contact_email,old.contact_name,old.request_notes) then
   raise exception 'Return to draft before editing authorized request details';
  end if;
  if new.status is distinct from old.status then
   if new.status='draft' then new.approval_by:=null;new.approval_at:=null;new.proof_url:='';
   elsif new.status='approval_required' and old.status='draft' then null;
   elsif new.status='authorized' and old.status='approval_required' then
    if not runctrl_private.has_role(new.workspace_id,array['owner']) then raise exception 'Only workspace owner can authorize outreach'; end if;
    if new.contact_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(trim(new.request_notes))<8 then raise exception 'Verified contact and request notes required'; end if;
    new.approval_by:=auth.uid();new.approval_at:=now();
   elsif new.status='sent' and old.status='authorized' and old.approval_at is not null then
    if not runctrl_private.has_role(new.workspace_id,array['owner']) then raise exception 'Owner must attest external sending'; end if;
    if new.proof_url !~ '^https://[^[:space:]]+$' then raise exception 'HTTPS sent-message evidence required'; end if;
   elsif new.status='pending' and old.status='sent' then null;
   elsif new.status in ('granted','denied') and old.status in ('sent','pending') then null;
   else raise exception 'Invalid credential status transition';
   end if;
  end if;
  if new.status in ('sent','pending','granted','denied') and (new.approval_at is null or new.approval_by is null or new.proof_url !~ '^https://[^[:space:]]+$') then
   raise exception 'Authorization and HTTPS evidence required';
  end if;
 end if;
 new.updated_at:=now();return new;
end $$;
drop trigger rc_credential_status_guard on public.rc_credentials;
create trigger rc_credential_status_guard before insert or update on public.rc_credentials for each row execute function runctrl_private.guard_credential_change();

create or replace function runctrl_private.guard_assignment()
returns trigger language plpgsql set search_path='' as $$
declare actual text;
begin
 if new.assigned_to is not null and not exists(select 1 from public.rc_members where workspace_id=new.workspace_id and user_id=new.assigned_to and role in ('owner','editor','contributor')) then raise exception 'Assignee must be an active contributor or editor in this workspace'; end if;
 select status into actual from public.rc_credentials where assignment_id=new.id;
 if new.credential_status <> coalesce(actual,'not_requested') then raise exception 'Credential status is derived from the credential record'; end if;
 new.updated_at:=now();return new;
end $$;
create trigger rc_assignment_guard before insert or update on public.rc_assignments for each row execute function runctrl_private.guard_assignment();
create or replace function runctrl_private.sync_credential_status()
returns trigger language plpgsql set search_path='' as $$
begin update public.rc_assignments set credential_status=new.status where id=new.assignment_id;return new;end $$;
create trigger rc_credential_sync after insert or update on public.rc_credentials for each row execute function runctrl_private.sync_credential_status();

-- Lock a package while its assets change; package approval takes the same row lock.
create or replace function runctrl_private.validate_asset_parent()
returns trigger language plpgsql security definer set search_path='' as $$
declare s public.rc_submissions;
begin
 select * into s from public.rc_submissions where id=new.submission_id for update;
 if not found or s.workspace_id<>new.workspace_id or s.uploaded_by<>new.uploader_id then raise exception 'Asset parent is invalid';end if;
 if not runctrl_private.has_role(s.workspace_id,array['owner','editor','contributor']) or (s.uploaded_by<>auth.uid() and not runctrl_private.has_role(s.workspace_id,array['owner','editor'])) then raise exception 'Asset access denied';end if;
 if s.status not in ('submitted','revision') then raise exception 'Reopen the package for revision before changing its assets';end if;
 if new.mime_type not in ('image/jpeg','image/png','image/webp','image/tiff','video/mp4','video/quicktime') then raise exception 'Unsupported media type';end if;
 if not exists(select 1 from storage.objects o where o.bucket_id='runctrl-media' and o.name=new.storage_path and (o.metadata->>'size')::bigint=new.bytes and o.metadata->>'mimetype'=new.mime_type) then raise exception 'Matching uploaded object is required';end if;
 return new;
end $$;
drop trigger rc_asset_parent on public.rc_assets;
create trigger rc_asset_parent before insert or update on public.rc_assets for each row execute function runctrl_private.validate_asset_parent();
create or replace function runctrl_private.validate_submission_release()
returns trigger language plpgsql set search_path='' as $$
begin
 if new.status='published' and old.status is distinct from new.status then raise exception 'Publication is not enabled in RUNCTRL';end if;
 if new.status in ('approved','published') then
  if not new.rights_attested or not exists(select 1 from public.rc_assets a where a.submission_id=new.id)
   or exists(select 1 from public.rc_assets a where a.submission_id=new.id and (a.review_status<>'approved' or a.rights_status<>'cleared' or length(trim(a.rights_note))<8)) then raise exception 'Cannot approve without cleared assets';end if;
 end if;
 return new;
end $$;
-- Policies are replaced narrowly; unrelated DSN policies are untouched.
drop policy "RUNCTRL uploader may upload to own submission" on storage.objects;
create policy "RUNCTRL uploader may upload to own submission" on storage.objects for insert to authenticated with check(
 bucket_id='runctrl-media' and exists(select 1 from public.rc_submissions s where s.id::text=(storage.foldername(name))[3] and s.workspace_id::text=(storage.foldername(name))[1] and s.uploaded_by=auth.uid() and (storage.foldername(name))[2]=auth.uid()::text and s.status in ('submitted','revision') and runctrl_private.has_role(s.workspace_id,array['owner','editor','contributor']))
);
-- Permit only uploader cleanup before a metadata row exists, for failed metadata writes.
create policy "RUNCTRL uploader removes orphan uploads" on storage.objects for delete to authenticated using(
 bucket_id='runctrl-media' and (storage.foldername(name))[2]=auth.uid()::text and runctrl_private.has_role(((storage.foldername(name))[1])::uuid,array['owner','editor','contributor']) and not exists(select 1 from public.rc_assets a where a.storage_path=name)
);
update storage.buckets set allowed_mime_types=array['image/jpeg','image/png','image/webp','image/tiff','video/mp4','video/quicktime'] where id='runctrl-media';
revoke all on function runctrl_private.guard_assignment(),runctrl_private.sync_credential_status() from public;
commit;
