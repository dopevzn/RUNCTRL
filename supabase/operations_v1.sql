-- RUNCTRL Operations v1. Namespaced tables do not alter DSN newsroom records.
-- Intended for the existing active DSN Newsroom Supabase project as an initial shared backend.
create extension if not exists pgcrypto;
create schema if not exists runctrl_private;
revoke all on schema runctrl_private from public;
grant usage on schema runctrl_private to authenticated;

create table if not exists public.rc_workspaces (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]+$'),
  name text not null,
  created_at timestamptz not null default now()
);
create table if not exists public.rc_members (
  workspace_id uuid not null references public.rc_workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','editor','contributor','viewer')),
  created_at timestamptz not null default now(),
  primary key(workspace_id,user_id)
);
create or replace function runctrl_private.has_role(w uuid, roles text[])
returns boolean language sql stable security definer set search_path = ''
as $$ select exists(
  select 1 from public.rc_members m
  where m.workspace_id=w and m.user_id=(select auth.uid()) and m.role=any(roles)
) $$;
revoke all on function runctrl_private.has_role(uuid,text[]) from public;
grant execute on function runctrl_private.has_role(uuid,text[]) to authenticated;

create table if not exists public.rc_access_requests (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.rc_workspaces(id),
  user_id uuid not null references auth.users(id),
  email text not null,
  requested_role text not null default 'contributor' check(requested_role in ('contributor','viewer')),
  status text not null default 'pending' check(status in ('pending','approved','denied')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique(workspace_id,user_id)
);
create table if not exists public.rc_assignments (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.rc_workspaces(id),
  title text not null check(length(trim(title)) between 3 and 200),
  sport text not null default '',
  venue text not null default '',
  event_at timestamptz,
  deadline_at timestamptz,
  brief text not null default '',
  assigned_to uuid references auth.users(id),
  created_by uuid not null default auth.uid() references auth.users(id),
  status text not null default 'requested' check(status in ('requested','approved','assigned','in_progress','review','completed','declined')),
  credential_status text not null default 'not_requested' check(credential_status in ('not_requested','draft','approval_required','authorized','sent','pending','granted','denied')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists rc_assignments_workspace_event_idx on public.rc_assignments(workspace_id,event_at desc);
create index if not exists rc_assignments_assignee_idx on public.rc_assignments(assigned_to);

create table if not exists public.rc_credentials (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null unique references public.rc_assignments(id) on delete cascade,
  workspace_id uuid not null references public.rc_workspaces(id),
  contact_email text not null default '',
  contact_name text not null default '',
  request_notes text not null default '',
  status text not null default 'draft' check(status in ('draft','approval_required','authorized','sent','pending','granted','denied')),
  approval_by uuid references auth.users(id),
  approval_at timestamptz,
  proof_url text not null default '',
  updated_at timestamptz not null default now()
);
create table if not exists public.rc_submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.rc_assignments(id),
  workspace_id uuid not null references public.rc_workspaces(id),
  uploaded_by uuid not null default auth.uid() references auth.users(id),
  title text not null,
  notes text not null default '',
  rights_attested boolean not null default false,
  status text not null default 'submitted' check(status in ('submitted','revision','approved','published')),
  created_at timestamptz not null default now()
);
create index if not exists rc_submissions_workspace_idx on public.rc_submissions(workspace_id,created_at desc);

create table if not exists public.rc_assets (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.rc_submissions(id) on delete cascade,
  workspace_id uuid not null references public.rc_workspaces(id),
  uploader_id uuid not null default auth.uid() references auth.users(id),
  original_name text not null,
  storage_path text not null unique,
  mime_type text not null,
  bytes bigint not null check(bytes between 1 and 50000000),
  caption text not null default '',
  review_status text not null default 'pending' check(review_status in ('pending','approved','rejected')),
  rights_status text not null default 'unreviewed' check(rights_status in ('unreviewed','cleared','restricted')),
  rights_note text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists rc_assets_submission_idx on public.rc_assets(submission_id);

create table if not exists public.rc_audit (
  id bigint generated always as identity primary key,
  workspace_id uuid not null references public.rc_workspaces(id),
  actor_id uuid,
  entity text not null,
  entity_id uuid not null,
  action text not null,
  prior_status text,
  next_status text,
  created_at timestamptz not null default now()
);

alter table public.rc_workspaces enable row level security;
alter table public.rc_members enable row level security;
alter table public.rc_access_requests enable row level security;
alter table public.rc_assignments enable row level security;
alter table public.rc_credentials enable row level security;
alter table public.rc_submissions enable row level security;
alter table public.rc_assets enable row level security;
alter table public.rc_audit enable row level security;

grant select on public.rc_workspaces to authenticated;
grant select,insert,update on public.rc_members to authenticated;
grant select,insert,update on public.rc_access_requests to authenticated;
grant select,insert,update on public.rc_assignments to authenticated;
grant select,insert,update on public.rc_credentials to authenticated;
grant select,insert,update on public.rc_submissions to authenticated;
grant select,insert,update on public.rc_assets to authenticated;
grant select on public.rc_audit to authenticated;

create policy "Authenticated sees workspace directory" on public.rc_workspaces for select to authenticated using (true);
create policy "Members read self and owner sees team" on public.rc_members for select to authenticated
 using(user_id=(select auth.uid()) or runctrl_private.has_role(workspace_id,array['owner','editor']));
create policy "Owner adds workspace members" on public.rc_members for insert to authenticated
 with check(runctrl_private.has_role(workspace_id,array['owner']));
create policy "Owner manages workspace members" on public.rc_members for update to authenticated
 using(runctrl_private.has_role(workspace_id,array['owner']))
 with check(runctrl_private.has_role(workspace_id,array['owner']));
create policy "User or owner reads access request" on public.rc_access_requests for select to authenticated
 using(user_id=(select auth.uid()) or runctrl_private.has_role(workspace_id,array['owner']));
create policy "Signed in users request own access" on public.rc_access_requests for insert to authenticated
 with check(user_id=(select auth.uid()) and email=coalesce((select auth.jwt()->>'email'),'') and status='pending');
create policy "Owner resolves access requests" on public.rc_access_requests for update to authenticated
 using(runctrl_private.has_role(workspace_id,array['owner']))
 with check(runctrl_private.has_role(workspace_id,array['owner']));
create policy "Member reads relevant assignments" on public.rc_assignments for select to authenticated
 using(runctrl_private.has_role(workspace_id,array['owner','editor']) or assigned_to=(select auth.uid()) or created_by=(select auth.uid()));
create policy "Contributor requests or editor creates assignment" on public.rc_assignments for insert to authenticated
 with check(
  created_by=(select auth.uid()) and (
   runctrl_private.has_role(workspace_id,array['owner','editor']) or
   (runctrl_private.has_role(workspace_id,array['contributor']) and assigned_to=(select auth.uid()) and status='requested' and credential_status='not_requested')
  )
 );
create policy "Editor updates assignments" on public.rc_assignments for update to authenticated
 using(runctrl_private.has_role(workspace_id,array['owner','editor']))
 with check(runctrl_private.has_role(workspace_id,array['owner','editor']));
create policy "Credential access by editors and assignee" on public.rc_credentials for select to authenticated
 using(runctrl_private.has_role(workspace_id,array['owner','editor']) or exists (select 1 from public.rc_assignments a where a.id=assignment_id and a.assigned_to=(select auth.uid())));
create policy "Editors create credential drafts" on public.rc_credentials for insert to authenticated
 with check(runctrl_private.has_role(workspace_id,array['owner','editor']) and status='draft'
  and exists(select 1 from public.rc_assignments a where a.id=assignment_id and a.workspace_id=rc_credentials.workspace_id));
create policy "Editors manage credential drafts" on public.rc_credentials for update to authenticated
 using(runctrl_private.has_role(workspace_id,array['owner','editor']))
 with check(runctrl_private.has_role(workspace_id,array['owner','editor']));
create policy "Members read authorized submissions" on public.rc_submissions for select to authenticated
 using(uploaded_by=(select auth.uid()) or runctrl_private.has_role(workspace_id,array['owner','editor']));
create policy "Assigned contributor submits with rights attestation" on public.rc_submissions for insert to authenticated
 with check(uploaded_by=(select auth.uid()) and rights_attested and status='submitted'
  and exists(select 1 from public.rc_assignments a where a.id=assignment_id and a.workspace_id=rc_submissions.workspace_id
   and a.status in ('approved','assigned','in_progress','review','completed')
   and (a.assigned_to=(select auth.uid()) or runctrl_private.has_role(a.workspace_id,array['owner','editor']))));
create policy "Editor reviews submissions" on public.rc_submissions for update to authenticated
 using(runctrl_private.has_role(workspace_id,array['owner','editor']))
 with check(runctrl_private.has_role(workspace_id,array['owner','editor']));
create policy "Owner/editor or uploader reads assets" on public.rc_assets for select to authenticated
 using(uploader_id=(select auth.uid()) or runctrl_private.has_role(workspace_id,array['owner','editor']));
create policy "Uploader adds own assets" on public.rc_assets for insert to authenticated
 with check(
 uploader_id=(select auth.uid()) and review_status='pending' and rights_status='unreviewed'
 and storage_path like workspace_id::text||'/'||(select auth.uid())::text||'/'||submission_id::text||'/%'
 and exists(select 1 from public.rc_submissions s where s.id=submission_id and s.workspace_id=rc_assets.workspace_id and s.uploaded_by=(select auth.uid()))
 );
create policy "Editor reviews assets" on public.rc_assets for update to authenticated
 using(runctrl_private.has_role(workspace_id,array['owner','editor']))
 with check(runctrl_private.has_role(workspace_id,array['owner','editor']));
create policy "Owner/editor reads audit" on public.rc_audit for select to authenticated
 using(runctrl_private.has_role(workspace_id,array['owner','editor']));

create or replace function runctrl_private.guard_credential_change()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
 if new.status <> old.status then
   if new.status='authorized' then
     if not runctrl_private.has_role(new.workspace_id,array['owner']) then
       raise exception 'Only workspace owner can authorize outbound credential requests';
     end if;
     new.approval_by := auth.uid();
     new.approval_at := now();
   elsif new.status='sent' and (old.status <> 'authorized' or old.approval_at is null) then
     raise exception 'Owner authorization required before marking as sent';
   elsif new.status='granted' and length(trim(new.proof_url)) < 8 then
     raise exception 'Written approval evidence required before marking granted';
   end if;
 end if;
 new.updated_at := now();
 return new;
end $$;
revoke all on function runctrl_private.guard_credential_change() from public;
create trigger rc_credential_status_guard before update on public.rc_credentials
for each row execute function runctrl_private.guard_credential_change();

create or replace function runctrl_private.guard_asset_review()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
 if (new.review_status='approved' or new.rights_status='cleared')
 and (new.rights_status <> 'cleared' or new.review_status <> 'approved' or length(trim(new.rights_note))<8) then
   raise exception 'Approval requires rights clearance and supporting rights notes';
 end if;
 return new;
end $$;
revoke all on function runctrl_private.guard_asset_review() from public;
create trigger rc_asset_rights_guard before update on public.rc_assets
for each row execute function runctrl_private.guard_asset_review();

create or replace function runctrl_private.log_assignment_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
 if new.status is distinct from old.status then
  insert into public.rc_audit(workspace_id,actor_id,entity,entity_id,action,prior_status,next_status)
  values(new.workspace_id,auth.uid(),'assignment',new.id,'status_change',old.status,new.status);
 end if;
 return new;
end $$;
revoke all on function runctrl_private.log_assignment_change() from public;
create trigger rc_assignment_audit after update on public.rc_assignments
for each row execute function runctrl_private.log_assignment_change();

insert into public.rc_workspaces(slug,name) values
('dsn','DOPE Sports Network'),('recruitlook','RecruitLook Hoops'),('dopevzn','DOPE VZN')
on conflict(slug) do nothing;

-- Bootstrap only the existing DSN active admin. No other user gains owner privileges.
insert into public.rc_members(workspace_id,user_id,role)
select w.id,p.id,'owner' from public.rc_workspaces w cross join public.profiles p
where p.role='admin' and p.active and w.slug in ('dsn','recruitlook','dopevzn')
on conflict do nothing;

insert into storage.buckets(id,name,public,file_size_limit)
values('runctrl-media','runctrl-media',false,50000000)
on conflict(id) do nothing;

create policy "RUNCTRL uploader may upload to own submission" on storage.objects for insert to authenticated
 with check(bucket_id='runctrl-media' and
  exists(select 1 from public.rc_submissions s where s.id::text=(storage.foldername(name))[3]
   and s.workspace_id::text=(storage.foldername(name))[1]
   and s.uploaded_by=(select auth.uid()) and
   (storage.foldername(name))[2]=(select auth.uid())::text));
create policy "RUNCTRL uploader and editors can download" on storage.objects for select to authenticated
 using(bucket_id='runctrl-media' and (
  (storage.foldername(name))[2]=(select auth.uid())::text
  or exists(select 1 from public.rc_members m where m.workspace_id::text=(storage.foldername(name))[1]
   and m.user_id=(select auth.uid()) and m.role in ('owner','editor'))
 ));
