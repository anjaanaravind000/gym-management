import { createClient } from "npm:@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-gym-session, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS","Content-Type":"application/json"};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:cors});
const sha256=async(v:string)=>{const b=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(v));return Array.from(new Uint8Array(b)).map(x=>x.toString(16).padStart(2,"0")).join("")};
Deno.serve(async(req)=>{if(req.method==="OPTIONS")return new Response("ok",{headers:cors});try{
 const sk=JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")??"{}"),url=Deno.env.get("SUPABASE_URL"),secret=sk.default;if(!url||!secret)return json({error:"Function configuration is incomplete"},500);
 const db=createClient(url,secret),token=req.headers.get("x-gym-session")?.trim();if(!token)return json({error:"Gym session required"},401);
 const hash=await sha256(token),{data:s}=await db.from("login_sessions").select("user_id").eq("token_hash",hash).gt("expires_at",new Date().toISOString()).maybeSingle();if(!s)return json({error:"Invalid or expired gym session"},401);
 const{data:g}=await db.from("users").select("id,gym_id,role,status").eq("id",s.user_id).maybeSingle();if(!g||g.status!=="active"||g.role!=="admin")return json({error:"Unauthorized"},403);
 const{data:cx}=await db.rpc("get_whatsapp_credentials_internal",{p_gym_id:g.gym_id});const c=Array.isArray(cx)?cx[0]:cx;if(!c)return json({error:"WhatsApp connection has not been saved"},400);
 let resp:Response;
 try{
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),10000);
  try{
   resp=await fetch("https://graph.facebook.com/"+c.api_version+"/"+c.phone_number_id+"?fields=display_phone_number,verified_name",{
    headers:{Authorization:"Bearer "+c.access_token},signal:controller.signal
   });
  }finally{clearTimeout(timer)}
 }catch(fetchError){
  const message="Connection test timed out or the network closed before Meta responded. Check the token, API version and network, then test again.";
  await db.rpc("record_whatsapp_test_internal",{p_gym_id:g.gym_id,p_ok:false,p_error:message});
  return json({ok:false,error:message},504);
 }
 const result=await resp.json(),ok=resp.ok;
 await db.rpc("record_whatsapp_test_internal",{p_gym_id:g.gym_id,p_ok:ok,p_error:ok?null:JSON.stringify(result)});
 if(!ok)return json({ok:false,error:"WhatsApp connection was rejected by Meta",details:result},502);
 return json({ok:true,display_phone_number:result?.display_phone_number??null,verified_name:result?.verified_name??null});
}catch(e){return json({error:e instanceof Error?e.message:"Unexpected error"},500)}});