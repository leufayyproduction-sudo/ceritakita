import { createClient } from "@supabase/supabase-js";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { ReviewPageData,ReviewSummary } from "@/app/app/review/types";

export function publicReviewClient() {
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) return null;
  try { return createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}}); } catch { return null; }
}
export const REVIEW_PAGE_SIZE=8;
export async function readReviews(client:SupabaseClient|null,options:{page?:number;stars?:number;sort?:"newest"|"helpful"}={}):Promise<ReviewPageData>{
 const page=Number.isSafeInteger(options.page)&&Number(options.page)>=0?Math.min(Number(options.page),10000):0;
 const stars=Number.isInteger(options.stars)&&Number(options.stars)>=1&&Number(options.stars)<=5?Number(options.stars):0;
 const sort=options.sort==="helpful"?"helpful":"newest";
 const summary:ReviewSummary={total:0,average:0,distribution:[5,4,3,2,1].map(rating=>({rating,count:0}))};
 const empty:ReviewPageData={reviews:[],error:true,total:0,summary,page,stars,sort};if(!client)return empty;
 let query=client.from("review_feed").select("id,name,rating,title,body,helpful_count,voted,day,plan_name",{count:"exact"});if(stars)query=query.eq("rating",stars);
 if(sort==="helpful")query=query.order("helpful_count",{ascending:false});
 query=query.order("created_at",{ascending:false}).order("id",{ascending:false}).range(page*REVIEW_PAGE_SIZE,(page+1)*REVIEW_PAGE_SIZE-1);
 try{
 const [{data,error,count},{data:totals,error:summaryError}]=await Promise.all([query,client.rpc("public_review_summary")]);
 if(error||summaryError||!totals||typeof totals!=="object")return empty;
 summary.total=Number(totals.total);summary.average=Number(totals.average);summary.distribution=[5,4,3,2,1].map(rating=>({rating,count:Number(totals.distribution?.[String(rating)]??0)}));
 return {reviews:(data??[]).map(row=>({id:row.id,name:row.name,rating:Number(row.rating),title:row.title,body:row.body,helpful:Number(row.helpful_count),voted:Boolean(row.voted),day:row.day,planName:row.plan_name})),error:false,total:count??0,summary,page,stars,sort};
 }catch{return empty;}
}

export async function readLandingReviews() {
  const client=publicReviewClient();
  if (!client) return [];
  const {data,error}=await client.from("review_feed").select("id,name,rating,title,body").eq("is_featured",true).order("created_at",{ascending:false}).order("id",{ascending:false}).limit(12);
  if(error)return [];
  return (data??[]).map(row=>({name:String(row.name),text:String(row.body??"").slice(0,240),tag:"Ulasan CeritaKita",rating:Number(row.rating)}));
}
