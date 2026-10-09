import type {PlanInput} from "./admin-types";
// Keep payment caps and the SQL validation in sync when changing these limits.
export const PLAN_PRICE_LIMITS={min:9000,max:20000} as const;
export function validatePlan(input:PlanInput):string|null{
 if(!input||typeof input!=="object")return "Paket tidak valid.";
 if(typeof input.name!=="string"||!input.name.trim()||input.name.trim().length>80)return "Nama paket harus berisi 1–80 karakter.";
 if(typeof input.slug!=="string"||input.slug.length>80||!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(input.slug))return "Slug hanya boleh berisi huruf kecil, angka, dan tanda hubung.";
 if(!["monthly","yearly"].includes(input.period))return "Pilih periode paket yang valid.";
 if(!Number.isSafeInteger(input.price_idr)||(input.price_idr<PLAN_PRICE_LIMITS.min||input.price_idr>PLAN_PRICE_LIMITS.max))return `Harga paket berbayar Rp${PLAN_PRICE_LIMITS.min.toLocaleString("id-ID")}–Rp${PLAN_PRICE_LIMITS.max.toLocaleString("id-ID")}.`;
 if(!Array.isArray(input.features)||input.features.length>30||input.features.some(f=>typeof f!=="string"||!f.trim()||f.length>200))return "Isi maksimal 30 fitur, masing-masing 1–200 karakter.";
 if(typeof input.is_active!=="boolean"||typeof input.is_highlighted!=="boolean"||!Number.isSafeInteger(input.sort)||input.sort<0||input.sort>9999)return "Status atau urutan paket tidak valid.";
 return null;
}
