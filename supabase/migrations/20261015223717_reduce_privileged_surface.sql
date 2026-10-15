-- Keep the RLS authorization helper outside the exposed Data API schema.
create or replace function private.has_permission(p_code text) returns boolean
language sql stable security definer set search_path='' as $$
  select private.has_permission_for((select auth.uid()),p_code)
$$;
revoke execute on function private.has_permission(text) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.has_permission(text) to authenticated;

do $$
declare item record; predicate text;
begin
  for item in
    select p.polname, n.nspname, c.relname, pg_catalog.pg_get_expr(p.polqual,p.polrelid) as expression
    from pg_catalog.pg_policy p
    join pg_catalog.pg_class c on c.oid=p.polrelid
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and pg_catalog.pg_get_expr(p.polqual,p.polrelid) like '%has_permission(%'
  loop
    predicate:=replace(item.expression,'public.has_permission(','private.has_permission(');
    if predicate=item.expression then predicate:=replace(item.expression,'has_permission(','private.has_permission('); end if;
    execute format('alter policy %I on %I.%I using (%s)',item.polname,item.nspname,item.relname,predicate);
  end loop;
end $$;

revoke execute on function public.has_permission(text) from public,anon,authenticated;
drop function public.has_permission(text);
