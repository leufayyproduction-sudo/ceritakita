begin;

alter table public.plans add column if not exists slug text;
create unique index if not exists plans_slug_unique on public.plans(slug);
alter table public.payment_settings add column if not exists unique_code_enabled boolean not null default true;
alter table public.payment_settings add column if not exists provider_label text not null default 'DANA';
alter table public.orders add column if not exists base_amount integer;
alter table public.orders add column if not exists unique_code integer not null default 0;
alter table public.orders add column if not exists expires_at timestamptz;
alter table public.orders add column if not exists qris_image_url text;
alter table public.orders add column if not exists merchant_name text;
alter table public.orders add column if not exists instructions text;
alter table public.orders add column if not exists note text;
update public.orders set base_amount=coalesce(total_amount,0) where base_amount is null;
update public.orders set expires_at=coalesce(created_at,now()) + interval '60 minutes' where expires_at is null;
alter table public.orders alter column expires_at set not null;
alter table public.orders drop constraint if exists orders_unique_code_check;
alter table public.orders add constraint orders_unique_code_check check (unique_code=0 or unique_code between 100 and 999);
create index if not exists orders_user_created_idx on public.orders(user_id,created_at desc);

insert into public.plans(slug,name,price_idr,period,features,is_active) values
('gratis','Gratis',0,'free',array['Cerita anonim','Mood harian','Jurnal privat','Edukasi publik'],false),
('bulanan','Bulanan',49000,'monthly',array['Semua fitur Gratis','Akses Premium selama 1 bulan'],true),
('tahunan','Tahunan',399000,'yearly',array['Semua fitur Gratis','Akses Premium selama 1 tahun'],true)
on conflict (slug) do nothing;
-- QRIS harus diisi dengan gambar merchant asli; tidak menggunakan QRIS rekaan.
insert into public.payment_settings(id,merchant_name,instructions,expiry_minutes) values
(1,'CeritaKita','Bayar melalui aplikasi yang mendukung QRIS dengan nominal tepat, lalu unggah bukti. Pembayaran diverifikasi manual.',60)
on conflict (id) do nothing;

-- Users may read their own orders but cannot set prices or payment status.
drop policy if exists own_orders on public.orders;
drop policy if exists orders_owner_read on public.orders;
create policy orders_owner_read on public.orders for select to authenticated using (user_id=auth.uid() or public.is_admin());
drop policy if exists orders_admin_update on public.orders;
create policy orders_admin_update on public.orders for update to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.orders from anon,authenticated;
grant select,update on public.orders to authenticated;

create or replace function public.expire_my_orders()
returns void language plpgsql security definer set search_path = public
as $$ begin
  if auth.uid() is null then raise exception 'Masuk terlebih dahulu'; end if;
  update public.orders set status='expired'
  where user_id=auth.uid() and status in ('pending','rejected') and expires_at <= now();
end; $$;
revoke all on function public.expire_my_orders() from public;
grant execute on function public.expire_my_orders() to authenticated;

