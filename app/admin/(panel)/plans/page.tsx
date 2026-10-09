import {requireAdmin} from "@/lib/admin";
import PlansManager from "@/components/admin/PlansManager";
import type {AdminPlan} from "@/lib/admin-types";
export const metadata={title:"Paket Langganan"};
export default async function PlansPage(){const {supabase}=await requireAdmin();const rows:AdminPlan[]=[];let failed=false;for(let offset=0;;){const {data,error}=await supabase.from("plans").select("id,name,slug,price_idr,period,features,is_highlighted,is_active,sort").gt("price_idr",0).in("period",["monthly","yearly"]).order("sort").order("id").range(offset,offset+999);if(error){failed=true;break;}if(!data?.length)break;rows.push(...data as AdminPlan[]);offset+=data.length;}return <main className="rounded-[28px] bg-white p-5 shadow-soft sm:p-7"><h1 className="text-2xl font-medium">Paket langganan</h1><p className="mb-6 mt-2 text-sm text-muted">Atur paket, harga, fitur, dan urutan tampilan publik.</p><PlansManager plans={rows} loadError={failed}/></main>;}
