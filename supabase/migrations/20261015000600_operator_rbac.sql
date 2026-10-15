begin;

-- Remove the original blanket read policies. Direct table access is rebuilt below.
do $$ declare t text; begin
 foreach t in array array['profiles','roles','settings','audit_logs','suppliers','categories','products','product_variants','product_images','inventory_balances','inventory_movements','purchase_orders','purchase_order_items','purchase_payments','goods_receipts','goods_receipt_items','customers','sales_orders','sales_order_items','inventory_reservations','sales_payments','shipments','sales_cancellations','sales_returns','sales_return_items','financial_accounts','financial_categories','financial_transactions','accounts_payable','accounts_receivable'] loop
  execute format('drop policy if exists %I on public.%I',t||'_read',t);
 end loop;
end $$;
drop policy if exists profiles_own_update on public.profiles;

-- A user can only read their own profile; administrators can inspect all profiles.
create policy profiles_scoped_read on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
create policy roles_authenticated_read on public.roles for select to authenticated using(public.is_active_user());

-- Non-sensitive master and operational rows. Sensitive child rows are exposed via safe RPCs.
do $$ declare t text; begin
 foreach t in array array['categories','products','product_images','customers','sales_orders','inventory_reservations','shipments'] loop
  execute format('create policy %I on public.%I for select to authenticated using (public.is_active_user())',t||'_active_read',t);
 end loop;
end $$;

-- Tables containing costs, suppliers, finance, audit or privileged workflows are admin-only.
do $$ declare t text; begin
 foreach t in array array['settings','audit_logs','suppliers','product_variants','inventory_balances','inventory_movements','purchase_orders','purchase_order_items','purchase_payments','goods_receipts','goods_receipt_items','sales_order_items','sales_payments','sales_cancellations','sales_returns','sales_return_items','financial_accounts','financial_categories','financial_transactions','accounts_payable','accounts_receivable'] loop
  execute format('create policy %I on public.%I for select to authenticated using (public.is_admin())',t||'_admin_read',t);
 end loop;
end $$;

create or replace function public.operator_catalog(p_query text default '',p_category uuid default null) returns jsonb
language sql stable security definer set search_path=public as $$
 select case when public.is_active_user() then coalesce(jsonb_agg(row_data order by row_data->>'name',row_data->>'sku'),'[]'::jsonb) else '[]'::jsonb end
 from (
  select jsonb_build_object('id',p.id,'name',p.name,'description',p.description,'brand',p.brand,'active',p.active,
   'category_id',p.category_id,'category_name',c.name,'variant_id',v.id,'sku',v.sku,'barcode',v.barcode,
   'compatible_model',v.compatible_model,'color',v.color,'sale_price_cents',v.sale_price_cents,'minimum_stock',v.minimum_stock,
   'variant_active',v.active,'physical',coalesce(b.physical,0),'reserved',coalesce(b.reserved,0),
   'available',coalesce(b.physical-b.reserved,0),'image_key',(select i.object_key from public.product_images i where i.product_id=p.id order by i.created_at desc limit 1)) row_data
  from public.products p join public.product_variants v on v.product_id=p.id
  left join public.categories c on c.id=p.category_id left join public.inventory_balances b on b.variant_id=v.id
  where p.active and v.active and (p_category is null or p.category_id=p_category)
   and (coalesce(trim(p_query),'')='' or p.name ilike '%'||trim(p_query)||'%' or v.sku ilike '%'||trim(p_query)||'%')
 ) q
$$;

create or replace function public.operator_inventory() returns jsonb
language sql stable security definer set search_path=public as $$
 select case when public.is_active_user() then coalesce(jsonb_agg(jsonb_build_object('variant_id',v.id,'product_id',p.id,'name',p.name,'sku',v.sku,
  'color',v.color,'compatible_model',v.compatible_model,'sale_price_cents',v.sale_price_cents,'minimum_stock',v.minimum_stock,
  'physical',b.physical,'reserved',b.reserved,'available',b.physical-b.reserved,'updated_at',b.updated_at) order by p.name,v.sku),'[]'::jsonb) else '[]'::jsonb end
 from public.inventory_balances b join public.product_variants v on v.id=b.variant_id join public.products p on p.id=v.product_id
 where p.active and v.active
$$;

