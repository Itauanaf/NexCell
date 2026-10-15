begin;

create or replace function public.duplicate_product(p_product_id uuid) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_source public.products%rowtype; v_id uuid:=gen_random_uuid(); v_variant public.product_variants%rowtype; v_variant_id uuid; v_suffix text:=upper(substr(replace(v_id::text,'-',''),1,6));
begin
 if not public.is_admin() then raise exception 'admin_required'; end if;
 select * into v_source from public.products where id=p_product_id;
 if not found then raise exception 'product_not_found'; end if;
 insert into public.products(id,name,description,category_id,brand,supplier_id,created_by)
 values(v_id,v_source.name||' (cópia)',v_source.description,v_source.category_id,v_source.brand,v_source.supplier_id,auth.uid());
 for v_variant in select * from public.product_variants where product_id=p_product_id order by created_at loop
  v_variant_id:=gen_random_uuid();
  insert into public.product_variants(id,product_id,sku,barcode,compatible_model,color,cost_cents,sale_price_cents,minimum_stock)
  values(v_variant_id,v_id,v_variant.sku||'-C'||v_suffix,null,v_variant.compatible_model,v_variant.color,v_variant.cost_cents,v_variant.sale_price_cents,v_variant.minimum_stock);
  insert into public.inventory_balances(variant_id,physical,reserved) values(v_variant_id,0,0);
 end loop;
 perform public.audit('product.duplicated','product',v_id::text,jsonb_build_object('source',p_product_id));
 return v_id;
end $$;

revoke execute on function public.duplicate_product(uuid) from public,anon;
grant execute on function public.duplicate_product(uuid) to authenticated;

commit;
