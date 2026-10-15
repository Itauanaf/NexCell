begin;

create table public.permission_groups (
 id uuid primary key default gen_random_uuid(), name text not null, description text,
 is_active boolean not null default true, is_system boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint permission_groups_name_unique unique(name), constraint permission_groups_name_present check(length(trim(name)) between 2 and 80)
);
create table public.permissions (
 id uuid primary key default gen_random_uuid(), code text not null unique, name text not null,
 description text not null, module text not null, is_sensitive boolean not null default false,
 created_at timestamptz not null default now(), constraint permissions_code_format check(code ~ '^[a-z]+([._][a-z]+)+$')
);
create table public.group_permissions (
 group_id uuid not null references public.permission_groups(id) on delete cascade,
 permission_id uuid not null references public.permissions(id) on delete cascade,
 created_at timestamptz not null default now(), primary key(group_id,permission_id)
);
create table public.user_groups (
 user_id uuid not null references public.profiles(id) on delete cascade,
 group_id uuid not null references public.permission_groups(id) on delete restrict,
 assigned_by uuid references public.profiles(id), created_at timestamptz not null default now(),
 primary key(user_id,group_id)
);
create table public.user_invitations (
 id uuid primary key default gen_random_uuid(), user_id uuid references public.profiles(id) on delete set null,
 email text not null, status text not null default 'pending' check(status in('pending','accepted','expired','cancelled')),
 invited_by uuid not null references public.profiles(id), invited_at timestamptz not null default now(),
 last_sent_at timestamptz not null default now(), accepted_at timestamptz
);
create unique index user_invitations_pending_email_idx on public.user_invitations(lower(email)) where status='pending';
create index group_permissions_permission_idx on public.group_permissions(permission_id,group_id);
create index user_groups_group_idx on public.user_groups(group_id,user_id);
create index user_invitations_status_idx on public.user_invitations(status,invited_at desc);
alter table public.profiles add column if not exists last_access_at timestamptz;
alter table public.audit_logs add column if not exists previous_value jsonb;
alter table public.audit_logs add column if not exists new_value jsonb;

-- Public signup never bootstraps an administrator. Existing administrators are
-- migrated below; a fresh installation must assign the first Administrator by a
-- trusted SQL/bootstrap procedure.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,email,full_name,role_id)
 values(new.id,coalesce(new.email,''),coalesce(new.raw_user_meta_data->>'full_name',split_part(coalesce(new.email,''),'@',1)),'operator');
 return new;
end $$;
revoke execute on function public.handle_new_user() from public,anon,authenticated;

