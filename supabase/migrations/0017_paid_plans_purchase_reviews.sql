begin;

-- Free is the account default, never a product checkout. Keep legacy rows/users.
update public.plans set is_active=false,is_highlighted=false where price_idr=0 or period='free';
alter table public.profiles alter column premium_until set default null;
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$ begin
 insert into public.profiles(id,display_name,premium_until) values(new.id,split_part(new.email,'@',1),null) on conflict(id) do nothing;
 return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
insert into public.profiles(id,display_name,premium_until) select id,split_part(email,'@',1),null from auth.users on conflict(id) do nothing;

create or replace function public.admin_save_plan(payload jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare plan_id uuid; feature_list text[]; old_plan jsonb;
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
 if payload is null or jsonb_typeof(payload)<>'object' or octet_length(payload::text)>20000 then raise exception 'Paket tidak valid'; end if;
 if coalesce(length(trim(payload->>'name')),0) not between 1 and 80 or coalesce(payload->>'slug','') !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or length(payload->>'slug')>80 then raise exception 'Paket tidak valid'; end if;
 if coalesce(payload->>'period','') not in ('monthly','yearly') or coalesce(payload->>'price_idr','') !~ '^[0-9]+$' or (payload->>'price_idr')::bigint>20000 then raise exception 'Harga tidak valid'; end if;
 if (payload->>'price_idr')::integer<9000 then raise exception 'Harga tidak valid'; end if;
 if jsonb_typeof(payload->'features') is distinct from 'array' or jsonb_array_length(payload->'features')>30 then raise exception 'Fitur tidak valid'; end if;
 if exists(select 1 from jsonb_array_elements(payload->'features') f where jsonb_typeof(f)<>'string' or length(trim(f#>>'{}')) not between 1 and 200) then raise exception 'Fitur tidak valid'; end if;
 select coalesce(array_agg(trim(f)),array[]::text[]) into feature_list from jsonb_array_elements_text(payload->'features') f;
 if jsonb_typeof(payload->'is_active') is distinct from 'boolean' or jsonb_typeof(payload->'is_highlighted') is distinct from 'boolean' or coalesce(payload->>'sort','') !~ '^[0-9]{1,4}$' then raise exception 'Status tidak valid'; end if;
 if nullif(payload->>'id','') is not null then
  plan_id:=(payload->>'id')::uuid;
  select to_jsonb(p) into old_plan from public.plans p where p.id=plan_id for update;
  if old_plan is null then raise exception 'Paket tidak ditemukan'; end if;
  update public.plans set name=trim(payload->>'name'),slug=payload->>'slug',price_idr=(payload->>'price_idr')::integer,period=payload->>'period',features=feature_list,is_active=(payload->>'is_active')::boolean,is_highlighted=(payload->>'is_highlighted')::boolean,sort=(payload->>'sort')::integer where id=plan_id;
 else
  insert into public.plans(name,slug,price_idr,period,features,is_active,is_highlighted,sort) values(trim(payload->>'name'),payload->>'slug',(payload->>'price_idr')::integer,payload->>'period',feature_list,(payload->>'is_active')::boolean,(payload->>'is_highlighted')::boolean,(payload->>'sort')::integer) returning id into plan_id;
 end if;
 perform public.record_admin_audit(case when old_plan is null then 'plan.create' else 'plan.update' end,plan_id::text,jsonb_build_object('before',old_plan,'after',payload));
 return plan_id;
end; $$;
create or replace function public.create_premium_order(selected_plan uuid)
returns uuid language plpgsql security definer set search_path = public
as $$
declare p record; settings record; code integer; order_id uuid; existing uuid; expiry integer;
begin
  if auth.uid() is null then raise exception 'Masuk terlebih dahulu'; end if;
  perform pg_advisory_xact_lock(hashtextextended('ceritakita-payment-orders',0));
  perform public.expire_my_orders();
  select id,name,slug,price_idr,period,features,is_active into p from public.plans where id=selected_plan and is_active for share;
  if p.id is null or p.period not in ('monthly','yearly') or p.price_idr is null or p.price_idr<9000 or p.price_idr>20000 then raise exception 'Paket tidak tersedia'; end if;

  select id into existing from public.orders where user_id=auth.uid() and plan_id=selected_plan and status in ('pending','rejected') and expires_at>now() order by created_at desc limit 1;
  if existing is not null then return existing; end if;
  if exists(select 1 from public.orders where user_id=auth.uid() and status in ('pending','awaiting_verification','rejected')) then raise exception 'Selesaikan pesanan sebelumnya dulu, ya.'; end if;
  if (select count(*) from public.orders where user_id=auth.uid() and created_at>now()-interval '1 day') >= 5 then raise exception 'Maksimal 5 pesanan per hari.'; end if;
  select id,qris_image_url,merchant_name,instructions,expiry_minutes,unique_code_enabled,provider_label into settings from public.payment_settings where id=1 for share;
  if settings.qris_image_url is null or settings.qris_image_url !~ '^https://' then raise exception 'QRIS belum tersedia'; end if;
  expiry := greatest(1,least(coalesce(settings.expiry_minutes,60),1440));
  code := 0;
  if settings.unique_code_enabled then
    select candidate into code from generate_series(1,99) candidate
    where not exists(select 1 from public.orders where total_amount=p.price_idr+candidate and status in ('pending','awaiting_verification','rejected'))
    order by random() limit 1;
    if code is null then raise exception 'Kode pembayaran sedang penuh. Coba lagi nanti.'; end if;
  end if;
  insert into public.profiles(id,display_name) select auth.uid(),split_part(email,'@',1) from auth.users where id=auth.uid() on conflict(id) do nothing;
  insert into public.orders(user_id,plan_id,base_amount,unique_code,total_amount,status,expires_at,qris_image_url,merchant_name,instructions)
  values(auth.uid(),p.id,p.price_idr,code,p.price_idr+code,'pending',now()+make_interval(mins=>expiry),settings.qris_image_url,settings.merchant_name,settings.instructions)
  returning id into order_id;
  return order_id;
end; $$;
revoke all on function public.create_premium_order(uuid) from public;
grant execute on function public.create_premium_order(uuid) to authenticated;

-- Admin REST writes cannot create or reactivate a free product either.
create or replace function public.guard_paid_plan()
returns trigger language plpgsql security definer set search_path=public as $$ begin
 if new.price_idr is null or new.price_idr<=0 or new.period is null or new.period not in ('monthly','yearly') then
  if tg_op='UPDATE' and (old.price_idr=0 or old.period='free') and new.price_idr is not distinct from old.price_idr and new.period is not distinct from old.period and new.is_active is false then return new;end if;
  raise exception 'Paket Gratis adalah status akun, bukan produk yang dapat dibeli';
 end if;
 return new;
end; $$;
drop trigger if exists guard_paid_plan on public.plans;
create trigger guard_paid_plan before insert or update of price_idr,period,is_active on public.plans for each row execute function public.guard_paid_plan();
revoke all on function public.guard_paid_plan() from public,anon,authenticated;

-- Defense in depth for service-side inserts as well as RPC checkout.
create or replace function public.guard_paid_order()
returns trigger language plpgsql security definer set search_path=public as $$ begin
 if new.base_amount is null or new.base_amount<=0 or new.total_amount is null or new.total_amount<=0
 or not exists(select 1 from public.plans where id=new.plan_id and price_idr>0 and period in ('monthly','yearly')) then raise exception 'Paket gratis tidak dapat dibeli';end if;
 return new;
end; $$;
drop trigger if exists guard_paid_order on public.orders;
create trigger guard_paid_order before insert or update of plan_id,base_amount,total_amount on public.orders for each row execute function public.guard_paid_order();

-- Reject verification of legacy zero-price orders as well.
create or replace function public.admin_verify_payment(actor uuid,order_id uuid,decision text,rejection_reason text default '')
returns jsonb language plpgsql security definer set search_path=public as $$
declare payment public.orders%rowtype;active_until timestamptz;next_until timestamptz;minutes integer;
begin
 if not exists(select 1 from public.profiles where id=actor and role='admin') then raise exception 'Admin required' using errcode='42501';end if;
 if decision is null or decision not in ('paid','rejected') or rejection_reason is null or char_length(rejection_reason)>1000 or (decision='rejected' and btrim(rejection_reason)='') then raise exception 'Invalid decision';end if;
 select * into payment from public.orders where id=order_id for update;
 if payment.id is null or payment.status is distinct from 'awaiting_verification' or payment.proof_url is null
 or payment.proof_url not like payment.user_id::text||'/'||payment.id::text||'/%'
 or not exists(select 1 from storage.objects where bucket_id='proofs' and name=payment.proof_url) then raise exception 'Order is not awaiting verification';end if;
 if decision='paid' then
  if coalesce(payment.base_amount,0)<=0 or coalesce(payment.total_amount,0)<=0 or payment.plan_period is null or payment.plan_period not in ('monthly','yearly') then raise exception 'Invalid paid plan period';end if;
  select premium_until into active_until from public.profiles where id=payment.user_id for update;
  if not found then raise exception 'Profile not found';end if;
  next_until:=greatest(coalesce(active_until,now()),now())+case when payment.plan_period='yearly' then interval '1 year' else interval '1 month' end;
  update public.profiles set premium_until=next_until where id=payment.user_id;
  update public.orders set status='paid',note=null,verified_by=actor,verified_at=now() where id=payment.id;
 else
  select greatest(1,least(coalesce(expiry_minutes,60),1440)) into minutes from public.payment_settings where id=1;
  update public.orders set status='rejected',note=btrim(rejection_reason),verified_by=actor,verified_at=now(),expires_at=greatest(expires_at,now()+make_interval(mins=>coalesce(minutes,60))) where id=payment.id;
 end if;
 insert into public.audit_logs(actor_id,action,target,meta) values(actor,'payment.'||decision,payment.id::text,jsonb_build_object('before_status',payment.status,'reason',case when decision='rejected' then btrim(rejection_reason) else null end,'premium_until',next_until));
 return jsonb_build_object('user_id',payment.user_id,'plan_name',payment.plan_name,'premium_until',next_until);
end; $$;

-- Preserve legacy reviews as a private archive; do not invent a purchase for them.
drop trigger if exists guard_review_write on public.reviews;
alter table public.reviews add column if not exists order_id uuid;
alter table public.reviews add column if not exists plan_id uuid;
alter table public.reviews add column if not exists comment text;
alter table public.reviews add column if not exists display_name text;
alter table public.reviews add column if not exists updated_at timestamptz;
alter table public.reviews drop constraint if exists reviews_user_id_key;
alter table public.reviews drop constraint if exists reviews_order_id_fkey;
alter table public.reviews add constraint reviews_order_id_fkey foreign key(order_id) references public.orders(id) on delete cascade;
alter table public.reviews drop constraint if exists reviews_plan_id_fkey;
alter table public.reviews add constraint reviews_plan_id_fkey foreign key(plan_id) references public.plans(id);
create unique index if not exists reviews_order_id_unique on public.reviews(order_id);
alter table public.reviews drop constraint if exists reviews_status_check;
update public.reviews set comment=coalesce(comment,body,''),display_name=coalesce(nullif(display_name,''),'Teman '||substr(id::text,1,6)),updated_at=coalesce(updated_at,created_at,now());
update public.reviews set status='hidden',is_featured=false where order_id is null or status is null or status not in ('pending','approved','hidden');
alter table public.reviews alter column comment set not null;
alter table public.reviews alter column display_name set not null;
alter table public.reviews alter column updated_at set default now();
alter table public.reviews alter column updated_at set not null;
alter table public.reviews alter column status set default 'pending';
alter table public.reviews alter column status set not null;
alter table public.reviews add constraint reviews_status_check check(status in ('pending','approved','hidden'));
create index if not exists reviews_user_order_idx on public.reviews(user_id,order_id);

-- A persistent, transaction-safe limit across server instances. No client access.
create table if not exists public.review_write_limits(user_id uuid primary key references public.profiles(id) on delete cascade,attempts timestamptz[] not null default '{}');
alter table public.review_write_limits enable row level security;
revoke all on public.review_write_limits from public,anon,authenticated;
create or replace function public.review_plain_text(value text)
returns text language sql immutable set search_path=public as $$
 select regexp_replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(coalesce(value,''),'<(script|style)[^>]*>.*?</(script|style)[[:space:]]*>','','gis'),'<[^>]*>','','g'),'[^[:print:][:space:]]','','g'),chr(11),''),chr(12),''),'^[[:space:]]+|[[:space:]]+$','','g');
