import type {Metadata} from "next";
import Link from "next/link";
import {authenticatedClient} from "@/lib/supabase-server";
import {readReviews} from "@/lib/reviews";
import ReviewBoard from "@/components/ReviewBoard";
import ReviewEditor from "@/components/ReviewEditor";
import type {OwnReview} from "./types";
export const metadata:Metadata={title:"Ulasan pembelianmu"};
export default async function UserReviewPage({searchParams}:{searchParams:Promise<{order?:string}>}){
 const {supabase,user}=await authenticatedClient();const params=await searchParams;
 const [feed,{data:orders,error:orderError},{data:rows,error:ownError},{data:profile}]=await Promise.all([readReviews(supabase),supabase.from("orders").select("id,plan_id,plan_name,created_at").eq("user_id",user.id).eq("status","paid").gt("base_amount",0).not("plan_id","is",null).order("created_at",{ascending:false}),supabase.from("reviews").select("id,order_id,rating,comment,display_name,status,admin_note").eq("user_id",user.id),supabase.from("profiles").select("display_name").eq("id",user.id).maybeSingle()]);
 const selected=orders?.find(o=>o.id===params.order)??orders?.[0];const row=rows?.find(r=>r.order_id===selected?.id);
 const own:OwnReview|null=row?{id:row.id,orderId:row.order_id,rating:row.rating,comment:row.comment??"",displayName:row.display_name??"",status:row.status,note:row.admin_note}:null;
 return <><p className="text-xs tracking-[.15em] text-purple-800">PENGALAMANMU BERARTI</p><h1 className="mt-4 text-3xl font-medium tracking-tight">Ulasan pembelian CeritaKita</h1><p className="mt-3 text-sm text-muted">Satu ulasan untuk setiap pesanan yang disetujui. Ulasan dan perubahan diperiksa admin sebelum tayang.</p>{orderError||ownError?<p role="alert" className="mt-6 rounded-2xl bg-peach p-5 text-sm">Pesanan atau ulasanmu belum bisa dimuat. Coba muat ulang sebelum mengedit.</p>:selected?<><nav aria-label="Pilih pesanan untuk diulas" className="mt-6 flex flex-wrap gap-3">{orders?.map(order=><Link key={order.id} href={`/app/review?order=${order.id}`} aria-current={selected.id===order.id?"page":undefined} className={`btn text-xs ${selected.id===order.id?"btn-brand":"btn-ghost"}`}>{order.plan_name??"Paket"} · {order.id.slice(0,8)}{rows?.some(r=>r.order_id===order.id)?" · Sudah diulas":""}</Link>)}</nav><ReviewEditor key={`${selected.id}:${own?.id??"new"}:${own?.status??""}`} orderId={selected.id} own={own} defaultName={profile?.display_name?.trim()||"Teman CeritaKita"}/></>:<div className="mt-6 rounded-[28px] bg-white p-6 shadow-soft"><p className="text-sm text-muted">Belum ada pesanan yang bisa diulas. Tombol ulasan tersedia setelah pembayaran disetujui.</p><Link href="/app/premium" className="btn btn-brand mt-4 text-sm">Lihat paket berbayar →</Link></div>}<ReviewBoard initial={feed} authenticated/></>;
}
