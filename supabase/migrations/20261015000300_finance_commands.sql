begin;

create or replace function public.create_financial_account(p_name text,p_type text,p_opening_balance_cents bigint) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid();
begin
 if not public.is_admin() then raise exception 'admin_required'; end if;
 if nullif(trim(p_name),'') is null or p_type not in ('cash','bank','wallet') then raise exception 'invalid_account'; end if;
 insert into public.financial_accounts(id,name,account_type,opening_balance_cents,created_by) values(v_id,trim(p_name),p_type,coalesce(p_opening_balance_cents,0),auth.uid());
 perform public.audit('finance.account_created','financial_account',v_id::text,jsonb_build_object('openingBalanceCents',coalesce(p_opening_balance_cents,0)));
 return v_id;
end $$;

create or replace function public.create_financial_transaction(p_account_id uuid,p_direction text,p_amount_cents bigint,p_date date,p_category_id text,p_description text) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid();
begin
 if not public.is_admin() then raise exception 'admin_required'; end if;
 if p_direction not in ('inflow','outflow') or p_amount_cents<=0 or nullif(trim(p_description),'') is null then raise exception 'invalid_transaction'; end if;
 if not exists(select 1 from public.financial_accounts where id=p_account_id and active) then raise exception 'invalid_account'; end if;
 insert into public.financial_transactions(id,account_id,direction,amount_cents,transaction_date,category_id,description,source_type,source_id,created_by)
 values(v_id,p_account_id,p_direction,p_amount_cents,p_date,p_category_id,trim(p_description),'manual',v_id,auth.uid());
 perform public.audit('finance.transaction_created','financial_transaction',v_id::text,jsonb_build_object('amountCents',p_amount_cents,'direction',p_direction));
 return v_id;
end $$;

create or replace function public.transfer_funds(p_from uuid,p_to uuid,p_amount_cents bigint,p_date date) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_group uuid:=gen_random_uuid(); v_out uuid:=gen_random_uuid(); v_in uuid:=gen_random_uuid(); v_balance bigint;
begin
 if not public.is_admin() then raise exception 'admin_required'; end if;
 if p_from=p_to or p_amount_cents<=0 then raise exception 'invalid_transfer'; end if;
 perform 1 from public.financial_accounts where id in (p_from,p_to) and active for update;
 if (select count(*) from public.financial_accounts where id in (p_from,p_to) and active)<>2 then raise exception 'invalid_account'; end if;
 select balance_cents into v_balance from public.financial_account_balances where id=p_from;
 if v_balance<p_amount_cents then raise exception 'insufficient_balance'; end if;
 insert into public.financial_transactions(id,account_id,direction,amount_cents,transaction_date,category_id,description,source_type,source_id,transfer_group_id,created_by) values
 (v_out,p_from,'outflow',p_amount_cents,p_date,'transfer','Transferência entre contas','transfer_leg',v_out,v_group,auth.uid()),
 (v_in,p_to,'inflow',p_amount_cents,p_date,'transfer','Transferência entre contas','transfer_leg',v_in,v_group,auth.uid());
 perform public.audit('finance.transfer_created','financial_transfer',v_group::text,jsonb_build_object('amountCents',p_amount_cents,'from',p_from,'to',p_to));
 return v_group;
end $$;

create or replace function public.reconcile_transaction(p_id uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'admin_required'; end if;
 update public.financial_transactions set reconciled_at=now(),reconciled_by=auth.uid() where id=p_id and reconciled_at is null;
 if not found then raise exception 'transaction_not_found_or_reconciled'; end if;
 perform public.audit('finance.transaction_reconciled','financial_transaction',p_id::text,'{}'::jsonb);
end $$;

create or replace function public.upsert_setting(p_key text,p_value jsonb) returns void
language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'admin_required'; end if;
 if nullif(trim(p_key),'') is null or length(p_key)>80 or p_value is null then raise exception 'invalid_setting'; end if;
 insert into public.settings(key,value_json,updated_by) values(trim(p_key),p_value,auth.uid())
 on conflict(key) do update set value_json=excluded.value_json,updated_by=excluded.updated_by,updated_at=now();
 perform public.audit('settings.updated','setting',trim(p_key),jsonb_build_object('key',trim(p_key)));
end $$;

revoke execute on function public.create_financial_account(text,text,bigint) from public,anon;
revoke execute on function public.create_financial_transaction(uuid,text,bigint,date,text,text) from public,anon;
revoke execute on function public.transfer_funds(uuid,uuid,bigint,date) from public,anon;
revoke execute on function public.reconcile_transaction(uuid) from public,anon;
revoke execute on function public.upsert_setting(text,jsonb) from public,anon;
grant execute on function public.create_financial_account(text,text,bigint) to authenticated;
grant execute on function public.create_financial_transaction(uuid,text,bigint,date,text,text) to authenticated;
grant execute on function public.transfer_funds(uuid,uuid,bigint,date) to authenticated;
grant execute on function public.reconcile_transaction(uuid) to authenticated;
grant execute on function public.upsert_setting(text,jsonb) to authenticated;

commit;
