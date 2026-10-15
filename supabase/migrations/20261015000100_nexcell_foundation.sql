begin;

create extension if not exists pgcrypto;

create table public.roles (
  id text primary key,
  name text not null unique check (name in ('Administrador','Operador'))
);
insert into public.roles(id,name) values ('admin','Administrador'),('operator','Operador');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text,
  role_id text not null default 'operator' references public.roles(id),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index profiles_email_idx on public.profiles(lower(email));

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,email,full_name,role_id)
  values(new.id,coalesce(new.email,''),coalesce(new.raw_user_meta_data->>'full_name',split_part(coalesce(new.email,''),'@',1)),
    case when not exists(select 1 from public.profiles) then 'admin' else 'operator' end);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.is_active_user() returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and active)
$$;
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and active and role_id='admin')
$$;

create table public.settings (
  key text primary key, value_json jsonb not null, updated_by uuid not null references public.profiles(id), updated_at timestamptz not null default now()
);
create table public.audit_logs (
  id bigint generated always as identity primary key, actor_id uuid references public.profiles(id), action text not null,
  entity_type text not null, entity_id text, metadata_json jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
create index audit_actor_date_idx on public.audit_logs(actor_id,created_at desc);
create index audit_entity_date_idx on public.audit_logs(entity_type,entity_id,created_at desc);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(), name text not null, phone text, whatsapp text, email text, city text, state text,
  lead_time_days integer not null default 0 check(lead_time_days>=0), notes text, active boolean not null default true,
  created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index suppliers_name_idx on public.suppliers using gin(to_tsvector('simple',name));
create table public.categories (
  id uuid primary key default gen_random_uuid(), name text not null unique, active boolean not null default true, created_at timestamptz not null default now()
);
insert into public.categories(name) values ('Capinhas'),('Películas'),('Carregadores'),('Cabos'),('Fones'),('Eletrônicos'),('Outros');
create table public.products (
  id uuid primary key default gen_random_uuid(), name text not null, description text, category_id uuid references public.categories(id), brand text,
  supplier_id uuid references public.suppliers(id), active boolean not null default true, created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index products_name_idx on public.products using gin(to_tsvector('simple',name));
create index products_supplier_idx on public.products(supplier_id);
create table public.product_variants (
  id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id), sku text not null unique,
  barcode text unique, compatible_model text, color text, cost_cents bigint not null check(cost_cents>=0), sale_price_cents bigint not null check(sale_price_cents>=0),
  minimum_stock integer not null default 0 check(minimum_stock>=0), active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index variants_product_idx on public.product_variants(product_id);
create table public.product_images (
  id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id), object_key text not null unique,
  content_type text not null, alt_text text, created_at timestamptz not null default now()
);

create table public.inventory_balances (
  variant_id uuid primary key references public.product_variants(id), physical integer not null default 0 check(physical>=0),
  reserved integer not null default 0 check(reserved>=0 and reserved<=physical), updated_at timestamptz not null default now()
);
create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(), variant_id uuid not null references public.product_variants(id),
  movement_type text not null check(movement_type in ('opening','receipt','reservation','release','shipment','adjustment','damage','return')),
  quantity integer not null check(quantity<>0), physical_after integer not null check(physical_after>=0),
  reserved_after integer not null check(reserved_after>=0 and reserved_after<=physical_after), reason text not null,
  reference_type text, reference_id uuid, created_by uuid references public.profiles(id), created_at timestamptz not null default now()
);
create index inventory_movement_variant_date_idx on public.inventory_movements(variant_id,created_at desc);

create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(), number text not null unique, supplier_id uuid not null references public.suppliers(id),
  order_date date not null, expected_date date, order_status text not null default 'draft' check(order_status in ('draft','confirmed','cancelled')),
  payment_status text not null default 'pending' check(payment_status in ('pending','partial','paid')),
  receipt_status text not null default 'pending' check(receipt_status in ('pending','partial','received')),
  discount_cents bigint not null default 0 check(discount_cents>=0), freight_cents bigint not null default 0 check(freight_cents>=0),
  other_costs_cents bigint not null default 0 check(other_costs_cents>=0), total_cents bigint not null check(total_cents>=0), notes text,
  created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index purchase_supplier_date_idx on public.purchase_orders(supplier_id,order_date desc);
