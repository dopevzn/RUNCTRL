-- RUNCTRL MVP schema. Apply only to a dedicated RUNCTRL Supabase project.
create extension if not exists pgcrypto;
create table if not exists public.assignments (
 id uuid primary key default gen_random_uuid(),
 workspace text not null check (workspace in ('DOPE Sports Network','RecruitLook Hoops','DOPE VZN')),
 title text not null,
 venue text not null default '',
 date timestamptz,
 assignee text not null default '',
 status text not null default 'Planned',
 drive_url text not null default '',
 created_by uuid not null default auth.uid() references auth.users(id),
 created_at timestamptz not null default now()
);
create table if not exists public.workspace_members (
 user_id uuid not null references auth.users(id) on delete cascade,
 workspace text not null check (workspace in ('DOPE Sports Network','RecruitLook Hoops','DOPE VZN')),
 role text not null check (role in ('admin','shooter','editor')),
 primary key(user_id,workspace)
);
alter table public.assignments enable row level security;
alter table public.workspace_members enable row level security;
create policy "Members see memberships" on public.workspace_members for select to authenticated using(user_id=auth.uid());
create policy "Members see assignments" on public.assignments for select to authenticated using(exists(select 1 from public.workspace_members m where m.user_id=auth.uid() and m.workspace=assignments.workspace));
create policy "Admins create assignments" on public.assignments for insert to authenticated with check(created_by=auth.uid() and exists(select 1 from public.workspace_members m where m.user_id=auth.uid() and m.workspace=assignments.workspace and m.role='admin'));
create policy "Admins update assignments" on public.assignments for update to authenticated using(exists(select 1 from public.workspace_members m where m.user_id=auth.uid() and m.workspace=assignments.workspace and m.role='admin')) with check(exists(select 1 from public.workspace_members m where m.user_id=auth.uid() and m.workspace=assignments.workspace and m.role='admin'));
-- Bootstrap the first admin through Supabase SQL editor after first Google login.
-- Insert workspace_members rows for the authenticated admin user ID.