insert into public.permissions(code,name,description,module,is_sensitive) values
('dashboard.admin.view','Dashboard administrativo','Visualizar indicadores administrativos e financeiros.','Dashboard',true),
('dashboard.operator.view','Dashboard operacional','Visualizar filas e indicadores operacionais.','Dashboard',false),
('products.view','Consultar produtos','Consultar catálogo e preços de venda.','Produtos',false),
('products.create','Criar produtos','Cadastrar produtos e SKUs.','Produtos',true),
('products.edit','Editar produtos','Alterar cadastro de produtos.','Produtos',true),
('products.deactivate','Inativar produtos','Inativar produtos e SKUs.','Produtos',true),
('products.cost.view','Visualizar custos','Consultar custos de aquisição.','Produtos',true),
('products.price.edit','Alterar preços','Alterar preços de venda.','Produtos',true),
('inventory.view','Consultar estoque','Consultar saldos físicos e disponíveis.','Estoque',false),
('inventory.movements.view','Consultar movimentações','Consultar o histórico operacional de estoque.','Estoque',false),
('inventory.adjust','Ajustar estoque','Executar ajustes manuais.','Estoque',true),
('inventory.receive','Receber mercadorias','Confirmar recebimentos de compras.','Estoque',true),
('inventory.cost.view','Visualizar valor do estoque','Consultar custos e valor financeiro do estoque.','Estoque',true),
('suppliers.view','Consultar fornecedores','Consultar fornecedores.','Fornecedores',true),
('suppliers.create','Criar fornecedores','Cadastrar fornecedores.','Fornecedores',true),
('suppliers.edit','Editar fornecedores','Alterar fornecedores.','Fornecedores',true),
('purchases.view','Consultar compras','Consultar pedidos de compra.','Compras',true),
('purchases.create','Criar compras','Registrar pedidos de compra.','Compras',true),
('purchases.edit','Editar compras','Alterar pedidos de compra.','Compras',true),
('purchases.payment.record','Registrar pagamento de compra','Registrar saída vinculada a uma compra.','Compras',true),
('purchases.receive','Receber compras','Conferir e receber uma compra.','Compras',true),
('sales.view','Consultar vendas','Consultar pedidos de venda.','Vendas',false),
('sales.create','Criar vendas','Registrar vendas.','Vendas',false),
('sales.edit','Editar vendas','Alterar vendas antes da expedição.','Vendas',true),
('sales.cancel','Cancelar vendas','Cancelar pedidos de venda.','Vendas',true),
('sales.discount','Conceder descontos','Aplicar descontos em vendas.','Vendas',true),
('sales.ship','Expedir vendas','Separar e registrar despacho.','Vendas',false),
('sales.refund','Registrar devoluções','Conferir devoluções e reflexos financeiros.','Vendas',true),
('finance.view','Consultar financeiro','Visualizar saldos e lançamentos financeiros.','Financeiro',true),
('finance.transactions.create','Criar lançamentos','Registrar transações financeiras.','Financeiro',true),
('finance.transactions.edit','Editar lançamentos','Alterar e conciliar transações.','Financeiro',true),
('finance.accounts.manage','Gerenciar contas','Criar e administrar contas financeiras.','Financeiro',true),
('finance.reports.view','Consultar relatórios financeiros','Visualizar resultados e fluxo financeiro.','Financeiro',true),
('pricing.view','Usar calculadora','Visualizar a calculadora de preços.','Calculadora',true),
('pricing.apply','Aplicar preços','Atualizar o preço de um SKU.','Calculadora',true),
('reports.operational.view','Relatórios operacionais','Consultar relatórios não financeiros.','Relatórios',false),
('reports.financial.view','Relatórios financeiros','Consultar custos, margens e resultados.','Relatórios',true),
('reports.export','Exportar relatórios','Exportar dados autorizados.','Relatórios',true),
('users.view','Consultar usuários','Visualizar usuários e acessos.','Administração',true),
('users.invite','Convidar usuários','Enviar convites de acesso.','Administração',true),
('users.edit','Editar usuários','Editar nomes e grupos.','Administração',true),
('users.disable','Desativar usuários','Revogar ou restaurar acesso.','Administração',true),
('groups.view','Consultar grupos','Visualizar grupos e permissões.','Administração',true),
('groups.manage','Gerenciar grupos','Criar, duplicar e alterar grupos.','Administração',true),
('audit.view','Consultar auditoria','Visualizar o histórico administrativo.','Administração',true)
on conflict(code) do update set name=excluded.name,description=excluded.description,module=excluded.module,is_sensitive=excluded.is_sensitive;

insert into public.permission_groups(name,description,is_active,is_system) values
('Administrador','Acesso completo às funcionalidades administrativas e operacionais.',true,true),
('Vendedor','Vendas, catálogo, estoque disponível, separação e expedição.',true,false),
('Estoquista','Consulta e movimentações operacionais de estoque.',true,false),
('Expedição','Separação, itens do pedido e registro de despacho.',true,false)
on conflict(name) do nothing;
insert into public.group_permissions(group_id,permission_id)
select g.id,p.id from public.permission_groups g cross join public.permissions p where g.name='Administrador' on conflict do nothing;
insert into public.group_permissions(group_id,permission_id)
select g.id,p.id from public.permission_groups g join public.permissions p on p.code=any(array['dashboard.operator.view','products.view','inventory.view','sales.view','sales.create','sales.ship']) where g.name='Vendedor' on conflict do nothing;
insert into public.group_permissions(group_id,permission_id)
select g.id,p.id from public.permission_groups g join public.permissions p on p.code=any(array['dashboard.operator.view','products.view','inventory.view','inventory.movements.view']) where g.name='Estoquista' on conflict do nothing;
insert into public.group_permissions(group_id,permission_id)
select g.id,p.id from public.permission_groups g join public.permissions p on p.code=any(array['dashboard.operator.view','products.view','inventory.view','sales.view','sales.ship']) where g.name='Expedição' on conflict do nothing;
insert into public.user_groups(user_id,group_id,assigned_by)
select p.id,g.id,p.id from public.profiles p join public.permission_groups g on g.name=case when p.role_id='admin' then 'Administrador' else 'Vendedor' end on conflict do nothing;

