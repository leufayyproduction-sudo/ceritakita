export type PublicReview = { id: string; name: string; rating: number; title: string; body: string; helpful: number; voted: boolean; day: string; planName?:string };
export type OwnReview = { id: string; orderId:string; rating: number; comment: string; displayName:string; status: string; note: string | null };
export type ReviewSummary={total:number;average:number;distribution:{rating:number;count:number}[]};
export type ReviewPageData={reviews:PublicReview[];error:boolean;total:number;summary:ReviewSummary;page:number;stars:number;sort:"newest"|"helpful"};