create or replace function public.create_premium_order(selected_plan uuid)
returns uuid language plpgsql security definer set search_path = public
as $$
declare p record; settings record; code integer; order_id uuid; existing uuid; expiry integer; attempts integer := 0;
begin
  if auth.uid() is null then raise exception 'Masuk terlebih dahulu'; end if;
  perform pg_advisory_xact_lock(hashtextextended('ceritakita-payment-orders',0));
  perform public.expire_my_orders();
  select id into existing from public.orders where user_id=auth.uid() and plan_id=selected_plan and status in ('pending','rejected') and expires_at>now() order by created_at desc limit 1;
  if existing is not null then return existing; end if;
  if exists(select 1 from public.orders where user_id=auth.uid() and status in ('pending','awaiting_verification','rejected')) then raise exception 'Selesaikan pesanan sebelumnya dulu, ya.'; end if;
  if (select count(*) from public.orders where user_id=auth.uid() and created_at>now()-interval '1 day') >= 5 then raise exception 'Maksimal 5 pesanan per hari.'; end if;
  select id,name,slug,price_idr,period,features,is_active into p from public.plans where id=selected_plan and is_active;
  if p.id is null or p.period not in ('monthly','yearly') or p.price_idr is null or p.price_idr<=0 or p.price_idr>2000000000 then raise exception 'Paket tidak tersedia'; end if;
  select id,qris_image_url,merchant_name,instructions,expiry_minutes,unique_code_enabled,provider_label into settings from public.payment_settings where id=1;
  if settings.qris_image_url is null or settings.qris_image_url !~ '^https://' then raise exception 'QRIS belum tersedia'; end if;
  expiry := greatest(1,least(coalesce(settings.expiry_minutes,60),1440));
  code := 0;
  if settings.unique_code_enabled then
    loop
      code := 100+floor(random()*900)::integer;
      exit when not exists(select 1 from public.orders where total_amount=p.price_idr+code and status in ('pending','awaiting_verification','rejected'));
      attempts := attempts+1;
      if attempts>=1800 then raise exception 'Kode pembayaran sedang penuh. Coba lagi nanti.'; end if;
    end loop;
  end if;
  insert into public.profiles(id,display_name) select auth.uid(),split_part(email,'@',1) from auth.users where id=auth.uid() on conflict(id) do nothing;
  insert into public.orders(user_id,plan_id,base_amount,unique_code,total_amount,status,expires_at,qris_image_url,merchant_name,instructions)
  values(auth.uid(),p.id,p.price_idr,code,p.price_idr+code,'pending',now()+make_interval(mins=>expiry),settings.qris_image_url,settings.merchant_name,settings.instructions)
  returning id into order_id;
  return order_id;
end; $$;
revoke all on function public.create_premium_order(uuid) from public;
grant execute on function public.create_premium_order(uuid) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('proofs','proofs',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists proofs_owner_read on storage.objects;
create policy proofs_owner_read on storage.objects for select to authenticated using (
  bucket_id='proofs' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin())
);
drop policy if exists proofs_owner_upload on storage.objects;
create policy proofs_owner_upload on storage.objects for insert to authenticated with check (
  bucket_id='proofs' and (storage.foldername(name))[1]=auth.uid()::text and exists(
    select 1 from public.orders o where o.id::text=(storage.foldername(name))[2] and o.user_id=auth.uid() and o.status in ('pending','rejected') and o.expires_at>now()
  )
);
drop policy if exists proofs_owner_cleanup on storage.objects;
create policy proofs_owner_cleanup on storage.objects for delete to authenticated using (
  bucket_id='proofs' and (storage.foldername(name))[1]=auth.uid()::text and not exists(select 1 from public.orders o where o.proof_url=name)
);

create or replace function public.submit_order_proof(order_id uuid, proof_path text)
returns void language plpgsql security definer set search_path = public
as $$ declare current_order record; begin
  if auth.uid() is null then raise exception 'Masuk terlebih dahulu'; end if;
  select id,user_id,plan_id,total_amount,status,proof_url,created_at,base_amount,unique_code,expires_at,qris_image_url,merchant_name,instructions,note into current_order
  from public.orders where id=order_id and user_id=auth.uid() for update;
  if current_order.id is null or current_order.status not in ('pending','rejected') or current_order.expires_at<=now() then raise exception 'Pesanan tidak bisa menerima bukti'; end if;
  if proof_path not like auth.uid()::text || '/' || order_id::text || '/%' or not exists(select 1 from storage.objects where bucket_id='proofs' and name=proof_path) then raise exception 'Bukti tidak valid'; end if;
  update public.orders set proof_url=proof_path,status='awaiting_verification',note=null where id=order_id;
end; $$;
revoke all on function public.submit_order_proof(uuid,text) from public;
grant execute on function public.submit_order_proof(uuid,text) to authenticated;

commit;
