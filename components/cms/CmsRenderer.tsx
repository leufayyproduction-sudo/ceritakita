import ReviewBoard from "@/components/ReviewBoard";
import type {ReviewPageData} from "@/app/app/review/types";
import SponsorCards from "@/components/SponsorCards";
import type {Sponsor} from "@/lib/sponsors-schema";
import Link from "next/link";
import Image from "next/image";
import {Fragment,type CSSProperties} from "react";
import Marquee from "@/components/Marquee";
import Reveal from "@/components/Reveal";
import {youtubeId,sanitizeEducationHtml} from "@/lib/education";
import type {SiteSettings} from "@/lib/site-settings-schema";
import type {PageBlock,CmsPlan,CmsReview} from "@/lib/cms";
const tint=["bg-peach","bg-blush","bg-lilac","bg-sage"];
const featureColors=["from-peach to-blush","from-sage to-lilac","from-lilac to-blush","from-blush to-peach"];
export type CmsContext={settings:SiteSettings;plans:CmsPlan[];reviews:CmsReview[];sponsors?:Sponsor[];preview?:boolean;customerReviews?:ReviewPageData};
export function CmsBlock({block,context,primary=true}:{block:PageBlock;context:CmsContext;primary?:boolean}){
 const {settings,plans,reviews}=context;
 const chips=block.useSiteChips?settings.chips:block.items.map(item=>item.title).filter(Boolean);
 const text=(value:string)=>value.replaceAll("{{site}}",settings.name);
 const stat=(value:number|null,fallback:string)=>value===null?fallback:new Intl.NumberFormat("id-ID",{notation:"compact",maximumFractionDigits:1}).format(value);
 if(block.type==="hero")return (<Reveal className="landing-hero">
          <div className="hero-copy">
            <p className="mb-4 text-[10px] tracking-[.15em] text-purple-800 lg:text-xs">{block.eyebrow}</p>
            <h1 className="text-[2.65rem] font-medium leading-[1.1] tracking-[-.045em] md:text-[2.7rem] lg:text-[3.25rem]">{block.title}</h1>
            <Link href={block.buttonHref||"/masuk"} className="btn btn-brand mt-6 text-sm">{block.buttonText} <span aria-hidden="true">→</span></Link>
            <div id={primary?"tentang":`tentang-${block.id}`} className="hero-about mt-9">
              <div className="brand-photo hero-circle mb-5"><Image src={block.secondaryImageUrl||"/images/laptop.jpg"} alt="" fill sizes="112px" className="brand-photo-image object-cover" /></div>
              <p className="mb-2 text-xs font-semibold text-purple-800">{text(block.aboutLabel)}</p>
              <h2 className="text-xl font-medium">{block.aboutTitle}</h2>
              <p className="mt-3 text-sm leading-relaxed text-muted">{block.aboutText}</p>
              <a href={block.aboutButtonHref||"#fitur"} className="mt-3 inline-flex min-h-11 items-center gap-3 text-xs font-semibold text-purple-800">{text(block.aboutButtonText)} <span aria-hidden="true">↗</span></a>
            </div>
          </div>
          <div className="hero-visual">
            <p className="mb-4 text-center text-[10px] tracking-[.17em] text-purple-800">{block.visualLabel}</p>
            <div className="brand-photo arch hero-arch shadow-soft"><Image src={block.imageUrl||"/images/meditasi.jpg"} alt={block.imageAlt} fill priority sizes="(min-width: 768px) 340px, 85vw" className="brand-photo-image object-cover" /></div>
            <span aria-hidden="true" className="absolute -right-2 top-16 grid h-11 w-11 place-items-center rounded-full bg-lilac/90 text-xl">↗</span>
          </div>
          <div className="hero-stats">
            <div className="flex items-center gap-3 rounded-full bg-blush/70 p-2 pr-4"><div className="brand-photo relative h-10 w-10 shrink-0 overflow-hidden rounded-full"><Image src={block.secondaryImageUrl||"/images/laptop.jpg"} alt="" fill sizes="40px" className="brand-photo-image object-cover" /></div><span className="text-xs">{stat(settings.stats.users,"2.4K+")} teman bercerita</span></div>
            <div className="mt-6 grid grid-cols-2 gap-2">{[[stat(settings.stats.users,"2.4K+"), "Pengguna"], [stat(settings.stats.stories,"1K+"), "Cerita dibagikan"], [stat(settings.stats.articles,"50+"), "Artikel & video"], ["1 ruang", "Untuk semua rasa"]].map(([number, label], i) => <div key={label} className={`stat-card ${tint[i]} rounded-2xl p-4`}><p className="stat-number text-xl font-medium text-purple-800">{number}</p><p className="mt-1 text-[10px] text-muted">{label}</p></div>)}</div>
            <div className="brand-photo hero-blob mx-auto mt-9"><Image src={block.secondaryImageUrl||"/images/laptop.jpg"} alt="Ilustrasi menulis cerita melalui laptop" fill sizes="180px" className="brand-photo-image object-cover" /></div>
          </div>
        </Reveal>);
 if(block.type==="features")return (<Reveal id={primary?"fitur":`fitur-${block.id}`} aria-label={`Fitur ${settings.name}`} className="px-5 py-8 sm:px-10 lg:px-14">
        {block.title&&<h2 className="mb-4 text-3xl font-medium">{block.title}</h2>}{block.text&&<p className="mb-5 text-sm text-muted">{block.text}</p>}
        <div className="flex snap-x snap-mandatory gap-4 overflow-x-auto pb-5 pt-3 md:gap-5">
          {block.items.map(({ title, text:description, label, symbol, href, imageUrl, imageAlt },index) => <Link href={href||"/masuk"} key={title} className={`feature-card group relative flex min-h-[340px] w-[260px] shrink-0 snap-start flex-col overflow-hidden rounded-[36px] bg-gradient-to-b ${featureColors[index%4]} p-6 md:w-[calc((100%-40px)/3)] lg:w-[calc((100%-60px)/4)]`}>
            <span aria-hidden="true" className="feature-arrow absolute right-5 top-5 grid h-8 w-8 place-items-center rounded-full bg-white/60">↗</span>
            <div aria-hidden="true" className="feature-visual relative mb-8 flex h-36 items-center justify-center"><span className="absolute h-32 w-32 rotate-12 rounded-[48%_52%_38%_62%] bg-white/40" />{imageUrl?<img src={imageUrl} alt={imageAlt} className="relative h-32 w-32 rounded-[48%_52%_38%_62%] object-cover"/>:<span className="relative text-7xl font-light text-purple-800/70">{symbol}</span>}<span className="absolute -bottom-1 rounded-full bg-white/70 px-4 py-2 text-[10px] text-purple-800">{label}</span></div>
            <h2 className="mt-auto text-xl font-medium tracking-tight">{title}</h2><p className="mt-3 text-xs leading-relaxed text-muted">{description}</p>
          </Link>)}
        </div>
      </Reveal>);
 if(block.type==="pricing")return (<Reveal id={primary?"harga":`harga-${block.id}`} className="px-5 py-10 sm:px-10 lg:px-14">
        <p className="text-xs tracking-widest text-purple-800">{block.eyebrow}</p><h2 className="mb-7 mt-3 text-3xl font-medium">{block.title}</h2>
        <div className="grid gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,240px),1fr))]">{plans.filter(plan=>plan.price_idr>0&&["monthly","yearly"].includes(plan.period)).map(plan=><article key={plan.id} className="feature-card flex flex-col rounded-[32px] bg-lilac/60 p-5">{plan.is_highlighted&&<span className="mb-3 self-start rounded-full bg-white px-3 py-1 text-[10px] text-purple-800">Pilihan unggulan</span>}<h3 className="text-xl">{plan.name}</h3><p className="mt-4 text-2xl font-semibold text-purple-800">{new Intl.NumberFormat("id-ID",{style:"currency",currency:"IDR",maximumFractionDigits:0}).format(Number(plan.price_idr))}</p><p className="text-xs text-muted">{plan.period==="yearly"?"per tahun":"per bulan"}</p><ul className="my-5 space-y-2 text-xs leading-relaxed text-muted">{(Array.isArray(plan.features)?plan.features:[]).filter((f:unknown):f is string=>typeof f==="string").map((f:string)=><li key={f}>✓ {f}</li>)}</ul><Link href="/app/premium" className="btn btn-brand mt-auto justify-center !px-4 text-xs">Pilih {plan.name} →</Link></article>)}</div>
        {!plans.some(plan=>plan.price_idr>0&&["monthly","yearly"].includes(plan.period))&&<p className="text-sm text-muted">Pilihan paket belum tersedia. Coba lagi sebentar, ya.</p>}
      </Reveal>);
 if(block.type==="testimonials")return (<Reveal id={primary?"review":`review-${block.id}`} className="my-8 overflow-hidden rounded-[40px] bg-lilac py-12 sm:rounded-[56px] sm:py-16">
        <p className="text-center text-xs tracking-[.15em] text-purple-800">{block.eyebrow}</p>
        <h2 className="mb-8 mt-3 text-center text-3xl font-medium tracking-tight sm:text-4xl">{block.title}</h2>
        {reviews.length > 0 ? <><Marquee items={reviews} dir="l" /><Marquee items={[...reviews].reverse()} dir="r" /></> : <p className="px-6 text-center text-sm text-muted">Ulasan pilihan akan tampil di sini. <Link href="/review" className="underline">Lihat ulasan pengguna</Link></p>}
        <p className="mt-7 px-6 text-center text-xs text-muted">{block.text}</p>
      </Reveal>);
 if(block.type==="chips")return (<Reveal className="px-5 pb-0 pt-9 text-center sm:px-10">
        <h2 className="text-3xl font-medium tracking-tight">{block.title}</h2>
        <p className="mt-3 text-sm text-muted">{block.text}</p>
        <div className="relative mx-auto mt-10 flex max-w-3xl flex-wrap items-center justify-center gap-x-2 gap-y-0 px-2 pb-4 pt-4 sm:px-14">
          {chips.map((chip, i) => <span key={`${chip}-${i}`} className={`cloud-chip relative -mx-1 -my-1 rounded-full px-6 py-4 text-sm text-purple-800 sm:px-9 sm:py-5 sm:text-lg ${tint[i % 4]}`} style={{ "--chip-tilt": `${[-24, 9, -12, 21, -8, 16, -19, 5, 23, -10, 0][i % 11]}deg`, zIndex: i % 3 } as CSSProperties}>{chip}</span>)}
        </div>
      </Reveal>);
 if(block.type==="cta")return (<Reveal className="relative z-[3] mx-3 rounded-[40px] px-7 py-10 text-white sm:mx-6 sm:flex sm:items-center sm:justify-between sm:gap-8 sm:rounded-[56px] sm:px-14 sm:py-12" style={{ background: "linear-gradient(120deg,#8E2F9C,#C93A8E)" }}>
        <div><h2 className="max-w-md text-3xl font-medium leading-tight tracking-tight sm:text-4xl">{block.title.split("\n").map((line,index)=><Fragment key={index}>{index>0&&<br/>}{line}</Fragment>)}</h2><p className="mt-3 text-sm text-white/80">{block.text}</p></div>
        <Link href={block.buttonHref||"/masuk"} className="btn btn-ghost mt-6 text-sm sm:mt-0">{block.buttonText} <span aria-hidden="true">→</span></Link>
      </Reveal>);
 const id=block.type==="video"?youtubeId(block.youtubeUrl):null;
 return <Reveal className="px-5 py-10 sm:px-10 lg:px-14"><div className={`rounded-[36px] p-6 sm:p-8 ${block.type==="sponsor"?"bg-peach":"bg-lilac/40"}`}>
 {block.type==="sponsor"&&<p className="mb-3 text-xs font-medium text-purple-800">Disponsori</p>}{block.eyebrow&&<p className="mb-3 text-xs tracking-widest text-purple-800">{block.eyebrow}</p>}{block.title&&<h2 className="text-3xl font-medium">{block.title}</h2>}{block.text&&<p className="mt-4 whitespace-pre-wrap text-sm leading-relaxed text-muted">{block.text}</p>}
 {block.imageUrl&&<img src={block.imageUrl} alt={block.imageAlt} className="mt-5 max-h-96 w-full rounded-[28px] object-cover"/>}
 {block.type==="video"&&id&&<iframe src={`https://www.youtube-nocookie.com/embed/${id}`} title={block.title||"Video edukasi"} className="mt-6 aspect-video w-full rounded-[28px] border-0" allow="encrypted-media; picture-in-picture; fullscreen" allowFullScreen/>}
 {block.type==="text"&&<div className="mt-5 whitespace-pre-wrap break-words text-sm leading-relaxed [&_h2]:my-4 [&_h2]:text-xl [&_p]:mb-3 [&_ul]:list-disc [&_ul]:pl-5 [&_ol]:list-decimal [&_ol]:pl-5" dangerouslySetInnerHTML={{__html:sanitizeEducationHtml(block.html)}}/>}
 {block.type==="gallery"&&<div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">{block.items.map((item,index)=><figure key={index} className="overflow-hidden rounded-[28px] bg-white">{item.imageUrl&&<img src={item.imageUrl} alt={item.imageAlt} className="aspect-square w-full object-cover"/>}<figcaption className="p-4 text-sm"><p className="font-medium">{item.title}</p><p className="mt-2 text-muted">{item.text}</p></figcaption></figure>)}</div>}
 {block.type==="faq"&&<div className="mt-6 grid gap-3">{block.items.map((item,index)=><details key={index} className="rounded-2xl bg-white p-5"><summary className="cursor-pointer font-medium">{item.title}</summary><p className="mt-4 whitespace-pre-wrap text-sm text-muted">{item.text}</p></details>)}</div>}
 {block.buttonText&&block.buttonHref&&<Link href={block.buttonHref} className="btn btn-brand mt-6 text-sm">{block.buttonText} →</Link>}
 </div></Reveal>;
}
export default function CmsLayout({blocks,context,home=true}:{blocks:PageBlock[];context:CmsContext;home?:boolean}){
 const {settings}=context;const firstHero=blocks[0]?.type==="hero";
 return <main className="mx-auto my-3 max-w-6xl overflow-hidden rounded-[32px] bg-white pb-8 shadow-soft sm:my-8 sm:rounded-[48px]">
 <svg aria-hidden="true" className="pointer-events-none absolute h-0 w-0"><defs><filter id="brand-photo-tone" colorInterpolationFilters="sRGB"><feColorMatrix type="matrix" values="1.05 -.45 .40 0 0  -.18 .95 .23 0 0  -.45 .70 .75 0 0  0 0 0 1 0"/></filter></defs></svg>
 <div className="bg-gradient-to-b from-lilac/60 via-blush/20 to-white px-5 sm:px-10 lg:px-14">
        <nav aria-label="Navigasi utama" className="landing-nav relative z-10 flex items-center justify-between gap-4 py-6">
          <Link href="/" className="brand-logo flex min-w-0 items-center gap-2 font-semibold text-purple-800"><Image src={settings.logoUrl} unoptimized alt="" width={40} height={40} className="h-10 w-10 shrink-0 object-contain" /><span className="truncate" title={settings.name}>{settings.name}</span></Link>
          <div className="nav-menu hidden gap-6 text-xs text-muted md:flex"><a href={home?"#fitur":"/#fitur"}>Fitur</a><a href={home?"#tentang":"/#tentang"}>Tentang</a><a href={home?"#harga":"/#harga"}>Harga</a><a href={home?"#review":"/#review"}>Ulasan</a><Link href="/kontak">Kontak</Link></div>
          <Link href="/masuk" className="btn btn-ghost !px-4 !py-2 text-xs">Masuk <span aria-hidden="true">→</span></Link>
        </nav>
{firstHero&&<CmsBlock block={blocks[0]} context={context}/>}</div>
 {blocks.slice(firstHero?1:0).map(block=>block.type==="hero"?<div key={block.id} className="bg-gradient-to-b from-lilac/60 via-blush/20 to-white px-5 sm:px-10 lg:px-14"><CmsBlock block={block} context={context} primary={blocks.find(b=>b.type===block.type)?.id===block.id}/></div>:<CmsBlock key={block.id} block={block} context={context} primary={blocks.find(b=>b.type===block.type)?.id===block.id}/>)}
      {home&&context.customerReviews&&!context.preview&&<div className="px-5 py-8 sm:px-10 lg:px-14"><ReviewBoard initial={context.customerReviews} authenticated={false}/></div>}
      {home&&<SponsorCards sponsors={context.sponsors??[]} track={!context.preview}/>}
      <footer className="px-6 pt-10 text-center text-xs text-muted"><Link href="/" className="inline-flex max-w-full items-center gap-2 text-lg font-semibold text-purple-800"><Image src={settings.logoUrl} unoptimized alt="" width={40} height={40} className="h-10 w-10 shrink-0 object-contain" /><span className="truncate" title={settings.name}>{settings.name}</span></Link><div className="my-5 flex flex-wrap justify-center gap-6"><a href={home?"#fitur":"/#fitur"}>Fitur</a><a href={home?"#tentang":"/#tentang"}>Tentang</a><Link href="/review">Ulasan</Link><Link href="/kontak">Kontak</Link></div><p className="break-words leading-relaxed">© {new Date().getFullYear()} {settings.name}. {settings.footerText}</p>{settings.contactEmail&&<a className="mt-4 inline-block break-all underline" href={`mailto:${settings.contactEmail}`}>{settings.contactEmail}</a>}{settings.socials.length>0&&<div className="mt-4 flex flex-wrap justify-center gap-4">{settings.socials.map((social,index)=><a key={index} href={social.url} target="_blank" rel="noopener noreferrer" className="underline">{social.label}</a>)}</div>}<div className="mx-auto mt-6 max-w-xl rounded-[24px] bg-peach/70 p-5 text-left"><p className="font-medium text-purple-800">Bantuan saat kamu membutuhkan</p><p className="mt-2 break-words leading-relaxed">{settings.emergencyText}</p>{settings.emergencyContacts.map((contact,index)=><a key={index} href={contact.url} className="mt-3 block font-medium text-purple-800 underline">{contact.label}{contact.phone?` · ${contact.phone}`:""}</a>)}</div></footer>
</main>;
}
