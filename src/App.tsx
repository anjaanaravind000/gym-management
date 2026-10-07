import React,{useEffect,useState}from'react';
import{Activity,BarChart3,Bell,Check,CircleDollarSign,FileBarChart,Home,LogOut,MoreHorizontal,Package,Settings as SettingsIcon,ShieldCheck,UserPlus,Users,WalletCards}from'lucide-react';
import{supabase,supabaseConfig}from'./supabase';
import{getCurrentAppSession,loadProfile,logoutAppSession}from'./data';
import type{Member,Payment,UserProfile}from'./data';
import{Brand,humanError}from'./components/ui';
import{AuthScreen,SetupScreen}from'./components/auth';
import{Dashboard}from'./screens/dashboard';
import{Members,MemberForm,MemberProfile}from'./screens/members';
import{Attendance,Memberships,PaymentForm,Payments}from'./screens/operations';
import{Analytics,Reports}from'./screens/reports';
import{Finance}from'./screens/finance';
import{Leads}from'./screens/leads';
import{Notifications,Settings,Staff}from'./screens/admin';
import{Sheet}from'./components/ui';import{CancelForm,FreezeForm,MessageForm,RenewForm}from'./components/lifecycle';

export type Screen='dashboard'|'members'|'memberships'|'payments'|'finance'|'leads'|'attendance'|'analytics'|'reports'|'notifications'|'settings'|'staff';
const nav:{id:Screen;label:string;icon:React.ElementType}[]=[
 {id:'dashboard',label:'Dashboard',icon:Home},{id:'members',label:'Members',icon:Users},{id:'memberships',label:'Memberships',icon:Package},
 {id:'payments',label:'Payments',icon:WalletCards},{id:'finance',label:'Finance',icon:CircleDollarSign},{id:'leads',label:'Leads',icon:UserPlus},{id:'attendance',label:'Attendance',icon:Check},{id:'analytics',label:'Analytics',icon:BarChart3},
 {id:'reports',label:'Reports',icon:FileBarChart},{id:'notifications',label:'Notifications',icon:Bell},{id:'settings',label:'Settings',icon:SettingsIcon},{id:'staff',label:'Staff',icon:ShieldCheck}
];
export default function App(){
 const[session,setSession]=useState<any>(null),[profile,setProfile]=useState<UserProfile|null>(null),[loading,setLoading]=useState(true),[error,setError]=useState('');
 useEffect(()=>{if(!supabase){setLoading(false);return}let live=true;
  getCurrentAppSession().then(async s=>{if(!live)return;if(s){setSession(s);try{setProfile(await loadProfile(s.user_id))}catch(e:any){setError(humanError(e))}}setLoading(false)}).catch((e:any)=>{if(!live)return;setError(humanError(e));setLoading(false)});
  return()=>{live=false};
 },[]);
 async function signedIn(s:any){setSession(s);try{setProfile(await loadProfile(s.user_id))}catch(e:any){setError(humanError(e))}}
 async function signOut(){await logoutAppSession();setSession(null);setProfile(null)}
 if(!supabase)return <Config config={supabaseConfig}/>;
 if(loading)return <AuthWrap title="Loading your gym"><p>Checking secure session…</p></AuthWrap>;
 if(!session)return <AuthScreen onSignedIn={signedIn}/>;
 if(!profile)return <SetupScreen user={session} onDone={async()=>setProfile(await loadProfile(session.user_id))}/>;
 return <Shell profile={profile} error={error} setError={setError} onLogout={signOut}/>
}
function Shell({profile,error,setError,onLogout}:{profile:UserProfile;error:string;setError:(x:string)=>void;onLogout:()=>Promise<void>}){
 const[screen,setScreen]=useState<Screen>('dashboard'),[refresh,setRefresh]=useState(0),[modal,setModal]=useState<{type:string;member?:Member;payment?:Payment}|null>(null),[more,setMore]=useState(false);const bump=()=>setRefresh(x=>x+1);
 useEffect(()=>{const fn=(e:Event)=>{const ce=e as CustomEvent;setModal({type:e.type.replace('gym:',''),member:ce.detail})};const names=['gym:open','gym:renew','gym:payment','gym:freeze','gym:cancel','gym:message'];names.forEach(n=>window.addEventListener(n,fn));const refreshFn=()=>setRefresh(x=>x+1);window.addEventListener('gym:refresh',refreshFn);return()=>{names.forEach(n=>window.removeEventListener(n,fn));window.removeEventListener('gym:refresh',refreshFn)}},[]);
 const open=(type:string|{type:string;member?:Member;payment?:Payment},member?:Member,payment?:Payment)=>{if(typeof type==='object')setModal(type);else setModal({type,member,payment});};const close=()=>setModal(null);
 const toast=(s:string)=>{setError(s);setTimeout(()=>setError(''),2200)};
 return <div className="app-shell"><aside className="sidebar"><Brand/><nav>{nav.map(n=>{const I=n.icon;return <button key={n.id} className={screen===n.id?'nav-item active':'nav-item'} onClick={()=>setScreen(n.id)}><I size={19}/><span>{n.label}</span></button>})}</nav><div className="profile"><div className="avatar">{initials(profile.name)}</div><div><b>{profile.name}</b><span>{profile.role}</span></div><button className="icon-button mini" onClick={onLogout}><LogOut size={15}/></button></div></aside>
 <main className="main">{error&&<div className="toast inline-toast">{error}</div>}{screen==='dashboard'&&<Dashboard gymId={profile.gym_id} onNavigate={setScreen} onOpen={open} refresh={refresh}/>}
 {screen==='members'&&<Members gymId={profile.gym_id} refresh={refresh} onRefresh={bump} onOpen={open}/>}
 {screen==='memberships'&&<Memberships gymId={profile.gym_id} refresh={refresh}/>}
 {screen==='payments'&&<Payments gymId={profile.gym_id} refresh={refresh} onOpen={open}/>} {screen==='finance'&&<Finance gymId={profile.gym_id} refresh={refresh}/>} {screen==='leads'&&<Leads gymId={profile.gym_id} refresh={refresh}/>} 
 {screen==='attendance'&&<Attendance gymId={profile.gym_id} refresh={refresh}/>}
 {screen==='analytics'&&<Analytics gymId={profile.gym_id} refresh={refresh}/>}
 {screen==='reports'&&<Reports gymId={profile.gym_id} refresh={refresh}/>}
 {screen==='notifications'&&<Notifications gymId={profile.gym_id} refresh={refresh}/>}
 {screen==='settings'&&<Settings gymId={profile.gym_id} refresh={refresh}/>}
 {screen==='staff'&&<Staff gymId={profile.gym_id} currentUser={profile}/>}</main>
 <nav className="mobile-nav"><button className={screen==='dashboard'?'selected':''} onClick={()=>setScreen('dashboard')}><Home size={18}/><span>Home</span></button><button className={screen==='members'?'selected':''} onClick={()=>setScreen('members')}><Users size={18}/><span>Members</span></button><button className={screen==='attendance'?'selected':''} onClick={()=>setScreen('attendance')}><Check size={18}/><span>Attend</span></button><button className={screen==='payments'?'selected':''} onClick={()=>setScreen('payments')}><WalletCards size={18}/><span>Payments</span></button><button className={more?'selected':''} onClick={()=>setMore(true)}><MoreHorizontal size={18}/><span>More</span></button></nav>{more&&<Sheet title="More" onClose={()=>setMore(false)}><div className="mobile-more-grid">{nav.filter(n=>!['dashboard','members','attendance','payments'].includes(n.id)).map(n=>{const I=n.icon;return <button key={n.id} className="quick" onClick={()=>{setMore(false);setScreen(n.id)}}><span><I size={19}/></span><b>{n.label}</b></button>})}</div></Sheet>}
 {modal?.type==='add'&&<MemberForm gymId={profile.gym_id} isAdmin={profile.role==='admin'} onClose={close} onSaved={()=>{close();bump();toast('Member created')}}/>}
 {modal?.type==='profile'&&modal.member&&<MemberProfile gymId={profile.gym_id} member={modal.member} isAdmin={profile.role==='admin'} onClose={close} onRefresh={bump}/>}
 {modal?.type==='payment'&&<PaymentForm gymId={profile.gym_id} target={modal.member} onClose={close} onSaved={()=>{close();bump();toast('Payment recorded')}}/>}
 {modal?.type==='refund'&&modal.payment&&<RefundForm gymId={profile.gym_id} payment={modal.payment} onClose={close} onSaved={()=>{close();bump();toast('Refund recorded')}}/>}{modal?.type==='renew'&&modal.member&&<RenewForm gymId={profile.gym_id} member={modal.member} onClose={close} onSaved={()=>{close();bump();toast('Membership renewed')}}/>}{modal?.type==='freeze'&&modal.member&&<FreezeForm gymId={profile.gym_id} member={modal.member} onClose={close} onSaved={()=>{close();bump();toast('Membership frozen')}}/>}{modal?.type==='cancel'&&modal.member&&<CancelForm gymId={profile.gym_id} member={modal.member} onClose={close} onSaved={()=>{close();bump();toast('Membership cancelled')}}/>}{modal?.type==='message'&&modal.member&&<MessageForm gymId={profile.gym_id} member={modal.member} onClose={close} onSaved={()=>{close();bump();toast('Message queued')}}/>}
 </div>
}
function RefundForm({gymId,payment,onClose,onSaved}:{gymId:string;payment:Payment;onClose:()=>void;onSaved:()=>void}){const[amount,setAmount]=useState(Number(payment.net_amount||payment.amount)),[reason,setReason]=useState('Customer requested refund'),[notes,setNotes]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');return <Sheet title="Refund payment" onClose={onClose}><div className="form"><div className="info-card"><b>{payment.member_name}</b><span>Original {payment.amount} · Already refunded {payment.refund_amount}</span></div><Field label="Refund amount"><input type="number" min="0.01" max={Number(payment.amount)-Number(payment.refund_amount||0)} value={amount} onChange={e=>setAmount(Number(e.target.value))}/></Field><Field label="Reason"><input required value={reason} onChange={e=>setReason(e.target.value)}/></Field><Field label="Notes"><textarea value={notes} onChange={e=>setNotes(e.target.value)}/></Field>{error&&<div className="error-inline">{humanError(error)}</div>}<button className="primary full" disabled={busy} onClick={async()=>{setBusy(true);try{const{refundPayment}=await import('./data');await refundPayment({gymId,paymentId:payment.payment_id,amount,reason,notes});onSaved()}catch(e:any){setError(humanError(e))}finally{setBusy(false)}}}>{busy?'Processing…':'Record refund'}</button></div></Sheet>}
function Field({label,children}:{label:string;children:React.ReactNode}){return <label className="field"><span>{label}</span>{children}</label>}
function AuthWrap({title,children}:{title:string;children:React.ReactNode}){return <div className="auth-page"><div className="auth-card"><Brand/><h1>{title}</h1>{children}</div></div>}
function Config({config}:{config:any}){return <AuthWrap title="Connect Supabase"><p>{config.urlConfigured?'The publishable key is missing.':'The Supabase URL is missing.'}</p><div className="env-check"><span>VITE_SUPABASE_URL <b>{config.urlConfigured?'✓':'✕'}</b></span><span>VITE_SUPABASE_PUBLISHABLE_KEY <b>{config.keyConfigured?'✓':'✕'}</b></span></div></AuthWrap>}
function initials(n:string){return n.split(/\s+/).filter(Boolean).slice(0,2).map(x=>x[0]).join('').toUpperCase()||'GM'}