create or replace function public.operator_sales() returns jsonb
language sql stable security definer set search_path=public as $$
 select case when public.is_active_user() then coalesce(jsonb_agg(jsonb_build_object('id',s.id,'number',s.number,'customer_name',s.customer_name,
  'order_date',s.order_date,'order_status',s.order_status,'payment_status',s.payment_status,'shipping_status',s.shipping_status,
  'subtotal_cents',s.subtotal_cents,'discount_cents',s.discount_cents,'shipping_charged_cents',s.shipping_charged_cents,'total_cents',s.total_cents,
  'notes',s.notes,'units',(select coalesce(sum(i.quantity),0) from public.sales_order_items i where i.sales_order_id=s.id),
  'paid_cents',(select coalesce(sum(p.amount_cents),0) from public.sales_payments p where p.sales_order_id=s.id)) order by s.created_at desc),'[]'::jsonb) else '[]'::jsonb end
 from public.sales_orders s
$$;

create or replace function public.operator_sale_items(p_sale_id uuid) returns jsonb
language sql stable security definer set search_path=public as $$
 select case when public.is_active_user() then coalesce(jsonb_agg(jsonb_build_object('id',i.id,'sales_order_id',i.sales_order_id,'variant_id',i.variant_id,
  'quantity',i.quantity,'returned_quantity',i.returned_quantity,'unit_price_cents',i.unit_price_cents,'discount_cents',i.discount_cents,
  'product_name',p.name,'sku',v.sku,'color',v.color) order by p.name,v.sku),'[]'::jsonb) else '[]'::jsonb end
 from public.sales_order_items i join public.product_variants v on v.id=i.variant_id join public.products p on p.id=v.product_id where i.sales_order_id=p_sale_id
$$;

create or replace function public.operator_payment_accounts() returns jsonb
language sql stable security definer set search_path=public as $$
 select case when public.is_active_user() then coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name),'[]'::jsonb) else '[]'::jsonb end
 from public.financial_accounts where active
$$;

create or replace function public.operator_dashboard() returns jsonb
language sql stable security definer set search_path=public as $$
 select case when public.is_active_user() then jsonb_build_object(
  'awaiting_processing',(select count(*) from public.sales_orders where order_status='created' and shipping_status='pending'),
  'awaiting_separation',(select count(*) from public.sales_orders where order_status='created' and shipping_status='pending'),
  'ready_to_ship',(select count(*) from public.sales_orders where shipping_status='separated'),
  'low_stock',(select count(*) from public.inventory_balances b join public.product_variants v on v.id=b.variant_id where v.active and b.physical-b.reserved<=v.minimum_stock),
  'orders',coalesce((select jsonb_agg(x order by x->>'order_date',x->>'number') from (select jsonb_build_object('id',id,'number',number,'customer_name',customer_name,'order_date',order_date,'shipping_status',shipping_status,'order_status',order_status) x from public.sales_orders where order_status<>'cancelled' and shipping_status in('pending','separated') limit 8) q),'[]'::jsonb)
 ) else '{}'::jsonb end
$$;

