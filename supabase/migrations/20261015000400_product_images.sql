begin;

create or replace function public.attach_product_image(p_product_id uuid,p_object_key text,p_content_type text,p_alt_text text default 'Foto do produto') returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid();
begin
 if not public.is_admin() then raise exception 'admin_required'; end if;
 if p_content_type not in ('image/jpeg','image/png','image/webp') or nullif(trim(p_object_key),'') is null then raise exception 'invalid_image'; end if;
 if not exists(select 1 from public.products where id=p_product_id) then raise exception 'product_not_found'; end if;
 insert into public.product_images(id,product_id,object_key,content_type,alt_text) values(v_id,p_product_id,p_object_key,p_content_type,nullif(trim(p_alt_text),''));
 perform public.audit('product.image_added','product',p_product_id::text,jsonb_build_object('imageId',v_id,'objectKey',p_object_key));
 return v_id;
end $$;

revoke execute on function public.attach_product_image(uuid,text,text,text) from public,anon;
grant execute on function public.attach_product_image(uuid,text,text,text) to authenticated;

commit;