$$;
create or replace function public.guard_review_write()
returns trigger language plpgsql security definer set search_path=public as $$
declare purchase public.orders%rowtype; recent timestamptz[];content_changed boolean;
begin
 if tg_op='UPDATE' and (new.user_id is distinct from old.user_id or new.order_id is distinct from old.order_id or new.plan_id is distinct from old.plan_id or new.created_at is distinct from old.created_at) then raise exception 'Identitas pesanan tidak dapat diubah';end if;
 if tg_op='INSERT' then content_changed:=true;
 else content_changed:=new.rating is distinct from old.rating or new.comment is distinct from old.comment or new.display_name is distinct from old.display_name or new.body is distinct from old.body or new.title is distinct from old.title;end if;
 if content_changed then
  if auth.uid() is null or (new.user_id<>auth.uid() and not public.is_admin()) then raise exception 'Akses ditolak';end if;
  select * into purchase from public.orders where id=new.order_id for share;
  if purchase.id is null or purchase.user_id is distinct from new.user_id or purchase.status is distinct from 'paid' or coalesce(purchase.base_amount,0)<=0 or purchase.plan_id is null then raise exception 'Pesanan berbayar disetujui diperlukan';end if;
  new.comment:=public.review_plain_text(new.comment);new.display_name:=public.review_plain_text(new.display_name);
  if new.rating is null or new.rating not between 1 and 5 or char_length(new.comment) not between 10 and 500 or char_length(new.display_name) not between 1 and 60 then raise exception 'Ulasan tidak valid';end if;
  perform pg_advisory_xact_lock(hashtextextended('review-write:'||auth.uid()::text,0));
  select coalesce(array_agg(t),array[]::timestamptz[]) into recent from public.review_write_limits l cross join lateral unnest(l.attempts) t where l.user_id=auth.uid() and t>now()-interval '10 minutes';
  if cardinality(recent)>=5 then raise exception 'Batas ulasan tercapai';end if;
  insert into public.review_write_limits(user_id,attempts) values(auth.uid(),array_append(recent,now())) on conflict(user_id) do update set attempts=excluded.attempts;
  new.plan_id:=purchase.plan_id;new.body:=new.comment;new.title:='';new.is_featured:=false;
  if tg_op='UPDATE' and old.status='hidden' then new.status:='hidden';else new.status:='pending';end if;
  new.updated_at:=now();
 elsif tg_op='UPDATE' and (new.status is distinct from old.status or new.is_featured is distinct from old.is_featured or new.admin_note is distinct from old.admin_note) then
  if not public.is_admin() then raise exception 'Moderasi hanya oleh admin';end if;
  new.updated_at:=now();
 end if;
 return new;
