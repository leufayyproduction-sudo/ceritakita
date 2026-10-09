"use server";
import {createServerClient,type CookieOptions} from "@supabase/ssr";
import {cookies} from "next/headers";
import {publicReviewClient,readReviews} from "@/lib/reviews";
export async function loadPublishedReviews(options:{page?:number;stars?:number;sort?:"newest"|"helpful"}){
 if(!options||typeof options!=="object")options={};
 const fallback=publicReviewClient();const url=process.env.NEXT_PUBLIC_SUPABASE_URL;const key=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
 if(!url||!key)return readReviews(fallback,options);
 const store=await cookies();const client=createServerClient(url,key,{cookies:{getAll:()=>store.getAll(),setAll(values:{name:string;value:string;options:CookieOptions}[]){values.forEach(({name,value,options})=>store.set(name,value,options));}}});
 try{const {data:{user},error}=await client.auth.getUser();return readReviews(!error&&user?client:fallback,options);}catch{return readReviews(fallback,options);}
}