create schema if not exists private;
revoke all on schema private from public,anon;
grant usage on schema private to authenticated;

create or replace function private.has_permission_for(p_user_id uuid,p_code text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles pr join public.user_groups ug on ug.user_id=pr.id join public.permission_groups g on g.id=ug.group_id and g.is_active join public.group_permissions gp on gp.group_id=g.id join public.permissions pe on pe.id=gp.permission_id where pr.id=p_user_id and pr.active and pe.code=p_code)
$$;
revoke execute on function private.has_permission_for(uuid,text) from public,anon;
grant execute on function private.has_permission_for(uuid,text) to authenticated;

create or replace function public.has_permission(p_code text) returns boolean
language sql stable security invoker set search_path='' as $$ select private.has_permission_for((select auth.uid()),p_code) $$;
revoke execute on function public.has_permission(text) from public,anon;
grant execute on function public.has_permission(text) to authenticated;

create or replace function public.current_access_context() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if (select auth.uid()) is null then raise exception 'authentication_required'; end if;
 update public.profiles set last_access_at=now(),updated_at=now() where id=(select auth.uid()) and active;
 if not found then raise exception 'user_inactive'; end if;
 select jsonb_build_object('user',jsonb_build_object('id',pr.id,'email',pr.email,'full_name',pr.full_name,'active',pr.active,'last_access_at',pr.last_access_at),
  'groups',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'name',g.name) order by g.name) from public.user_groups ug join public.permission_groups g on g.id=ug.group_id and g.is_active where ug.user_id=pr.id),'[]'::jsonb),
  'permissions',coalesce((select jsonb_agg(code order by code) from (select distinct pe.code from public.user_groups ug join public.permission_groups g on g.id=ug.group_id and g.is_active join public.group_permissions gp on gp.group_id=g.id join public.permissions pe on pe.id=gp.permission_id where ug.user_id=pr.id) q),'[]'::jsonb)) into result
 from public.profiles pr where pr.id=(select auth.uid()); return result;
end $$;

create or replace function public.admin_access_overview() returns jsonb
language sql stable security definer set search_path='' as $$
 select case when private.has_permission_for((select auth.uid()),'users.view') then jsonb_build_object(
  'active_users',(select count(*) from public.profiles where active),'inactive_users',(select count(*) from public.profiles where not active),
  'pending_invitations',(select count(*) from public.user_invitations where status='pending'),'groups',(select count(*) from public.permission_groups)
 ) else null end
$$;

create or replace function public.admin_users() returns jsonb
language sql stable security definer set search_path='' as $$
 select case when private.has_permission_for((select auth.uid()),'users.view') then coalesce(jsonb_agg(jsonb_build_object('id',pr.id,'name',pr.full_name,'email',pr.email,'active',pr.active,'last_access_at',pr.last_access_at,'created_at',pr.created_at,'invitation_id',(select i.id from public.user_invitations i where i.user_id=pr.id and i.status='pending' order by i.invited_at desc limit 1),'invitation_status',(select i.status from public.user_invitations i where i.user_id=pr.id order by i.invited_at desc limit 1),'groups',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'name',g.name) order by g.name) from public.user_groups ug join public.permission_groups g on g.id=ug.group_id where ug.user_id=pr.id),'[]'::jsonb),'permissions',coalesce((select jsonb_agg(code order by code) from (select distinct pe.code from public.user_groups ug join public.permission_groups g on g.id=ug.group_id and g.is_active join public.group_permissions gp on gp.group_id=g.id join public.permissions pe on pe.id=gp.permission_id where ug.user_id=pr.id) ep),'[]'::jsonb)) order by pr.created_at desc),'[]'::jsonb) else null end from public.profiles pr
