import { createClient } from "npm:@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS","Content-Type":"application/json"};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:cors});
Deno.serve(async(req)=>{if(req.method==="OPTIONS")return new Response("ok",{headers:cors});try{
const token=req.headers.get("Authorization")?.replace(/^Bearer\s+/i,"");if(!token)return json({error:"Authentication required"},401);
const pk=JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")??"{}"),sk=JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")??"{}"),url=Deno.env.get("SUPABASE_URL"),pub=pk.default,secret=sk.default;
if(!url||!pub||!secret)return json({error:"Function configuration is incomplete"},500);
const callerAuth=createClient(url,pub),ad=createClient(url,secret);const au=await callerAuth.auth.getUser(token);if(au.error||!au.data.user)return json({error:"Invalid session"},401);
const b=await req.json(),gymId=String(b.gymId??""),email=String(b.email??"").trim(),name=String(b.name??"").trim(),phone=String(b.phone??"").trim(),role=b.role==="staff"?"staff":"coach";
const{data:caller}=await ad.from("users").select("id,gym_id,role,status").eq("id",au.data.user.id).eq("gym_id",gymId).maybeSingle();
if(!caller||caller.status!=="active")return json({error:"Unauthorized"},403);
const{data:p}=await ad.from("user_permissions").select("allowed").eq("user_id",caller.id).eq("permission","staff.manage").maybeSingle();
if(caller.role!=="admin"&&!p?.allowed)return json({error:"Unauthorized"},403);
const inv=await ad.auth.admin.inviteUserByEmail(email,{data:{full_name:name,gym_id:gymId,role},redirectTo:String(b.redirectTo??"")||undefined});
if(inv.error||!inv.data.user)return json({error:inv.error?.message??"Invite failed"},400);
const ins=await ad.from("users").insert({id:inv.data.user.id,gym_id:gymId,name,email,phone:phone||null,role,status:"active"});
if(ins.error){await ad.auth.admin.deleteUser(inv.data.user.id);return json({error:ins.error.message},400)}
return json({ok:true,user_id:inv.data.user.id});
}catch(e){return json({error:e instanceof Error?e.message:"Unexpected error"},500)}});