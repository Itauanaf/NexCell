-- Security hardening for access administration and exposed Data API objects.

do $$
declare table_name text;
begin
  foreach table_name in array array['permission_groups','permissions','group_permissions','user_groups','user_invitations'] loop
    execute format('drop policy if exists %I on public.%I',table_name||'_admin_read',table_name);
    execute format('create policy %I on public.%I for select to authenticated using ((select public.has_permission(''groups.view'')))',table_name||'_admin_read',table_name);
  end loop;
end $$;

revoke all privileges on all tables in schema public from anon;
revoke insert,update,delete,truncate,references,trigger on all tables in schema public from authenticated;
revoke all privileges on all sequences in schema public from anon,authenticated;

-- Enforce the invariant at transaction end for every path that can alter
-- effective administrator capability, not only set_user_access().
create or replace function private.require_active_administrator() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('nexcell:last-administrator',0));
 if not exists(
   select 1 from public.profiles candidate
   where candidate.active
     and private.has_permission_for(candidate.id,'dashboard.admin.view')
 ) then
   raise exception 'last_active_administrator';
 end if;
 return null;
end $$;
revoke execute on function private.require_active_administrator() from public,anon,authenticated;

create constraint trigger profiles_require_active_administrator after insert or update or delete on public.profiles deferrable initially deferred for each row execute function private.require_active_administrator();
create constraint trigger user_groups_require_active_administrator after insert or update or delete on public.user_groups deferrable initially deferred for each row execute function private.require_active_administrator();
create constraint trigger group_permissions_require_active_administrator after insert or update or delete on public.group_permissions deferrable initially deferred for each row execute function private.require_active_administrator();
create constraint trigger permission_groups_require_active_administrator after insert or update or delete on public.permission_groups deferrable initially deferred for each row execute function private.require_active_administrator();
create constraint trigger permissions_require_active_administrator after insert or update or delete on public.permissions deferrable initially deferred for each row execute function private.require_active_administrator();

create or replace function public.set_user_access(p_user_id uuid,p_full_name text,p_active boolean,p_group_ids uuid[]) returns void
language plpgsql security definer set search_path='' as $$
declare previous jsonb; old_group_ids uuid[]; assigned_groups jsonb; removed_groups jsonb; currently_admin boolean; remains_admin boolean;
begin
 if not private.has_permission_for((select auth.uid()),'users.edit') then raise exception 'permission_denied'; end if;
 if (select count(*) from public.permission_groups where id=any(coalesce(p_group_ids,array[]::uuid[])) and is_active)<>coalesce(array_length(p_group_ids,1),0) then raise exception 'invalid_group'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('nexcell:last-administrator',0));
 select coalesce(array_agg(group_id order by group_id),array[]::uuid[]) into old_group_ids from public.user_groups where user_id=p_user_id;
 select jsonb_build_object('name',full_name,'active',active,'groups',(select coalesce(jsonb_agg(group_id),'[]'::jsonb) from public.user_groups where user_id=p_user_id)) into previous from public.profiles where id=p_user_id for update;
 if previous is null then raise exception 'user_not_found'; end if;
 if (previous->>'active')::boolean is distinct from p_active and not private.has_permission_for((select auth.uid()),'users.disable') then raise exception 'permission_denied'; end if;
 if old_group_ids is distinct from (select coalesce(array_agg(id order by id),array[]::uuid[]) from public.permission_groups where id=any(coalesce(p_group_ids,array[]::uuid[]))) and not private.has_permission_for((select auth.uid()),'groups.manage') then raise exception 'permission_denied'; end if;
 currently_admin:=private.has_permission_for(p_user_id,'dashboard.admin.view');
 select p_active and exists(select 1 from public.permission_groups g join public.group_permissions gp on gp.group_id=g.id join public.permissions pe on pe.id=gp.permission_id where g.id=any(coalesce(p_group_ids,array[]::uuid[])) and g.is_active and pe.code='dashboard.admin.view') into remains_admin;
 if currently_admin and not remains_admin and not exists(select 1 from public.profiles candidate where candidate.id<>p_user_id and candidate.active and private.has_permission_for(candidate.id,'dashboard.admin.view')) then raise exception 'last_active_administrator'; end if;
 update public.profiles set full_name=coalesce(nullif(trim(p_full_name),''),full_name),active=p_active,updated_at=now() where id=p_user_id;
 delete from public.user_groups where user_id=p_user_id;
 insert into public.user_groups(user_id,group_id,assigned_by) select p_user_id,id,(select auth.uid()) from public.permission_groups where id=any(coalesce(p_group_ids,array[]::uuid[])) and is_active;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,previous_value,new_value) values((select auth.uid()),case when p_active then 'user.access_updated' else 'user.disabled' end,'profile',p_user_id::text,previous,jsonb_build_object('name',p_full_name,'active',p_active,'groups',p_group_ids));
 if (previous->>'active')::boolean is distinct from p_active then insert into public.audit_logs(actor_id,action,entity_type,entity_id,previous_value,new_value) values((select auth.uid()),case when p_active then 'user.activated' else 'user.disabled' end,'profile',p_user_id::text,jsonb_build_object('active',(previous->>'active')::boolean),jsonb_build_object('active',p_active)); end if;
 select coalesce(jsonb_agg(x),'[]'::jsonb) into assigned_groups from (select unnest(coalesce(p_group_ids,array[]::uuid[])) except select unnest(old_group_ids)) q(x);
 select coalesce(jsonb_agg(x),'[]'::jsonb) into removed_groups from (select unnest(old_group_ids) except select unnest(coalesce(p_group_ids,array[]::uuid[]))) q(x);
 if assigned_groups<>'[]'::jsonb then insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_value) values((select auth.uid()),'user.group_assigned','profile',p_user_id::text,jsonb_build_object('groups',assigned_groups)); end if;
 if removed_groups<>'[]'::jsonb then insert into public.audit_logs(actor_id,action,entity_type,entity_id,previous_value) values((select auth.uid()),'user.group_removed','profile',p_user_id::text,jsonb_build_object('groups',removed_groups)); end if;
end $$;

create or replace function public.invitation_for_resend(p_invitation_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.has_permission_for((select auth.uid()),'users.invite') then raise exception 'permission_denied'; end if;
 select jsonb_build_object('email',i.email,'full_name',p.full_name) into result from public.user_invitations i join public.profiles p on p.id=i.user_id where i.id=p_invitation_id and i.status in ('pending','expired');
 if result is null then raise exception 'pending_invitation_not_found'; end if;
 return result;
end $$;

revoke execute on function public.invitation_for_resend(uuid) from public,anon;
grant execute on function public.invitation_for_resend(uuid) to authenticated;
