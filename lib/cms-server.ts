import {activeSponsors} from "./sponsors";
import "server-only";
import {publicReviewClient,readLandingReviews,readReviews} from "./reviews";
import {readSiteSettings} from "./site-settings";
import {normalizeBlocks,type CmsPlan} from "./cms";
export async function readPublishedPage(slug:string){const client=publicReviewClient();if(!client)return null;try{const {data,error}=await client.from("page_feed").select("id,slug,title,blocks").eq("slug",slug).maybeSingle();return !error&&data?{...data,blocks:normalizeBlocks(data.blocks)}:null;}catch{return null;}}
export async function readCmsContext(){const client=publicReviewClient();const [settings,reviews,plans,sponsors,customerReviews]=await Promise.all([readSiteSettings(),readLandingReviews(),client?client.from("plans").select("id,name,price_idr,period,features,is_highlighted").eq("is_active",true).gt("price_idr",0).in("period",["monthly","yearly"]).order("sort").order("price_idr"):Promise.resolve({data:null}),activeSponsors("landing"),readReviews(client)]);return {settings,reviews,sponsors,customerReviews,plans:(plans.data??[]).map(p=>({...p,features:Array.isArray(p.features)?p.features.filter((v:unknown):v is string=>typeof v==="string"):[]})) as CmsPlan[]};}
