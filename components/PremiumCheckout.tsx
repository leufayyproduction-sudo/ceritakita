"use client";

import { useEffect, useRef, useState, useTransition, type FormEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createOrder } from "@/app/app/premium/actions";
import { rupiah, type Plan, type PaymentOrder } from "@/app/app/premium/types";

const labels: Record<string, string> = { pending: "Menunggu pembayaran", awaiting_verification: "Menunggu verifikasi", paid: "Pembayaran disetujui", rejected: "Bukti ditolak", expired: "Kedaluwarsa" };

function OrderCard({ order, now, provider }: { order: PaymentOrder; now: number | null; provider: string }) {
  const router = useRouter();
  const [file, setFile] = useState<File | null>(null);
  const [message, setMessage] = useState("");
  const [pending, startTransition] = useTransition();
  const fileInput = useRef<HTMLInputElement>(null);
  const remaining = now === null ? null : Math.max(0, Math.ceil((new Date(order.expiresAt).getTime() - now) / 1000));
  const expired = order.status === "expired" || (remaining === 0 && ["pending", "rejected"].includes(order.status));
  const canUpload = !expired && ["pending", "rejected"].includes(order.status);
  const countdown = remaining === null ? "Menghitung…" : `${String(Math.floor(remaining / 3600)).padStart(2, "0")}:${String(Math.floor(remaining / 60) % 60).padStart(2, "0")}:${String(remaining % 60).padStart(2, "0")}`;

  async function copy() {
    try { await navigator.clipboard.writeText(String(order.total)); setMessage("Nominal tepat sudah disalin."); }
    catch { setMessage(`Salin nominal secara manual: ${order.total}`); }
  }
  function upload(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!file || !["image/jpeg", "image/png", "image/webp"].includes(file.type) || file.size === 0 || file.size > 5 * 1024 * 1024) { setMessage("Pilih JPG, PNG, atau WebP maksimal 5 MB."); return; }
    setMessage("");
    startTransition(async () => {
      try {
        const form = new FormData(); form.set("orderId", order.id); form.set("proof", file);
        const response = await fetch("/app/premium/proof", { method: "POST", body: form });
        const result: unknown = await response.json();
        if (!response.ok) {
          setMessage(result && typeof result === "object" && "error" in result && typeof result.error === "string" ? result.error : "Bukti belum terunggah. Coba lagi sebentar, ya.");
          router.refresh(); return;
        }
        setFile(null); if (fileInput.current) fileInput.current.value = "";
        setMessage("Bukti terkirim. Pembayaranmu menunggu verifikasi manual."); router.refresh();
      } catch { setMessage("Bukti belum terunggah. Periksa koneksi lalu coba lagi, ya."); }
    });
  }

  return <article className="mt-5 rounded-[36px] bg-white p-5 shadow-soft sm:p-8">
    <div className="flex flex-wrap items-center justify-between gap-3"><h3 className="text-xl font-medium">Pesanan {order.planName}</h3><span role="status" className="rounded-full bg-lilac px-4 py-2 text-xs text-purple-800">{expired ? "Kedaluwarsa" : labels[order.status] ?? "Status belum tersedia"}</span></div>
    <p className="mt-2 break-all text-[10px] text-muted">ID pesanan: {order.id}</p>
    <div className="mt-6 rounded-[24px] bg-blush/50 p-5"><p className="text-xs text-muted">Nominal tepat</p><p className="mt-2 text-3xl font-semibold text-purple-800">{rupiah(order.total)}</p><p className="mt-2 text-xs text-muted">Harga {rupiah(order.baseAmount)}{order.uniqueCode > 0 ? ` + kode unik ${order.uniqueCode}` : " · tanpa kode unik"}</p>{canUpload && <button type="button" onClick={copy} className="btn btn-ghost mt-4 text-xs">Salin nominal</button>}</div>
    {canUpload && <><div className="mt-5 rounded-2xl bg-peach p-4"><p className="text-sm">Sisa waktu: <span className="font-semibold tabular-nums">{countdown}</span></p><p className="mt-1 text-xs text-muted">Batas bayar: {new Intl.DateTimeFormat("id-ID", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Jakarta" }).format(new Date(order.expiresAt))} WIB</p></div><div className="mt-6 grid gap-6 sm:grid-cols-2"><div><p className="mb-3 text-sm font-medium">QRIS {provider} · {order.merchant ?? "CeritaKita"}</p>{order.qris ? <img src={order.qris} alt={`QRIS pembayaran ${order.merchant ?? "CeritaKita"}`} width={320} height={320} className="mx-auto h-auto max-h-96 w-full max-w-xs rounded-2xl border border-[#EADFF2] bg-white object-contain" /> : <p className="rounded-2xl bg-lilac p-5 text-sm text-muted">QRIS pesanan ini belum tersedia. Jangan melakukan pembayaran sebelum QRIS muncul.</p>}</div><div><p className="whitespace-pre-wrap text-sm leading-relaxed text-muted">{order.instructions ?? "Bayar nominal tepat dengan aplikasi pendukung QRIS, lalu unggah bukti pembayaran."}</p><form onSubmit={upload} className="mt-5"><label htmlFor={`proof-${order.id}`} className="text-sm font-medium">Bukti pembayaran</label><input ref={fileInput} id={`proof-${order.id}`} type="file" accept="image/jpeg,image/png,image/webp" required disabled={pending || !order.qris} onChange={event => setFile(event.target.files?.[0] ?? null)} aria-describedby={`proof-help-${order.id}`} className="mt-3 block w-full rounded-2xl border border-[#EADFF2] p-3 text-xs file:mr-3 file:rounded-full file:border-0 file:bg-lilac file:px-4 file:py-2 file:text-purple-800" /><p id={`proof-help-${order.id}`} className="mt-2 text-xs text-muted">JPG, PNG, atau WebP, maksimal 5 MB. Bukti bersifat privat.</p><button type="submit" disabled={pending || !order.qris} className="btn btn-brand mt-4 text-sm disabled:opacity-60">{pending ? "Mengunggah…" : order.status === "rejected" ? "Unggah ulang bukti →" : "Kirim bukti pembayaran →"}</button></form></div></div></>}
    {order.status === "paid" && order.baseAmount > 0 && <Link href={`/app/review?order=${order.id}`} className="btn btn-brand mt-5 text-sm">Beri Ulasan / Edit Ulasan →</Link>}
    {order.note && <p className="mt-5 rounded-2xl bg-peach p-4 text-sm">Catatan verifikasi: {order.note}</p>}
    {order.status === "awaiting_verification" && <p className="mt-5 text-sm leading-relaxed text-muted">Bukti sudah diterima. Admin akan mencocokkannya dengan pembayaran. Premium aktif setelah pesanan disetujui.</p>}
    {expired && <p className="mt-5 text-sm text-muted">Batas pembayaran telah lewat. Pilih paket untuk membuat pesanan baru.</p>}
    {order.proofLink && <a href={order.proofLink} target="_blank" rel="noopener noreferrer" className="btn btn-ghost mt-5 text-xs">Lihat bukti privat ↗</a>}
    <button type="button" disabled={pending} onClick={() => router.refresh()} className="btn btn-ghost mt-5 text-xs">Perbarui status</button>
    <p role="status" className="mt-4 text-sm text-purple-800">{message}</p>
  </article>;
}

export default function PremiumCheckout({ plans, orders, available, provider, loadError }: { plans: Plan[]; orders: PaymentOrder[]; available: boolean; provider: string; loadError: boolean }) {
  const router = useRouter();
  const [message, setMessage] = useState("");
  const [pending, startTransition] = useTransition();
  const [selectedOrder, setSelectedOrder] = useState<string | null>(null);
  const [now, setNow] = useState<number | null>(null);
  const expiredIds = useRef(new Set<string>());
  useEffect(() => { setNow(Date.now()); const timer = window.setInterval(() => setNow(Date.now()), 1000); return () => window.clearInterval(timer); }, []);
  useEffect(() => {
    if (now === null) return;
    let refresh = false;
    for (const order of orders) {
      if (["pending", "rejected"].includes(order.status) && new Date(order.expiresAt).getTime() <= now && !expiredIds.current.has(order.id)) { expiredIds.current.add(order.id); refresh = true; }
    }
    if (refresh) router.refresh();
  }, [now, orders, router]);
  function choose(planId: string) {
    setMessage("");
    startTransition(async () => {
      try {
        const result = await createOrder(planId);
        if (result.error) setMessage(result.error);
        else { setSelectedOrder(result.orderId ?? null); setMessage("Pesanan dibuat. Bayar nominal tepat, lalu kirim bukti pembayaran."); router.refresh(); }
      } catch { setMessage("Pesanan belum bisa dibuat. Coba lagi sebentar, ya."); }
    });
  }
  const active = orders.find(order => order.id === selectedOrder) ?? orders[0];
  return <div className="mt-8">{loadError && <p role="alert" className="mb-5 rounded-2xl bg-peach p-5 text-sm">Data pembayaran belum bisa dimuat. Coba muat ulang sebelum melakukan pembayaran, ya.</p>}{!available && !loadError && <p className="mb-5 rounded-2xl bg-lilac p-5 text-sm text-muted">Pembayaran Premium belum tersedia karena QRIS merchant belum dipasang. Fitur Gratis tetap bisa kamu gunakan.</p>}
    <div className="grid gap-5 [grid-template-columns:repeat(auto-fit,minmax(min(100%,240px),1fr))]">{plans.filter(plan=>plan.price>0&&["monthly","yearly"].includes(plan.period)).map(plan => <article key={plan.id} className="flex flex-col rounded-[36px] bg-white p-6 shadow-soft transition-transform duration-[250ms] ease-out motion-safe:[@media(hover:hover)]:hover:-translate-y-1">{plan.highlighted&&<span className="mb-3 self-start rounded-full bg-lilac px-3 py-1 text-[10px] text-purple-800">Pilihan unggulan</span>}<h2 className="text-xl font-medium">{plan.name}</h2><p className="mt-4 text-3xl font-semibold text-purple-800">{rupiah(plan.price)}</p><p className="mt-1 text-xs text-muted">{plan.period === "yearly" ? "per tahun" : "per bulan"}</p><ul className="my-6 space-y-3 text-xs leading-relaxed text-muted">{plan.features.map(feature => <li key={feature}>✓ {feature}</li>)}</ul><button type="button" disabled={pending || !available || loadError} onClick={() => choose(plan.id)} className="btn btn-brand mt-auto justify-center text-xs disabled:opacity-60">{pending ? "Memproses…" : `Pilih ${plan.name} →`}</button></article>)}</div>
    {!loadError && !plans.some(plan=>plan.price>0&&["monthly","yearly"].includes(plan.period)) && <p className="rounded-2xl bg-lilac p-6 text-sm text-muted">Belum ada paket yang tersedia.</p>}
    <p role="status" className="mt-5 min-h-6 text-sm text-purple-800">{message}</p>
    <section aria-labelledby="order-heading" className="mt-8"><h2 id="order-heading" className="text-xl font-medium">Pesananmu</h2>{orders.length === 0 ? <p className="mt-3 text-sm text-muted">Belum ada pesanan. Pilih paket berbayar saat pembayaran tersedia.</p> : <><div role="group" aria-label="Pilih pesanan" className="mt-4 flex flex-wrap gap-2">{orders.map(order => <button key={order.id} type="button" aria-pressed={active?.id === order.id} onClick={() => setSelectedOrder(order.id)} className={`btn text-xs ${active?.id === order.id ? "btn-brand" : "btn-ghost"}`}>{order.planName} · {order.id.slice(0, 8)}</button>)}</div>{active && <OrderCard key={active.id} order={active} now={now} provider={provider} />}</>}</section>
  </div>;
}