end; $$;
create trigger guard_review_write before insert or update on public.reviews for each row execute function public.guard_review_write();
revoke all on function public.guard_review_write(),public.guard_paid_order(),public.handle_new_user() from public,anon,authenticated;

create or replace function public.review_is_published(target uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.reviews r join public.orders o on o.id=r.order_id where r.id=target and r.status='approved' and o.status='paid' and o.base_amount>0 and o.user_id=r.user_id and o.plan_id=r.plan_id);
$$;
revoke all on function public.review_is_published(uuid) from public;
grant execute on function public.review_is_published(uuid) to anon,authenticated;
alter table public.reviews enable row level security;
do $$ declare pol record;begin
 for pol in select policyname from pg_policies where schemaname='public' and tablename='reviews' loop execute format('drop policy if exists %I on public.reviews',pol.policyname);end loop;
end; $$;
create policy reviews_public_approved on public.reviews for select to anon using(status='approved' and public.review_is_published(id));
create policy reviews_owner_read on public.reviews for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy reviews_owner_insert on public.reviews for insert to authenticated with check(user_id=auth.uid() and status='pending' and exists(select 1 from public.orders o where o.id=order_id and o.user_id=auth.uid() and o.status='paid' and o.base_amount>0 and o.plan_id=reviews.plan_id));
create policy reviews_owner_update on public.reviews for update to authenticated using(user_id=auth.uid() or public.is_admin()) with check(user_id=auth.uid() or public.is_admin());
create policy reviews_owner_delete on public.reviews for delete to authenticated using(user_id=auth.uid() or public.is_admin());
revoke all on public.reviews from public,anon,authenticated;
grant select(id,rating,comment,display_name,status,created_at,updated_at) on public.reviews to anon;
grant select,delete on public.reviews to authenticated;
grant insert(user_id,order_id,rating,comment,display_name) on public.reviews to authenticated;
grant update(rating,comment,display_name) on public.reviews to authenticated;

