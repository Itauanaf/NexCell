begin;

-- Product rows contain supplier references. Operators use operator_catalog(), which
-- deliberately projects only the approved columns.
drop policy if exists products_active_read on public.products;
create policy products_admin_read on public.products for select to authenticated using(public.is_admin());

-- Legacy purchasing commands originally accepted every active user. Keep their
-- signatures for the administrative UI, but enforce the administrator role even
-- when the RPC is called directly through PostgREST.
do $$
declare fn regprocedure; definition text;
begin
 foreach fn in array array[
  'public.create_purchase(uuid,date,date,bigint,bigint,bigint,text,jsonb)'::regprocedure,
  'public.receive_purchase(uuid,uuid,date,text,jsonb)'::regprocedure,
  'public.record_purchase_payment(uuid,uuid,bigint,date,text,text)'::regprocedure
 ] loop
  select pg_get_functiondef(fn::oid) into definition;
  definition:=replace(definition,
   'if not public.is_active_user() then raise exception ''not_authorized''; end if;',
   'if not public.is_admin() then raise exception ''admin_required''; end if;');
  execute definition;
 end loop;
end $$;

-- Payments remain operational, but only for valid, non-cancelled sales and active
-- accounts. Amounts are bounded by the outstanding sale total inside the database.
create or replace function public.record_sale_payment(p_sale_id uuid,p_account_id uuid,p_amount_cents bigint,p_date date,p_method text) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid(); v_total bigint; v_paid bigint; v_number text;
begin
 if not public.is_active_user() then raise exception 'not_authorized'; end if;
 select total_cents,number into v_total,v_number from public.sales_orders where id=p_sale_id and order_status<>'cancelled' for update;
 if not found then raise exception 'sale_not_payable'; end if;
 perform 1 from public.financial_accounts where id=p_account_id and active;
 if not found then raise exception 'payment_account_unavailable'; end if;
 select coalesce(sum(amount_cents),0) into v_paid from public.sales_payments where sales_order_id=p_sale_id;
 if p_amount_cents<=0 or v_paid+p_amount_cents>v_total then raise exception 'payment_exceeds_sale_total'; end if;
 insert into public.sales_payments(id,sales_order_id,amount_cents,payment_date,method,account_id,created_by) values(v_id,p_sale_id,p_amount_cents,p_date,p_method,p_account_id,auth.uid());
 insert into public.financial_transactions(account_id,direction,amount_cents,transaction_date,category_id,description,source_type,source_id,created_by) values(p_account_id,'inflow',p_amount_cents,p_date,'sales','Recebimento '||v_number,'sales_payment',v_id,auth.uid());
 update public.accounts_receivable set received_cents=received_cents+p_amount_cents,status=case when received_cents+p_amount_cents>=original_cents then 'received' else 'partial' end where sales_order_id=p_sale_id;
 update public.sales_orders set payment_status=case when v_paid+p_amount_cents>=v_total then 'paid' else 'partial' end,updated_at=now() where id=p_sale_id;
 perform public.audit('sale.payment_recorded','sales_order',p_sale_id::text,jsonb_build_object('paymentId',v_id,'amountCents',p_amount_cents)); return v_id;
end $$;

-- Audit rows can only be produced by trusted security-definer workflows.
revoke execute on function public.audit(text,text,text,jsonb) from public,anon,authenticated;

commit;
