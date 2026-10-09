"use server";

import { revalidatePath } from "next/cache";
import { authenticatedClient } from "@/lib/supabase-server";
import { staticQrisProvider } from "./provider";

export async function createOrder(planId: string) {
  if (typeof planId !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(planId)) return { error: "Paket tidak valid." };
  const { supabase } = await authenticatedClient();
  const {data:plan,error:planError}=await supabase.from("plans").select("id,price_idr,period,is_active").eq("id",planId).maybeSingle();
  if(planError||!plan||!plan.is_active||!Number.isSafeInteger(plan.price_idr)||!["monthly","yearly"].includes(plan.period)||plan.price_idr<9000||plan.price_idr>20000)return {error:"Pilih paket berbayar yang tersedia. Akun Gratis tidak memerlukan pembelian."};
  const result = await staticQrisProvider.createOrder(supabase, planId);
  if (result.error || !result.orderId) {
    const known = ["Selesaikan pesanan sebelumnya dulu, ya.", "Maksimal 5 pesanan per hari.", "QRIS belum tersedia", "Paket tidak tersedia", "Kode pembayaran sedang penuh. Coba lagi nanti."];
    return { error: known.includes(result.error?.message ?? "") ? result.error!.message : "Pesanan belum bisa dibuat. Coba lagi sebentar, ya." };
  }
  revalidatePath("/app/premium");
  return { error: null, orderId: result.orderId };
}