-- Deliberate owner-executed view: identity columns stay private even to logged-in readers.
create or replace view public.review_feed with(security_barrier=true) as
select r.id,r.display_name as name,r.rating,r.title,r.comment as body,r.photos,r.is_featured,r.helpful_count,
 (r.created_at at time zone 'Asia/Jakarta')::date as day,
 exists(select 1 from public.review_votes v where v.review_id=r.id and v.user_id=auth.uid()) as voted,
 r.created_at,coalesce(o.plan_name,p.name,'Paket') as plan_name
from public.reviews r join public.orders o on o.id=r.order_id left join public.plans p on p.id=r.plan_id
where r.status='approved' and r.rating between 1 and 5 and o.status='paid' and o.base_amount>0 and o.user_id=r.user_id and o.plan_id=r.plan_id
order by r.created_at desc,r.id desc;
revoke all on public.review_feed from public,anon,authenticated;
grant select on public.review_feed to anon,authenticated;
create or replace function public.public_review_summary()
returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('total',count(*),'average',coalesce(avg(rating),0),'distribution',jsonb_build_object('1',count(*) filter(where rating=1),'2',count(*) filter(where rating=2),'3',count(*) filter(where rating=3),'4',count(*) filter(where rating=4),'5',count(*) filter(where rating=5))) from public.review_feed;
$$;
revoke all on function public.public_review_summary() from public;
grant execute on function public.public_review_summary() to anon,authenticated;

