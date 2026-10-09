const {test}=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs");
const path=require("node:path");
const ts=require("typescript");
function load(relative,mocks={}){
 const source=fs.readFileSync(path.join(__dirname,"..",relative),"utf8");
 const output=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,jsx:ts.JsxEmit.ReactJSX,esModuleInterop:true}}).outputText;
 const module={exports:{}};new Function("require","module","exports",output)(id=>{if(Object.hasOwn(mocks,id))return mocks[id];if(["react","react/jsx-runtime"].includes(id))return require(id);throw new Error(`Unexpected import: ${id}`);},module,module.exports);return module.exports;
}
const validation=load("lib/review-validation.ts");
const orderId="11111111-1111-4111-8111-111111111111";
const valid={orderId,rating:5,comment:"Paket ini membantu saya bercerita.",displayName:"Ak***a"};
test("rating, comment bounds, order UUID and public alias are validated",()=>{
 assert.equal(validation.validatePurchaseReview(valid),null);
 for(const input of [null,{...valid,orderId:"bad"},{...valid,rating:0},{...valid,rating:6},{...valid,rating:2.5},{...valid,comment:"pendek"},{...valid,comment:"a".repeat(501)},{...valid,displayName:" "},{...valid,displayName:"a".repeat(61)}])assert.notEqual(validation.validatePurchaseReview(input),null);
 for(const length of [10,500])assert.equal(validation.validatePurchaseReview({...valid,comment:"a".repeat(length)}),null);
});
test("review text strips executable markup and preserves normal text/newlines",()=>{
 assert.equal(validation.reviewText('<script>alert(1)</script><b>Pengalaman baik</b>\u0001'),"Pengalaman baik");
 assert.equal(validation.reviewText(" Baris satu\nBaris dua "),"Baris satu\nBaris dua");
 assert.notEqual(validation.validatePurchaseReview({...valid,comment:"<script>teks yang panjang</script>"}),null);
});
test("only the owner of a positive-price paid order can review",()=>{
 const order={user_id:"owner",status:"paid",base_amount:9000,plan_id:orderId};
 assert.equal(validation.eligibleReviewOrder(order,"owner"),true);
 for(const status of ["pending","awaiting_verification","rejected","expired"])assert.equal(validation.eligibleReviewOrder({...order,status},"owner"),false);
 assert.equal(validation.eligibleReviewOrder(order,"other"),false);
 assert.equal(validation.eligibleReviewOrder({...order,base_amount:0},"owner"),false);
 assert.equal(validation.eligibleReviewOrder({...order,plan_id:null},"owner"),false);
});
test("admin validation excludes free and zero-priced catalog products",()=>{
 const {validatePlan}=load("lib/plan-validation.ts");
 const input={name:"Plus",slug:"plus",price_idr:9000,period:"monthly",features:[],is_active:true,is_highlighted:false,sort:0};
 assert.equal(validatePlan(input),null);assert.equal(validatePlan({...input,price_idr:20000,period:"yearly"}),null);
 for(const item of [{price_idr:0},{price_idr:8999},{price_idr:20001},{period:"free",price_idr:0},{period:"free",price_idr:9000}])assert.notEqual(validatePlan({...input,...item}),null);
});
function checkout(plan){let calls=0;const query={select(){return this;},eq(){return this;},async maybeSingle(){return {data:plan,error:null};}};return {calls:()=>calls,actions:load("app/app/premium/actions.ts",{"next/cache":{revalidatePath(){}},"@/lib/supabase-server":{authenticatedClient:async()=>({supabase:{from:()=>query}})},"./provider":{staticQrisProvider:{createOrder:async()=>{calls++;return {orderId,error:null};}}}})};}
test("server checkout rejects zero, free, unavailable and inactive plans before calling provider",async()=>{
 for(const plan of [null,{id:orderId,price_idr:null,period:"monthly",is_active:true},{id:orderId,price_idr:0,period:"free",is_active:true},{id:orderId,price_idr:9000,period:"free",is_active:true},{id:orderId,price_idr:9000,period:"monthly",is_active:false},{id:orderId,price_idr:20001,period:"monthly",is_active:true}]){const context=checkout(plan);assert.ok((await context.actions.createOrder(orderId)).error);assert.equal(context.calls(),0);}
});
test("server checkout accepts an active paid plan",async()=>{const context=checkout({id:orderId,price_idr:15000,period:"monthly",is_active:true});const result=await context.actions.createOrder(orderId);assert.equal(result.error,null);assert.equal(result.orderId,orderId);assert.equal(context.calls(),1);});
function reviewClient(order,existing=null,writeError=null){const writes=[];const query=table=>({select(){return this;},eq(){return this;},async maybeSingle(){return {data:table==="orders"?order:existing,error:null};},upsert(){return Promise.resolve({error:null});},insert(values){writes.push({type:"insert",values});return Promise.resolve({error:writeError});},update(values){writes.push({type:"update",values});return this;},then(resolve){return Promise.resolve({error:writeError}).then(resolve);}});return {writes,actions:load("app/app/review/actions.ts",{"next/cache":{revalidatePath(){}},"@/lib/review-validation":validation,"@/lib/supabase-server":{authenticatedClient:async()=>({user:{id:"owner",email:"owner@example.invalid"},supabase:{from:query}})}})};}
test("review submission rejects other owners and incomplete orders without writes",async()=>{for(const order of [{user_id:"other",status:"paid",base_amount:9000,plan_id:orderId},{user_id:"owner",status:"pending",base_amount:9000,plan_id:orderId}]){const context=reviewClient(order);assert.ok((await context.actions.saveReview(valid)).error);assert.equal(context.writes.length,0);}});
test("new review stores explicit order and sanitized public display fields",async()=>{const context=reviewClient({user_id:"owner",status:"paid",base_amount:9000,plan_id:orderId});assert.equal((await context.actions.saveReview({...valid,comment:"<b>Pengalaman yang sangat membantu.</b>"})).error,null);assert.deepEqual(context.writes,[{type:"insert",values:{rating:5,comment:"Pengalaman yang sangat membantu.",display_name:"Ak***a",order_id:orderId,user_id:"owner"}}]);});
test("existing purchase review is edited without changing its order/owner",async()=>{const context=reviewClient({user_id:"owner",status:"paid",base_amount:9000,plan_id:orderId},{id:orderId});assert.equal((await context.actions.saveReview(valid)).error,null);assert.equal(context.writes.length,1);assert.equal(context.writes[0].type,"update");assert.equal(context.writes[0].values.order_id,undefined);assert.equal(context.writes[0].values.user_id,undefined);});
test("review rate limit and duplicate errors receive actionable messages",async()=>{const order={user_id:"owner",status:"paid",base_amount:9000,plan_id:orderId};assert.match((await reviewClient(order,null,{code:"P0001",message:"Batas ulasan tercapai"}).actions.saveReview(valid)).error,/10 menit/);assert.match((await reviewClient(order,null,{code:"23505",message:"unique"}).actions.saveReview(valid)).error,/mengedit/);});

