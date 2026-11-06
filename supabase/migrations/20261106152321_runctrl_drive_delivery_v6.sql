begin;
alter table public.rc_assignments add column delivery_folder_url text not null default '' check(delivery_folder_url='' or delivery_folder_url ~ '^https://drive[.]google[.]com/drive/folders/[A-Za-z0-9_-]{10,200}$');
alter table public.rc_submissions
 add column source text not null default 'upload' check(source in ('upload','drive')),
 add column drive_folder_url text not null default '',
 add column drive_file_count integer,
 add column drive_total_bytes bigint,
 add column drive_verified boolean not null default false,
 add column drive_verified_by uuid references auth.users(id),
 add column drive_verified_at timestamptz,
 add column drive_verification_note text not null default '',
 add constraint rc_drive_manifest check (
  (source='upload' and drive_folder_url='' and drive_file_count is null and drive_total_bytes is null)
  or (source='drive' and drive_folder_url ~ '^https://drive[.]google[.]com/drive/folders/[A-Za-z0-9_-]{10,200}$' and drive_file_count is not null and drive_total_bytes is not null and drive_file_count>0 and drive_file_count<=1000000 and drive_total_bytes>0)
 );
create table public.rc_storage_locations (
 workspace_id uuid primary key references public.rc_workspaces(id),
 library_url text not null check(library_url ~ '^https://drive[.]google[.]com/drive/folders/[A-Za-z0-9_-]{10,200}$')
);
alter table public.rc_storage_locations enable row level security;
grant select on public.rc_storage_locations to authenticated;
create policy "Editors read workspace storage library" on public.rc_storage_locations for select to authenticated using(runctrl_private.has_role(workspace_id,array['owner','editor']));

create function runctrl_private.guard_delivery_folder() returns trigger language plpgsql set search_path='' as $$
begin
 if (tg_op='INSERT' and new.delivery_folder_url<>'') or (tg_op='UPDATE' and new.delivery_folder_url is distinct from old.delivery_folder_url) then
  if not runctrl_private.has_role(new.workspace_id,array['owner','editor']) then raise exception 'Only editors set delivery folders';end if;
 end if;
 return new;
end $$;
revoke all on function runctrl_private.guard_delivery_folder() from public;
create trigger rc_assignment_delivery before insert or update on public.rc_assignments for each row execute function runctrl_private.guard_delivery_folder();

create function runctrl_private.guard_drive_delivery() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='INSERT' then
  if new.drive_verified or new.drive_verified_by is not null or new.drive_verified_at is not null or new.drive_verification_note<>'' then raise exception 'Drive verification must be recorded by an editor after submission';end if;
  if new.source='drive' and not exists(select 1 from public.rc_assignments a where a.id=new.assignment_id and a.workspace_id=new.workspace_id and a.delivery_folder_url=new.drive_folder_url and a.delivery_folder_url<>'') then raise exception 'Use the assigned Drive delivery folder';end if;
 else
  if row(new.source,new.drive_folder_url,new.drive_file_count,new.drive_total_bytes) is distinct from row(old.source,old.drive_folder_url,old.drive_file_count,old.drive_total_bytes) then raise exception 'Delivery manifest is immutable; submit a new version';end if;
  if new.drive_verified_by is distinct from old.drive_verified_by or new.drive_verified_at is distinct from old.drive_verified_at then raise exception 'Drive verification identity and time are server controlled';end if;
  if new.status='revision' and old.status is distinct from new.status then
   new.drive_verified:=false;new.drive_verified_by:=null;new.drive_verified_at:=null;new.drive_verification_note:='';
  elsif new.drive_verified is distinct from old.drive_verified or new.drive_verification_note is distinct from old.drive_verification_note then
   if old.status='approved' then raise exception 'Reopen the package before changing Drive verification';end if;
   if new.source<>'drive' or not runctrl_private.has_role(new.workspace_id,array['owner','editor']) then raise exception 'Editor Drive verification required';end if;
   if new.drive_verified then
    if length(trim(new.drive_verification_note))<8 then raise exception 'Record file completeness and rights evidence';end if;
    new.drive_verified_by:=auth.uid();new.drive_verified_at:=now();
   else new.drive_verified_by:=null;new.drive_verified_at:=null;end if;
  end if;
 end if;
 return new;
end $$;
revoke all on function runctrl_private.guard_drive_delivery() from public;
create trigger rc_drive_delivery_guard before insert or update on public.rc_submissions for each row execute function runctrl_private.guard_drive_delivery();

create or replace function runctrl_private.validate_submission_release()
returns trigger language plpgsql set search_path='' as $$
begin
 if new.status='published' and old.status is distinct from new.status then raise exception 'Publication is not enabled in RUNCTRL';end if;
 if new.status in ('approved','published') then
  if new.source='drive' then
   if not new.rights_attested or not new.drive_verified or new.drive_verified_by is null or new.drive_verified_at is null or length(trim(new.drive_verification_note))<8 then raise exception 'Verify Drive completeness and rights before approval';end if;
  elsif not new.rights_attested or not exists(select 1 from public.rc_assets a where a.submission_id=new.id)
   or exists(select 1 from public.rc_assets a where a.submission_id=new.id and (a.review_status<>'approved' or a.rights_status<>'cleared' or length(trim(a.rights_note))<8)) then raise exception 'Cannot approve without cleared assets';end if;
 end if;
 return new;
end $$;
create or replace function runctrl_private.validate_asset_parent()
returns trigger language plpgsql security definer set search_path='' as $$
declare s public.rc_submissions;
begin
 select * into s from public.rc_submissions where id=new.submission_id for update;
 if not found or s.workspace_id<>new.workspace_id or s.uploaded_by<>new.uploader_id then raise exception 'Asset parent is invalid';end if;
 if not runctrl_private.has_role(s.workspace_id,array['owner','editor','contributor']) or (s.uploaded_by<>auth.uid() and not runctrl_private.has_role(s.workspace_id,array['owner','editor'])) then raise exception 'Asset access denied';end if;
 if s.source='drive' then raise exception 'Drive deliveries do not accept internal uploads';end if;
 if s.status not in ('submitted','revision') then raise exception 'Reopen the package for revision before changing its assets';end if;
 if new.mime_type not in ('image/jpeg','image/png','image/webp','image/tiff','video/mp4','video/quicktime') then raise exception 'Unsupported media type';end if;
 if not exists(select 1 from storage.objects o where o.bucket_id='runctrl-media' and o.name=new.storage_path and (o.metadata->>'size')::bigint=new.bytes and o.metadata->>'mimetype'=new.mime_type) then raise exception 'Matching uploaded object is required';end if;
 return new;
end $$;
drop policy "RUNCTRL uploader may upload to own submission" on storage.objects;
create policy "RUNCTRL uploader may upload to own submission" on storage.objects for insert to authenticated with check(
 bucket_id='runctrl-media' and exists(select 1 from public.rc_submissions s where s.id::text=(storage.foldername(name))[3] and s.workspace_id::text=(storage.foldername(name))[1] and s.uploaded_by=auth.uid() and (storage.foldername(name))[2]=auth.uid()::text and s.source='upload' and s.status in ('submitted','revision') and runctrl_private.has_role(s.workspace_id,array['owner','editor','contributor']))
);
commit;
