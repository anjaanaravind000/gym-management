import { supabase } from './supabase';

export type UserProfile = { id:string; gym_id:string; name:string; email:string|null; phone:string|null; role:string; status:string };
export type Member = {
  id:string; gym_id:string; member_id:string; name:string; phone:string; email:string|null; dob:string|null; gender:string|null;
  address:string|null; emergency_contact:string|null; emergency_phone:string|null; photo_url:string|null;
  member_status:string; assigned_coach_id:string|null; assigned_coach_name:string|null; join_date:string;
  membership_uuid:string|null; package_name:string|null; membership_type:string|null; start_date:string|null;
  end_date:string|null; duration_months:number|null; membership_status:string|null; days_remaining:number|null;
  price:number|null; discount:number|null; final_amount:number|null; paid_amount:number; balance_amount:number; payment_status:string;
};
export type Package = { id:string; gym_id:string; name:string; duration_months:number; duration_unit:string; price:number; description:string|null; status:string; display_order:number };
export type Payment = {
  payment_id:string; gym_id:string; payment_date:string; member_id:string; member_name:string; membership_type:string;
  package_name:string|null; payment_method:string; amount:number; refund_amount:number; net_amount:number;
  transaction_reference:string|null; status:string; recorded_by:string|null; notes:string|null;
};
export type Attendance = { id:string; gym_id:string; member_id:string; member_name:string; check_in:string; check_out:string|null; method:string };
export type Notification = {
  id:string; gym_id:string; member_id:string|null; membership_id:string|null; notification_type:string;
  channel:string; scheduled_at:string; sent_at:string|null; status:string; delivery_status:string;
  error_message:string|null; retry_count:number; message_body:string|null; read_at:string|null;
  member_name?:string|null; member_code?:string|null; member_phone?:string|null;
};
export type Staff = UserProfile;
export type Gym = {
  id:string; name:string; logo_url:string|null; address:string|null; phone:string|null; whatsapp:string|null; email:string|null;
  gst_number:string|null; currency:string; timezone:string; opening_time:string|null; closing_time:string|null;
  weekly_holidays:number[]; member_id_prefix:string; member_id_next:number; renewal_grace_days:number;
  whatsapp_enabled:boolean; email_enabled:boolean; push_enabled:boolean;
};
export type GymSettings = {
  expiry_reminder_10_days:boolean; expiry_reminder_5_days:boolean; expiry_reminder_today:boolean;
  payment_reminders:boolean; admin_alerts:boolean; whatsapp_enabled:boolean; email_enabled:boolean; push_enabled:boolean;
};
export type PaymentMethodSetting = { gym_id:string; payment_method:string; enabled:boolean };
export type Template = {
  id:string; gym_id:string; notification_type:string; channel:string; subject:string|null; body:string; enabled:boolean;
  provider_template_name:string|null; provider_template_language:string; provider_template_variables:string[];
};

function requireClient(){if(!supabase)throw new Error('Supabase is not configured.');return supabase}
export type AppSession={
  user_id:string;
  username:string;
  display_name:string;
  role:string;
  gym_id:string|null;
  expires_at:string;
  session_token?:string;
};

export async function loginWithPassword(username:string,password:string):Promise<AppSession>{
  const client=requireClient();
  const {data,error}=await client.rpc('login_with_password',{p_username:username,p_password:password});
  if(error)throw error;
  const row=Array.isArray(data)?data[0]:data;
  if(!row?.session_token)throw new Error('Invalid username or password');
  const {setAppSession}=await import('./supabase');
  setAppSession(row.session_token);
  return row as AppSession;
}

export async function getCurrentAppSession():Promise<AppSession|null>{
  const client=requireClient();
  const {data,error}=await client.rpc('get_current_app_session');
  if(error)throw error;
  const row=Array.isArray(data)?data[0]:data;
  return row?(row as AppSession):null;
}

export async function logoutAppSession(){
  try{await requireClient().rpc('logout_app')}
  finally{const {setAppSession}=await import('./supabase');setAppSession(null)}
}

function unwrap<T>(r:{data:T|null,error:any}):T{if(r.error)throw r.error;return r.data as T}