create or replace function public.separate_sale(p_sale_id uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
 if not public.is_active_user() then raise exception 'not_authorized'; end if;
 update public.sales_orders set order_status='separated',shipping_status='separated',updated_at=now()
 where id=p_sale_id and order_status='created' and shipping_status='pending';
 if not found then raise exception 'sale_not_separable'; end if;
 perform public.audit('sale.separated','sales_order',p_sale_id::text,'{}'::jsonb);
end $$;

-- Operators cannot discount or override the registered selling price.
create or replace function public.create_sale(p_customer_name text,p_order_date date,p_discount_cents bigint,p_shipping_cents bigint,p_notes text,p_items jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_sale uuid:=gen_random_uuid(); v_number text; v_item jsonb; v_variant public.product_variants%rowtype; v_balance public.inventory_balances%rowtype; v_item_id uuid; v_qty integer; v_price bigint; v_requested bigint; v_subtotal bigint:=0; v_total bigint; v_admin boolean:=public.is_admin();
begin
 if not public.is_active_user() then raise exception 'not_authorized'; end if;
 if nullif(trim(p_customer_name),'') is null or coalesce(jsonb_array_length(p_items),0)=0 then raise exception 'invalid_sale'; end if;
 if not v_admin and coalesce(p_discount_cents,0)<>0 then raise exception 'discount_requires_admin'; end if;
 v_number:='VND-'||to_char(clock_timestamp(),'YYYYMMDD')||'-'||upper(substr(replace(v_sale::text,'-',''),1,5));
 for v_item in select * from jsonb_array_elements(p_items) loop
  v_qty:=(v_item->>'quantity')::integer;
  select pv.* into v_variant from public.product_variants pv where pv.id=(v_item->>'variantId')::uuid and pv.active for update;
  if not found then raise exception 'invalid_variant'; end if;
  select * into v_balance from public.inventory_balances where variant_id=v_variant.id for update;
  if not found then raise exception 'inventory_not_found'; end if;
  v_requested:=(v_item->>'unitPriceCents')::bigint;
  if not v_admin and v_requested is not null and v_requested<>v_variant.sale_price_cents then raise exception 'price_override_requires_admin'; end if;
  v_price:=case when v_admin then coalesce(v_requested,v_variant.sale_price_cents) else v_variant.sale_price_cents end;
  if v_qty<=0 or v_qty>v_balance.physical-v_balance.reserved or v_price<0 then raise exception 'insufficient_stock'; end if;
  v_subtotal:=v_subtotal+v_qty*v_price;
 end loop;
 v_total:=greatest(0,v_subtotal-coalesce(p_discount_cents,0)+coalesce(p_shipping_cents,0)); if v_total<=0 then raise exception 'sale_total_must_be_positive'; end if;
 insert into public.sales_orders(id,number,customer_name,order_date,subtotal_cents,discount_cents,shipping_charged_cents,total_cents,notes,created_by) values(v_sale,v_number,trim(p_customer_name),p_order_date,v_subtotal,coalesce(p_discount_cents,0),coalesce(p_shipping_cents,0),v_total,p_notes,auth.uid());
 insert into public.accounts_receivable(sales_order_id,customer_name,description,original_cents,due_date,created_by) values(v_sale,trim(p_customer_name),'Venda '||v_number,v_total,p_order_date,auth.uid());
 for v_item in select * from jsonb_array_elements(p_items) loop
  v_qty:=(v_item->>'quantity')::integer; select * into v_variant from public.product_variants where id=(v_item->>'variantId')::uuid for update; select * into v_balance from public.inventory_balances where variant_id=v_variant.id for update;
  v_requested:=(v_item->>'unitPriceCents')::bigint; v_price:=case when v_admin then coalesce(v_requested,v_variant.sale_price_cents) else v_variant.sale_price_cents end; v_item_id:=gen_random_uuid();
  insert into public.sales_order_items(id,sales_order_id,variant_id,quantity,unit_price_cents,historical_cost_cents) values(v_item_id,v_sale,v_variant.id,v_qty,v_price,v_variant.cost_cents);
  insert into public.inventory_reservations(sales_order_id,sales_order_item_id,variant_id,quantity) values(v_sale,v_item_id,v_variant.id,v_qty);
  update public.inventory_balances set reserved=reserved+v_qty,updated_at=now() where variant_id=v_variant.id returning * into v_balance;
  insert into public.inventory_movements(variant_id,movement_type,quantity,physical_after,reserved_after,reason,reference_type,reference_id,created_by) values(v_variant.id,'reservation',v_qty,v_balance.physical,v_balance.reserved,'Reserva de venda','sales_order',v_sale,auth.uid());
 end loop;
 perform public.audit('sale.created','sales_order',v_sale::text,jsonb_build_object('number',v_number,'totalCents',v_total)); return jsonb_build_object('id',v_sale,'number',v_number,'totalCents',v_total);
end $$;

-- Cancellation and returns can affect finance/stock and remain administrative.
create or replace function public.cancel_sale(p_sale_id uuid,p_reason text) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_cancel uuid:=gen_random_uuid(); v_res record; v_balance public.inventory_balances%rowtype; v_paid bigint;
begin
 if not public.is_admin() then raise exception 'admin_required'; end if;
 perform 1 from public.sales_orders where id=p_sale_id and shipping_status in ('pending','separated') for update; if not found then raise exception 'sale_not_cancellable'; end if;
 select coalesce(sum(amount_cents),0) into v_paid from public.sales_payments where sales_order_id=p_sale_id; if v_paid>0 then raise exception 'financial_refund_required'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'reason_required'; end if;
 insert into public.sales_cancellations(id,sales_order_id,reason,created_by) values(v_cancel,p_sale_id,trim(p_reason),auth.uid());
 for v_res in select * from public.inventory_reservations where sales_order_id=p_sale_id and status='active' for update loop
  update public.inventory_balances set reserved=reserved-v_res.quantity,updated_at=now() where variant_id=v_res.variant_id returning * into v_balance;
  update public.inventory_reservations set status='released',updated_at=now() where id=v_res.id;
  insert into public.inventory_movements(variant_id,movement_type,quantity,physical_after,reserved_after,reason,reference_type,reference_id,created_by) values(v_res.variant_id,'release',-v_res.quantity,v_balance.physical,v_balance.reserved,'Cancelamento de venda','sales_order',p_sale_id,auth.uid());
 end loop;
 update public.sales_orders set order_status='cancelled',shipping_status='cancelled',updated_at=now() where id=p_sale_id; update public.accounts_receivable set status='cancelled' where sales_order_id=p_sale_id;
 perform public.audit('sale.cancelled','sales_order',p_sale_id::text,jsonb_build_object('reason',trim(p_reason))); return v_cancel;
end $$;

create or replace function public.return_sale(p_sale_id uuid,p_notes text,p_items jsonb) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_return uuid:=gen_random_uuid(); v_item jsonb; v_order_item public.sales_order_items%rowtype; v_qty integer; v_balance public.inventory_balances%rowtype;
begin
 if not public.is_admin() then raise exception 'admin_required'; end if;
 perform 1 from public.sales_orders where id=p_sale_id and shipping_status in ('shipped','delivered') for update; if not found then raise exception 'sale_not_returnable'; end if;
 if jsonb_array_length(p_items)=0 then raise exception 'return_items_required'; end if;
 insert into public.sales_returns(id,sales_order_id,notes,checked_by) values(v_return,p_sale_id,p_notes,auth.uid());
 for v_item in select * from jsonb_array_elements(p_items) loop
  v_qty:=(v_item->>'quantity')::integer; select * into v_order_item from public.sales_order_items where id=(v_item->>'itemId')::uuid and sales_order_id=p_sale_id for update;
  if not found or v_qty<=0 or v_qty>v_order_item.quantity-v_order_item.returned_quantity then raise exception 'invalid_return_quantity'; end if;
  insert into public.sales_return_items(sales_return_id,sales_order_item_id,variant_id,quantity) values(v_return,v_order_item.id,v_order_item.variant_id,v_qty);
  update public.sales_order_items set returned_quantity=returned_quantity+v_qty where id=v_order_item.id;
  update public.inventory_balances set physical=physical+v_qty,updated_at=now() where variant_id=v_order_item.variant_id returning * into v_balance;
  insert into public.inventory_movements(variant_id,movement_type,quantity,physical_after,reserved_after,reason,reference_type,reference_id,created_by) values(v_order_item.variant_id,'return',v_qty,v_balance.physical,v_balance.reserved,'Devolução conferida','sales_return',v_return,auth.uid());
 end loop;
 update public.sales_orders set order_status='returned',updated_at=now() where id=p_sale_id; perform public.audit('sale.return_checked','sales_return',v_return::text,jsonb_build_object('salesOrderId',p_sale_id)); return v_return;
end $$;

revoke execute on function public.operator_catalog(text,uuid) from public,anon;
revoke execute on function public.operator_inventory() from public,anon;
revoke execute on function public.operator_sales() from public,anon;
revoke execute on function public.operator_sale_items(uuid) from public,anon;
revoke execute on function public.operator_payment_accounts() from public,anon;
revoke execute on function public.operator_dashboard() from public,anon;
revoke execute on function public.separate_sale(uuid) from public,anon;
grant execute on function public.operator_catalog(text,uuid) to authenticated;
grant execute on function public.operator_inventory() to authenticated;
grant execute on function public.operator_sales() to authenticated;
grant execute on function public.operator_sale_items(uuid) to authenticated;
grant execute on function public.operator_payment_accounts() to authenticated;
grant execute on function public.operator_dashboard() to authenticated;
grant execute on function public.separate_sale(uuid) to authenticated;

commit;
