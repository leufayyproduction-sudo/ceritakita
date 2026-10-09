import type { Metadata } from "next";
import { authenticatedClient } from "@/lib/supabase-server";
import PremiumCheckout from "@/components/PremiumCheckout";
import type { Plan, PaymentOrder } from "./types";

export const metadata: Metadata = { title: "Premium" };

export default async function PremiumPage() {
  const { supabase, user } = await authenticatedClient();
  const { error: expiryError } = await supabase.rpc("expire_my_orders");
  const [{ data: rows, error: planError }, { data: settings }, { data: orders, error: orderError }] = await Promise.all([
    supabase.from("plans").select("id,name,price_idr,period,features,is_highlighted,sort").eq("is_active", true).gt("price_idr", 0).in("period", ["monthly", "yearly"]).order("sort").order("price_idr"),
    supabase.from("payment_settings").select("qris_image_url,provider_label").eq("id", 1).maybeSingle(),
    supabase.from("orders").select("id,plan_id,plan_name,base_amount,unique_code,total_amount,status,expires_at,qris_image_url,merchant_name,instructions,note,proof_url").eq("user_id", user.id).order("created_at", { ascending: false }).limit(10),
  ]);
  const plans: Plan[] = (rows ?? []).map(plan => ({ id: plan.id, name: plan.name, price: Number(plan.price_idr), period: plan.period, highlighted:Boolean(plan.is_highlighted), features: Array.isArray(plan.features) ? plan.features.filter((feature: unknown): feature is string => typeof feature === "string") : [] }));
  const safeOrders: PaymentOrder[] = await Promise.all((orders ?? []).map(async order => {
    let proofLink: string | null = null;
    if (typeof order.proof_url === "string" && order.proof_url.startsWith(`${user.id}/${order.id}/`)) {
      const { data } = await supabase.storage.from("proofs").createSignedUrl(order.proof_url, 300);
      proofLink = data?.signedUrl ?? null;
    }
    return { id: order.id, planName: order.plan_name ?? plans.find(plan => plan.id === order.plan_id)?.name ?? "Paket Premium", baseAmount: Number(order.base_amount), uniqueCode: Number(order.unique_code), total: Number(order.total_amount), status: order.status, expiresAt: order.expires_at, qris: typeof order.qris_image_url === "string" && /^https:\/\//.test(order.qris_image_url) ? order.qris_image_url : null, merchant: order.merchant_name, instructions: order.instructions, note: order.note, proofLink };
  }));
  const available = typeof settings?.qris_image_url === "string" && /^https:\/\//.test(settings.qris_image_url);
  return <><p className="text-xs tracking-[.15em] text-purple-800">TEMANI PERJALANANMU</p><h1 className="mt-4 text-3xl font-medium tracking-tight sm:text-4xl">Pilihan paket CeritaKita</h1><p className="mt-3 text-sm leading-relaxed text-muted">Pilih paket yang cocok untukmu. Pembayaran QRIS diperiksa manual sebelum Premium aktif.</p><PremiumCheckout plans={plans} orders={safeOrders} available={available} provider={typeof settings?.provider_label === "string" ? settings.provider_label : "DANA"} loadError={Boolean(planError || orderError || expiryError)} /></>;
}
