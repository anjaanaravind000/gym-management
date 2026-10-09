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
export async function saveGym(gymId:string,patch:Partial<Gym>){return unwrap(await requireClient().rpc('save_gym_profile',{p_gym_id:gymId,p_name:patch.name??'',p_address:patch.address??null,p_phone:patch.phone??null,p_whatsapp:patch.whatsapp??null,p_email:patch.email??null,p_gst_number:patch.gst_number??null,p_currency:patch.currency??'INR',p_timezone:patch.timezone??'Asia/Kolkata',p_opening_time:patch.opening_time??null,p_closing_time:patch.closing_time??null,p_weekly_holidays:patch.weekly_holidays??[],p_member_id_prefix:patch.member_id_prefix??'GYM',p_renewal_grace_days:patch.renewal_grace_days??7})) as Gym}
export async function saveGymSettings(gymId:string,patch:Partial<GymSettings>){return unwrap(await requireClient().rpc('save_gym_settings',{p_gym_id:gymId,p_expiry_reminder_10_days:patch.expiry_reminder_10_days??false,p_expiry_reminder_5_days:patch.expiry_reminder_5_days??false,p_expiry_reminder_today:patch.expiry_reminder_today??false,p_payment_reminders:patch.payment_reminders??false,p_admin_alerts:patch.admin_alerts??false,p_whatsapp_enabled:patch.whatsapp_enabled??false,p_email_enabled:patch.email_enabled??false,p_push_enabled:patch.push_enabled??false})) as GymSettings}
export async function savePaymentMethod(gymId:string,method:string,enabled:boolean){return unwrap(await requireClient().rpc('save_payment_method_setting',{p_gym_id:gymId,p_payment_method:method,p_enabled:enabled})) as unknown}
export async function loadPackages(gymId:string,includeInactive=true){let q=requireClient().from('membership_packages').select('*').eq('gym_id',gymId).order('display_order').order('name');if(!includeInactive)q=q.eq('status','active');return unwrap(await q) as Package[]}
export async function savePackage(a:{gymId:string;packageId?:string|null;name:string;durationMonths:number;durationUnit?:string;price:number;description?:string|null;status?:string;displayOrder?:number}){return unwrap(await requireClient().rpc('save_package',{p_gym_id:a.gymId,p_package_id:a.packageId??null,p_name:a.name,p_duration_months:a.durationMonths,p_duration_unit:a.durationUnit??'month',p_price:a.price,p_description:a.description??null,p_status:a.status??'active',p_display_order:a.displayOrder??0})) as string}
export async function loadMembers(a:{gymId:string;page:number;pageSize:number;q?:string;status?:string;paymentStatus?:string}){let q=requireClient().from('member_report').select('*',{count:'exact'}).eq('gym_id',a.gymId);if(a.q?.trim()){const term=a.q.trim(),phoneTerm=term.replace(/[^0-9]/g,'');const ors=[`name.ilike.%${term}%`,`member_id.ilike.%${term}%`];if(phoneTerm)ors.push(`phone.ilike.%${phoneTerm}%`);q=q.or(ors.join(','))}if(a.status&&a.status!=='all'){if(a.status==='inactive')q=q.eq('member_status','inactive');else q=q.eq('membership_status',a.status).eq('member_status','active')}else q=q.eq('member_status','active');if(a.paymentStatus&&a.paymentStatus!=='all')q=q.eq('payment_status',a.paymentStatus);const{data,error,count}=await q.order('join_date',{ascending:false}).range(a.page*a.pageSize,a.page*a.pageSize+a.pageSize-1);if(error)throw error;return{rows:(data??[])as Member[],count:count??0}}
export async function findMemberByPhone(gymId:string,phone:string){const normalized=phone.replace(/[^0-9]/g,'');if(!normalized)return [];return unwrap(await requireClient().from('members').select('id,member_id,name,phone').eq('gym_id',gymId).eq('phone',normalized).limit(10)) as any[]}
export async function createMember(a:any){
 const client=requireClient();
 const args={p_gym_id:a.gymId,p_name:a.name,p_phone:a.phone,p_email:a.email??null,p_dob:a.dob??null,p_gender:a.gender??null,p_address:a.address??null,p_emergency_contact:a.emergencyContact??null,p_emergency_phone:a.emergencyPhone??null,p_member_id:a.memberId??null,p_package_id:a.packageId??null,p_duration_months:a.durationMonths??null,p_join_date:a.joinDate,p_start_date:a.startDate,p_price:a.price??null,p_discount:a.discount,p_amount_paid:a.amountPaid,p_payment_method:a.paymentMethod,p_transaction_reference:a.transactionReference??null,p_payment_notes:a.paymentNotes??null,p_assigned_coach_id:a.assignedCoachId??null,p_allow_duplicate_phone:a.allowDuplicatePhone??false};
 if(a.leadId)return unwrap(await client.rpc('create_member_from_lead',{...args,p_lead_id:a.leadId})) as string;
 return unwrap(await client.rpc('create_member_registration_v2',{...args,p_manual_end_date:a.manualEndDate??null})) as string
}
export async function createOldMember(a:{
 gymId:string;name:string;phone:string;memberId?:string|null;email?:string|null;dob?:string|null;gender?:string|null;address?:string|null;
 emergencyContact?:string|null;emergencyPhone?:string|null;joinDate?:string;status?:string;assignedCoachId?:string|null;allowDuplicatePhone?:boolean;
 addMembership?:boolean;packageId?:string|null;membershipStartDate?:string|null;membershipEndDate?:string|null;membershipStatus?:string;
 price?:number|null;durationMonths?:number|null;discount?:number;amountPaid?:number;paymentMethod?:string;paymentDate?:string|null;
 transactionReference?:string|null;paymentNotes?:string|null
}){
 return unwrap(await requireClient().rpc('create_old_member',{
  p_gym_id:a.gymId,p_name:a.name,p_phone:a.phone,p_email:a.email??null,p_dob:a.dob??null,p_gender:a.gender??null,p_address:a.address??null,
  p_emergency_contact:a.emergencyContact??null,p_emergency_phone:a.emergencyPhone??null,p_member_id:a.memberId??null,p_join_date:a.joinDate??localToday(),
  p_status:a.status??'active',p_assigned_coach_id:a.assignedCoachId??null,p_allow_duplicate_phone:a.allowDuplicatePhone??false,
  p_add_membership:a.addMembership??false,p_package_id:a.packageId??null,p_membership_start_date:a.membershipStartDate??null,
  p_membership_end_date:a.membershipEndDate??null,p_membership_status:a.membershipStatus??'active',p_price:a.price??null,
  p_duration_months:a.durationMonths??null,p_discount:a.discount??0,p_amount_paid:a.amountPaid??0,p_payment_method:(a.paymentMethod??'cash') as any,
  p_payment_date:a.paymentDate??null,p_transaction_reference:a.transactionReference??null,p_payment_notes:a.paymentNotes??null
 })) as string
}
export async function updateMember(gymId:string,memberId:string,patch:Record<string,unknown>){
 return unwrap(await requireClient().rpc('update_member_profile',{
   p_gym_id:gymId,p_member_id:memberId,p_name:patch.name,p_phone:patch.phone,p_email:patch.email??null,
   p_dob:patch.dob??null,p_gender:patch.gender??null,p_address:patch.address??null,
   p_emergency_contact:patch.emergency_contact??null,p_emergency_phone:patch.emergency_phone??null,
   p_assigned_coach_id:patch.assigned_coach_id??null
 })) as any
}
export async function deleteMember(gymId:string,memberId:string){return unwrap(await requireClient().rpc('delete_member',{p_gym_id:gymId,p_member_id:memberId})) as string}
export async function setMemberStatus(gymId:string,memberId:string,status:'active'|'inactive'|'cancelled'){return unwrap(await requireClient().rpc('set_member_status',{p_gym_id:gymId,p_member_id:memberId,p_status:status})) as unknown}
export async function loadMemberDetail(gymId:string,memberUuid:string){const db=requireClient();const member=unwrap(await db.from('member_report').select('*').eq('gym_id',gymId).eq('id',memberUuid).single()) as Member;const[memberships,payments,attendance,notifications,audit]=await Promise.all([db.from('memberships').select('*,membership_packages(name)').eq('gym_id',gymId).eq('member_id',memberUuid).order('start_date',{ascending:false}),db.from('revenue_report').select('*').eq('gym_id',gymId).eq('member_id',memberUuid).order('payment_date',{ascending:false}),db.from('attendance_report').select('*').eq('gym_id',gymId).eq('member_id',member.member_id).order('check_in',{ascending:false}).limit(50),db.from('notifications').select('*').eq('gym_id',gymId).eq('member_id',memberUuid).order('created_at',{ascending:false}).limit(50),db.from('audit_logs').select('*').eq('gym_id',gymId).eq('entity_id',memberUuid).order('created_at',{ascending:false}).limit(50)]);for(const r of[memberships,payments,attendance,notifications,audit])if(r.error)throw r.error;return{member,memberships:memberships.data??[],payments:payments.data??[],attendance:attendance.data??[],notifications:notifications.data??[],audit:audit.data??[]}}
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
function reportQuery(name:ReportName,a:{gymId:string;q?:string;from?:string;to?:string;status?:string}){let q=requireClient().from(reportMap[name]).select('*').eq('gym_id',a.gymId);const dc=name==='payments'||name==='revenue'?'payment_date':name==='attendance'?'check_in':name==='renewals'?'renewal_date':name==='did_not_renew'?'expiry_date':name==='outstanding'?'due_date':name==='expiring'||name==='expired'?'end_date':'join_date';if(a.from&&!['outstanding'].includes(name))q=q.gte(dc,a.from);if(a.to&&!['outstanding'].includes(name))q=q.lte(dc,a.to);if(a.status&&a.status!=='all'&&name==='members')q=q.eq('membership_status',a.status);if(a.q?.trim()){const f=name==='attendance'||name==='renewals'||name==='payments'||name==='revenue'?'member_name':name==='outstanding'?'name':'name';q=q.ilike(f,`%${a.q.trim()}%`)}if(name==='new_joiners')q=q.eq('membership_type','new');return q}
export async function loadReport(name:ReportName,a:{gymId:string;page:number;pageSize:number;q?:string;from?:string;to?:string;status?:string}){let q=reportQuery(name,a);const order=name==='renewals'?'renewal_date':name==='attendance'?'check_in':name==='payments'||name==='revenue'?'payment_date':name==='did_not_renew'?'expiry_date':name==='outstanding'?'due_date':name==='expiring'||name==='expired'?'end_date':'join_date';q=q.order(order,{ascending:false});const{data,error,count}=await q.range(a.page*a.pageSize,a.page*a.pageSize+a.pageSize-1);if(error)throw error;return{rows:data??[],count:count??0}}
export async function exportReport(name:ReportName,a:{gymId:string;q?:string;from?:string;to?:string;status?:string}){let offset=0;const all:any[]=[];while(true){const{data,error}=await reportQuery(name,a).range(offset,offset+999);if(error)throw error;if(!data?.length)break;all.push(...data);if(data.length<1000)break;offset+=1000}return all}

