export type PurchaseReviewInput={orderId:string;rating:number;comment:string;displayName:string};
export const reviewOrderId=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function reviewText(value:string){return value.replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1\s*>/gi,"").replace(/<[^>]*>/g,"").replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g,"").trim();}
export function validatePurchaseReview(input:PurchaseReviewInput):string|null{
 if(!input||typeof input!=="object"||typeof input.orderId!=="string"||!reviewOrderId.test(input.orderId))return "Pilih pesanan yang telah disetujui.";
 if(!Number.isInteger(input.rating)||input.rating<1||input.rating>5)return "Pilih bintang 1–5.";
 if(typeof input.comment!=="string"||input.comment.length>2000||reviewText(input.comment).length<10||reviewText(input.comment).length>500)return "Isi komentar 10–500 karakter.";
 if(typeof input.displayName!=="string"||input.displayName.length>200||reviewText(input.displayName).length<1||reviewText(input.displayName).length>60)return "Isi nama tampilan 1–60 karakter.";
 return null;
}
export function eligibleReviewOrder(order:{user_id:string;status:string;base_amount:number;plan_id:string|null}|null,userId:string){return Boolean(order&&order.user_id===userId&&order.status==="paid"&&order.base_amount>0&&order.plan_id);}