create or replace function public.admin_review_list()
returns jsonb language plpgsql security definer set search_path=public as $$ declare result jsonb;begin
 if not public.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into result from (
 select r.id,r.order_id,r.display_name,coalesce(o.plan_name,pl.name,'Paket') as plan_name,coalesce(p.display_name,'Teman CeritaKita') as name,coalesce(u.email,'Akun dihapus') as email,r.rating,r.title,r.body,r.status,r.is_featured,r.admin_note,
 (select count(*) from public.reports x where x.target_type='review' and x.target_id=r.id) as report_count,
 (select count(*) from public.reports x where x.target_type='review' and x.target_id=r.id and x.status='open') as open_reports
 from public.reviews r left join public.orders o on o.id=r.order_id left join public.plans pl on pl.id=r.plan_id left join public.profiles p on p.id=r.user_id left join auth.users u on u.id=r.user_id order by r.created_at desc,r.id desc
 )t;return result;
end; $$;

create or replace function public.admin_moderate_review(target_id uuid,operation text,reason text,note text,featured boolean)
returns void language plpgsql security definer set search_path=public as $$ declare previous record;reason_label text;begin
 if not public.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 if operation is null or operation not in ('hidden','removed','restore','feature','note') or note is null or char_length(note)>1000 or featured is null then raise exception 'Invalid action';end if;
 if operation in ('hidden','removed') and (reason is null or reason not in ('spam','sara','lainnya') or char_length(btrim(note))<3) then raise exception 'Reason required';end if;
 select id,status,is_featured,admin_note,order_id,user_id into previous from public.reviews where id=target_id for update;
 if previous.id is null then raise exception 'Review missing';end if;
 if operation='removed' then
 delete from public.reviews where id=target_id;
 elsif operation='hidden' then
 reason_label:=case reason when 'spam' then 'Spam' when 'sara' then 'SARA' else 'Lainnya' end;
 update public.reviews set status=operation,is_featured=false,admin_note=reason_label||': '||btrim(note) where id=target_id;
 elsif operation='restore' then
 if not exists(select 1 from public.orders o join public.reviews r on r.order_id=o.id where r.id=target_id and o.user_id=r.user_id and o.status='paid' and o.base_amount>0 and o.plan_id=r.plan_id) then raise exception 'Paid purchase required';end if;
 update public.reviews set status='approved',admin_note=null where id=target_id;
 elsif operation='feature' then
 if previous.status is distinct from 'approved' then raise exception 'Only approved reviews can be featured';end if;
 update public.reviews set is_featured=featured where id=target_id;
 else
 if previous.status in ('hidden','removed') and char_length(btrim(note))<3 then raise exception 'Keep the takedown reason';end if;
 update public.reviews set admin_note=nullif(btrim(note),'') where id=target_id;
 end if;
 if operation in ('hidden','removed','restore') then update public.reports set status='handled',handled_by=auth.uid(),handled_at=now() where target_type='review' and reports.target_id=admin_moderate_review.target_id and status='open';end if;
 perform public.record_admin_audit('moderation.review.'||operation,target_id::text,jsonb_build_object('before',to_jsonb(previous),'reason',reason,'note',note,'featured',featured));
end; $$;


revoke all on function public.admin_save_plan(jsonb),public.admin_review_list(),public.admin_moderate_review(uuid,text,text,text,boolean) from public,anon;
grant execute on function public.admin_save_plan(jsonb),public.admin_review_list(),public.admin_moderate_review(uuid,text,text,text,boolean) to authenticated;
commit;