export async function loadExpenses(a:{gymId:string;page:number;pageSize:number;from?:string;to?:string;q?:string;status?:string}){
 let q=requireClient().from('expenses').select('*',{count:'exact'}).eq('gym_id',a.gymId);
 if(a.from)q=q.gte('expense_date',a.from);if(a.to)q=q.lte('expense_date',a.to);
 if(a.status&&a.status!=='all')q=q.eq('status',a.status);
 if(a.q?.trim())q=q.or(`category.ilike.%${a.q.trim()}%,description.ilike.%${a.q.trim()}%,vendor.ilike.%${a.q.trim()}%,reference.ilike.%${a.q.trim()}%`);
 const{data,error,count}=await q.order('expense_date',{ascending:false}).order('created_at',{ascending:false}).range(a.page*a.pageSize,a.page*a.pageSize+a.pageSize-1);
 if(error)throw error;return{rows:data??[],count:count??0};
}
export async function saveExpense(a:any){return unwrap(await requireClient().rpc('save_expense',{p_gym_id:a.gymId,p_expense_id:a.id??null,p_expense_date:a.expenseDate,p_category:a.category,p_description:a.description,p_amount:a.amount,p_payment_method:a.paymentMethod,p_vendor:a.vendor??null,p_reference:a.reference??null,p_notes:a.notes??null})) as string}
export async function voidExpense(gymId:string,expenseId:string,reason:string){return unwrap(await requireClient().rpc('void_expense',{p_gym_id:gymId,p_expense_id:expenseId,p_reason:reason})) as unknown}
export async function loadFinanceSummary(gymId:string,from:string,to:string){return unwrap(await requireClient().rpc('get_finance_summary',{p_gym_id:gymId,p_from:from,p_to:to})) as any}
export async function loadLeads(gymId:string,a:{status?:string;q?:string}={}){
 let q=requireClient().from('leads').select('*,membership_packages(name),users!leads_assigned_to_fkey(name)').eq('gym_id',gymId);
 if(a.status&&a.status!=='all')q=q.eq('status',a.status);
 if(a.q?.trim())q=q.or(`name.ilike.%${a.q.trim()}%,phone.ilike.%${a.q.trim()}%`);
 const{data,error}=await q.order('follow_up_date',{ascending:true,nullsFirst:false}).order('updated_at',{ascending:false});
 if(error)throw error;return(data??[]).map((x:any)=>({...x,package_name:x.membership_packages?.name??null,assigned_name:x.users?.name??null}));
}
export async function saveLead(a:any){return unwrap(await requireClient().rpc('save_lead',{p_gym_id:a.gymId,p_lead_id:a.id??null,p_name:a.name,p_phone:a.phone??null,p_email:a.email??null,p_source:a.source,p_status:a.status,p_interested_package_id:a.packageId??null,p_assigned_to:a.assignedTo??null,p_follow_up_date:a.followUpDate??null,p_notes:a.notes??null,p_lost_reason:a.lostReason??null})) as string}
export async function deleteLead(gymId:string,leadId:string){return unwrap(await requireClient().rpc('delete_lead',{p_gym_id:gymId,p_lead_id:leadId})) as unknown}