$$;

create or replace function public.admin_permission_groups() returns jsonb
language sql stable security definer set search_path='' as $$
 select case when private.has_permission_for((select auth.uid()),'groups.view') then coalesce(jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'description',g.description,'is_active',g.is_active,'is_system',g.is_system,'created_at',g.created_at,'user_count',(select count(*) from public.user_groups ug where ug.group_id=g.id),'permissions',coalesce((select jsonb_agg(pe.code order by pe.code) from public.group_permissions gp join public.permissions pe on pe.id=gp.permission_id where gp.group_id=g.id),'[]'::jsonb)) order by g.is_system desc,g.name),'[]'::jsonb) else null end from public.permission_groups g
$$;

create or replace function public.admin_permissions() returns jsonb
language sql stable security definer set search_path='' as $$
 select case when private.has_permission_for((select auth.uid()),'groups.view') then coalesce(jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'description',description,'module',module,'is_sensitive',is_sensitive) order by module,name),'[]'::jsonb) else null end from public.permissions
$$;

create or replace function public.save_permission_group(p_id uuid,p_name text,p_description text,p_is_active boolean,p_permission_codes text[]) returns uuid
language plpgsql security definer set search_path='' as $$
declare target uuid:=coalesce(p_id,gen_random_uuid()); previous jsonb;
begin
 if not private.has_permission_for((select auth.uid()),'groups.manage') then raise exception 'permission_denied'; end if;
 if nullif(trim(p_name),'') is null or length(trim(p_name))>80 then raise exception 'invalid_group_name'; end if;
 select to_jsonb(g) into previous from public.permission_groups g where g.id=p_id for update;
 if previous->>'is_system'='true' then raise exception 'system_group_locked'; end if;
 insert into public.permission_groups(id,name,description,is_active) values(target,trim(p_name),nullif(trim(p_description),''),coalesce(p_is_active,true))
 on conflict(id) do update set name=excluded.name,description=excluded.description,is_active=excluded.is_active,updated_at=now();
 delete from public.group_permissions where group_id=target;
 insert into public.group_permissions(group_id,permission_id) select target,id from public.permissions where code=any(coalesce(p_permission_codes,array[]::text[]));
 if (select count(*) from public.permissions where code=any(coalesce(p_permission_codes,array[]::text[])))<>coalesce(array_length(p_permission_codes,1),0) then raise exception 'unknown_permission'; end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,previous_value,new_value) values((select auth.uid()),case when p_id is null then 'group.created' else 'group.updated' end,'permission_group',target::text,previous,jsonb_build_object('name',trim(p_name),'active',p_is_active,'permissions',p_permission_codes)); return target;
end $$;

create or replace function public.duplicate_permission_group(p_group_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare source public.permission_groups%rowtype; target uuid:=gen_random_uuid();
begin
 if not private.has_permission_for((select auth.uid()),'groups.manage') then raise exception 'permission_denied'; end if;
 select * into source from public.permission_groups where id=p_group_id; if not found then raise exception 'group_not_found'; end if;
 insert into public.permission_groups(id,name,description,is_active) values(target,left(source.name||' (cópia)',80),source.description,true);
 insert into public.group_permissions select target,permission_id,now() from public.group_permissions where group_id=p_group_id;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_value) values((select auth.uid()),'group.duplicated','permission_group',target::text,jsonb_build_object('source_id',p_group_id,'name',source.name)); return target;
end $$;

