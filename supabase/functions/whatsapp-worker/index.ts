import { createClient } from "npm:@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"content-type, x-worker-secret","Access-Control-Allow-Methods":"POST, OPTIONS","Content-Type":"application/json"};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:cors});
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 try{
  const secret=Deno.env.get("WHATSAPP_WORKER_SECRET");
  if(!secret||req.headers.get("x-worker-secret")!==secret)return json({error:"Unauthorized"},401);
  const sk=JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")??"{}"),url=Deno.env.get("SUPABASE_URL"),service=sk.default;
  const access=Deno.env.get("WHATSAPP_ACCESS_TOKEN"),numberId=Deno.env.get("WHATSAPP_PHONE_NUMBER_ID"),version=Deno.env.get("WHATSAPP_API_VERSION");
  if(!url||!service||!access||!numberId||!version)return json({error:"WhatsApp worker is not configured"},500);
  const db=createClient(url,service);
  const{data:rows}=await db.from("notifications").select("id,message_body,members(phone)").eq("channel","whatsapp").in("status",["queued","failed"]).lt("retry_count",3).order("scheduled_at").limit(50);
  let sent=0,failed=0;
  for(const n of rows??[]){
   const phone=n.members?.phone;if(!phone)continue;
   const resp=await fetch("https://graph.facebook.com/"+version+"/"+numberId+"/messages",{method:"POST",headers:{Authorization:"Bearer "+access,"Content-Type":"application/json"},body:JSON.stringify({messaging_product:"whatsapp",to:phone.replace(/\D/g,""),type:"text",text:{preview_url:false,body:n.message_body??"Your gym membership needs attention."}})});
   const result=await resp.json(),providerId=result?.messages?.[0]?.id??null;
   await db.from("notification_logs").insert({notification_id:n.id,status:resp.ok?"sent":"failed",delivery_status:resp.ok?"sent":"failed",provider_message_id:providerId,error_message:resp.ok?null:JSON.stringify(result)});
   await db.from("notifications").update({status:resp.ok?"sent":"failed",delivery_status:resp.ok?"sent":"failed",sent_at:resp.ok?new Date().toISOString():null,error_message:resp.ok?null:JSON.stringify(result),retry_count:(n.retry_count??0)+(resp.ok?0:1)}).eq("id",n.id);
   if(resp.ok)sent++;else failed++;
  }
  return json({ok:true,processed:sent+failed,sent,failed});
 }catch(e){return json({error:e instanceof Error?e.message:"Unexpected error"},500)}
});