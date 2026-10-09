export type ModerationKind="story"|"comment";
export type ModerationReview={id:string;order_id:string|null;display_name:string;plan_name:string;name:string;email:string;rating:number;title:string;body:string;status:string;is_featured:boolean;admin_note:string|null;report_count:number;open_reports:number};
export type ModerationReport={reason:string;detail:string;status:string};
export type ModerationStory={id:string;kind:ModerationKind;alias:string;body:string;status:string;needs_moderation:boolean;report_count:number;open_reports:number;repeat_reporters:number;suspended:boolean;reports:ModerationReport[]};
export const moderationLabels:Record<string,string>={published:"Tayang",pending:"Menunggu moderasi",hidden:"Disembunyikan",removed:"Dihapus dari publik"};
export function moderationReason(reason:string,note:string){return ['spam','sara','lainnya'].includes(reason)&&typeof note==='string'&&note.trim().length>=3&&note.length<=1000;}
export function targetValid(kind:string,id:string){return ['story','comment'].includes(kind)&&typeof id==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);}

export const reviewModerationLabels:Record<string,string>={pending:"Menunggu persetujuan",approved:"Disetujui",hidden:"Disembunyikan"};
