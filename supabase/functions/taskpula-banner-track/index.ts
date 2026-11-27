import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const respond=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
async function hash(value:string){const bytes=new TextEncoder().encode(value);const digest=await crypto.subtle.digest("SHA-256",bytes);return Array.from(new Uint8Array(digest)).map(x=>x.toString(16).padStart(2,"0")).join("");}
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return respond({error:"POST required."},405);
 const url=Deno.env.get("SUPABASE_URL"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!url||!service)return respond({error:"Tracking service unavailable."},503);
 let body:Record<string,unknown>;try{body=await req.json();}catch{return respond({error:"Invalid request."},400);}
 if(typeof body.ad_id!=="string"||!["impression","click"].includes(String(body.event)))return respond({error:"Invalid ad event."},400);
 const forwarded=req.headers.get("x-forwarded-for")?.split(",")[0]?.trim()||req.headers.get("cf-connecting-ip")||"unknown";
 const agent=req.headers.get("user-agent")||"unknown";
 const visitorHash=await hash(forwarded+"|"+agent);
 const db=createClient(url,service,{auth:{persistSession:false}});
 const {error}=await db.rpc("track_banner_ad_event",{p_ad_id:body.ad_id,p_event:body.event,p_visitor_hash:visitorHash});
 if(error)return respond({error:"Ad event could not be recorded."},400);
 return respond({ok:true});
});