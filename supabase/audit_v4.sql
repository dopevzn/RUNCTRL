begin;
create or replace function runctrl_private.guard_last_owner()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not runctrl_private.has_role(old.workspace_id,array['owner']) then raise exception 'Workspace owner required';end if;
 perform 1 from public.rc_workspaces where id=old.workspace_id for update;
 if old.role='owner' and new.role<>'owner' and not exists(select 1 from public.rc_members where workspace_id=old.workspace_id and user_id<>old.user_id and role='owner') then raise exception 'A workspace must retain an owner';end if;
 return new;
end $$;
revoke all on function runctrl_private.guard_last_owner() from public;
create trigger rc_member_owner_guard before update on public.rc_members for each row execute function runctrl_private.guard_last_owner();
-- Store decisions and actor IDs, never contact details, notes, file names or signed URLs.
create or replace function runctrl_private.audit_decision()
returns trigger language plpgsql security definer set search_path='' as $$
declare prior text; following text; record_id uuid;
begin
 if auth.uid() is null then return new;end if;
 record_id:=coalesce((to_jsonb(new)->>'id')::uuid,(to_jsonb(new)->>'user_id')::uuid);
 following:=coalesce(to_jsonb(new)->>'status',to_jsonb(new)->>'review_status',to_jsonb(new)->>'role');
 if tg_op='UPDATE' then prior:=coalesce(to_jsonb(old)->>'status',to_jsonb(old)->>'review_status',to_jsonb(old)->>'role');end if;
 if tg_op='INSERT' or prior is distinct from following then
  insert into public.rc_audit(workspace_id,actor_id,entity,entity_id,action,prior_status,next_status)
  values(new.workspace_id,auth.uid(),tg_table_name,record_id,lower(tg_op),prior,following);
 end if;
 return new;
end $$;
revoke all on function runctrl_private.audit_decision() from public;
create trigger rc_credential_decision_audit after insert or update on public.rc_credentials for each row execute function runctrl_private.audit_decision();
create trigger rc_submission_decision_audit after insert or update on public.rc_submissions for each row execute function runctrl_private.audit_decision();
create trigger rc_asset_decision_audit after insert or update on public.rc_assets for each row execute function runctrl_private.audit_decision();
create trigger rc_access_decision_audit after insert or update on public.rc_access_requests for each row execute function runctrl_private.audit_decision();
create trigger rc_member_decision_audit after insert or update on public.rc_members for each row execute function runctrl_private.audit_decision();
commit;