create or replace function public.set_user_access(p_user_id uuid,p_full_name text,p_active boolean,p_group_ids uuid[]) returns void
language plpgsql security definer set search_path='' as $$
declare previous jsonb; removes_last_admin boolean;
begin
 if not private.has_permission_for((select auth.uid()),'users.edit') then raise exception 'permission_denied'; end if;
 select jsonb_build_object('name',full_name,'active',active,'groups',(select coalesce(jsonb_agg(group_id),'[]'::jsonb) from public.user_groups where user_id=p_user_id)) into previous from public.profiles where id=p_user_id for update;
 if previous is null then raise exception 'user_not_found'; end if;
 if (previous->>'active')::boolean is distinct from p_active and not private.has_permission_for((select auth.uid()),'users.disable') then raise exception 'permission_denied'; end if;
 select exists(select 1 from public.user_groups ug join public.permission_groups g on g.id=ug.group_id where ug.user_id=p_user_id and g.name='Administrador') and (not p_active or not exists(select 1 from public.permission_groups g where g.id=any(coalesce(p_group_ids,array[]::uuid[])) and g.name='Administrador')) into removes_last_admin;
 if removes_last_admin and (select count(distinct pr.id) from public.profiles pr join public.user_groups ug on ug.user_id=pr.id join public.permission_groups g on g.id=ug.group_id where pr.active and g.is_active and g.name='Administrador')<=1 then raise exception 'last_active_administrator'; end if;
 update public.profiles set full_name=coalesce(nullif(trim(p_full_name),''),full_name),active=p_active,updated_at=now() where id=p_user_id;
 delete from public.user_groups where user_id=p_user_id;
 insert into public.user_groups(user_id,group_id,assigned_by) select p_user_id,id,(select auth.uid()) from public.permission_groups where id=any(coalesce(p_group_ids,array[]::uuid[])) and is_active;
 if (select count(*) from public.permission_groups where id=any(coalesce(p_group_ids,array[]::uuid[])) and is_active)<>coalesce(array_length(p_group_ids,1),0) then raise exception 'invalid_group'; end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,previous_value,new_value) values((select auth.uid()),case when p_active then 'user.access_updated' else 'user.disabled' end,'profile',p_user_id::text,previous,jsonb_build_object('name',p_full_name,'active',p_active,'groups',p_group_ids));
end $$;

create or replace function public.record_user_invitation(p_user_id uuid,p_email text,p_group_ids uuid[]) returns uuid
language plpgsql security definer set search_path='' as $$
declare invitation uuid:=gen_random_uuid();
begin
 if not private.has_permission_for((select auth.uid()),'users.invite') then raise exception 'permission_denied'; end if;
 insert into public.user_invitations(id,user_id,email,invited_by) values(invitation,p_user_id,lower(trim(p_email)),(select auth.uid()));
 insert into public.user_groups(user_id,group_id,assigned_by) select p_user_id,id,(select auth.uid()) from public.permission_groups where id=any(coalesce(p_group_ids,array[]::uuid[])) and is_active on conflict do nothing;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_value) values((select auth.uid()),'user.invited','profile',p_user_id::text,jsonb_build_object('email',lower(trim(p_email)),'groups',p_group_ids)); return invitation;
end $$;

create or replace function public.mark_invitation_resent(p_invitation_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not private.has_permission_for((select auth.uid()),'users.invite') then raise exception 'permission_denied'; end if;
 update public.user_invitations set last_sent_at=now() where id=p_invitation_id and status='pending';
 if not found then raise exception 'pending_invitation_not_found'; end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_value) values((select auth.uid()),'user.invitation_resent','user_invitation',p_invitation_id::text,jsonb_build_object('resent_at',now()));
end $$;

create or replace function public.admin_audit_logs(p_actor uuid default null,p_action text default null,p_entity text default null,p_from timestamptz default null,p_to timestamptz default null) returns jsonb
language sql stable security definer set search_path='' as $$
 select case when private.has_permission_for((select auth.uid()),'audit.view') then coalesce(jsonb_agg(jsonb_build_object('id',a.id,'actor_id',a.actor_id,'actor_name',pr.full_name,'actor_email',pr.email,'action',a.action,'target_type',a.entity_type,'target_id',a.entity_id,'previous_value',a.previous_value,'new_value',a.new_value,'created_at',a.created_at) order by a.created_at desc),'[]'::jsonb) else null end
 from public.audit_logs a left join public.profiles pr on pr.id=a.actor_id where (p_actor is null or a.actor_id=p_actor) and (nullif(p_action,'') is null or a.action=p_action) and (nullif(p_entity,'') is null or a.entity_type=p_entity) and (p_from is null or a.created_at>=p_from) and (p_to is null or a.created_at<=p_to)
