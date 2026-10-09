import { createClient } from "npm:@supabase/supabase-js@2";

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"content-type, x-worker-secret","Access-Control-Allow-Methods":"POST, OPTIONS","Content-Type":"application/json"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:cors});
const value=(key:string,n:any)=>({
  member_name:n.members?.name,
  member_id:n.members?.member_id,
  gym_name:n.gyms?.name,
  package_name:n.memberships?.membership_packages?.name,
  start_date:n.memberships?.start_date,
  expiry_date:n.memberships?.end_date,
  gym_phone:n.gyms?.phone,
  gym_whatsapp:n.gyms?.whatsapp
} as Record<string,unknown>)[key]??"";
const scalarBool=(v:any)=>Array.isArray(v)?v[0]===true:v===true;

Deno.serve(async req=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({error:"Method not allowed"},405);
 try{
  const sk=JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")??"{}");
  const url=Deno.env.get("SUPABASE_URL"),service=sk.default;
  if(!url||!service)return json({error:"WhatsApp worker is not configured"},500);
  const db=createClient(url,service);
  const{data:workerSecret,error:secretError}=await db.rpc("get_whatsapp_worker_secret_internal");
  const expected=Array.isArray(workerSecret)?workerSecret[0]:workerSecret;
  if(secretError||!expected||req.headers.get("x-worker-secret")!==expected)return json({error:"Unauthorized"},401);

  const{data:rows,error:queueError}=await db.from("notifications")
   .select("id,message_body,retry_count,notification_type,gym_id,members(name,member_id,phone),gyms(name,phone,whatsapp),memberships(start_date,end_date,membership_packages(name))")
   .eq("channel","whatsapp").in("status",["queued","failed"]).lt("retry_count",3)
   .order("scheduled_at").limit(8);
  if(queueError)return json({error:"Unable to load WhatsApp queue"},500);

  let sent=0,failed=0,skipped=0;
  for(const n of rows??[]){
   const phone=String(n.members?.phone??"").replace(/\D/g,"");
   if(!phone){
    await db.from("notifications").update({status:"failed",delivery_status:"failed",error_message:"No usable member phone number is saved.",retry_count:3}).eq("id",n.id);
    failed++;continue;
   }

   const{data:cx,error:connectionError}=await db.rpc("get_whatsapp_credentials_internal",{p_gym_id:n.gym_id});
   const connection=Array.isArray(cx)?cx[0]:cx;
   if(connectionError||!connection?.enabled||connection.last_test_ok!==true){skipped++;continue;}

   const{data:claimed,error:claimError}=await db.rpc("claim_whatsapp_notification_internal",{p_notification_id:n.id});
   if(claimError||!scalarBool(claimed)){skipped++;continue;}

   try{
    const{data:t,error:templateError}=await db.from("notification_templates")
     .select("provider_template_name,provider_template_language,provider_template_variables")
     .eq("gym_id",n.gym_id).eq("notification_type",n.notification_type).eq("channel","whatsapp").eq("enabled",true).maybeSingle();
    if(templateError)throw new Error("Unable to load WhatsApp template");

    let message:any={messaging_product:"whatsapp",to:phone};
    if(t?.provider_template_name){
     message.type="template";
     message.template={name:t.provider_template_name,language:{code:t.provider_template_language||"en_US"}};
     const variables=t.provider_template_variables??[];
     if(variables.length)message.template.components=[{type:"body",parameters:variables.map((key:string)=>({type:"text",text:String(value(key,n))}))}];
    }else{
     message.type="text";
     message.text={preview_url:false,body:n.message_body??"Your gym membership needs attention."};
    }

    let response:Response;
    try{
     const controller=new AbortController();
     const timer=setTimeout(()=>controller.abort(),10000);
     try{
      response=await fetch("https://graph.facebook.com/"+connection.api_version+"/"+connection.phone_number_id+"/messages",{
       method:"POST",
       headers:{Authorization:"Bearer "+connection.access_token,"Content-Type":"application/json"},
       body:JSON.stringify(message),
       signal:controller.signal
      });
     }finally{clearTimeout(timer)}
    }catch(fetchError){
     const errorMessage="Message delivery timed out or the network closed before Meta returned a result. Delivery is unconfirmed; this attempt was not automatically retried to avoid a duplicate. Check WhatsApp Manager before sending again.";
     const{error:finishError}=await db.rpc("finish_whatsapp_notification_internal",{
      p_notification_id:n.id,p_provider_message_id:null,p_success:false,
      p_error_message:errorMessage,p_previous_retry_count:2
     });
     if(finishError){
      await db.from("notifications").update({status:"failed",delivery_status:"failed",error_message:errorMessage,retry_count:3}).eq("id",n.id);
      await db.from("notification_logs").insert({notification_id:n.id,status:"failed",delivery_status:"failed",error_message:errorMessage});
      await db.rpc("release_whatsapp_notification_internal",{p_notification_id:n.id});
     }
     console.error("WhatsApp request timed out or lost connection; automatic retry disabled",n.id,fetchError);
     failed++;
     continue;
    }
    const result=await response.json(),providerId=result?.messages?.[0]?.id??null;
    const state=response.ok?"sent":"failed";
    const errorMessage=response.ok?null:JSON.stringify(result);
    const{error:finishError}=await db.rpc("finish_whatsapp_notification_internal",{
     p_notification_id:n.id,p_provider_message_id:providerId,p_success:response.ok,
     p_error_message:errorMessage,p_previous_retry_count:n.retry_count??0
    });
    if(finishError)throw new Error("Provider responded, but delivery could not be finalized atomically; the lease will expire automatically.");
    if(response.ok)sent++;else failed++;
   }catch(error){
    // Keep the five-minute lease after unexpected failures. It will expire automatically
    // so another worker can recover, without racing this attempt.
    console.error("WhatsApp notification processing failed",n.id,error);
    failed++;
   }
  }
  return json({ok:true,processed:sent+failed,sent,failed,skipped});
 }catch(error){
  console.error("WhatsApp worker failed",error);
  return json({error:"Unexpected worker error"},500);
 }
});
