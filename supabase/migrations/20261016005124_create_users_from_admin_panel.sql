begin;

update public.permissions set name='Criar usuários',description='Criar contas com senha definida no painel.',is_sensitive=true
where code='users.invite';

delete from public.group_permissions gp using public.permissions p
where gp.permission_id=p.id and p.code='users.invite';
insert into public.group_permissions(group_id,permission_id)
select g.id,p.id from public.permission_groups g join public.permissions p on p.code='users.invite'
where g.name='Administrador' and g.is_system
on conflict do nothing;

update public.user_invitations set status='cancelled'
where status in ('pending','expired');

create or replace function public.record_created_user(p_user_id uuid,p_email text,p_group_ids uuid[]) returns void
language plpgsql security definer set search_path='' as $$
begin
  if not exists(
    select 1 from public.user_groups ug join public.permission_groups g on g.id=ug.group_id
    where ug.user_id=(select auth.uid()) and g.name='Administrador' and g.is_system and g.is_active
  ) or not private.has_permission_for((select auth.uid()),'users.invite') then
    raise exception 'permission_denied';
  end if;
  if (select count(*) from public.permission_groups where id=any(coalesce(p_group_ids,array[]::uuid[])) and is_active)
    <>coalesce(array_length(p_group_ids,1),0) then raise exception 'invalid_group'; end if;
  if not exists(select 1 from public.profiles where id=p_user_id) then raise exception 'user_not_found'; end if;
  insert into public.user_groups(user_id,group_id,assigned_by)
  select p_user_id,id,(select auth.uid()) from public.permission_groups
  where id=any(coalesce(p_group_ids,array[]::uuid[])) and is_active on conflict do nothing;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_value)
  values((select auth.uid()),'user.created','profile',p_user_id::text,
    jsonb_build_object('email',lower(trim(p_email)),'groups',p_group_ids));
end $$;

revoke execute on function public.record_created_user(uuid,text,uuid[]) from public,anon;
grant execute on function public.record_created_user(uuid,text,uuid[]) to authenticated;

commit;