create table public.purchase_order_items (
  id uuid primary key default gen_random_uuid(), purchase_order_id uuid not null references public.purchase_orders(id), variant_id uuid not null references public.product_variants(id),
  quantity integer not null check(quantity>0), unit_cost_cents bigint not null check(unit_cost_cents>=0), received_quantity integer not null default 0 check(received_quantity>=0 and received_quantity<=quantity),
  damaged_quantity integer not null default 0 check(damaged_quantity>=0), unique(purchase_order_id,variant_id)
);
create table public.purchase_payments (
  id uuid primary key default gen_random_uuid(), purchase_order_id uuid not null references public.purchase_orders(id), amount_cents bigint not null check(amount_cents>0),
  payment_date date not null, method text not null, notes text, account_id uuid, created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
create table public.goods_receipts (
  id uuid primary key default gen_random_uuid(), purchase_order_id uuid not null references public.purchase_orders(id), idempotency_key uuid not null unique,
  receipt_date date not null, notes text, created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
create table public.goods_receipt_items (
  id uuid primary key default gen_random_uuid(), goods_receipt_id uuid not null references public.goods_receipts(id),
  purchase_order_item_id uuid not null references public.purchase_order_items(id), variant_id uuid not null references public.product_variants(id),
  received_quantity integer not null check(received_quantity>0), damaged_quantity integer not null default 0 check(damaged_quantity>=0 and damaged_quantity<=received_quantity)
);

create table public.customers (
  id uuid primary key default gen_random_uuid(), name text not null, phone text, email text, created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
create index customers_name_idx on public.customers using gin(to_tsvector('simple',name));
create table public.sales_orders (
  id uuid primary key default gen_random_uuid(), number text not null unique, customer_id uuid references public.customers(id), customer_name text not null,
  order_date date not null, order_status text not null default 'created' check(order_status in ('created','separated','shipped','delivered','cancelled','returned')),
  payment_status text not null default 'pending' check(payment_status in ('pending','partial','paid','refunded')),
  shipping_status text not null default 'pending' check(shipping_status in ('pending','separated','shipped','delivered','cancelled')),
  subtotal_cents bigint not null check(subtotal_cents>=0), discount_cents bigint not null default 0 check(discount_cents>=0),
  shipping_charged_cents bigint not null default 0 check(shipping_charged_cents>=0), total_cents bigint not null check(total_cents>=0), notes text,
  created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.sales_order_items (
  id uuid primary key default gen_random_uuid(), sales_order_id uuid not null references public.sales_orders(id), variant_id uuid not null references public.product_variants(id),
  quantity integer not null check(quantity>0), returned_quantity integer not null default 0 check(returned_quantity>=0 and returned_quantity<=quantity),
  unit_price_cents bigint not null check(unit_price_cents>=0), historical_cost_cents bigint not null check(historical_cost_cents>=0),
  discount_cents bigint not null default 0 check(discount_cents>=0), unique(sales_order_id,variant_id)
);
create table public.inventory_reservations (
  id uuid primary key default gen_random_uuid(), sales_order_id uuid not null references public.sales_orders(id), sales_order_item_id uuid not null unique references public.sales_order_items(id),
  variant_id uuid not null references public.product_variants(id), quantity integer not null check(quantity>0), status text not null default 'active' check(status in ('active','released','consumed')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.sales_payments (
  id uuid primary key default gen_random_uuid(), sales_order_id uuid not null references public.sales_orders(id), amount_cents bigint not null check(amount_cents>0),
  payment_date date not null, method text not null, account_id uuid, created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
create table public.shipments (
  id uuid primary key default gen_random_uuid(), sales_order_id uuid not null unique references public.sales_orders(id), shipped_at timestamptz not null,
  tracking_code text, created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
create table public.sales_cancellations (
  id uuid primary key default gen_random_uuid(), sales_order_id uuid not null unique references public.sales_orders(id), reason text not null,
  created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
create table public.sales_returns (
  id uuid primary key default gen_random_uuid(), sales_order_id uuid not null references public.sales_orders(id), notes text,
  checked_by uuid not null references public.profiles(id), checked_at timestamptz not null default now()
);
create table public.sales_return_items (
  id uuid primary key default gen_random_uuid(), sales_return_id uuid not null references public.sales_returns(id), sales_order_item_id uuid not null references public.sales_order_items(id),
  variant_id uuid not null references public.product_variants(id), quantity integer not null check(quantity>0)
);

create table public.financial_accounts (
  id uuid primary key default gen_random_uuid(), name text not null, account_type text not null check(account_type in ('cash','bank','wallet')),
  opening_balance_cents bigint not null default 0, active boolean not null default true, created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
create table public.financial_categories (
  id text primary key, name text not null unique, kind text not null check(kind in ('revenue','expense','merchandise','transfer')),
  affects_result boolean not null
);
insert into public.financial_categories(id,name,kind,affects_result) values
 ('sales','Vendas','revenue',true),('merchandise','Mercadorias','merchandise',false),('freight','Frete','expense',true),
 ('packaging','Embalagem','expense',true),('marketing','Marketing','expense',true),('payment-fees','Taxas de pagamento','expense',true),
 ('taxes','Impostos','expense',true),('tools','Ferramentas','expense',true),('operations','Operacional','expense',true),
 ('other','Outros','expense',true),('transfer','Transferência','transfer',false);
create table public.financial_transactions (
  id uuid primary key default gen_random_uuid(), account_id uuid not null references public.financial_accounts(id), direction text not null check(direction in ('inflow','outflow')),
  amount_cents bigint not null check(amount_cents>0), transaction_date date not null, category_id text not null references public.financial_categories(id), description text not null,
  source_type text, source_id uuid, transfer_group_id uuid, reconciled_at timestamptz, reconciled_by uuid references public.profiles(id),
  created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), unique(source_type,source_id)
);
alter table public.purchase_payments add constraint purchase_payment_account_fk foreign key(account_id) references public.financial_accounts(id);
alter table public.sales_payments add constraint sales_payment_account_fk foreign key(account_id) references public.financial_accounts(id);
create table public.accounts_payable (
  id uuid primary key default gen_random_uuid(), purchase_order_id uuid unique references public.purchase_orders(id), supplier_id uuid references public.suppliers(id),
  description text not null, original_cents bigint not null check(original_cents>0), paid_cents bigint not null default 0 check(paid_cents>=0 and paid_cents<=original_cents),
  due_date date not null, status text not null default 'pending' check(status in ('pending','partial','paid','cancelled')),
  created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
create table public.accounts_receivable (
  id uuid primary key default gen_random_uuid(), sales_order_id uuid unique references public.sales_orders(id), customer_id uuid references public.customers(id), customer_name text,
  description text not null, original_cents bigint not null check(original_cents>0), received_cents bigint not null default 0 check(received_cents>=0 and received_cents<=original_cents),
  due_date date not null, status text not null default 'pending' check(status in ('pending','partial','received','cancelled')),
  created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);

create index sales_orders_date_status_idx on public.sales_orders(order_date,order_status);
create index sales_orders_shipping_idx on public.sales_orders(shipping_status,order_date);
create index purchase_orders_expected_receipt_idx on public.purchase_orders(receipt_status,expected_date);
create index financial_transactions_account_date_idx on public.financial_transactions(account_id,transaction_date desc);
create index financial_transactions_date_direction_idx on public.financial_transactions(transaction_date,direction);
create index accounts_payable_status_due_idx on public.accounts_payable(status,due_date);
create index accounts_receivable_status_due_idx on public.accounts_receivable(status,due_date);

create view public.financial_account_balances with (security_invoker=true) as
select a.*,a.opening_balance_cents+coalesce(sum(case t.direction when 'inflow' then t.amount_cents else -t.amount_cents end),0) balance_cents
from public.financial_accounts a left join public.financial_transactions t on t.account_id=a.id group by a.id;

create or replace function public.audit(p_action text,p_entity_type text,p_entity_id text,p_metadata jsonb default '{}'::jsonb) returns void
language sql security definer set search_path=public as $$
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata_json) values(auth.uid(),p_action,p_entity_type,p_entity_id,p_metadata)
$$;

create or replace function public.create_product(p_name text,p_description text,p_category_id uuid,p_brand text,p_supplier_id uuid,p_variants jsonb) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_product uuid:=gen_random_uuid(); v_variant jsonb; v_variant_id uuid; v_opening integer; v_cost bigint; v_price bigint;
begin
 if not public.is_admin() then raise exception 'admin_required'; end if;
 if nullif(trim(p_name),'') is null or coalesce(jsonb_array_length(p_variants),0)=0 then raise exception 'invalid_product'; end if;
 insert into public.products(id,name,description,category_id,brand,supplier_id,created_by) values(v_product,trim(p_name),nullif(trim(p_description),''),p_category_id,nullif(trim(p_brand),''),p_supplier_id,auth.uid());
 for v_variant in select * from jsonb_array_elements(p_variants) loop
  v_variant_id:=gen_random_uuid(); v_opening:=coalesce((v_variant->>'openingStock')::integer,0); v_cost:=(v_variant->>'costCents')::bigint; v_price:=(v_variant->>'priceCents')::bigint;
  if nullif(trim(v_variant->>'sku'),'') is null or v_opening<0 or v_cost<0 or v_price<0 then raise exception 'invalid_variant'; end if;
  insert into public.product_variants(id,product_id,sku,barcode,compatible_model,color,cost_cents,sale_price_cents,minimum_stock)
  values(v_variant_id,v_product,upper(trim(v_variant->>'sku')),nullif(trim(v_variant->>'barcode'),''),nullif(trim(v_variant->>'model'),''),nullif(trim(v_variant->>'color'),''),v_cost,v_price,coalesce((v_variant->>'minimumStock')::integer,0));
  insert into public.inventory_balances(variant_id,physical,reserved) values(v_variant_id,v_opening,0);
  if v_opening>0 then insert into public.inventory_movements(variant_id,movement_type,quantity,physical_after,reserved_after,reason,reference_type,reference_id,created_by) values(v_variant_id,'opening',v_opening,v_opening,0,'Saldo inicial','product',v_product,auth.uid()); end if;
 end loop;
 perform public.audit('product.created','product',v_product::text,jsonb_build_object('name',trim(p_name),'variants',jsonb_array_length(p_variants))); return v_product;
end $$;

create or replace function public.create_purchase(p_supplier_id uuid,p_order_date date,p_expected_date date,p_discount_cents bigint,p_freight_cents bigint,p_other_costs_cents bigint,p_notes text,p_items jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_order uuid:=gen_random_uuid(); v_number text; v_item jsonb; v_variant uuid; v_qty integer; v_cost bigint; v_subtotal bigint:=0; v_total bigint;
begin
 if not public.is_active_user() then raise exception 'not_authorized'; end if;
 perform 1 from public.suppliers where id=p_supplier_id and active; if not found or jsonb_array_length(p_items)=0 then raise exception 'invalid_purchase'; end if;
 for v_item in select * from jsonb_array_elements(p_items) loop v_variant:=(v_item->>'variantId')::uuid; v_qty:=(v_item->>'quantity')::integer; v_cost:=(v_item->>'unitCostCents')::bigint; if v_qty<=0 or v_cost<0 or not exists(select 1 from public.product_variants where id=v_variant and active) then raise exception 'invalid_purchase_item'; end if; v_subtotal:=v_subtotal+v_qty*v_cost; end loop;
 v_total:=greatest(0,v_subtotal-coalesce(p_discount_cents,0)+coalesce(p_freight_cents,0)+coalesce(p_other_costs_cents,0));
 if v_total<=0 then raise exception 'purchase_total_must_be_positive'; end if;
 v_number:='CMP-'||to_char(clock_timestamp(),'YYYYMMDD')||'-'||upper(substr(replace(v_order::text,'-',''),1,5));
 insert into public.purchase_orders(id,number,supplier_id,order_date,expected_date,order_status,discount_cents,freight_cents,other_costs_cents,total_cents,notes,created_by) values(v_order,v_number,p_supplier_id,p_order_date,p_expected_date,'confirmed',coalesce(p_discount_cents,0),coalesce(p_freight_cents,0),coalesce(p_other_costs_cents,0),v_total,p_notes,auth.uid());
 for v_item in select * from jsonb_array_elements(p_items) loop insert into public.purchase_order_items(purchase_order_id,variant_id,quantity,unit_cost_cents) values(v_order,(v_item->>'variantId')::uuid,(v_item->>'quantity')::integer,(v_item->>'unitCostCents')::bigint); end loop;
 insert into public.accounts_payable(purchase_order_id,supplier_id,description,original_cents,due_date,created_by) values(v_order,p_supplier_id,'Compra '||v_number,v_total,coalesce(p_expected_date,p_order_date),auth.uid());
 perform public.audit('purchase.created','purchase_order',v_order::text,jsonb_build_object('number',v_number,'totalCents',v_total)); return jsonb_build_object('id',v_order,'number',v_number,'totalCents',v_total);
end $$;

create or replace function public.receive_purchase(p_order_id uuid,p_idempotency_key uuid,p_date date,p_notes text,p_items jsonb) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_receipt uuid:=gen_random_uuid(); v_item jsonb; v_order_item public.purchase_order_items%rowtype; v_received integer; v_damaged integer; v_balance public.inventory_balances%rowtype;
begin
 if not public.is_active_user() then raise exception 'not_authorized'; end if;
 if exists(select 1 from public.goods_receipts where idempotency_key=p_idempotency_key) then raise exception 'duplicate_receipt'; end if;
 perform 1 from public.purchase_orders where id=p_order_id and order_status<>'cancelled' for update;
 if not found then raise exception 'purchase_unavailable'; end if;
 insert into public.goods_receipts(id,purchase_order_id,idempotency_key,receipt_date,notes,created_by) values(v_receipt,p_order_id,p_idempotency_key,p_date,p_notes,auth.uid());
 for v_item in select * from jsonb_array_elements(p_items) loop
  v_received:=(v_item->>'received')::integer; v_damaged:=coalesce((v_item->>'damaged')::integer,0);
  select * into v_order_item from public.purchase_order_items where id=(v_item->>'itemId')::uuid and purchase_order_id=p_order_id for update;
  if not found or v_received<=0 or v_damaged<0 or v_damaged>v_received or v_received>v_order_item.quantity-v_order_item.received_quantity then raise exception 'invalid_receipt_quantity'; end if;
  insert into public.goods_receipt_items(goods_receipt_id,purchase_order_item_id,variant_id,received_quantity,damaged_quantity) values(v_receipt,v_order_item.id,v_order_item.variant_id,v_received,v_damaged);
  update public.purchase_order_items set received_quantity=received_quantity+v_received,damaged_quantity=damaged_quantity+v_damaged where id=v_order_item.id;
  update public.inventory_balances set physical=physical+(v_received-v_damaged),updated_at=now() where variant_id=v_order_item.variant_id returning * into v_balance;
  if v_received>v_damaged then insert into public.inventory_movements(variant_id,movement_type,quantity,physical_after,reserved_after,reason,reference_type,reference_id,created_by) values(v_order_item.variant_id,'receipt',v_received-v_damaged,v_balance.physical,v_balance.reserved,'Recebimento de compra','goods_receipt',v_receipt,auth.uid()); end if;
 end loop;
 update public.purchase_orders set receipt_status=case when exists(select 1 from public.purchase_order_items where purchase_order_id=p_order_id and received_quantity<quantity) then 'partial' else 'received' end,updated_at=now() where id=p_order_id;
 perform public.audit('receipt.confirmed','goods_receipt',v_receipt::text,jsonb_build_object('purchaseOrderId',p_order_id)); return v_receipt;
end $$;

create or replace function public.create_sale(p_customer_name text,p_order_date date,p_discount_cents bigint,p_shipping_cents bigint,p_notes text,p_items jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_sale uuid:=gen_random_uuid(); v_number text; v_item jsonb; v_variant public.product_variants%rowtype; v_balance public.inventory_balances%rowtype; v_item_id uuid; v_qty integer; v_price bigint; v_subtotal bigint:=0; v_total bigint;
begin
 if not public.is_active_user() then raise exception 'not_authorized'; end if;
 if nullif(trim(p_customer_name),'') is null or coalesce(jsonb_array_length(p_items),0)=0 then raise exception 'invalid_sale'; end if;
 v_number:='VND-'||to_char(clock_timestamp(),'YYYYMMDD')||'-'||upper(substr(replace(v_sale::text,'-',''),1,5));
 for v_item in select * from jsonb_array_elements(p_items) loop
  v_qty:=(v_item->>'quantity')::integer;
  select pv.* into v_variant from public.product_variants pv where pv.id=(v_item->>'variantId')::uuid and pv.active for update;
  select * into v_balance from public.inventory_balances where variant_id=v_variant.id for update;
  v_price:=coalesce((v_item->>'unitPriceCents')::bigint,v_variant.sale_price_cents);
  if not found or v_qty<=0 or v_qty>v_balance.physical-v_balance.reserved or v_price<0 then raise exception 'insufficient_stock'; end if;
  v_subtotal:=v_subtotal+v_qty*v_price;
 end loop;
 v_total:=greatest(0,v_subtotal-coalesce(p_discount_cents,0)+coalesce(p_shipping_cents,0));
 if v_total<=0 then raise exception 'sale_total_must_be_positive'; end if;
 insert into public.sales_orders(id,number,customer_name,order_date,subtotal_cents,discount_cents,shipping_charged_cents,total_cents,notes,created_by) values(v_sale,v_number,trim(p_customer_name),p_order_date,v_subtotal,coalesce(p_discount_cents,0),coalesce(p_shipping_cents,0),v_total,p_notes,auth.uid());
 insert into public.accounts_receivable(sales_order_id,customer_name,description,original_cents,due_date,created_by) values(v_sale,trim(p_customer_name),'Venda '||v_number,v_total,p_order_date,auth.uid());
 for v_item in select * from jsonb_array_elements(p_items) loop
  v_qty:=(v_item->>'quantity')::integer; select * into v_variant from public.product_variants where id=(v_item->>'variantId')::uuid for update; select * into v_balance from public.inventory_balances where variant_id=v_variant.id for update; v_price:=coalesce((v_item->>'unitPriceCents')::bigint,v_variant.sale_price_cents); v_item_id:=gen_random_uuid();
  insert into public.sales_order_items(id,sales_order_id,variant_id,quantity,unit_price_cents,historical_cost_cents) values(v_item_id,v_sale,v_variant.id,v_qty,v_price,v_variant.cost_cents);
  insert into public.inventory_reservations(sales_order_id,sales_order_item_id,variant_id,quantity) values(v_sale,v_item_id,v_variant.id,v_qty);
  update public.inventory_balances set reserved=reserved+v_qty,updated_at=now() where variant_id=v_variant.id returning * into v_balance;
  insert into public.inventory_movements(variant_id,movement_type,quantity,physical_after,reserved_after,reason,reference_type,reference_id,created_by) values(v_variant.id,'reservation',v_qty,v_balance.physical,v_balance.reserved,'Reserva de venda','sales_order',v_sale,auth.uid());
 end loop;
 perform public.audit('sale.created','sales_order',v_sale::text,jsonb_build_object('number',v_number,'totalCents',v_total)); return jsonb_build_object('id',v_sale,'number',v_number,'totalCents',v_total);
end $$;

create or replace function public.ship_sale(p_sale_id uuid,p_tracking_code text default null) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_ship uuid:=gen_random_uuid(); v_res record; v_balance public.inventory_balances%rowtype;
begin
 if not public.is_active_user() then raise exception 'not_authorized'; end if;
 perform 1 from public.sales_orders where id=p_sale_id and shipping_status in ('pending','separated') for update;
 if not found then raise exception 'sale_not_shippable'; end if;
 insert into public.shipments(id,sales_order_id,shipped_at,tracking_code,created_by) values(v_ship,p_sale_id,now(),nullif(trim(p_tracking_code),''),auth.uid());
 for v_res in select * from public.inventory_reservations where sales_order_id=p_sale_id and status='active' for update loop
  update public.inventory_balances set physical=physical-v_res.quantity,reserved=reserved-v_res.quantity,updated_at=now() where variant_id=v_res.variant_id returning * into v_balance;
  update public.inventory_reservations set status='consumed',updated_at=now() where id=v_res.id;
  insert into public.inventory_movements(variant_id,movement_type,quantity,physical_after,reserved_after,reason,reference_type,reference_id,created_by) values(v_res.variant_id,'shipment',-v_res.quantity,v_balance.physical,v_balance.reserved,'Expedição de venda','shipment',v_ship,auth.uid());
 end loop;
 update public.sales_orders set order_status='shipped',shipping_status='shipped',updated_at=now() where id=p_sale_id;
 perform public.audit('sale.shipped','sales_order',p_sale_id::text,jsonb_build_object('shipmentId',v_ship)); return v_ship;
end $$;

create or replace function public.cancel_sale(p_sale_id uuid,p_reason text) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_cancel uuid:=gen_random_uuid(); v_res record; v_balance public.inventory_balances%rowtype; v_paid bigint;
begin
 if not public.is_active_user() then raise exception 'not_authorized'; end if;
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
 if not public.is_active_user() then raise exception 'not_authorized'; end if;
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

create or replace function public.record_sale_payment(p_sale_id uuid,p_account_id uuid,p_amount_cents bigint,p_date date,p_method text) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid(); v_total bigint; v_paid bigint; v_number text;
begin
 if not public.is_active_user() then raise exception 'not_authorized'; end if;
 select total_cents,number into v_total,v_number from public.sales_orders where id=p_sale_id for update;
 select coalesce(sum(amount_cents),0) into v_paid from public.sales_payments where sales_order_id=p_sale_id;
 if p_amount_cents<=0 or v_paid+p_amount_cents>v_total then raise exception 'payment_exceeds_sale_total'; end if;
 insert into public.sales_payments(id,sales_order_id,amount_cents,payment_date,method,account_id,created_by) values(v_id,p_sale_id,p_amount_cents,p_date,p_method,p_account_id,auth.uid());
 insert into public.financial_transactions(account_id,direction,amount_cents,transaction_date,category_id,description,source_type,source_id,created_by) values(p_account_id,'inflow',p_amount_cents,p_date,'sales','Recebimento '||v_number,'sales_payment',v_id,auth.uid());
 update public.accounts_receivable set received_cents=received_cents+p_amount_cents,status=case when received_cents+p_amount_cents>=original_cents then 'received' else 'partial' end where sales_order_id=p_sale_id;
 update public.sales_orders set payment_status=case when v_paid+p_amount_cents>=v_total then 'paid' else 'partial' end,updated_at=now() where id=p_sale_id;
 perform public.audit('sale.payment_recorded','sales_order',p_sale_id::text,jsonb_build_object('paymentId',v_id,'amountCents',p_amount_cents)); return v_id;
end $$;

create or replace function public.record_purchase_payment(p_order_id uuid,p_account_id uuid,p_amount_cents bigint,p_date date,p_method text,p_notes text default null) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid(); v_total bigint; v_paid bigint; v_number text;
begin
 if not public.is_active_user() then raise exception 'not_authorized'; end if;
 select total_cents,number into v_total,v_number from public.purchase_orders where id=p_order_id and order_status<>'cancelled' for update;
 select coalesce(sum(amount_cents),0) into v_paid from public.purchase_payments where purchase_order_id=p_order_id;
 if p_amount_cents<=0 or v_paid+p_amount_cents>v_total then raise exception 'payment_exceeds_order_total'; end if;
 insert into public.purchase_payments(id,purchase_order_id,amount_cents,payment_date,method,notes,account_id,created_by) values(v_id,p_order_id,p_amount_cents,p_date,p_method,p_notes,p_account_id,auth.uid());
 insert into public.financial_transactions(account_id,direction,amount_cents,transaction_date,category_id,description,source_type,source_id,created_by) values(p_account_id,'outflow',p_amount_cents,p_date,'merchandise','Pagamento '||v_number,'purchase_payment',v_id,auth.uid());
 update public.accounts_payable set paid_cents=paid_cents+p_amount_cents,status=case when paid_cents+p_amount_cents>=original_cents then 'paid' else 'partial' end where purchase_order_id=p_order_id;
 update public.purchase_orders set payment_status=case when v_paid+p_amount_cents>=v_total then 'paid' else 'partial' end,updated_at=now() where id=p_order_id;
 perform public.audit('purchase.payment_recorded','purchase_order',p_order_id::text,jsonb_build_object('paymentId',v_id,'amountCents',p_amount_cents)); return v_id;
end $$;

do $$ declare t text; begin
 foreach t in array array['profiles','roles','settings','audit_logs','suppliers','categories','products','product_variants','product_images','inventory_balances','inventory_movements','purchase_orders','purchase_order_items','purchase_payments','goods_receipts','goods_receipt_items','customers','sales_orders','sales_order_items','inventory_reservations','sales_payments','shipments','sales_cancellations','sales_returns','sales_return_items','financial_accounts','financial_categories','financial_transactions','accounts_payable','accounts_receivable'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('create policy %I on public.%I for select to authenticated using (public.is_active_user())',t||'_read',t);
 end loop;
end $$;
create policy profiles_own_update on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy admin_settings_all on public.settings for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy admin_catalog_suppliers on public.suppliers for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy admin_catalog_products on public.products for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy admin_catalog_variants on public.product_variants for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy admin_catalog_images on public.product_images for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy admin_financial_accounts on public.financial_accounts for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy admin_financial_transactions on public.financial_transactions for all to authenticated using(public.is_admin()) with check(public.is_admin());

grant usage on schema public to authenticated;
grant select on all tables in schema public to authenticated;
grant insert,update,delete on public.settings,public.suppliers,public.products,public.product_variants,public.product_images,public.financial_accounts,public.financial_transactions to authenticated;
grant usage,select on all sequences in schema public to authenticated;
revoke execute on function public.handle_new_user() from public,anon,authenticated;
revoke execute on function public.is_active_user() from public,anon;
revoke execute on function public.is_admin() from public,anon;
revoke execute on function public.audit(text,text,text,jsonb) from public,anon,authenticated;
revoke execute on function public.create_product(text,text,uuid,text,uuid,jsonb) from public,anon;
revoke execute on function public.create_purchase(uuid,date,date,bigint,bigint,bigint,text,jsonb) from public,anon;
revoke execute on function public.receive_purchase(uuid,uuid,date,text,jsonb) from public,anon;
revoke execute on function public.create_sale(text,date,bigint,bigint,text,jsonb) from public,anon;
revoke execute on function public.ship_sale(uuid,text) from public,anon;
revoke execute on function public.cancel_sale(uuid,text) from public,anon;
revoke execute on function public.return_sale(uuid,text,jsonb) from public,anon;
revoke execute on function public.record_sale_payment(uuid,uuid,bigint,date,text) from public,anon;
revoke execute on function public.record_purchase_payment(uuid,uuid,bigint,date,text,text) from public,anon;
grant execute on function public.create_product(text,text,uuid,text,uuid,jsonb) to authenticated;
grant execute on function public.create_purchase(uuid,date,date,bigint,bigint,bigint,text,jsonb) to authenticated;
grant execute on function public.receive_purchase(uuid,uuid,date,text,jsonb) to authenticated;
grant execute on function public.create_sale(text,date,bigint,bigint,text,jsonb) to authenticated;
grant execute on function public.ship_sale(uuid,text) to authenticated;
grant execute on function public.cancel_sale(uuid,text) to authenticated;
grant execute on function public.return_sale(uuid,text,jsonb) to authenticated;
grant execute on function public.record_sale_payment(uuid,uuid,bigint,date,text) to authenticated;
grant execute on function public.record_purchase_payment(uuid,uuid,bigint,date,text,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('product-images','product-images',false,4194304,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy product_images_read on storage.objects for select to authenticated using(bucket_id='product-images' and public.is_active_user());
create policy product_images_admin_insert on storage.objects for insert to authenticated with check(bucket_id='product-images' and public.is_admin());
create policy product_images_admin_update on storage.objects for update to authenticated using(bucket_id='product-images' and public.is_admin()) with check(bucket_id='product-images' and public.is_admin());
create policy product_images_admin_delete on storage.objects for delete to authenticated using(bucket_id='product-images' and public.is_admin());

commit;
