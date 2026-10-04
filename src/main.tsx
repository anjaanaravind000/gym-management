import React, { useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Area, AreaChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import {
  Activity, AlertTriangle, ArrowUpRight, Bell, Check, ChevronRight,
  CircleDollarSign, Clock3, Dumbbell, Home, MoreHorizontal, Plus, Search,
  Settings, SlidersHorizontal, Users, WalletCards, X, Snowflake, UserPlus, RotateCcw
} from 'lucide-react';
import './styles.css';

type MemberStatus = 'Active'|'Expiring soon'|'Expired'|'Frozen';
type Member = { id:string; name:string; phone:string; package:string; status:MemberStatus; expiry:string; avatar:string };

const members: Member[] = [
  {id:'GYM-10284',name:'Rahul Kumar',phone:'98765•••21',package:'Premium',status:'Active',expiry:'24 Oct 2026',avatar:'RK'},
  {id:'GYM-10283',name:'Priya Sharma',phone:'98452•••18',package:'12 Month',status:'Expiring soon',expiry:'8 Oct 2026',avatar:'PS'},
  {id:'GYM-10281',name:'Anil Kumar',phone:'99876•••43',package:'6 Month',status:'Expired',expiry:'2 Oct 2026',avatar:'AK'},
  {id:'GYM-10279',name:'Anjali R',phone:'97890•••65',package:'Premium',status:'Active',expiry:'12 Dec 2026',avatar:'AR'},
  {id:'GYM-10277',name:'Karthik M',phone:'98430•••72',package:'3 Month',status:'Frozen',expiry:'18 Nov 2026',avatar:'KM'},
];

const revenue = [
  {name:'Apr',value:62000},{name:'May',value:68000},{name:'Jun',value:73500},{name:'Jul',value:71000},{name:'Aug',value:79200},{name:'Sep',value:84500}
];

const navItems = [
  {key:'dashboard' as const, label:'Dashboard', Icon:Home},
  {key:'members' as const, label:'Members', Icon:Users},
  {key:'attendance' as const, label:'Attendance', Icon:Check},
  {key:'payments' as const, label:'Payments', Icon:WalletCards},
];

function App(){
  const [screen,setScreen] = useState<'dashboard'|'members'>('dashboard');
  const [search,setSearch] = useState('');
  const [filter,setFilter] = useState<'All'|MemberStatus>('All');
  const [selected,setSelected] = useState<Member|null>(null);
  const [showAdd,setShowAdd] = useState(false);
  const [showFilters,setShowFilters] = useState(false);
  const [notice,setNotice] = useState<string|null>(null);
  const filtered = useMemo(()=>members.filter(m=>(filter==='All'||m.status===filter)&&(!search||`${m.name} ${m.phone} ${m.id}`.toLowerCase().includes(search.toLowerCase()))),[filter,search]);
  const notify=(s:string)=>{setNotice(s);setTimeout(()=>setNotice(null),2200)};

  return <div className="app-shell">
    <aside className="sidebar">
      <div className="brand"><div className="brand-mark"><Dumbbell size={19}/></div><div><b>FitCore</b><span>Gym Management</span></div></div>
      <nav>{navItems.map(({key,label,Icon})=><button key={key} className={screen===key?'nav-item active':'nav-item'} onClick={()=>setScreen(key)}><Icon size={19}/><span>{label}</span></button>)}</nav>
      <div className="sidebar-section">MANAGEMENT</div>
      <button className="nav-item" onClick={()=>notify('Analytics is ready for the next module.')}><Activity size={19}/><span>Analytics</span></button>
      <button className="nav-item" onClick={()=>notify('Reports is ready for the next module.')}><Clock3 size={19}/><span>Reports</span></button>
      <button className="nav-item" onClick={()=>notify('Settings is ready for the next module.')}><Settings size={19}/><span>Settings</span></button>
      <div className="profile"><div className="avatar">AR</div><div><b>Admin</b><span>Gym Owner</span></div><MoreHorizontal size={18}/></div>
    </aside>

    <main className="main">
      {screen==='dashboard' ? <Dashboard onAdd={()=>setShowAdd(true)} onMembers={()=>setScreen('members')} onNotice={notify}/> :
      <MembersScreen members={filtered} filter={filter} setFilter={setFilter} search={search} setSearch={setSearch} onFilter={()=>setShowFilters(true)} onAdd={()=>setShowAdd(true)} onSelect={setSelected}/>} 
    </main>

    <nav className="mobile-nav">
      <button className={screen==='dashboard'?'selected':''} onClick={()=>setScreen('dashboard')}><Home size={19}/><span>Home</span></button>
      <button className={screen==='members'?'selected':''} onClick={()=>setScreen('members')}><Users size={19}/><span>Members</span></button>
      <button onClick={()=>notify('Check-in flow ready.')}><Check size={19}/><span>Attend</span></button>
      <button onClick={()=>notify('Payments module ready.')}><WalletCards size={19}/><span>Payments</span></button>
      <button onClick={()=>notify('More menu ready.')}><MoreHorizontal size={19}/><span>More</span></button>
    </nav>

    {showAdd && <BottomSheet title="Add member" onClose={()=>setShowAdd(false)}><AddMember onDone={()=>{setShowAdd(false);notify('Member registration started.')}}/></BottomSheet>}
    {showFilters && <BottomSheet title="Filters" onClose={()=>setShowFilters(false)}><FilterSheet filter={filter} setFilter={setFilter} onDone={()=>setShowFilters(false)}/></BottomSheet>}
    {selected && <BottomSheet title={selected.name} onClose={()=>setSelected(null)}><MemberActions member={selected} onDone={(s)=>{setSelected(null);notify(s)}}/></BottomSheet>}
    {notice && <div className="toast"><Check size={17}/>{notice}</div>}
  </div>
}

function Dashboard({onAdd,onMembers,onNotice}:{onAdd:()=>void;onMembers:()=>void;onNotice:(s:string)=>void}){
 return <>
  <header className="topbar"><div><div className="eyebrow">MONDAY · 4 OCTOBER</div><h1>Good morning 👋</h1><p>Here’s what’s happening at your gym today.</p></div><div className="top-actions"><button className="icon-button" onClick={()=>onNotice('You have 3 notifications.')}><Bell size={19}/><i/></button><button className="primary desktop-only" onClick={onAdd}><Plus size={18}/> Add member</button></div></header>
  <section><div className="section-title"><div><span className="eyebrow">TODAY’S SNAPSHOT</span></div></div><div className="metric-grid">
    <Metric title="Revenue" value="₹84,500" detail="+12.4% vs last month" positive/><Metric title="Active members" value="1,248" detail="+24 this month" positive/><Metric title="Renewals" value="18" detail="6 due today"/><Metric title="Outstanding" value="₹32,400" detail="14 members" warning/>
  </div></section>
  <section><div className="section-title"><h2>Quick actions</h2></div><div className="quick-grid"><Quick label="Add member" icon={UserPlus} onClick={onAdd}/><Quick label="Check in" icon={Check} onClick={()=>onNotice('Check-in search opened.')}/><Quick label="Payment" icon={CircleDollarSign} onClick={()=>onNotice('Payment flow opened.')}/><Quick label="Renew" icon={RotateCcw} onClick={()=>onNotice('Renewal search opened.')}/></div></section>
  <section className="attention"><div className="section-title"><h2>Needs attention</h2><button className="text-button">View all</button></div><div className="attention-list"><Attention icon={AlertTriangle} title="12 memberships expiring" sub="3 expire today" onClick={onMembers}/><Attention icon={CircleDollarSign} title="₹18,400 outstanding" sub="8 members need follow-up" onClick={onMembers}/><Attention icon={RotateCcw} title="4 renewals need follow-up" sub="Grace period ending soon" onClick={onMembers}/></div></section>
  <div className="dashboard-grid"><section className="panel revenue-panel"><div className="section-title"><div><h2>Revenue</h2><span className="muted">Last 6 months</span></div><span className="trend"><ArrowUpRight size={15}/>12.4%</span></div><div className="chart-wrap"><ResponsiveContainer width="100%" height="100%"><AreaChart data={revenue}><defs><linearGradient id="rev" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#8b5cf6" stopOpacity=".32"/><stop offset="100%" stopColor="#8b5cf6" stopOpacity="0"/></linearGradient></defs><XAxis dataKey="name" axisLine={false} tickLine={false} tick={{fill:'#7e8190',fontSize:12}}/><YAxis hide/><Tooltip formatter={(v)=>[`₹${Number(v).toLocaleString('en-IN')}`,'Revenue']} contentStyle={{background:'#17171f',border:'1px solid #2b2b35',borderRadius:12,color:'#fff'}}/><Area type="monotone" dataKey="value" stroke="#9b7cff" strokeWidth={3} fill="url(#rev)"/></AreaChart></ResponsiveContainer></div></section>
  <section className="panel"><div className="section-title"><div><h2>Membership health</h2><span className="muted">1,248 total members</span></div></div><Health label="Active" value="1,042" pct={83}/><Health label="Expiring soon" value="86" pct={7}/><Health label="Expired" value="120" pct={10}/><Health label="Frozen" value="18" pct={2}/><button className="panel-link" onClick={onMembers}>View members <ChevronRight size={16}/></button></section></div>
  <div className="dashboard-grid"><section className="panel attendance-card"><div className="section-title"><div><h2>Today’s attendance</h2><span className="muted">Expected 220 visits</span></div><Activity size={20}/></div><div className="attendance-number">184 <span>/ 220</span></div><div className="progress"><span style={{width:'83.6%'}}/></div><div className="attendance-foot"><span>83.6% attendance</span><span>Peak 6–8 PM</span></div></section><section className="panel"><div className="section-title"><div><h2>Recent activity</h2><span className="muted">Latest updates</span></div></div><ActivityRow text="Priya renewed 12M membership" time="2 min ago"/><ActivityRow text="Rahul paid ₹3,500" time="8 min ago"/><ActivityRow text="Anjali checked in" time="11 min ago"/><ActivityRow text="New member registered" time="18 min ago"/></section></div>
 </>
}

function MembersScreen({members,filter,setFilter,search,setSearch,onFilter,onAdd,onSelect}:{members:Member[];filter:'All'|MemberStatus;setFilter:(v:'All'|MemberStatus)=>void;search:string;setSearch:(v:string)=>void;onFilter:()=>void;onAdd:()=>void;onSelect:(m:Member)=>void}){
 return <><header className="topbar members-header"><div><div className="eyebrow">MEMBER DIRECTORY</div><h1>Members</h1><p>Manage profiles, memberships and payments.</p></div><button className="primary desktop-only" onClick={onAdd}><Plus size={18}/> Add member</button></header>
 <section className="member-toolbar"><div className="search-box"><Search size={18}/><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search name, mobile or Member ID"/><button className="filter-button" onClick={onFilter}><SlidersHorizontal size={18}/></button></div><div className="chips">{(['All','Active','Expiring soon','Expired','Frozen'] as const).map(f=><button key={f} className={filter===f?'chip active':'chip'} onClick={()=>setFilter(f)}>{f}{filter===f&&<Check size={13}/>}</button>)}</div></section>
 <section><div className="result-line"><b>{members.length} {members.length===1?'member':'members'}</b><button className="sort-button">Sort <ArrowUpRight size={15}/></button></div><div className="member-list">{members.map(m=><MemberCard key={m.id} member={m} onClick={()=>onSelect(m)}/>)}</div>{members.length===0&&<EmptyMembers search={search} onClear={()=>{setSearch('');setFilter('All')}}/>}</section><button className="mobile-fab" onClick={onAdd}><Plus size={21}/><span>Add member</span></button></>
}

function MemberCard({member,onClick}:{member:Member;onClick:()=>void}){return <button className="member-card" onClick={onClick}><div className="avatar member-avatar">{member.avatar}</div><div className="member-main"><b>{member.name}</b><span>#{member.id} · {member.phone}</span><div><Status status={member.status}/><span className="member-package">{member.package} · {member.status==='Expired'?'Expired':'Expires'} {member.expiry.replace(' 2026','')}</span></div></div><ChevronRight className="member-chevron" size={19}/></button>}
function Status({status}:{status:MemberStatus}){return <span className={`status ${status.toLowerCase().replace(' ','-')}`}><i/> {status}</span>}
function Metric({title,value,detail,positive,warning}:{title:string;value:string;detail:string;positive?:boolean;warning?:boolean}){return <div className="metric-card"><span>{title}</span><strong>{value}</strong><small className={positive?'positive':warning?'warning':''}>{positive?'↑ ':warning?'⚠ ':''}{detail}</small></div>}
function Quick({label,icon:Icon,onClick}:{label:string;icon:any;onClick:()=>void}){return <button className="quick" onClick={onClick}><span><Icon size={20}/></span><b>{label}</b><ChevronRight size={16}/></button>}
function Attention({icon:Icon,title,sub,onClick}:{icon:any;title:string;sub:string;onClick:()=>void}){return <button className="attention-row" onClick={onClick}><span className="attention-icon"><Icon size={18}/></span><div><b>{title}</b><small>{sub}</small></div><ChevronRight size={18}/></button>}
function Health({label,value,pct}:{label:string;value:string;pct:number}){return <div className="health"><div><span>{label}</span><b>{value}</b></div><div className="health-track"><i style={{width:`${pct}%`}}/></div></div>}
function ActivityRow({text,time}:{text:string;time:string}){return <div className="activity-row"><span className="activity-dot"/><div><b>{text}</b><small>{time}</small></div></div>}
function EmptyMembers({search,onClear}:{search:string;onClear:()=>void}){return <div className="empty"><Users size={28}/><h3>{search?'No members found':'No members yet'}</h3><p>{search?'Try a different name, mobile number or Member ID.':'Add your first member to start managing the gym.'}</p><button className="secondary" onClick={onClear}>{search?'Clear search':'Refresh'}</button></div>}
function BottomSheet({title,onClose,children}:{title:string;onClose:()=>void;children:React.ReactNode}){return <div className="sheet-backdrop" onMouseDown={e=>{if(e.currentTarget===e.target)onClose()}}><div className="sheet"><div className="sheet-handle"/><div className="sheet-head"><h2>{title}</h2><button className="icon-button" onClick={onClose}><X size={18}/></button></div>{children}</div></div>}
function AddMember({onDone}:{onDone:()=>void}){return <div className="form"><label>Full name<input placeholder="Rahul Kumar"/></label><label>Mobile number<input placeholder="98765 43210" inputMode="tel"/></label><label>Package<select defaultValue=""><option value="" disabled>Select package</option><option>1 Month</option><option>3 Months</option><option>6 Months</option><option>12 Months</option></select></label><label>Amount paid<input placeholder="₹ 0" inputMode="decimal"/></label><button className="primary full" onClick={onDone}>Continue</button></div>}
function FilterSheet({filter,setFilter,onDone}:{filter:'All'|MemberStatus;setFilter:(v:'All'|MemberStatus)=>void;onDone:()=>void}){return <div className="form"><div className="filter-options">{(['All','Active','Expiring soon','Expired','Frozen'] as const).map(f=><button key={f} className={filter===f?'filter-option selected':'filter-option'} onClick={()=>setFilter(f)}><span>{f}</span>{filter===f&&<Check size={18}/>}</button>)}</div><label>Package<select><option>All packages</option><option>Premium</option><option>12 Month</option><option>6 Month</option></select></label><label>Payment<select><option>Any payment status</option><option>Fully paid</option><option>Partial</option><option>Pending</option></select></label><button className="primary full" onClick={onDone}>Show members</button></div>}
function MemberActions({member,onDone}:{member:Member;onDone:(s:string)=>void}){return <div className="action-sheet"><div className="sheet-member"><div className="avatar member-avatar">{member.avatar}</div><div><b>{member.name}</b><span>#{member.id}</span></div></div><button onClick={()=>onDone('Member profile opened.')}><Users size={19}/>View profile<ChevronRight/></button><button onClick={()=>onDone('Renewal flow opened.')}><RotateCcw size={19}/>Renew membership<ChevronRight/></button><button onClick={()=>onDone('Payment flow opened.')}><CircleDollarSign size={19}/>Collect payment<ChevronRight/></button><button onClick={()=>onDone('Check-in flow opened.')}><Check size={19}/>Mark attendance<ChevronRight/></button><button onClick={()=>onDone('WhatsApp action opened.')}><Bell size={19}/>WhatsApp<ChevronRight/></button><button onClick={()=>onDone('Freeze flow opened.')}><Snowflake size={19}/>Freeze membership<ChevronRight/></button></div>}

createRoot(document.getElementById('root')!).render(<React.StrictMode><App/></React.StrictMode>);