export async function convertLead(gymId:string,leadId:string,memberId:string){return unwrap(await requireClient().rpc('convert_lead',{p_gym_id:gymId,p_lead_id:leadId,p_member_id:memberId})) as unknown}
export type GymClass={id:string;gym_id:string;name:string;description:string|null;duration_minutes:number;capacity:number;status:string;created_by:string|null};
export type ClassSession={id:string;gym_id:string;class_id:string;class_name:string;class_description:string|null;duration_minutes:number;capacity:number;instructor_id:string;instructor_name:string;start_at:string;end_at:string;status:string;cancellation_reason:string|null;booked_count:number;waitlist_count:number};
export type ClassBooking={id:string;gym_id:string;member_id:string;session_id:string;status:string;waitlist_position:number|null;booked_at:string;cancelled_at:string|null;start_at:string;end_at:string;session_status:string;class_name:string;instructor_name:string;capacity:number};

export async function loadClasses(gymId:string,includeInactive=true){
 let q=requireClient().from('gym_classes').select('*').eq('gym_id',gymId).order('status').order('name');
 if(!includeInactive)q=q.eq('status','active');
 return unwrap(await q) as GymClass[];
}
export async function saveClass(a:{gymId:string;id?:string|null;name:string;description?:string|null;durationMinutes:number;capacity:number;status?:string}){return unwrap(await requireClient().rpc('save_class',{
 p_gym_id:a.gymId,p_class_id:a.id??null,p_name:a.name,p_description:a.description??null,p_duration_minutes:a.durationMinutes,p_capacity:a.capacity,p_status:a.status??'active'
})) as string}
export async function loadClassTimetable(gymId:string,fromLocal:string,toLocal:string,instructorId?:string,classId?:string){
 return unwrap(await requireClient().rpc('get_class_timetable',{
  p_gym_id:gymId,p_from_local:fromLocal,p_to_local:toLocal,
  p_instructor_id:instructorId&&instructorId!=='all'?instructorId:null,
  p_class_id:classId&&classId!=='all'?classId:null
 })) as ClassSession[];
}
export async function saveClassSession(a:{gymId:string;id?:string|null;classId:string;instructorId:string;startLocal:string;endLocal:string;capacity?:number|null;repeatWeeks?:number}){return unwrap(await requireClient().rpc('save_class_session',{
 p_gym_id:a.gymId,p_session_id:a.id??null,p_class_id:a.classId,p_instructor_id:a.instructorId,p_start_local:a.startLocal,p_end_local:a.endLocal,p_capacity:a.capacity??null,p_repeat_weeks:a.repeatWeeks??1
})) as string[]}
export async function cancelClassSession(gymId:string,sessionId:string,reason:string){return unwrap(await requireClient().rpc('cancel_class_session',{p_gym_id:gymId,p_session_id:sessionId,p_reason:reason})) as unknown}
export async function bookClass(gymId:string,sessionId:string,memberId:string){return unwrap(await requireClient().rpc('book_class',{p_gym_id:gymId,p_session_id:sessionId,p_member_id:memberId})) as {status:string;waitlist_position:number|null}}
export async function cancelClassBooking(gymId:string,bookingId:string){return unwrap(await requireClient().rpc('cancel_class_booking',{p_gym_id:gymId,p_booking_id:bookingId})) as {cancelled:boolean;promoted:boolean}}
export async function setClassBookingAttendance(gymId:string,bookingId:string,status:'attended'|'no_show'){return unwrap(await requireClient().rpc('set_class_booking_attendance',{p_gym_id:gymId,p_booking_id:bookingId,p_status:status})) as unknown}
export async function loadMemberClassBookings(gymId:string,memberId:string,from?:string){
 let q=requireClient().from('member_class_bookings_report').select('*').eq('gym_id',gymId).eq('member_id',memberId).order('start_at');
 if(from)q=q.gte('start_at',from);
 return unwrap(await q) as ClassBooking[];
}
export async function loadClassRoster(gymId:string,sessionId:string){
 const q=await requireClient().from('class_bookings').select('id,member_id,status,waitlist_position,booked_at,cancelled_at,members!inner(name,member_id,phone)').eq('gym_id',gymId).eq('session_id',sessionId).order('status').order('waitlist_position',{ascending:true,nullsFirst:false}).order('booked_at');
 return unwrap(q) as any[];
}

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
export async function saveTemplate(id:string,patch:Partial<Template>&{gym_id?:string}){return unwrap(await requireClient().rpc('save_notification_template',{p_gym_id:patch.gym_id??'',p_template_id:id,p_body:patch.body??'',p_enabled:patch.enabled??false,p_subject:patch.subject??null,p_provider_template_name:patch.provider_template_name??null,p_provider_template_language:patch.provider_template_language??'en_US',p_provider_template_variables:patch.provider_template_variables??[]})) as Template}
export async function uploadMemberPhoto(gymId:string,memberId:string,file:File){
 const db=requireClient();const ext=file.name.split('.').pop()?.toLowerCase()||'jpg';const path=`${gymId}/${memberId}/${crypto.randomUUID()}.${ext}`;
 const up=await db.storage.from('member-photos').upload(path,file,{contentType:file.type,upsert:false});
 if(up.error)throw up.error;
 try{await db.rpc('set_member_photo',{p_gym_id:gymId,p_member_id:memberId,p_photo_path:path});return path}
 catch(e){await db.storage.from('member-photos').remove([path]);throw e}
}
export async function signedMemberPhoto(path:string){return unwrap(await requireClient().storage.from('member-photos').createSignedUrl(path,1800)) as {signedUrl:string}}
export function localToday(){const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`}
export function localDateOffset(value:string|Date,days:number){
 const d=typeof value==='string'?new Date(value+'T12:00:00'):new Date(value.getTime());
 d.setHours(12,0,0,0);d.setDate(d.getDate()+days);
 return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`
}
export function membershipEndByUnit(start:string,duration:number,unit='month'){
 if(!start||!Number.isInteger(duration)||duration<=0)return '';
 const d=new Date(start+'T12:00:00');
 if((unit||'month').toLowerCase()==='day'){d.setDate(d.getDate()+duration-1);return localDateOffset(d,0)}
 const originalDay=d.getDate(),targetMonth=d.getMonth()+duration,targetYear=d.getFullYear()+Math.floor(targetMonth/12),targetMonthIndex=((targetMonth%12)+12)%12;
 const targetStart=new Date(targetYear,targetMonthIndex,1,12);
 const candidate=new Date(targetStart);candidate.setDate(originalDay);
 if(candidate.getMonth()!==targetMonthIndex)return localDateOffset(new Date(targetYear,targetMonthIndex+1,0,12),0);
 candidate.setDate(candidate.getDate()-1);
 return localDateOffset(candidate,0);
}
export function money(value:number,currency='INR'){return new Intl.NumberFormat('en-IN',{style:'currency',currency,maximumFractionDigits:0}).format(Number(value||0))}
export function date(value:string|null){return value?new Intl.DateTimeFormat('en-IN',{day:'2-digit',month:'short',year:'numeric'}).format(new Date(value+'T00:00:00')):'—'}
export function dateTime(value:string|null){return value?new Intl.DateTimeFormat('en-IN',{day:'2-digit',month:'short',hour:'numeric',minute:'2-digit'}).format(new Date(value)):'—'}

