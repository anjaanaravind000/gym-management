import React,{useEffect,useMemo,useState}from'react';
import{CalendarDays,ChevronLeft,ChevronRight,Edit3,Plus,RefreshCw,Users,UserCheck,XCircle}from'lucide-react';
import{bookClass,cancelClassBooking,cancelClassSession,loadClassRoster,loadClasses,loadClassTimetable,loadMembers,loadStaff,localDateOffset,localToday,saveClass,saveClassSession,setClassBookingAttendance}from'../data';
import type{ClassSession,GymClass,Member,Staff}from'../data';
import{DataTable,Empty,Field,Metric,Panel,PageHeader,Sheet,StatusTag,humanError,initials}from'../components/ui';

function toWeekStart(value:string){
 const d=new Date(value+'T12:00:00');
 const day=d.getDay();
 d.setDate(d.getDate()-day);
 return localDateOffset(d,0);
}
function localDateTime(v:string){return v.replace(' ','T').slice(0,16)}
function timeLabel(v:string){return new Date(v).toLocaleTimeString('en-IN',{hour:'numeric',minute:'2-digit'})}
function dayLabel(date:string){return new Date(date+'T12:00:00').toLocaleDateString('en-IN',{weekday:'short',day:'numeric',month:'short'})}
function addMinutesLocal(value:string,minutes:number){
 const d=new Date(value);d.setMinutes(d.getMinutes()+minutes);
 const pad=(n:number)=>String(n).padStart(2,'0');
 return d.getFullYear()+'-'+pad(d.getMonth()+1)+'-'+pad(d.getDate())+'T'+pad(d.getHours())+':'+pad(d.getMinutes());
}

