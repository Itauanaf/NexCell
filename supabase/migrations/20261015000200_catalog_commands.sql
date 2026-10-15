begin;

create or replace function public.create_supplier(p_data jsonb) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid(); v_name text:=nullif(trim(p_data->>'name'),'');
begin
  if not public.is_admin() then raise exception 'admin_required'; end if;
  if v_name is null then raise exception 'supplier_name_required'; end if;
  insert into public.suppliers(id,name,phone,whatsapp,email,city,state,lead_time_days,notes,created_by)
  values(v_id,v_name,nullif(trim(p_data->>'phone'),''),nullif(trim(p_data->>'whatsapp'),''),nullif(trim(p_data->>'email'),''),
    nullif(trim(p_data->>'city'),''),nullif(upper(trim(p_data->>'state')),''),greatest(0,coalesce((p_data->>'leadTime')::integer,0)),
    nullif(trim(p_data->>'notes'),''),auth.uid());
  perform public.audit('supplier.created','supplier',v_id::text,jsonb_build_object('name',v_name));
  return v_id;
end $$;

create or replace function public.update_supplier(p_id uuid,p_data jsonb) returns void
language plpgsql security definer set search_path=public as $$
declare v_current public.suppliers%rowtype;
begin
  if not public.is_admin() then raise exception 'admin_required'; end if;
  select * into v_current from public.suppliers where id=p_id for update;
  if not found then raise exception 'supplier_not_found'; end if;
  update public.suppliers set
    name=coalesce(nullif(trim(p_data->>'name'),''),name),
    phone=case when p_data ? 'phone' then nullif(trim(p_data->>'phone'),'') else phone end,
    whatsapp=case when p_data ? 'whatsapp' then nullif(trim(p_data->>'whatsapp'),'') else whatsapp end,
    email=case when p_data ? 'email' then nullif(trim(p_data->>'email'),'') else email end,
    city=case when p_data ? 'city' then nullif(trim(p_data->>'city'),'') else city end,
    state=case when p_data ? 'state' then nullif(upper(trim(p_data->>'state')),'') else state end,
    lead_time_days=case when p_data ? 'leadTime' then greatest(0,(p_data->>'leadTime')::integer) else lead_time_days end,
    notes=case when p_data ? 'notes' then nullif(trim(p_data->>'notes'),'') else notes end,
    active=case when p_data ? 'active' then (p_data->>'active')::boolean else active end,
    updated_at=now()
  where id=p_id;
  perform public.audit('supplier.updated','supplier',p_id::text,jsonb_build_object('active',coalesce((p_data->>'active')::boolean,v_current.active)));
end $$;

create or replace function public.update_product(p_id uuid,p_data jsonb) returns void
language plpgsql security definer set search_path=public as $$
declare v_current public.products%rowtype;
begin
  if not public.is_admin() then raise exception 'admin_required'; end if;
  select * into v_current from public.products where id=p_id for update;
  if not found then raise exception 'product_not_found'; end if;
  update public.products set
    name=coalesce(nullif(trim(p_data->>'name'),''),name),
    description=case when p_data ? 'description' then nullif(trim(p_data->>'description'),'') else description end,
    category_id=case when p_data ? 'categoryId' and nullif(p_data->>'categoryId','') is not null then (p_data->>'categoryId')::uuid when p_data ? 'categoryId' then null else category_id end,
    brand=case when p_data ? 'brand' then nullif(trim(p_data->>'brand'),'') else brand end,
    supplier_id=case when p_data ? 'supplierId' and nullif(p_data->>'supplierId','') is not null then (p_data->>'supplierId')::uuid when p_data ? 'supplierId' then null else supplier_id end,
    active=case when p_data ? 'active' then (p_data->>'active')::boolean else active end,
    updated_at=now()
  where id=p_id;
  perform public.audit('product.updated','product',p_id::text,jsonb_build_object('active',coalesce((p_data->>'active')::boolean,v_current.active)));
end $$;

create or replace function public.apply_variant_price(p_variant_id uuid,p_price_cents bigint,p_calculation jsonb default '{}'::jsonb) returns bigint
language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'admin_required'; end if;
  if p_price_cents<=0 then raise exception 'invalid_price'; end if;
  update public.product_variants set sale_price_cents=p_price_cents,updated_at=now() where id=p_variant_id and active;
  if not found then raise exception 'variant_not_found'; end if;
  perform public.audit('variant.price_updated','product_variant',p_variant_id::text,p_calculation||jsonb_build_object('priceCents',p_price_cents));
  return p_price_cents;
end $$;

revoke execute on function public.create_supplier(jsonb) from public,anon;
revoke execute on function public.update_supplier(uuid,jsonb) from public,anon;
revoke execute on function public.update_product(uuid,jsonb) from public,anon;
revoke execute on function public.apply_variant_price(uuid,bigint,jsonb) from public,anon;
grant execute on function public.create_supplier(jsonb) to authenticated;
grant execute on function public.update_supplier(uuid,jsonb) to authenticated;
grant execute on function public.update_product(uuid,jsonb) to authenticated;
grant execute on function public.apply_variant_price(uuid,bigint,jsonb) to authenticated;

commit;