$$;

do $$ declare t text; begin foreach t in array array['permission_groups','permissions','group_permissions','user_groups','user_invitations'] loop execute format('alter table public.%I enable row level security',t); execute format('revoke all on public.%I from anon,authenticated',t); execute format('grant select on public.%I to authenticated',t); execute format('create policy %I on public.%I for select to authenticated using (private.has_permission_for((select auth.uid()),''groups.view''))',t||'_admin_read',t); end loop; end $$;

revoke execute on function public.current_access_context() from public,anon;
revoke execute on function public.admin_access_overview() from public,anon;
revoke execute on function public.admin_users() from public,anon;
revoke execute on function public.admin_permission_groups() from public,anon;
revoke execute on function public.admin_permissions() from public,anon;
revoke execute on function public.save_permission_group(uuid,text,text,boolean,text[]) from public,anon;
revoke execute on function public.duplicate_permission_group(uuid) from public,anon;
revoke execute on function public.set_user_access(uuid,text,boolean,uuid[]) from public,anon;
revoke execute on function public.record_user_invitation(uuid,text,uuid[]) from public,anon;
revoke execute on function public.mark_invitation_resent(uuid) from public,anon;
revoke execute on function public.admin_audit_logs(uuid,text,text,timestamptz,timestamptz) from public,anon;
grant execute on function public.current_access_context(),public.admin_access_overview(),public.admin_users(),public.admin_permission_groups(),public.admin_permissions(),public.save_permission_group(uuid,text,text,boolean,text[]),public.duplicate_permission_group(uuid),public.set_user_access(uuid,text,boolean,uuid[]),public.record_user_invitation(uuid,text,uuid[]),public.mark_invitation_resent(uuid),public.admin_audit_logs(uuid,text,text,timestamptz,timestamptz) to authenticated;

-- Compatibility helpers now derive authority from effective permissions rather
-- than the legacy single role stored on profiles.
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select private.has_permission_for((select auth.uid()),'dashboard.admin.view')
$$;

-- Replace broad read policies with capability-specific policies. Tables that mix
-- operational and confidential columns remain unavailable to ordinary readers;
-- their approved columns are exposed by the existing safe RPC projections.
do $$ declare t text; begin
 foreach t in array array['categories','products','product_images','customers','sales_orders','inventory_reservations','shipments'] loop
  execute format('drop policy if exists %I on public.%I',t||'_active_read',t);
 end loop;
 foreach t in array array['settings','audit_logs','suppliers','product_variants','inventory_balances','inventory_movements','purchase_orders','purchase_order_items','purchase_payments','goods_receipts','goods_receipt_items','sales_order_items','sales_payments','sales_cancellations','sales_returns','sales_return_items','financial_accounts','financial_categories','financial_transactions','accounts_payable','accounts_receivable'] loop
  execute format('drop policy if exists %I on public.%I',t||'_admin_read',t);
 end loop;