export function Classes({gymId,refresh,onBookMember}:{gymId:string;refresh:number;onBookMember?:(session?:ClassSession)=>void}){
 const[week,setWeek]=useState(toWeekStart(localToday()));
 const[classes,setClasses]=useState<GymClass[]>([]);
 const[staff,setStaff]=useState<Staff[]>([]);
 const[sessions,setSessions]=useState<ClassSession[]>([]);
 const[classFilter,setClassFilter]=useState('all');
 const[instructorFilter,setInstructorFilter]=useState('all');
 const[busy,setBusy]=useState(true);
 const[error,setError]=useState('');
 const[editingClass,setEditingClass]=useState<any|null>(null);
 const[editingSession,setEditingSession]=useState<any|null>(null);
 const[roster,setRoster]=useState<ClassSession|null>(null);

 const weekDates=useMemo(()=>Array.from({length:7},(_,i)=>localDateOffset(week,i)),[week]);
 const from=weekDates[0];
 const to=localDateOffset(weekDates[0],7);

 async function load(){
  setBusy(true);
  try{
   const[c,s,ses]=await Promise.all([
    loadClasses(gymId,true),
    loadStaff(gymId),
    loadClassTimetable(gymId,from,to,instructorFilter,classFilter)
   ]);
   setClasses(c);setStaff(s);setSessions(ses);setError('');
  }catch(x:any){setError(humanError(x))}
  finally{setBusy(false)}
 }
 useEffect(()=>{load()},[gymId,week,instructorFilter,classFilter,refresh]);

 const grouped=useMemo(()=>{
  const map:Record<string,ClassSession[]>={};
  weekDates.forEach(d=>map[d]=[]);
  sessions.forEach(s=>{const d=new Date(s.start_at).toLocaleDateString('en-CA');if(map[d])map[d].push(s)});
  return map;
 },[sessions,weekDates]);

 const upcoming=sessions.filter(s=>s.status==='scheduled').reduce((n,s)=>n+1,0);
 const totalBooked=sessions.reduce((n,s)=>n+Number(s.booked_count||0),0);
 const totalWait=sessions.reduce((n,s)=>n+Number(s.waitlist_count||0),0);

 return <div>
  <PageHeader title="Classes & Timetable" subtitle="Schedule instructors, manage capacity and book members into sessions."
   action={<div className="toolbar-actions">
    <button className="icon-button" title="Previous week" onClick={()=>setWeek(localDateOffset(week,-7))}><ChevronLeft size={17}/></button>
    <button className="secondary small" onClick={()=>setWeek(toWeekStart(localToday()))}>This week</button>
    <button className="icon-button" title="Next week" onClick={()=>setWeek(localDateOffset(week,7))}><ChevronRight size={17}/></button>
    <button className="icon-button" title="Refresh" onClick={load}><RefreshCw size={17}/></button>
    <button className="primary class-schedule-btn" onClick={()=>setEditingSession({id:null,classId:classes.find(c=>c.status==='active')?.id||'',instructorId:staff.find(s=>s.status==='active')?.id||'',startLocal:week+'T09:00',endLocal:week+'T10:00',capacity:'',repeatWeeks:1})}><Plus size={16}/> Schedule</button>
   </div>}
  />
  {error&&<div className="error-banner">{error}</div>}
  <div className="kpi-grid">
   <Metric title="Scheduled sessions" value={busy?'—':upcoming}/>
   <Metric title="Booked spots" value={busy?'—':totalBooked}/>
   <Metric title="Waitlisted" value={busy?'—':totalWait}/>
   <Metric title="Visible classes" value={classes.filter(c=>c.status==='active').length}/>
  </div>

  <div className="classes-layout">
   <Panel title="Class library" extra={<button className="text-button" onClick={()=>setEditingClass({id:null,name:'',description:'',duration_minutes:60,capacity:20,status:'active'})}><Plus size={14}/> Add class</button>}>
    {!classes.length?<Empty title="No classes yet" text="Create your first class type, then schedule sessions from the timetable."/>:
    <div className="class-library">{classes.map(c=><div className="class-card" key={c.id}><div><b>{c.name}</b><span>{c.duration_minutes} min · capacity {c.capacity}</span>{c.description&&<small>{c.description}</small>}</div><div className="row-actions"><StatusTag value={c.status}/><button className="icon-button mini" title="Edit class" onClick={()=>setEditingClass(c)}><Edit3 size={13}/></button></div></div>)}</div>}
   </Panel>

   <Panel title="Schedule filters" extra={<CalendarDays size={17}/>}>
    <div className="form-grid">
     <Field label="Class"><select value={classFilter} onChange={e=>setClassFilter(e.target.value)}><option value="all">All classes</option>{classes.filter(c=>c.status==='active').map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></Field>
     <Field label="Instructor"><select value={instructorFilter} onChange={e=>setInstructorFilter(e.target.value)}><option value="all">All instructors</option>{staff.filter(s=>s.status==='active').map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select></Field>
    </div>
    <div className="info-card"><CalendarDays size={16}/><span>Week of {dayLabel(week)}</span></div>
   </Panel>
  </div>

  <div className="timetable-grid">
   {weekDates.map(date=><div className="day-column" key={date}>
    <div className="day-header"><b>{dayLabel(date)}</b><span>{grouped[date]?.length||0} sessions</span></div>
    <div className="day-sessions">
     {!grouped[date]?.length&&<div className="day-empty">No sessions</div>}
     {(grouped[date]||[]).map(session=><SessionCard key={session.id} session={session} onEdit={()=>setEditingSession({
       id:session.id,classId:session.class_id,instructorId:session.instructor_id,
       startLocal:localDateTime(new Date(session.start_at).toLocaleString('sv-SE',{hour12:false})),
       endLocal:localDateTime(new Date(session.end_at).toLocaleString('sv-SE',{hour12:false})),
       capacity:session.capacity,repeatWeeks:1
      })} onBook={()=>onBookMember?onBookMember(session):setRoster(session)} onRoster={()=>setRoster(session)} onCancel={async()=>{
       const reason=window.prompt('Reason for cancelling this session:');if(!reason)return;
       try{await cancelClassSession(gymId,session.id,reason);load()}catch(x:any){setError(humanError(x))}
      }}/>)}
    </div>
   </div>)}
  </div>

  {editingClass&&<ClassEditor gymId={gymId} initial={editingClass} onClose={()=>setEditingClass(null)} onSaved={()=>{setEditingClass(null);load()}}/>}
  {editingSession&&<SessionEditor gymId={gymId} classes={classes} staff={staff} initial={editingSession} onClose={()=>setEditingSession(null)} onSaved={()=>{setEditingSession(null);load()}}/>}
  {roster&&<ClassRoster gymId={gymId} session={roster} onClose={()=>setRoster(null)} onChanged={load}/>}
 </div>;
}

function SessionCard({session,onEdit,onBook,onRoster,onCancel}:{session:ClassSession;onEdit:()=>void;onBook:()=>void;onRoster:()=>void;onCancel:()=>void}){
 const full=Number(session.booked_count)>=Number(session.capacity);
 return <div className={'session-card '+(session.status==='cancelled'?'cancelled':'')}>
  <div className="session-time">{timeLabel(session.start_at)} – {timeLabel(session.end_at)}</div>
  <b>{session.class_name}</b>
  <span>{session.instructor_name}</span>
  <div className="capacity-line"><strong>{session.booked_count}/{session.capacity}</strong><span>{session.waitlist_count?session.waitlist_count+' waiting':''}</span></div>
  <div className="session-actions">
   {session.status==='scheduled'&&<button className="secondary small" onClick={onBook}><Users size={13}/> {full?'Waitlist':'Book'}</button>}
   <button className="secondary small" onClick={onRoster}><UserCheck size={13}/> Roster</button>
   {session.status==='scheduled'&&<button className="icon-button mini" title="Edit" onClick={onEdit}><Edit3 size={13}/></button>}
   {session.status==='scheduled'&&<button className="icon-button mini" title="Cancel" onClick={onCancel}><XCircle size={13}/></button>}
  </div>
 </div>;
}

function ClassEditor({gymId,initial,onClose,onSaved}:{gymId:string;initial:any;onClose:()=>void;onSaved:()=>void}){
 const[f,setF]=useState(initial),[busy,setBusy]=useState(false),[error,setError]=useState('');
 return <Sheet title={f.id?'Edit class':'Add class'} onClose={onClose}><form className="form" onSubmit={async e=>{e.preventDefault();setBusy(true);setError('');try{await saveClass({gymId,id:f.id,name:f.name,description:f.description,durationMinutes:Number(f.duration_minutes),capacity:Number(f.capacity),status:f.status});onSaved()}catch(x:any){setError(humanError(x))}finally{setBusy(false)}}}>
  <Field label="Class name"><input required minLength={2} value={f.name} onChange={e=>setF({...f,name:e.target.value})}/></Field>
  <div className="form-grid"><Field label="Duration (minutes)"><input type="number" min="15" max="240" value={f.duration_minutes} onChange={e=>setF({...f,duration_minutes:Number(e.target.value)})}/></Field><Field label="Default capacity"><input type="number" min="1" max="1000" value={f.capacity} onChange={e=>setF({...f,capacity:Number(e.target.value)})}/></Field></div>
  <Field label="Description"><textarea value={f.description||''} onChange={e=>setF({...f,description:e.target.value})}/></Field>
  <Field label="Status"><select value={f.status} onChange={e=>setF({...f,status:e.target.value})}><option value="active">Active</option><option value="inactive">Inactive</option></select></Field>
  {error&&<div className="error-inline">{humanError(error)}</div>}<button className="primary full" disabled={busy}>{busy?'Saving…':'Save class'}</button>
 </form></Sheet>;
}

function SessionEditor({gymId,classes,staff,initial,onClose,onSaved}:{gymId:string;classes:GymClass[];staff:Staff[];initial:any;onClose:()=>void;onSaved:()=>void}){
 const[f,setF]=useState(initial),[busy,setBusy]=useState(false),[error,setError]=useState('');
 useEffect(()=>{const c=classes.find(x=>x.id===f.classId);if(c&&!initial.id&&f.endLocal){const next=addMinutesLocal(f.startLocal,c.duration_minutes);setF((x:any)=>({...x,endLocal:next}))}},[f.classId]);
 const cls=classes.find(x=>x.id===f.classId);
 return <Sheet title={f.id?'Edit scheduled session':'Schedule class'} onClose={onClose}><form className="form" onSubmit={async e=>{e.preventDefault();setBusy(true);setError('');try{await saveClassSession({gymId,id:f.id,classId:f.classId,instructorId:f.instructorId,startLocal:f.startLocal,endLocal:f.endLocal,capacity:f.capacity===''?null:Number(f.capacity),repeatWeeks:Number(f.repeatWeeks)||1});onSaved()}catch(x:any){setError(humanError(x))}finally{setBusy(false)}}}>
  <div className="form-grid"><Field label="Class"><select required value={f.classId} onChange={e=>setF({...f,classId:e.target.value})}><option value="">Select class</option>{classes.filter(c=>c.status==='active').map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></Field><Field label="Instructor"><select required value={f.instructorId} onChange={e=>setF({...f,instructorId:e.target.value})}><option value="">Select instructor</option>{staff.filter(s=>s.status==='active').map(s=><option key={s.id} value={s.id}>{s.name} · {s.role}</option>)}</select></Field></div>
  <div className="form-grid"><Field label="Start"><input required type="datetime-local" value={f.startLocal} onChange={e=>setF({...f,startLocal:e.target.value})}/></Field><Field label="End"><input required type="datetime-local" value={f.endLocal} onChange={e=>setF({...f,endLocal:e.target.value})}/></Field></div>
  <div className="form-grid"><Field label="Session capacity override"><input type="number" min="1" max="1000" placeholder={cls?String(cls.capacity):'Default'} value={f.capacity} onChange={e=>setF({...f,capacity:e.target.value})}/></Field><Field label="Repeat weekly"><input type="number" min="1" max="52" value={f.repeatWeeks} disabled={!!f.id} onChange={e=>setF({...f,repeatWeeks:Number(e.target.value)})}/></Field></div>
  <div className="info-card"><span>{cls?cls.duration_minutes+' minute class · default capacity '+cls.capacity:'Choose a class to see defaults.'}</span></div>
  {error&&<div className="error-inline">{humanError(error)}</div>}<button className="primary full" disabled={busy||!f.classId||!f.instructorId}>{busy?'Scheduling…':f.id?'Save changes':'Schedule session(s)'}</button>
 </form></Sheet>;
}

function ClassRoster({gymId,session,onClose,onChanged}:{gymId:string;session:ClassSession;onClose:()=>void;onChanged:()=>void}){
 const[rows,setRows]=useState<any[]>([]),[error,setError]=useState('');
 const load=()=>loadClassRoster(gymId,session.id).then(setRows).catch((x:any)=>setError(humanError(x)));
 useEffect(()=>{load()},[gymId,session.id]);
 return <Sheet title={session.class_name+' · Roster'} onClose={onClose}><div className="info-card"><b>{timeLabel(session.start_at)} – {timeLabel(session.end_at)}</b><span>{session.instructor_name} · {session.booked_count}/{session.capacity} booked · {session.waitlist_count} waitlisted</span></div>{error&&<div className="error-inline">{error}</div>}{!rows.length?<Empty title="No bookings" text="Members booked into this session will appear here."/>:<DataTable rows={rows.map((r:any)=>({_id:r.id,Member:r.members?.name||'—',MemberID:r.members?.member_id||'—',Phone:r.members?.phone||'—',Status:r.status,Waitlist:r.waitlist_position||'—',Booked:r.booked_at}))} actions={(r:any)=>r.Status==='booked'?<div className="row-actions"><button className="secondary small" onClick={async()=>{try{await setClassBookingAttendance(gymId,r._id,'attended');load();onChanged()}catch(x:any){setError(humanError(x))}}}>Attended</button><button className="secondary small" onClick={async()=>{try{await setClassBookingAttendance(gymId,r._id,'no_show');load();onChanged()}catch(x:any){setError(humanError(x))}}}>No show</button><button className="danger-action small" onClick={async()=>{try{await cancelClassBooking(gymId,r._id);load();onChanged()}catch(x:any){setError(humanError(x))}}}>Cancel</button></div>:null}/>}</Sheet>;
}

export function ClassBookingForm({gymId,member,onClose,onSaved,session}:{gymId:string;member?:Member;onClose:()=>void;onSaved:()=>void;session?:ClassSession}){
 const[search,setSearch]=useState(''),[members,setMembers]=useState<Member[]>([]),[selected,setSelected]=useState<Member|undefined>(member),[sessions,setSessions]=useState<ClassSession[]>(session?[session]:[]),[selectedSession,setSelectedSession]=useState(session?.id||''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 useEffect(()=>{if(!session){const start=localToday();const end=localDateOffset(start,31);loadClassTimetable(gymId,start,end).then(x=>setSessions(x.filter(s=>s.status==='scheduled'&&new Date(s.start_at)>new Date()))).catch((x:any)=>setError(humanError(x)))}},[gymId,session?.id]);
 useEffect(()=>{if(search.trim().length<2){setMembers([]);return}loadMembers({gymId,page:0,pageSize:8,q:search,status:'active'}).then(x=>setMembers(x.rows)).catch((x:any)=>setError(humanError(x)))},[search,gymId]);
 const picked=sessions.find(s=>s.id===selectedSession);
 const submit=async()=>{
  if(!selected||!selectedSession)return;
  setBusy(true);setError('');
  try{const result=await bookClass(gymId,selectedSession,selected.id);onSaved();alert(result.status==='waitlisted'?'Member added to the waitlist at #'+result.waitlist_position:'Member booked successfully')}
  catch(x:any){setError(humanError(x))}
  finally{setBusy(false)}
 };
 return <Sheet title="Book member into class" onClose={onClose}><div className="form">
  {!member&&<><Field label="Find member"><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Name, phone or Member ID"/></Field>{members.map(m=><button key={m.id} className={selected?.id===m.id?'quick selected':'quick'} onClick={()=>{setSelected(m);setMembers([])}}><span className="avatar">{initials(m.name)}</span><b>{m.name} · #{m.member_id}</b></button>)}</>}
  {selected&&<div className="current-membership compact"><div><b>{selected.name}</b><span>#{selected.member_id} · {selected.phone}</span></div>{!member&&<button className="text-button" onClick={()=>setSelected(undefined)}>Change</button>}</div>}
  <Field label="Class session"><select value={selectedSession} onChange={e=>setSelectedSession(e.target.value)}><option value="">Select a session</option>{sessions.map(s=><option key={s.id} value={s.id}>{new Date(s.start_at).toLocaleString('en-IN',{weekday:'short',day:'numeric',month:'short',hour:'numeric',minute:'2-digit'})} · {s.class_name} · {s.booked_count}/{s.capacity}</option>)}</select></Field>
  {picked&&<div className="info-card"><span>{picked.instructor_name}</span><span>{picked.booked_count>=picked.capacity?'Full — member will join the waitlist.':picked.capacity-picked.booked_count+' spot(s) available.'}</span></div>}
  {error&&<div className="error-inline">{humanError(error)}</div>}
  <button className="primary full" disabled={busy||!selected||!selectedSession}>{busy?'Booking…':'Book member'}</button>
 </div></Sheet>;
}