export async function inviteStaff(args:{gymId:string;email?:string;name:string;phone?:string;role:'coach'|'staff';username:string;password:string}){
 return unwrap(await requireClient().rpc('create_staff_account',{
   p_gym_id:args.gymId,p_name:args.name,p_username:args.username,p_password:args.password,
   p_email:args.email??null,p_phone:args.phone??null,p_role:args.role
 })) as string;
}
export async function exportGymBackup(gymId:string){return unwrap(await requireClient().rpc('export_gym_backup',{p_gym_id:gymId})) as Record<string,any>}
export type WhatsAppConnection={connected:boolean;business_account_id:string|null;phone_number_id:string|null;api_version:string|null;enabled:boolean;last_tested_at:string|null;last_test_ok:boolean|null;last_error:string|null};
export async function loadWhatsappConnection(gymId:string){return unwrap(await requireClient().rpc('get_whatsapp_connection',{p_gym_id:gymId})) as unknown as WhatsAppConnection[]}
export async function saveWhatsappConnection(a:{gymId:string;businessAccountId?:string;phoneNumberId:string;accessToken:string;apiVersion:string;verifyToken?:string;metaAppSecret:string}){return unwrap(await requireClient().rpc('save_whatsapp_connection',{p_gym_id:a.gymId,p_business_account_id:a.businessAccountId??null,p_phone_number_id:a.phoneNumberId,p_access_token:a.accessToken,p_api_version:a.apiVersion,p_verify_token:a.verifyToken??null,p_meta_app_secret:a.metaAppSecret})) as unknown}
export async function disconnectWhatsapp(gymId:string){return unwrap(await requireClient().rpc('disconnect_whatsapp_connection',{p_gym_id:gymId})) as unknown}

export async function syncStatuses(){return unwrap(await requireClient().rpc('sync_membership_statuses')) as unknown}

export async function loadCoachPerformance(gymId:string){
  return unwrap(await requireClient().from('coach_performance_report').select('*').eq('gym_id',gymId).order('revenue_recorded',{ascending:false})) as any[];
}

export async function unfreezeMembership(gymId:string,membershipId:string){return unwrap(await requireClient().rpc('unfreeze_membership',{p_gym_id:gymId,p_membership_id:membershipId})) as unknown}
export async function reversePayment(gymId:string,paymentId:string,reason:string,notes?:string){return unwrap(await requireClient().rpc('reverse_payment',{p_gym_id:gymId,p_payment_id:paymentId,p_reason:reason,p_notes:notes??null})) as unknown}