export async function loadProfile(userId:string){return unwrap(await requireClient().from('users').select('id,gym_id,name,email,phone,role,status').eq('id',userId).maybeSingle()) as UserProfile|null}
export async function bootstrapGym(name:string,email:string,phone:string,gymName:string){return unwrap(await requireClient().rpc('bootstrap_gym',{p_gym_name:gymName,p_user_name:name,p_email:email||null,p_phone:phone||null})) as string}
export async function loadGym(gymId:string){return unwrap(await requireClient().from('gyms').select('*').eq('id',gymId).single()) as Gym}
export async function loadGymSettings(gymId:string){return unwrap(await requireClient().from('gym_settings').select('*').eq('gym_id',gymId).single()) as GymSettings}
export async function loadPaymentMethodSettings(gymId:string){return unwrap(await requireClient().from('payment_method_settings').select('*').eq('gym_id',gymId).order('payment_method')) as PaymentMethodSetting[]}
export async function saveGym(gymId:string,patch:Partial<Gym>){return unwrap(await requireClient().from('gyms').update(patch).eq('id',gymId).select('*').single()) as Gym}
export async function saveGymSettings(gymId:string,patch:Partial<GymSettings>){return unwrap(await requireClient().from('gym_settings').update(patch).eq('gym_id',gymId).select('*').single()) as GymSettings}
export async function savePaymentMethod(gymId:string,method:string,enabled:boolean){return unwrap(await requireClient().from('payment_method_settings').upsert({gym_id:gymId,payment_method:method,enabled},{onConflict:'gym_id,payment_method'})) as unknown}
export async function loadPackages(gymId:string,includeInactive=true){let q=requireClient().from('membership_packages').select('*').eq('gym_id',gymId).order('display_order').order('name');if(!includeInactive)q=q.eq('status','active');return unwrap(await q) as Package[]}
export async function savePackage(a:{gymId:string;packageId?:string|null;name:string;durationMonths:number;durationUnit?:string;price:number;description?:string|null;status?:string;displayOrder?:number}){return unwrap(await requireClient().rpc('save_package',{p_gym_id:a.gymId,p_package_id:a.packageId??null,p_name:a.name,p_duration_months:a.durationMonths,p_duration_unit:a.durationUnit??'month',p_price:a.price,p_description:a.description??null,p_status:a.status??'active',p_display_order:a.displayOrder??0})) as string}
export async function loadMembers(a:{gymId:string;page:number;pageSize:number;q?:string;status?:string;paymentStatus?:string}){let q=requireClient().from('member_report').select('*',{count:'exact'}).eq('gym_id',a.gymId);if(a.q?.trim())q=q.or(`name.ilike.%${a.q.trim()}%,member_id.ilike.%${a.q.trim()}%,phone.ilike.%${a.q.trim()}%`);if(a.status&&a.status!=='all')q=q.eq('membership_status',a.status);if(a.paymentStatus&&a.paymentStatus!=='all')q=q.eq('payment_status',a.paymentStatus);const{data,error,count}=await q.order('join_date',{ascending:false}).range(a.page*a.pageSize,a.page*a.pageSize+a.pageSize-1);if(error)throw error;return{rows:(data??[])as Member[],count:count??0}}
export async function findMemberByPhone(gymId:string,phone:string){return unwrap(await requireClient().from('members').select('id,member_id,name,phone').eq('gym_id',gymId).eq('phone',phone).limit(10)) as any[]}
export async function createMember(a:any){return unwrap(await requireClient().rpc('create_member_registration_v2',{p_gym_id:a.gymId,p_name:a.name,p_phone:a.phone,p_email:a.email??null,p_dob:a.dob??null,p_gender:a.gender??null,p_address:a.address??null,p_emergency_contact:a.emergencyContact??null,p_emergency_phone:a.emergencyPhone??null,p_member_id:a.memberId??null,p_package_id:a.packageId??null,p_duration_months:a.durationMonths??null,p_join_date:a.joinDate,p_start_date:a.startDate,p_price:a.price??null,p_discount:a.discount,p_amount_paid:a.amountPaid,p_payment_method:a.paymentMethod,p_transaction_reference:a.transactionReference??null,p_payment_notes:a.paymentNotes??null,p_manual_end_date:a.manualEndDate??null,p_assigned_coach_id:a.assignedCoachId??null,p_allow_duplicate_phone:a.allowDuplicatePhone??false})) as string}
export async function updateMember(memberId:string,patch:Record<string,unknown>){return unwrap(await requireClient().from('members').update(patch).eq('id',memberId).select('*').single()) as any}
export async function setMemberStatus(gymId:string,memberId:string,status:'active'|'inactive'|'cancelled'){return unwrap(await requireClient().rpc('set_member_status',{p_gym_id:gymId,p_member_id:memberId,p_status:status})) as unknown}
export async function loadMemberDetail(gymId:string,memberUuid:string){const db=requireClient();const member=unwrap(await db.from('member_report').select('*').eq('gym_id',gymId).eq('id',memberUuid).single()) as Member;const[memberships,payments,attendance,notifications,audit]=await Promise.all([db.from('memberships').select('*,membership_packages(name)').eq('gym_id',gymId).eq('member_id',memberUuid).order('start_date',{ascending:false}),db.from('payments').select('*').eq('gym_id',gymId).eq('member_id',memberUuid).order('payment_date',{ascending:false}),db.from('attendance_report').select('*').eq('gym_id',gymId).eq('member_id',member.member_id).order('check_in',{ascending:false}).limit(50),db.from('notifications').select('*').eq('gym_id',gymId).eq('member_id',memberUuid).order('created_at',{ascending:false}).limit(50),db.from('audit_logs').select('*').eq('gym_id',gymId).eq('entity_id',memberUuid).order('created_at',{ascending:false}).limit(50)]);for(const r of[memberships,payments,attendance,notifications,audit])if(r.error)throw r.error;return{member,memberships:memberships.data??[],payments:payments.data??[],attendance:attendance.data??[],notifications:notifications.data??[],audit:audit.data??[]}}
export async function renewMembership(a:any){return unwrap(await requireClient().rpc('create_renewal',{p_gym_id:a.gymId,p_member_id:a.memberId,p_package_id:a.packageId??null,p_duration_months:a.durationMonths??null,p_start_date:a.startDate??null,p_price:a.price??null,p_discount:a.discount,p_amount_paid:a.amountPaid,p_payment_method:a.paymentMethod,p_transaction_reference:a.transactionReference??null,p_notes:a.notes??null,p_end_date:a.endDate??null})) as string}
export async function recordPayment(a:any){return unwrap(await requireClient().rpc('record_payment',{p_gym_id:a.gymId,p_member_id:a.memberId,p_membership_id:a.membershipId,p_amount:a.amount,p_payment_method:a.paymentMethod,p_transaction_reference:a.transactionReference??null,p_payment_date:a.paymentDate??new Date().toISOString(),p_notes:a.notes??null})) as string}
export async function refundPayment(a:any){return unwrap(await requireClient().rpc('refund_payment',{p_gym_id:a.gymId,p_payment_id:a.paymentId,p_amount:a.amount,p_reason:a.reason,p_notes:a.notes??null})) as string}
export async function freezeMembership(a:any){return unwrap(await requireClient().rpc('freeze_membership',{p_gym_id:a.gymId,p_membership_id:a.membershipId,p_start_date:a.startDate,p_end_date:a.endDate,p_reason:a.reason})) as string}
export async function cancelMembership(a:any){return unwrap(await requireClient().rpc('cancel_membership',{p_gym_id:a.gymId,p_membership_id:a.membershipId,p_cancellation_date:a.date,p_reason:a.reason,p_notes:a.notes??null})) as string}
export async function loadMemberships(gymId:string,page:number,pageSize:number,status?:string){let q=requireClient().from('memberships').select('*,members(member_id,name,phone),membership_packages(name)',{count:'exact'}).eq('gym_id',gymId);if(status&&status!=='all')q=q.eq('status',status);const{data,error,count}=await q.order('start_date',{ascending:false}).range(page*pageSize,page*pageSize+pageSize-1);if(error)throw error;return{rows:data??[],count:count??0}}
export async function loadPayments(gymId:string,page:number,pageSize:number,qText?:string){let q=requireClient().from('revenue_report').select('*',{count:'exact'}).eq('gym_id',gymId);if(qText?.trim())q=q.or(`member_name.ilike.%${qText.trim()}%,member_id.ilike.%${qText.trim()}%,transaction_reference.ilike.%${qText.trim()}%`);const{data,error,count}=await q.order('payment_date',{ascending:false}).range(page*pageSize,page*pageSize+pageSize-1);if(error)throw error;return{rows:(data??[])as Payment[],count:count??0}}
export async function loadAttendance(gymId:string,page:number,pageSize:number,qText?:string){let q=requireClient().from('attendance_report').select('*',{count:'exact'}).eq('gym_id',gymId);if(qText?.trim())q=q.or(`member_name.ilike.%${qText.trim()}%,member_id.ilike.%${qText.trim()}%`);const{data,error,count}=await q.order('check_in',{ascending:false}).range(page*pageSize,page*pageSize+pageSize-1);if(error)throw error;return{rows:(data??[])as Attendance[],count:count??0}}
export async function recordAttendance(gymId:string,memberId:string,method='manual'){return unwrap(await requireClient().rpc('record_attendance',{p_gym_id:gymId,p_member_id:memberId,p_method:method})) as string}
export async function checkoutAttendance(gymId:string,attendanceId:string){return unwrap(await requireClient().rpc('checkout_attendance',{p_gym_id:gymId,p_attendance_id:attendanceId})) as unknown}
export async function loadAnalytics(gymId:string,from:string,to:string){return unwrap(await requireClient().rpc('get_analytics',{p_gym_id:gymId,p_from:from,p_to:to})) as any}
export async function loadAttention(gymId:string){const db=requireClient();const[exp,out]=await Promise.all([db.from('expiring_members_report').select('*').eq('gym_id',gymId).order('end_date').limit(8),db.from('outstanding_payment_report').select('*').eq('gym_id',gymId).order('balance',{ascending:false}).limit(8)]);if(exp.error)throw exp.error;if(out.error)throw out.error;return{expiring:(exp.data??[])as Member[],outstanding:out.data??[]}}
export type ReportName='members'|'new_joiners'|'renewals'|'did_not_renew'|'expiring'|'expired'|'payments'|'outstanding'|'revenue'|'attendance';
const reportMap:Record<ReportName,string>={members:'member_report',new_joiners:'member_report',renewals:'renewal_report',did_not_renew:'did_not_renew_report',expiring:'expiring_members_report',expired:'expired_members_report',payments:'revenue_report',outstanding:'outstanding_payment_report',revenue:'revenue_report',attendance:'attendance_report'};
function reportQuery(name:ReportName,a:{gymId:string;q?:string;from?:string;to?:string;status?:string}){let q=requireClient().from(reportMap[name]).select('*').eq('gym_id',a.gymId);const dc=name==='payments'||name==='revenue'?'payment_date':name==='attendance'?'check_in':name==='renewals'?'renewal_date':'join_date';if(a.from&&['payments','revenue','attendance','members','new_joiners','renewals'].includes(name))q=q.gte(dc,a.from);if(a.to&&['payments','revenue','attendance','members','new_joiners','renewals'].includes(name))q=q.lte(dc,a.to);if(a.status&&name==='members')q=q.eq('membership_status',a.status);if(a.q?.trim()){const f=name==='attendance'||name==='renewals'||name==='payments'||name==='revenue'?'member_name':name==='outstanding'?'name':'name';q=q.ilike(f,`%${a.q.trim()}%`)}if(name==='new_joiners')q=q.eq('membership_type','new');return q}
export async function loadReport(name:ReportName,a:{gymId:string;page:number;pageSize:number;q?:string;from?:string;to?:string;status?:string}){let q=reportQuery(name,a);const order=name==='renewals'?'renewal_date':name==='attendance'?'check_in':name==='payments'||name==='revenue'?'payment_date':name==='expiring'||name==='expired'?'end_date':'join_date';q=q.order(order,{ascending:false});const{data,error,count}=await q.range(a.page*a.pageSize,a.page*a.pageSize+a.pageSize-1);if(error)throw error;return{rows:data??[],count:count??0}}
export async function exportReport(name:ReportName,a:{gymId:string;q?:string;from?:string;to?:string;status?:string}){let offset=0;const all:any[]=[];while(true){const{data,error}=await reportQuery(name,a).range(offset,offset+999);if(error)throw error;if(!data?.length)break;all.push(...data);if(data.length<1000)break;offset+=1000}return all}
export async function loadNotifications(gymId:string,page:number,pageSize:number){const{data,error,count}=await requireClient().from('notifications').select('*,members(name,member_id,phone)',{count:'exact'}).eq('gym_id',gymId).order('created_at',{ascending:false}).range(page*pageSize,page*pageSize+pageSize-1);if(error)throw error;return{rows:(data??[]).map((n:any)=>({...n,member_name:n.members?.name??null,member_code:n.members?.member_id??null,member_phone:n.members?.phone??null}))as Notification[],count:count??0}}
export async function loadNotificationLogs(gymId:string,page:number,pageSize:number){const{data,error,count}=await requireClient().from('notification_logs').select('*,notifications!inner(gym_id,notification_type,channel,member_id,members(name,member_id))',{count:'exact'}).eq('notifications.gym_id',gymId).order('attempt_at',{ascending:false}).range(page*pageSize,page*pageSize+pageSize-1);if(error)throw error;return{rows:data??[],count:count??0}}
export async function notificationCounts(gymId:string){return unwrap(await requireClient().rpc('get_notification_counts',{p_gym_id:gymId})) as {unread:number;queued:number;failed:number}}
export async function markNotificationRead(gymId:string,id:string){return unwrap(await requireClient().rpc('mark_notification_read',{p_gym_id:gymId,p_notification_id:id})) as unknown}
export async function cancelNotification(gymId:string,id:string){return unwrap(await requireClient().rpc('cancel_notification',{p_gym_id:gymId,p_notification_id:id})) as unknown}
export async function queueNotification(a:{gymId:string;memberId:string;membershipId?:string|null;channel:string;type?:string;body?:string|null}){return unwrap(await requireClient().rpc('queue_member_notification',{p_gym_id:a.gymId,p_member_id:a.memberId,p_membership_id:a.membershipId??null,p_channel:a.channel,p_notification_type:a.type??'manual_message',p_message_body:a.body??null})) as string}
export async function loadStaff(gymId:string){return unwrap(await requireClient().from('users').select('id,gym_id,name,email,phone,role,status,created_at').eq('gym_id',gymId).order('name')) as Staff[]}
export async function loadPermissions(){return unwrap(await requireClient().from('permissions').select('key,description').order('key')) as {key:string;description:string}[]}
export async function loadStaffPermissions(userId:string){return unwrap(await requireClient().from('user_permissions').select('permission,allowed').eq('user_id',userId)) as {permission:string;allowed:boolean}[]}
export async function setStaffRole(gymId:string,userId:string,role:string,status='active'){return unwrap(await requireClient().rpc('set_staff_role',{p_gym_id:gymId,p_user_id:userId,p_role:role,p_status:status})) as unknown}
export async function setStaffPermission(gymId:string,userId:string,permission:string,allowed:boolean){return unwrap(await requireClient().rpc('set_staff_permission',{p_gym_id:gymId,p_user_id:userId,p_permission:permission,p_allowed:allowed})) as unknown}
export async function loadTemplates(gymId:string){return unwrap(await requireClient().from('notification_templates').select('*').eq('gym_id',gymId).order('notification_type').order('channel')) as Template[]}
export async function saveTemplate(id:string,patch:Partial<Template>){return unwrap(await requireClient().from('notification_templates').update(patch).eq('id',id).select('*').single()) as Template}
export async function uploadMemberPhoto(gymId:string,memberId:string,file:File){const db=requireClient();const ext=file.name.split('.').pop()?.toLowerCase()||'jpg';const path=`${gymId}/${memberId}/${crypto.randomUUID()}.${ext}`;const up=await db.storage.from('member-photos').upload(path,file,{contentType:file.type,upsert:false});if(up.error)throw up.error;const update=await db.from('members').update({photo_url:path}).eq('id',memberId).eq('gym_id',gymId);if(update.error)throw update.error;return path}
export async function signedMemberPhoto(path:string){return unwrap(await requireClient().storage.from('member-photos').createSignedUrl(path,1800)) as {signedUrl:string}}
export function localToday(){const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`}
export function money(value:number,currency='INR'){return new Intl.NumberFormat('en-IN',{style:'currency',currency,maximumFractionDigits:0}).format(Number(value||0))}
export function date(value:string|null){return value?new Intl.DateTimeFormat('en-IN',{day:'2-digit',month:'short',year:'numeric'}).format(new Date(value+'T00:00:00')):'—'}
export function dateTime(value:string|null){return value?new Intl.DateTimeFormat('en-IN',{day:'2-digit',month:'short',hour:'numeric',minute:'2-digit'}).format(new Date(value)):'—'}

export async function inviteStaff(args:{gymId:string;email:string;name:string;phone?:string;role:'coach'|'staff';redirectTo:string}){
 const {data,error}=await requireClient().functions.invoke('invite-staff',{body:args});
 if(error)throw error;if(data?.error)throw new Error(data.error);return data;
}
export async function sendWhatsapp(notificationId:string){
 const {data,error}=await requireClient().functions.invoke('send-whatsapp',{body:{notification_id:notificationId}});
 if(error)throw error;if(data?.error)throw new Error(data.error);return data;
}
export async function syncStatuses(){return unwrap(await requireClient().rpc('sync_membership_statuses')) as unknown}

export async function loadCoachPerformance(gymId:string){
  return unwrap(await requireClient().from('coach_performance_report').select('*').eq('gym_id',gymId).order('revenue_recorded',{ascending:false})) as any[];
}

export async function unfreezeMembership(gymId:string,membershipId:string){return unwrap(await requireClient().rpc('unfreeze_membership',{p_gym_id:gymId,p_membership_id:membershipId})) as unknown}
export async function reversePayment(gymId:string,paymentId:string,reason:string,notes?:string){return unwrap(await requireClient().rpc('reverse_payment',{p_gym_id:gymId,p_payment_id:paymentId,p_reason:reason,p_notes:notes??null})) as unknown}
