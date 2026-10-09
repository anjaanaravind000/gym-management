import { createClient } from "npm:@supabase/supabase-js@2";

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-gym-session, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS","Content-Type":"application/json"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:cors});
const sha256=async(value:string)=>{const bytes=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value));return Array.from(new Uint8Array(bytes)).map(x=>x.toString(16).padStart(2,"0")).join("")};
const scalarBool=(v:any)=>Array.isArray(v)?v[0]===true:v===true;
const normalizeWhatsappNumber=(value:unknown)=>{const digits=String(value??"").replace(/\D/g,"");if(digits.length===10)return "91"+digits;if(digits.length===11&&digits.startsWith("0"))return "91"+digits.slice(1);if(digits.length>=11&&digits.length<=15)return digits;return ""};

Deno.serve(async req=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({error:"Method not allowed"},405);
 try{
  const sk=JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")??"{}");
  const url=Deno.env.get("SUPABASE_URL"),secret=sk.default;
  if(!url||!secret)return json({error:"Function configuration is incomplete"},500);
  const db=createClient(url,secret);
  const sessionToken=req.headers.get("x-gym-session")?.trim();
  if(!sessionToken)return json({error:"Gym session required"},401);

  const tokenHash=await sha256(sessionToken);
  const{data:session}=await db.from("login_sessions").select("user_id,expires_at").eq("token_hash",tokenHash).gt("expires_at",new Date().toISOString()).maybeSingle();
  if(!session)return json({error:"Invalid or expired gym session"},401);

  const payload=await req.json(),notificationId=payload?.notification_id;
  if(typeof notificationId!=="string"||!notificationId)return json({error:"notification_id is required"},400);
  const{data:n,error:notificationError}=await db.from("notifications")
   .select("*,members(name,member_id,phone),gyms(name,phone,whatsapp)")
   .eq("id",notificationId).maybeSingle();
  if(notificationError||!n)return json({error:"Notification not found"},404);

  const{data:u}=await db.from("users").select("id,gym_id,role,status").eq("id",session.user_id).eq("gym_id",n.gym_id).maybeSingle();
  if(!u||u.status!=="active")return json({error:"Unauthorized"},403);
  const{data:perm}=await db.from("user_permissions").select("allowed").eq("user_id",u.id).eq("permission","whatsapp.manage").maybeSingle();
  if(u.role!=="admin"&&!perm?.allowed)return json({error:"Unauthorized"},403);
  if(n.status==="sent"||n.delivery_status==="delivered"||n.delivery_status==="read")return json({ok:true,already_sent:true});
  if(!["queued","failed"].includes(n.status)||Number(n.retry_count??0)>=3)return json({error:"This message is no longer eligible to send"},409);

  const phone=normalizeWhatsappNumber(n.members?.phone);
  if(!phone)return json({error:"Member phone number is invalid for WhatsApp. Use a 10-digit Indian number or include the international country calling code."},400);

  const{data:cx,error:connectionError}=await db.rpc("get_whatsapp_credentials_internal",{p_gym_id:n.gym_id});
  if(connectionError)return json({error:"Unable to load WhatsApp connection"},500);
  const connection=Array.isArray(cx)?cx[0]:cx;
  if(!connection?.enabled||connection.last_test_ok!==true)return json({error:"WhatsApp connection must be tested successfully before sending messages"},503);

  const{data:claimed,error:claimError}=await db.rpc("claim_whatsapp_notification_internal",{p_notification_id:notificationId});
  if(claimError)return json({error:"Unable to claim this message safely"},500);
  if(!scalarBool(claimed))return json({error:"This message is already being sent or has already been handled"},409);

  // If fetch times out, leave the lease to expire automatically. This blocks competing sends
  // for five minutes because Meta may have accepted the message even if the response was lost.
  let response:Response;
  try{
   const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),10000);
   try{
    response=await fetch("https://graph.facebook.com/"+connection.api_version+"/"+connection.phone_number_id+"/messages",{
     method:"POST",headers:{Authorization:"Bearer "+connection.access_token,"Content-Type":"application/json"},
     body:JSON.stringify({messaging_product:"whatsapp",to:phone,type:"text",text:{preview_url:false,body:n.message_body??"Please contact your gym regarding your membership."}}),
     signal:controller.signal
    });
   }finally{clearTimeout(timer)}
  }catch(fetchError){
   const errorMessage="Message delivery timed out or the network closed before Meta returned a result. Delivery is unconfirmed; this attempt was not automatically retried to avoid a duplicate. Check WhatsApp Manager before sending again.";
   const{error:finishError}=await db.rpc("finish_whatsapp_notification_internal",{
    p_notification_id:notificationId,p_provider_message_id:null,p_success:false,
    p_error_message:errorMessage,p_previous_retry_count:2
   });
   if(finishError){
    await db.from("notifications").update({status:"failed",delivery_status:"failed",error_message:errorMessage,retry_count:3}).eq("id",notificationId);
    await db.from("notification_logs").insert({notification_id:notificationId,status:"failed",delivery_status:"failed",error_message:errorMessage});
    await db.rpc("release_whatsapp_notification_internal",{p_notification_id:notificationId});
   }
   console.error("WhatsApp request timed out or lost connection; automatic retry disabled",notificationId,fetchError);
   return json({error:errorMessage,delivery_status:"unconfirmed"},504);
  }
  const result=await response.json(),providerId=result?.messages?.[0]?.id??null;
  const errorMessage=response.ok?null:JSON.stringify(result);
  const{error:finishError}=await db.rpc("finish_whatsapp_notification_internal",{
   p_notification_id:notificationId,p_provider_message_id:providerId,p_success:response.ok,
   p_error_message:errorMessage,p_previous_retry_count:Number(n.retry_count??0)
  });
  if(finishError)return json({error:"Provider responded, but delivery could not be finalized atomically. The send lease will expire automatically."},500);
  if(!response.ok)return json({error:"WhatsApp provider rejected the message",provider:result},502);
  return json({ok:true,provider_message_id:providerId});
 }catch(error){
  console.error("send-whatsapp failed",error);
  return json({error:"Unexpected error. If the provider accepted the message, wait before retrying."},500);
 }
});
