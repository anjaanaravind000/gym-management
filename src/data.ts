import { supabase } from './supabase';

export type UserProfile = { id:string; gym_id:string; name:string; email:string|null; phone:string|null; role:string };
export type Member = { id:string; member_id:string; name:string; phone:string; status:string; package_name:string|null; end_date:string|null; paid_amount:number; balance_amount:number; payment_status:string };
export type Payment = { payment_id:string; payment_date:string; member_id:string; member_name:string; membership_type:string; package_name:string|null; payment_method:string; amount:number; transaction_reference:string|null; status:string };
export type Attendance = { id:string; member_id:string; check_in:string; check_out:string|null; method:string; member?:{name:string;member_id:string}|null };

export async function loadProfile(userId:string){
 if(!supabase) throw new Error('Supabase is not configured. Add VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY.');
 const {data,error}=await supabase.from('users').select('id,gym_id,name,email,phone,role').eq('id',userId).maybeSingle();
 if(error) throw error; return data as UserProfile|null;
}
export async function bootstrapGym(name:string,email:string,phone:string,gymName:string){
 if(!supabase) throw new Error('Supabase is not configured.');
 const {data,error}=await supabase.rpc('bootstrap_gym',{p_gym_name:gymName,p_user_name:name,p_email:email||null,p_phone:phone||null});
 if(error) throw error; return data as string;
}
export async function loadMembers(){if(!supabase)throw new Error('Supabase is not configured.');const {data,error}=await supabase.from('member_report').select('id,member_id,name,phone,status,package_name,end_date,paid_amount,balance_amount,payment_status').order('join_date',{ascending:false}).limit(500);if(error)throw error;return(data??[])as Member[]}
export async function loadPayments(){if(!supabase)throw new Error('Supabase is not configured.');const {data,error}=await supabase.from('revenue_report').select('payment_id,payment_date,member_id,member_name,membership_type,package_name,payment_method,amount,transaction_reference,status').order('payment_date',{ascending:false}).limit(500);if(error)throw error;return(data??[])as Payment[]}
export async function loadAttendance(){if(!supabase)throw new Error('Supabase is not configured.');const {data,error}=await supabase.from('attendance').select('id,member_id,check_in,check_out,method,members(name,member_id)').order('check_in',{ascending:false}).limit(500);if(error)throw error;return(data??[])as Attendance[]}
export async function loadDashboard(){const[members,payments,attendance]=await Promise.all([loadMembers(),loadPayments(),loadAttendance()]);const now=new Date(),monthStart=new Date(now.getFullYear(),now.getMonth(),1),revenue=payments.filter(p=>new Date(p.payment_date)>=monthStart&&p.status==='paid').reduce((s,p)=>s+Number(p.amount),0),outstanding=members.reduce((s,m)=>s+Number(m.balance_amount||0),0),active=members.filter(m=>m.status==='active').length,expiring=members.filter(m=>m.status==='expiring_soon').length,today=now.toISOString().slice(0,10),todayAttendance=attendance.filter(a=>a.check_in.slice(0,10)===today).length;return{members,payments,attendance,revenue,outstanding,active,expiring,todayAttendance}}
export function money(value:number){return new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR',maximumFractionDigits:0}).format(value)}
export function date(value:string|null){return value?new Intl.DateTimeFormat('en-IN',{day:'numeric',month:'short',year:'numeric'}).format(new Date(value+'T00:00:00')):'—'}