end $$;
drop policy if exists products_admin_read on public.products;
create policy categories_permission_read on public.categories for select to authenticated using(public.has_permission('products.view'));
create policy product_images_permission_read on public.product_images for select to authenticated using(public.has_permission('products.view'));
create policy products_confidential_read on public.products for select to authenticated using(public.has_permission('products.cost.view'));
create policy customers_sales_read on public.customers for select to authenticated using(public.has_permission('sales.view'));
create policy sales_orders_permission_read on public.sales_orders for select to authenticated using(public.has_permission('sales.view'));
create policy reservations_permission_read on public.inventory_reservations for select to authenticated using(public.has_permission('sales.view'));
create policy shipments_permission_read on public.shipments for select to authenticated using(public.has_permission('sales.view'));
create policy settings_permission_read on public.settings for select to authenticated using(public.has_permission('dashboard.admin.view'));
create policy audit_permission_read on public.audit_logs for select to authenticated using(public.has_permission('audit.view'));
create policy suppliers_permission_read on public.suppliers for select to authenticated using(public.has_permission('suppliers.view'));
create policy variants_confidential_read on public.product_variants for select to authenticated using(public.has_permission('products.cost.view'));
create policy balances_confidential_read on public.inventory_balances for select to authenticated using(public.has_permission('inventory.cost.view'));
create policy movements_permission_read on public.inventory_movements for select to authenticated using(public.has_permission('inventory.movements.view'));
create policy purchases_permission_read on public.purchase_orders for select to authenticated using(public.has_permission('purchases.view'));
create policy purchase_items_permission_read on public.purchase_order_items for select to authenticated using(public.has_permission('purchases.view'));
create policy purchase_payments_permission_read on public.purchase_payments for select to authenticated using(public.has_permission('purchases.view'));
create policy receipts_permission_read on public.goods_receipts for select to authenticated using(public.has_permission('purchases.view'));
create policy receipt_items_permission_read on public.goods_receipt_items for select to authenticated using(public.has_permission('purchases.view'));
create policy sales_items_confidential_read on public.sales_order_items for select to authenticated using(public.has_permission('reports.financial.view'));
create policy sales_payments_permission_read on public.sales_payments for select to authenticated using(public.has_permission('finance.view'));
create policy cancellations_permission_read on public.sales_cancellations for select to authenticated using(public.has_permission('sales.cancel'));
create policy returns_permission_read on public.sales_returns for select to authenticated using(public.has_permission('sales.refund'));
create policy return_items_permission_read on public.sales_return_items for select to authenticated using(public.has_permission('sales.refund'));
create policy accounts_permission_read on public.financial_accounts for select to authenticated using(public.has_permission('finance.view'));
create policy financial_categories_permission_read on public.financial_categories for select to authenticated using(public.has_permission('finance.view'));
create policy transactions_permission_read on public.financial_transactions for select to authenticated using(public.has_permission('finance.view'));
create policy payable_permission_read on public.accounts_payable for select to authenticated using(public.has_permission('finance.view'));
create policy receivable_permission_read on public.accounts_receivable for select to authenticated using(public.has_permission('finance.view'));

-- Existing command functions retain their stable signatures. Their internal
-- guards are upgraded in-place to the permission catalog so all callers,
-- including direct Data API callers, receive the same authorization decision.
do $$
declare item record; definition text;
begin
 for item in select * from (values
  ('public.create_product(text,text,uuid,text,uuid,jsonb)'::regprocedure,'products.create'),
  ('public.create_supplier(jsonb)'::regprocedure,'suppliers.create'),
  ('public.update_supplier(uuid,jsonb)'::regprocedure,'suppliers.edit'),
  ('public.update_product(uuid,jsonb)'::regprocedure,'products.edit'),
  ('public.apply_variant_price(uuid,bigint,jsonb)'::regprocedure,'pricing.apply'),
  ('public.attach_product_image(uuid,text,text,text)'::regprocedure,'products.edit'),
  ('public.duplicate_product(uuid)'::regprocedure,'products.create'),
  ('public.create_purchase(uuid,date,date,bigint,bigint,bigint,text,jsonb)'::regprocedure,'purchases.create'),
  ('public.receive_purchase(uuid,uuid,date,text,jsonb)'::regprocedure,'purchases.receive'),
  ('public.record_purchase_payment(uuid,uuid,bigint,date,text,text)'::regprocedure,'purchases.payment.record'),
  ('public.cancel_sale(uuid,text)'::regprocedure,'sales.cancel'),
  ('public.return_sale(uuid,text,jsonb)'::regprocedure,'sales.refund'),
  ('public.create_financial_account(text,text,bigint)'::regprocedure,'finance.accounts.manage'),
  ('public.create_financial_transaction(uuid,text,bigint,date,text,text)'::regprocedure,'finance.transactions.create'),
  ('public.transfer_funds(uuid,uuid,bigint,date)'::regprocedure,'finance.transactions.create'),
  ('public.reconcile_transaction(uuid)'::regprocedure,'finance.transactions.edit'),
  ('public.upsert_setting(text,jsonb)'::regprocedure,'dashboard.admin.view')
 ) as x(fn,permission_code) loop
  select pg_get_functiondef(item.fn::oid) into definition;
  definition:=replace(definition,'if not public.is_admin() then raise exception ''admin_required''; end if;',format('if not private.has_permission_for((select auth.uid()),%L) then raise exception ''permission_denied''; end if;',item.permission_code));
  definition:=replace(definition,'if not public.is_active_user() then raise exception ''not_authorized''; end if;',format('if not private.has_permission_for((select auth.uid()),%L) then raise exception ''permission_denied''; end if;',item.permission_code));
  execute definition;
 end loop;
