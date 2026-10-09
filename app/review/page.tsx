import {publicMetadata} from "@/lib/seo";
import Link from "next/link";
import { publicReviewClient,readReviews } from "@/lib/reviews";
import ReviewBoard from "@/components/ReviewBoard";
export async function generateMetadata(){return publicMetadata("/review","Ulasan CeritaKita");}
export const dynamic="force-dynamic";
export default async function ReviewPage(){
  const initial=await readReviews(publicReviewClient());
  return <main className="mx-auto my-8 max-w-5xl px-5 py-8"><Link href="/" className="text-sm text-purple-800">← CeritaKita</Link><h1 className="mt-6 text-3xl font-medium tracking-tight">Cerita dari pengguna CeritaKita</h1><p className="mt-3 text-sm text-muted">Pengalaman setiap orang berbeda. Baca ulasan mereka di sini.</p><Link href="/app/review" className="btn btn-brand mt-5 text-sm">Tulis ulasan →</Link><ReviewBoard initial={initial} authenticated={false}/></main>;
}
