begin;

insert into public.permissions(code,name,description,module,is_sensitive)
values('users.delete','Excluir usuários','Excluir permanentemente uma conta sem histórico operacional.','Administração',true)
on conflict(code) do update set name=excluded.name,description=excluded.description,module=excluded.module,is_sensitive=excluded.is_sensitive;

insert into public.group_permissions(group_id,permission_id)
select g.id,p.id from public.permission_groups g join public.permissions p on p.code='users.delete'
where g.name='Administrador' and g.is_system
on conflict do nothing;

create or replace function public.authorize_user_deletion(p_user_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare target jsonb; target_is_admin boolean;
begin
  if (select auth.uid()) is null or not exists(
    select 1 from public.user_groups ug join public.permission_groups g on g.id=ug.group_id
    where ug.user_id=(select auth.uid()) and g.name='Administrador' and g.is_system and g.is_active
  ) or not private.has_permission_for((select auth.uid()),'users.delete') then
    raise exception 'permission_denied';
  end if;
  if p_user_id=(select auth.uid()) then raise exception 'cannot_delete_self'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('nexcell:last-administrator',0));
  select jsonb_build_object('id',pr.id,'email',pr.email,'name',pr.full_name,'active',pr.active),
    private.has_permission_for(pr.id,'dashboard.admin.view')
  into target,target_is_admin from public.profiles pr where pr.id=p_user_id for update;
  if target is null then raise exception 'user_not_found'; end if;
  if target_is_admin and not exists(
    select 1 from public.profiles candidate
    where candidate.id<>p_user_id and candidate.active and private.has_permission_for(candidate.id,'dashboard.admin.view')
  ) then raise exception 'last_active_administrator'; end if;
  return target;
end $$;

create or replace function public.record_user_deletion(p_user_id uuid,p_email text,p_name text) returns void
language plpgsql security definer set search_path='' as $$
begin
  if not exists(
    select 1 from public.user_groups ug join public.permission_groups g on g.id=ug.group_id
    where ug.user_id=(select auth.uid()) and g.name='Administrador' and g.is_system and g.is_active
  ) or not private.has_permission_for((select auth.uid()),'users.delete') then
    raise exception 'permission_denied';
  end if;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,previous_value,new_value)
  values((select auth.uid()),'user.deleted','profile',p_user_id::text,
    jsonb_build_object('email',p_email,'name',p_name),jsonb_build_object('deleted',true));
end $$;

revoke execute on function public.authorize_user_deletion(uuid) from public,anon;
revoke execute on function public.record_user_deletion(uuid,text,text) from public,anon;
grant execute on function public.authorize_user_deletion(uuid),public.record_user_deletion(uuid,text,text) to authenticated;

commit;
