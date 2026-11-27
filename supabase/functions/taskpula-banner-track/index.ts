import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const respond=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json","Cache-Control":"no-store"}});
async function visitorDigest(ip:string,agent:string,secret:string){
 const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
 const signature=await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(ip+"|"+agent));
 return Array.from(new Uint8Array(signature)).map(x=>x.toString(16).padStart(2,"0")).join("");
}
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return respond({error:"POST required."},405);
 const url=Deno.env.get("SUPABASE_URL"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!url||!service)return respond({error:"Tracking service unavailable."},503);
 let body:Record<string,unknown>;try{body=await req.json();}catch{return respond({error:"Invalid request."},400);}
 if(typeof body.ad_id!=="string"||!["impression","click"].includes(String(body.event)))return respond({error:"Invalid ad event."},400);
 const viewableMs=body.event==="impression"?Number(body.viewable_ms):0;
 if(body.event==="impression"&&(!Number.isInteger(viewableMs)||viewableMs<1000||viewableMs>60000))return respond({error:"Banner was not viewable for long enough."},400);
 const ip=req.headers.get("cf-connecting-ip")||req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
 if(!ip)return respond({error:"Visitor network identity unavailable."},400);
 const agent=req.headers.get("user-agent")||"unknown";
 const visitorHash=await visitorDigest(ip,agent,service);
 const db=createClient(url,service,{auth:{persistSession:false}});
 const {error}=await db.rpc("track_banner_ad_event",{
  p_ad_id:body.ad_id,p_event:body.event,p_visitor_hash:visitorHash,p_viewable_ms:viewableMs
 });
 if(error)return respond({error:"Ad event could not be recorded."},400);
 return respond({ok:true});
});