const React=require("react");const {renderToStaticMarkup}=require("react-dom/server");
const uiMocks={"next/link":({children,href,...props})=>React.createElement("a",{href,...props},children),"next/navigation":{useRouter:()=>({refresh(){}})},"@/app/app/review/actions":{},"@/app/review/actions":{}};
const Board=load("components/ReviewBoard.tsx",uiMocks).default;
const summary={total:9,average:4.5,distribution:[5,4,3,2,1].map(rating=>({rating,count:rating===5?5:rating===4?4:0}))};
const initial={reviews:[{id:orderId,name:"Ak***a",rating:5,title:"",body:"<script>alert(1)</script> Pengalaman membantu",helpful:0,voted:false,day:"2026-10-09",planName:"Plus"}],summary,total:9,page:0,stars:0,sort:"newest",error:false};
test("public board renders aggregate totals, purchase label, pagination and escapes text",()=>{const html=renderToStaticMarkup(React.createElement(Board,{initial,authenticated:false}));assert.match(html,/Ulasan Pelanggan/);assert.match(html,/9 ulasan disetujui/);assert.match(html,/Pembelian Plus/);assert.match(html,/Lihat lebih banyak/);assert.match(html,/&lt;script&gt;/);assert.ok(!html.includes("<script>"));assert.ok(!html.includes("user_id"));});
test("review board distinguishes an empty feed from a load failure",()=>{const empty=renderToStaticMarkup(React.createElement(Board,{initial:{...initial,reviews:[],total:0,summary:{...summary,total:0,average:0}},authenticated:false}));assert.match(empty,/Belum ada ulasan/);assert.ok(!empty.includes("Lihat lebih banyak"));const error=renderToStaticMarkup(React.createElement(Board,{initial:{...initial,error:true},authenticated:false}));assert.match(error,/role="alert"/);assert.match(error,/belum bisa dimuat/);});
test("migration delivery files match and the schema guards legacy privacy and order uniqueness",()=>{
 const sql=fs.readFileSync(path.join(__dirname,"../supabase/migrations/0017_paid_plans_purchase_reviews.sql"),"utf8");
 assert.equal(fs.readFileSync(path.join(__dirname,"../supabase/NEXT_MIGRATION.sql"),"utf8"),sql);
 assert.ok(fs.readFileSync(path.join(__dirname,"../supabase/ALL_IN_ONE.sql"),"utf8").endsWith(sql));
 assert.match(sql,/create unique index if not exists reviews_order_id_unique/);
 assert.match(sql,/reviews_owner_insert[\s\S]*o.status='paid'/);
 const view=sql.split("create or replace view public.review_feed")[1].split("revoke all")[0];const columns=view.split("from public.reviews")[0];assert.ok(!/r\.user_id|r\.order_id/.test(columns));assert.match(view,/r.status='approved'/);
 assert.ok(!/delete from public.profiles|delete from public.plans/.test(sql));
 assert.ok(sql.indexOf("select id,name,slug,price_idr")<sql.indexOf("if existing is not null then return existing"));
});