end $$;

-- Operational RPCs receive explicit capabilities and remain safe projections.
do $$ declare definition text; begin
 select pg_get_functiondef('public.operator_catalog(text,uuid)'::regprocedure::oid) into definition;
 execute replace(definition,'public.is_active_user()','private.has_permission_for((select auth.uid()),''products.view'')');
 select pg_get_functiondef('public.operator_inventory()'::regprocedure::oid) into definition;
 execute replace(definition,'public.is_active_user()','private.has_permission_for((select auth.uid()),''inventory.view'')');
 select pg_get_functiondef('public.operator_sales()'::regprocedure::oid) into definition;
 execute replace(definition,'public.is_active_user()','private.has_permission_for((select auth.uid()),''sales.view'')');
 select pg_get_functiondef('public.operator_sale_items(uuid)'::regprocedure::oid) into definition;
 execute replace(definition,'public.is_active_user()','private.has_permission_for((select auth.uid()),''sales.view'')');
 select pg_get_functiondef('public.operator_payment_accounts()'::regprocedure::oid) into definition;
 execute replace(definition,'public.is_active_user()','private.has_permission_for((select auth.uid()),''sales.create'')');
 select pg_get_functiondef('public.operator_dashboard()'::regprocedure::oid) into definition;
 execute replace(definition,'public.is_active_user()','private.has_permission_for((select auth.uid()),''dashboard.operator.view'')');
 select pg_get_functiondef('public.separate_sale(uuid)'::regprocedure::oid) into definition;
 execute replace(definition,'if not public.is_active_user() then raise exception ''not_authorized''; end if;','if not private.has_permission_for((select auth.uid()),''sales.ship'') then raise exception ''permission_denied''; end if;');
 select pg_get_functiondef('public.ship_sale(uuid,text)'::regprocedure::oid) into definition;
 execute replace(definition,'if not public.is_active_user() then raise exception ''not_authorized''; end if;','if not private.has_permission_for((select auth.uid()),''sales.ship'') then raise exception ''permission_denied''; end if;');
 select pg_get_functiondef('public.record_sale_payment(uuid,uuid,bigint,date,text)'::regprocedure::oid) into definition;
 execute replace(definition,'if not public.is_active_user() then raise exception ''not_authorized''; end if;','if not private.has_permission_for((select auth.uid()),''sales.create'') then raise exception ''permission_denied''; end if;');
end $$;

-- Sale creation keeps price and discount validation, but authority comes from
-- effective permissions rather than group names.
do $$ declare definition text; begin
 select pg_get_functiondef('public.create_sale(text,date,bigint,bigint,text,jsonb)'::regprocedure::oid) into definition;
 definition:=replace(definition,'v_admin boolean:=public.is_admin()','v_admin boolean:=private.has_permission_for((select auth.uid()),''sales.discount'')');
 definition:=replace(definition,'if not public.is_active_user() then raise exception ''not_authorized''; end if;','if not private.has_permission_for((select auth.uid()),''sales.create'') then raise exception ''permission_denied''; end if;');
 execute definition;
end $$;

commit;
