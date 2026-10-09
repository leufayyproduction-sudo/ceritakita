import {requireAdmin} from "@/lib/admin";
import ReviewModeration from "@/components/admin/ReviewModeration";
import type {ModerationReview} from "@/lib/moderation-types";
export default async function Page(){const {supabase}=await requireAdmin();const {data,error}=await supabase.rpc("admin_review_list");return <><h1 className="text-3xl font-medium">Moderasi ulasan</h1><p className="mt-2 text-sm text-muted">Setujui ulasan pembelian, tinjau laporan, dan pilih ulasan untuk carousel landing.</p><ReviewModeration rows={(data??[]) as ModerationReview[]} loadError={Boolean(error)}/></>;}
