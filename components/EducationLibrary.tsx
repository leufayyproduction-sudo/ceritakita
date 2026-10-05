"use client";

import Link from "next/link";
import SponsorCards from "@/components/SponsorCards";
import type {Sponsor} from "@/lib/sponsors-schema";
import { useState } from "react";
import type { EducationArticle, EducationVideo } from "@/app/app/edukasi/types";

const card = "overflow-hidden rounded-[36px] bg-white shadow-soft transition-[transform,box-shadow] duration-[250ms] ease-out motion-safe:[@media(hover:hover)]:hover:-translate-y-1 motion-safe:[@media(hover:hover)]:hover:shadow-lg";

export default function EducationLibrary({ articles, videos, articleError, videoError, sponsors=[] }: {
  sponsors?:Sponsor[]; articles: EducationArticle[]; videos: EducationVideo[]; articleError: boolean; videoError: boolean;
}) {
  const [category, setCategory] = useState("");
  const [playing, setPlaying] = useState<string | null>(null);
  const categories = [...new Set([...articles, ...videos].map(item => item.category))].sort((a, b) => a.localeCompare(b, "id"));
  const filteredArticles = articles.filter(item => !category || item.category === category);
  const filteredVideos = videos.filter(item => !category || item.category === category);
  function selectCategory(next: string) { setCategory(next); setPlaying(null); }

  return <div className="mt-8">
    <div role="group" aria-label="Filter kategori edukasi" className="flex flex-wrap gap-2">
      {[{ value: "", label: "Semua" }, ...categories.map(value => ({ value, label: value }))].map(({ value, label }) => <button key={value} type="button" aria-pressed={category === value} onClick={() => selectCategory(value)} className={`btn text-xs focus-visible:outline focus-visible:outline-2 focus-visible:outline-purple-600 ${category === value ? "btn-brand" : "btn-ghost"}`}>{label}</button>)}
    </div>
    <p role="status" className="mt-4 text-xs text-muted">{filteredVideos.length} video · {filteredArticles.length} artikel{category ? ` dalam kategori ${category}` : ""}</p>
    <section aria-labelledby="education-videos" className="mt-8"><h2 id="education-videos" className="mb-5 text-xl font-medium">Video pilihan</h2>
      {videoError ? <p role="alert" className="rounded-2xl bg-peach p-5 text-sm">Video belum bisa dimuat. Coba muat ulang sebentar lagi, ya.</p> : filteredVideos.length === 0 ? <p className="rounded-[24px] bg-lilac/60 p-6 text-sm text-muted">Belum ada video dalam kategori ini.</p> : <div className="grid gap-5 sm:grid-cols-2">{filteredVideos.map(video => <article key={video.id} className={card}>
        <div className="relative aspect-video overflow-hidden bg-lilac">
          {video.locked||!video.youtubeId ? <div className="grid h-full place-items-center p-6 text-center text-purple-800"><p>🔒 Video Premium</p></div> : playing === video.id ? <iframe src={`https://www.youtube-nocookie.com/embed/${video.youtubeId}?autoplay=1&rel=0`} title={video.title} className="absolute inset-0 h-full w-full border-0" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" referrerPolicy="strict-origin-when-cross-origin" allowFullScreen /> : <button type="button" onClick={() => setPlaying(video.id)} aria-label={`Putar video: ${video.title}`} className="group absolute inset-0 w-full overflow-hidden focus-visible:outline focus-visible:outline-4 focus-visible:outline-purple-600 focus-visible:outline-offset-[-4px]">
            <span aria-hidden="true" className="absolute inset-0 bg-cover bg-center transition-transform duration-[250ms] ease-out motion-safe:group-active:scale-105 motion-safe:[@media(hover:hover)]:group-hover:scale-105" style={{ backgroundImage: `url(https://img.youtube.com/vi/${video.youtubeId}/hqdefault.jpg)` }} />
            <span aria-hidden="true" className="absolute inset-0 bg-gradient-to-t from-purple-800/50 to-transparent" />
            <span aria-hidden="true" className="relative inline-grid h-14 w-14 place-items-center rounded-full bg-white/95 text-xl text-purple-800 shadow-soft">▶</span>
          </button>}
        </div>
        <div className="p-6"><span className="rounded-full bg-blush px-3 py-1.5 text-[10px] text-purple-800">{video.category}</span>{video.premium&&<span className="ml-2 text-xs text-purple-800">Premium</span>}<h3 className="mt-4 text-lg font-medium leading-snug">{video.title}</h3><p className="mt-3 text-xs leading-relaxed text-muted">{video.description||"Video dari YouTube. Pilihan subtitle mengikuti video."}</p><div className="mt-4 flex flex-wrap gap-3">{playing === video.id && <button type="button" onClick={() => setPlaying(null)} className="btn btn-ghost text-xs">Tutup pemutar</button>}{video.locked?<Link href="/app/premium" className="btn btn-brand text-xs">Buka akses Premium →</Link>:video.youtubeId&&<a href={`https://www.youtube.com/watch?v=${video.youtubeId}`} target="_blank" rel="noopener noreferrer" className="inline-flex min-h-11 items-center text-xs text-purple-800 underline underline-offset-4">Buka di YouTube ↗</a>}</div></div>
      </article>)}</div>}
    </section>
    <section aria-labelledby="education-articles" className="mt-10"><h2 id="education-articles" className="mb-5 text-xl font-medium">Bacaan untukmu</h2>
      {articleError ? <p role="alert" className="rounded-2xl bg-peach p-5 text-sm">Artikel belum bisa dimuat. Coba muat ulang sebentar lagi, ya.</p> : filteredArticles.length === 0 ? <p className="rounded-[24px] bg-lilac/60 p-6 text-sm text-muted">Belum ada artikel dalam kategori ini.</p> : <div className="grid items-start gap-5 sm:grid-cols-2">{filteredArticles.map(article => <article key={article.id} className={`${card} p-6 sm:p-8`}>{article.coverUrl&&<img src={article.coverUrl} alt={article.title} className="mb-5 aspect-video w-full rounded-2xl object-cover"/>}<span className="rounded-full bg-sage px-3 py-1.5 text-[10px] text-purple-800">{article.category}</span>{article.premium&&<span className="ml-2 text-xs text-purple-800">Premium</span>}<h3 className="mt-4 text-xl font-medium leading-snug">{article.title}</h3><p className="mt-3 text-sm leading-relaxed text-muted">{article.excerpt}</p>{article.locked?<Link href="/app/premium" className="btn btn-brand mt-5 text-xs">🔒 Buka akses Premium →</Link>:<details className="mt-5"><summary className="btn btn-ghost cursor-pointer text-xs focus-visible:outline-purple-600">Baca artikel ↗</summary><div className="mt-5 whitespace-pre-wrap break-words border-t border-[#EADFF2] pt-5 text-sm leading-relaxed text-muted [&_h2]:my-4 [&_h2]:text-xl [&_h3]:my-3 [&_h3]:text-lg [&_p]:mb-3 [&_ul]:list-disc [&_ul]:pl-5 [&_ol]:list-decimal [&_ol]:pl-5 [&_blockquote]:border-l-4 [&_blockquote]:border-purple-600 [&_blockquote]:pl-4" dangerouslySetInnerHTML={{__html:article.content??""}} /><SponsorCards sponsors={sponsors}/></details>}</article>)}</div>}
    </section>
  </div>;
}
