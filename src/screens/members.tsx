import React,{useEffect,useMemo,useState}from'react';
import{ArrowLeft,CalendarDays,CircleDollarSign,Edit3,MessageCircle,PauseCircle,Phone,Plus,RefreshCw,Search,Snowflake,Trash2,UserCheck,UserPlus,Check}from'lucide-react';
import{cancelClassBooking,cancelMembership,checkoutAttendance,createMember,createOldMember,deleteMember,findMemberByPhone,freezeMembership,loadPaymentMethodSettings,loadMemberClassBookings,loadGym,localDateOffset,localToday,loadMemberDetail,loadMembers,loadPackages,loadStaff,money,recordAttendance,recordPayment,refundPayment,renewMembership,setMemberStatus,signedMemberPhoto,uploadMemberPhoto,date}from'../data';
import type{Gym,Member,Package,Staff}from'../data';
import{DataTable,Detail,Empty,Field,Metric,Pagination,Panel,PageHeader,Sheet,StatusTag,Summary,Toggle,humanError,initials}from'../components/ui';

const METHODS=['cash','upi','card','bank_transfer','cheque','other'];
const today=localToday;
const addDay=localDateOffset;

export function Members({gymId,refresh,onRefresh,onOpen}:{gymId:string;refresh:number;onRefresh:()=>void;onOpen:(x:any)=>void}){
 const[q,setQ]=useState(''),[status,setStatus]=useState('all'),[payment,setPayment]=useState('all'),[page,setPage]=useState(0),[data,setData]=useState<Member[]>([]),[count,setCount]=useState(0),[busy,setBusy]=useState(true),[error,setError]=useState('');const size=20;
 useEffect(()=>{let a=true;setBusy(true);loadMembers({gymId,page,pageSize:size,q,status,paymentStatus:payment}).then(r=>a&&(setData(r.rows),setCount(r.count),setError(''))).catch((x:any)=>a&&setError(humanError(x))).finally(()=>a&&setBusy(false));return()=>{a=false}},[gymId,page,q,status,payment,refresh]);
 return <><PageHeader title="Members" subtitle={count+' live members'} action={<div className="toolbar-actions"><button className="secondary" onClick={()=>onOpen('old')}><UserPlus size={17}/> Add old member</button><button className="primary" onClick={()=>onOpen('add')}><Plus size={17}/> Add member</button><button className="icon-button" onClick={onRefresh}><RefreshCw size={18}/></button></div>}/>
 {error&&<div className="error-banner">{error}<button onClick={()=>setError('')}>Dismiss</button></div>}<div className="filters-row"><div className="search-box"><Search size={18}/><input value={q} onChange={e=>{setQ(e.target.value);setPage(0)}} placeholder="Search name, mobile or Member ID"/></div><select value={status} onChange={e=>{setStatus(e.target.value);setPage(0)}}><option value="all">All statuses</option>{['active','expiring_soon','grace_period','did_not_renew','expired','frozen','cancelled','inactive'].map(x=><option key={x}>{x}</option>)}</select><select value={payment} onChange={e=>{setPayment(e.target.value);setPage(0)}}><option value="all">Any payment</option><option value="paid">Paid</option><option value="partially_paid">Partially paid</option><option value="pending">Pending</option></select></div>
 <div className="member-list">{data.map(m=><button className="member-card" key={m.id} onClick={()=>onOpen({type:'profile',member:m})}><div className="avatar member-avatar">{initials(m.name)}</div><div className="member-main"><b>{m.name}</b><span>#{m.member_id} · {m.phone}</span><div><StatusTag value={m.membership_status||m.member_status}/><span className="member-package">{m.package_name||'Custom'} · {m.end_date||'No expiry'}</span></div></div><span className="member-balance">{m.balance_amount>0?money(m.balance_amount):'Paid'}</span></button>)}</div>
 {!busy&&!data.length&&<Empty title={q?'No matching members':'No members yet'} text={q?'Try another search or filter.':'Your database is empty. Add the first member.'} action={<button className="secondary" onClick={()=>onOpen('add')}><UserPlus size={16}/> Add member</button>}/>}
 <Pagination page={page} pages={Math.max(1,Math.ceil(count/20))} onPage={setPage}/>
 </>}
export function OldMemberForm({gymId,isAdmin,onClose,onSaved}:{gymId:string;isAdmin:boolean;onClose:()=>void;onSaved:(memberId?:string)=>void}){
 const[packages,setPackages]=useState<Package[]>([]),[staff,setStaff]=useState<Staff[]>([]),[methods,setMethods]=useState<string[]>(METHODS),[gym,setGym]=useState<Gym|null>(null);
 const[dup,setDup]=useState<any[]>([]),[busy,setBusy]=useState(false),[error,setError]=useState(''),[fieldErrors,setFieldErrors]=useState<Record<string,string>>({});
 const[saveState,setSaveState]=useState<'idle'|'saving'|'success'>('idle'),[saveStage,setSaveStage]=useState(''),[savedMemberId,setSavedMemberId]=useState(''),[photoWarning,setPhotoWarning]=useState('');
 const[f,setF]=useState<any>({
  name:'',phone:'',memberId:'',email:'',dob:'',gender:'',address:'',emergencyContact:'',emergencyPhone:'',
  joinDate:today(),status:'active',coach:'',allowDuplicate:false,
  addMembership:true,packageId:'',membershipStart:today(),membershipEnd:'',membershipStatus:'active',
  price:0,duration:1,discount:0,amountPaid:0,paymentMethod:'cash',paymentDate:today(),reference:'',paymentNotes:'',photo:null
 });
 const setField=(key:string,value:any)=>{setF((old:any)=>({...old,[key]:value}));setFieldErrors(old=>old[key]?{...old,[key]:''}:old);if(saveState==='success')setSaveState('idle')};
 const toYmd=(d:Date)=>`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
 const packageEnd=(start:string,pkg?:Package)=>{
  if(!start||!pkg)return '';
  const duration=Math.max(1,Math.floor(Number(pkg.duration_months||1)));
  const d=new Date(start+'T12:00:00');
  if(pkg.duration_unit==='day')d.setDate(d.getDate()+duration-1);
  else{
   const originalDay=d.getDate();d.setDate(1);d.setMonth(d.getMonth()+duration);
   const lastDay=new Date(d.getFullYear(),d.getMonth()+1,0).getDate();d.setDate(Math.min(originalDay,lastDay));d.setDate(d.getDate()-1);
  }
  return toYmd(d);
 };
 useEffect(()=>{let live=true;
  Promise.all([loadPackages(gymId,true),loadStaff(gymId),loadPaymentMethodSettings(gymId),loadGym(gymId)]).then(([p,s,ms,g])=>{
   if(!live)return;
   const enabledMethods=ms.filter((x:any)=>x.enabled).map((x:any)=>x.payment_method),first=p.find((x:any)=>x.status==='active')||p[0];
   setPackages(p);setStaff(s);setGym(g);setMethods(enabledMethods);
   setF((old:any)=>({...old,paymentMethod:enabledMethods.includes(old.paymentMethod)?old.paymentMethod:(enabledMethods[0]||old.paymentMethod),packageId:old.packageId||first?.id||'',price:old.packageId?old.price:(first?Number(first.price):0),duration:old.packageId?old.duration:(first?Number(first.duration_months):1),membershipEnd:old.packageId?old.membershipEnd:(first?packageEnd(old.membershipStart||old.joinDate,first):old.membershipEnd),coach:s.some((x:any)=>x.id===old.coach&&x.status==='active')?old.coach:''}));
  }).catch((x:any)=>live&&setError(humanError(x)));
  return()=>{live=false};
 },[gymId]);
 const blurPhone=async()=>{if(!f.phone.trim()){setDup([]);return}try{setDup(await findMemberByPhone(gymId,f.phone.trim()))}catch{setDup([])}};
 const selectedPackage=packages.find(x=>x.id===f.packageId),final=Math.max(Number(f.price||0)-Number(f.discount||0),0),balance=Math.max(final-Number(f.amountPaid||0),0);
 const graceDays=gym?.renewal_grace_days??7;
 const gymToday=useMemo(()=>{
  if(!gym?.timezone)return today();
  try{const parts=new Intl.DateTimeFormat('en',{timeZone:gym.timezone,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date()),get=(type:string)=>parts.find(x=>x.type===type)?.value||'';return `${get('year')}-${get('month')}-${get('day')}`;}catch{return today()}
 },[gym?.timezone]);
 const derivedStatus=useMemo(()=>{
  if(!f.addMembership||!f.membershipStart||!f.membershipEnd)return null;
  if(f.membershipStatus==='cancelled'||f.status==='cancelled')return 'cancelled';
  const t=gymToday,end=new Date(f.membershipEnd+'T12:00:00'),todayDate=new Date(t+'T12:00:00'),days=Math.round((end.getTime()-todayDate.getTime())/86400000);
  if(f.membershipStart>t)return 'active';
  if(days<0)return (todayDate.getTime()-end.getTime())/86400000<=graceDays?'grace_period':'did_not_renew';
  if(days<=10)return 'expiring_soon';
  return 'active';
 },[f.addMembership,f.membershipStart,f.membershipEnd,f.membershipStatus,f.status,graceDays,gymToday]);
 const choosePackage=(value:string)=>{
  const p=packages.find(x=>x.id===value);
  setF((old:any)=>({...old,packageId:value,price:p?Number(p.price):old.price,duration:p?Number(p.duration_months):old.duration,membershipEnd:p?packageEnd(old.membershipStart||old.joinDate,p):(old.membershipEnd&&old.membershipEnd>=old.membershipStart?old.membershipEnd:old.membershipStart)}));
  setFieldErrors(old=>({...old,packageId:'',membershipEnd:'',price:'',duration:''}));setSaveState('idle');
 };
 const changeJoinDate=(joinDate:string)=>{
  setF((old:any)=>{const start=old.membershipStart&&old.membershipStart>=joinDate?old.membershipStart:joinDate,pay=old.paymentDate&&old.paymentDate>=joinDate?old.paymentDate:joinDate,p=packages.find(x=>x.id===old.packageId);return {...old,joinDate,membershipStart:start,paymentDate:pay,membershipEnd:p?packageEnd(start,p):(old.membershipEnd&&old.membershipEnd>=start?old.membershipEnd:start)}});
  setFieldErrors(old=>({...old,joinDate:'',membershipStart:'',membershipEnd:'',paymentDate:''}));setSaveState('idle');
 };
 const changeMembershipStart=(startDate:string)=>{
  setF((old:any)=>{const p=packages.find(x=>x.id===old.packageId);return {...old,membershipStart:startDate,membershipEnd:p?packageEnd(startDate,p):(old.membershipEnd&&old.membershipEnd>=startDate?old.membershipEnd:startDate)}});
  setFieldErrors(old=>({...old,membershipStart:'',membershipEnd:''}));setSaveState('idle');
 };
 const toggleMembership=(enabled:boolean)=>{
  setF((old:any)=>({...old,addMembership:enabled,...(enabled?{}:{amountPaid:0,paymentDate:old.joinDate,reference:'',paymentNotes:'',membershipStatus:'active'})}));
  setFieldErrors({});setSaveState('idle');
 };
 const validate=()=>{
  const e:Record<string,string>={};
  if(!f.name.trim())e.name='Enter the member’s full name.';
  else if(f.name.trim().length<2)e.name='Name must contain at least 2 characters.';
  if(!f.phone.trim())e.phone='Enter the member’s mobile number.';
  else if(!/^[0-9+][0-9 ()-]{7,19}$/.test(f.phone.trim()))e.phone='Enter a valid mobile number.';
  if(!f.joinDate)e.joinDate='Choose the original joining date.';
  else if(f.joinDate>gymToday)e.joinDate='Joining date cannot be in the future.';
  if(dup.length&&!f.allowDuplicate)e.phone='This mobile number already belongs to an existing member. Only an admin can allow a duplicate.';
  if(f.addMembership){
   if(!f.membershipStart)e.membershipStart='Choose when this membership started.';
   else if(f.membershipStart<f.joinDate)e.membershipStart='Membership start cannot be before the joining date.';
   else if(f.membershipStart>gymToday)e.membershipStart='Imported membership start cannot be in the future.';
   if(!f.membershipEnd)e.membershipEnd='Choose the membership expiry date.';
   else if(f.membershipStart&&f.membershipEnd<f.membershipStart)e.membershipEnd='Expiry must be on or after the membership start.';
   const price=Number(f.price);
   if(selectedPackage===undefined){
    if(!String(f.price??'').trim()||!Number.isFinite(price)||price<0)e.price='Enter a valid membership price.';
    const duration=Number(f.duration);if(!String(f.duration??'').trim()||!Number.isInteger(duration)||duration<=0)e.duration='Enter a valid whole-number duration in months.';
   }
   const discount=Number(f.discount||0),paid=Number(f.amountPaid||0);
   if(discount<0||discount>price)e.discount='Discount cannot be greater than the membership price.';
   if(paid<0||paid>final)e.amountPaid=paid>final?'Paid amount cannot exceed the final amount.':'Enter a valid paid amount.';
   if(paid>0){
    if(!f.paymentDate)e.paymentDate='Choose the date the payment was actually received.';
    else if(f.paymentDate>gymToday)e.paymentDate='Payment date cannot be in the future.';
    else if(f.paymentDate<f.joinDate)e.paymentDate='Payment date cannot be before the member joined the gym.';
    if(!methods.length)e.amountPaid='Enable at least one payment method in Settings before recording a payment.';
   }
  }
  setFieldErrors(e);return Object.keys(e).length===0;
 };
 const save=async(e:React.FormEvent)=>{
  e.preventDefault();setError('');setPhotoWarning('');
  if(saveState==='saving')return;
  if(!validate()){setError('Please fix the highlighted fields before importing this member.');return}
  setBusy(true);setSaveState('saving');setSaveStage('Creating member record…');
  try{
   const id=await createOldMember({gymId,name:f.name,phone:f.phone,memberId:f.memberId||null,email:f.email||null,dob:f.dob||null,gender:f.gender||null,address:f.address||null,emergencyContact:f.emergencyContact||null,emergencyPhone:f.emergencyPhone||null,joinDate:f.joinDate,status:f.status,assignedCoachId:f.coach||null,allowDuplicatePhone:f.allowDuplicate,addMembership:f.addMembership,packageId:f.packageId||null,membershipStartDate:f.addMembership?f.membershipStart:null,membershipEndDate:f.addMembership?f.membershipEnd:null,membershipStatus:f.membershipStatus,price:f.addMembership?Number(f.price):null,durationMonths:f.addMembership?Number(f.duration):null,discount:f.addMembership?Number(f.discount):0,amountPaid:f.addMembership?Number(f.amountPaid):0,paymentMethod:f.paymentMethod,paymentDate:f.addMembership&&Number(f.amountPaid)>0?f.paymentDate:null,transactionReference:f.addMembership&&Number(f.amountPaid)>0?(f.reference||null):null,paymentNotes:f.addMembership&&Number(f.amountPaid)>0?(f.paymentNotes||null):null});
   if(f.photo){setSaveStage('Uploading profile photo…');try{await uploadMemberPhoto(gymId,id,f.photo)}catch{setPhotoWarning('Member imported, but the profile photo could not be uploaded. You can add it later from the member profile.')}}
   setSaveStage('Import complete');setSavedMemberId(id);setSaveState('success');setBusy(false);setFieldErrors({});
  }catch(x:any){setBusy(false);setSaveState('idle');setSaveStage('');setError(humanError(x))}
 };
 const duplicateBlocked=dup.length>0&&!(isAdmin&&f.allowDuplicate),noMethods=f.addMembership&&Number(f.amountPaid)>0&&!methods.length;
 if(saveState==='success')return <Sheet title="Import complete" onClose={()=>onSaved(savedMemberId)}><div className="old-member-success"><div className="success-icon"><Check size={26}/></div><div className="success-kicker">DONE</div><h3>Member imported successfully</h3><p>The member record and selected historical details are now saved.</p>{photoWarning&&<div className="success-warning" role="status"><b>One small issue</b><span>{photoWarning}</span></div>}<div className="success-summary"><Summary title="Member ID" value={savedMemberId||'Generated'}/><Summary title="Membership" value={f.addMembership?(f.membershipEnd?date(f.membershipEnd):'Added'):'Not added'}/><Summary title="Status" value={f.addMembership&&derivedStatus?<StatusTag value={derivedStatus}/>: '—'}/><Summary title="Payment" value={f.addMembership&&Number(f.amountPaid)>0?money(Number(f.amountPaid)):'No payment'}/></div><button className="primary full" onClick={()=>onSaved(savedMemberId)}>Done</button></div></Sheet>;
 return <Sheet title="Import old member" onClose={()=>{if(!busy)onClose()}}><form className="form old-member-form" noValidate onSubmit={save}>
  <div className="old-member-intro"><div><b>Bring an existing member into FitCore</b><span>Use this flow for members who joined before the software. Historical membership and payment dates stay intact.</span></div><small>Required: name, mobile and joining date. Membership is optional.</small></div>
  {error&&<div className="import-alert" role="alert"><b>Import needs attention</b><span>{error}</span></div>}
  <div className="form-section">
   <div className="section-title form-section-title"><div><h3>Member details</h3><span className="form-hint">Start with the information staff will use to identify the member.</span></div><span className="step-badge">1</span></div>
   <div className="form-grid">
    <Field label="Full name *"><input required maxLength={100} autoFocus aria-invalid={!!fieldErrors.name} value={f.name} onChange={e=>setField('name',e.target.value)}/>{fieldErrors.name&&<small className="field-error">{fieldErrors.name}</small>}</Field>
    <Field label="Mobile *"><input required maxLength={20} inputMode="tel" pattern="[0-9+][0-9 ()-]{7,19}" title="Enter a valid mobile number" aria-invalid={!!fieldErrors.phone} value={f.phone} onBlur={blurPhone} onChange={e=>{setDup([]);setField('phone',e.target.value);}}/>{fieldErrors.phone&&<small className="field-error">{fieldErrors.phone}</small>}</Field>
    <Field label="Joining date *"><input required type="date" max={gymToday} aria-invalid={!!fieldErrors.joinDate} value={f.joinDate} onChange={e=>changeJoinDate(e.target.value)}/><small className={fieldErrors.joinDate?'field-error':'field-help'}>{fieldErrors.joinDate||'Original gym joining date.'}</small></Field>
    <Field label="Old Member ID"><input maxLength={40} placeholder="Leave blank to generate" value={f.memberId} onChange={e=>setField('memberId',e.target.value)}/></Field>
    <Field label="Member status"><select value={f.status} onChange={e=>setField('status',e.target.value)}><option value="active">Active</option><option value="inactive">Inactive</option><option value="cancelled">Cancelled</option></select></Field>
    <Field label="Assigned coach"><select value={f.coach} onChange={e=>setField('coach',e.target.value)}><option value="">Unassigned</option>{staff.map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select></Field>
   </div>
   {dup.length>0&&<div className="warning-card duplicate-card"><div><b>Mobile number already exists</b><span>{dup.map(x=>x.name+' · #'+x.member_id).join(' | ')}</span></div>{isAdmin?<label className="checkbox-row"><input type="checkbox" checked={!!f.allowDuplicate} onChange={e=>setField('allowDuplicate',e.target.checked)}/><span>Allow this duplicate</span></label>:<small>This import is blocked. Ask an admin to allow a duplicate mobile number.</small>}</div>}
   <details className="optional-details"><summary>Additional member information <span>Optional</span></summary><div className="form-grid">
     <Field label="Email"><input type="email" maxLength={255} value={f.email} onChange={e=>setField('email',e.target.value)}/></Field>
     <Field label="Date of birth"><input type="date" max={gymToday} value={f.dob} onChange={e=>setField('dob',e.target.value)}/></Field>
     <Field label="Gender"><select value={f.gender} onChange={e=>setField('gender',e.target.value)}><option value="">Select</option><option>Male</option><option>Female</option><option>Other</option></select></Field>
     <Field label="Emergency contact"><input maxLength={100} value={f.emergencyContact} onChange={e=>setField('emergencyContact',e.target.value)}/></Field>
     <Field label="Emergency phone"><input maxLength={20} inputMode="tel" value={f.emergencyPhone} onChange={e=>setField('emergencyPhone',e.target.value)}/></Field>
   </div><Field label="Address"><textarea maxLength={500} value={f.address} onChange={e=>setField('address',e.target.value)}/></Field><Field label="Profile photo (max 5 MB)"><input type="file" accept="image/jpeg,image/png,image/webp" onChange={e=>{const file=e.target.files?.[0]||null;if(file&&file.size>5*1024*1024){setError('Profile photo must be 5 MB or smaller.');setF((o:any)=>({...o,photo:null}))}else{setError('');setF((o:any)=>({...o,photo:file}))}}}/></details>
  </div>
  <div className="form-section">
   <div className="section-title form-section-title"><div><h3>Current membership</h3><span className="form-hint">Add the membership that should appear on the member profile today.</span></div><span className="step-badge">2</span></div>
   <div className="membership-toggle-card"><div><b>Add membership</b><span>Create a historical membership record along with the member.</span></div><button type="button" className={f.addMembership?'switch on':'switch'} onClick={()=>toggleMembership(!f.addMembership)} aria-pressed={f.addMembership}><i/></button></div>
   {!f.addMembership&&<div className="info-card"><b>Member only</b><span>No membership or payment will be created. You can add a membership later from the member profile.</span></div>}
   {f.addMembership&&<div className="form">
    <div><label className="field-label">Package</label><div className="package-choice-grid old-package-grid">{packages.map(p=><button type="button" className={f.packageId===p.id?'package-choice selected':'package-choice'} key={p.id} onClick={()=>choosePackage(p.id)}><b>{p.name}</b><span>{money(p.price)} · {p.duration_months} {p.duration_unit||'month'}{p.duration_months===1?'':'s'}</span><small>{p.status==='inactive'?'Historical package':'Available package'}</small></button>)}<button type="button" className={!f.packageId?'package-choice selected':'package-choice'} onClick={()=>choosePackage('')}><b>Custom / other</b><span>Enter your own price</span><small>No package required</small></button></div></div>
    <div className="form-grid">
     <Field label="Membership start *"><input required type="date" min={f.joinDate} max={gymToday} aria-invalid={!!fieldErrors.membershipStart} value={f.membershipStart} onChange={e=>changeMembershipStart(e.target.value)}/><small className={fieldErrors.membershipStart?'field-error':'field-help'}>{fieldErrors.membershipStart||'Historical memberships must already have started.'}</small></Field>
     <Field label="Membership expiry *"><input required type="date" min={f.membershipStart} aria-invalid={!!fieldErrors.membershipEnd} value={f.membershipEnd} onChange={e=>setField('membershipEnd',e.target.value)}/>{fieldErrors.membershipEnd&&<small className="field-error">{fieldErrors.membershipEnd}</small>}</Field>
     {selectedPackage&&<Field label="Price"><input type="number" min="0" step="0.01" aria-invalid={!!fieldErrors.price} value={f.price} onChange={e=>{const price=Math.max(0,Number(e.target.value)||0);setF((o:any)=>({...o,price,discount:Math.min(Number(o.discount||0),price),amountPaid:Math.min(Number(o.amountPaid||0),Math.max(price-Number(o.discount||0),0))}));setFieldErrors(o=>({...o,price:'',discount:'',amountPaid:''}))}}/><small className="field-help">Defaults to the package price; change it for historical pricing.</small></Field>}
     {!selectedPackage&&<Field label="Custom price *"><input required type="number" min="0" step="0.01" aria-invalid={!!fieldErrors.price} value={f.price} onChange={e=>setField('price',Math.max(0,Number(e.target.value)||0))}/>{fieldErrors.price&&<small className="field-error">{fieldErrors.price}</small>}</Field>}
     {!selectedPackage&&<Field label="Duration (months) *"><input required type="number" min="1" step="1" aria-invalid={!!fieldErrors.duration} value={f.duration} onChange={e=>setField('duration',Math.max(1,Math.floor(Number(e.target.value)||1)))}/>{fieldErrors.duration&&<small className="field-error">{fieldErrors.duration}</small>}</Field>}
     <Field label="Discount"><input type="number" min="0" max={Number(f.price||0)} step="0.01" aria-invalid={!!fieldErrors.discount} value={f.discount} onChange={e=>{const discount=Math.min(Math.max(0,Number(e.target.value)||0),Number(f.price||0));setF((o:any)=>({...o,discount,amountPaid:Math.min(Number(o.amountPaid||0),Math.max(Number(o.price||0)-discount,0))}));setFieldErrors(o=>({...o,discount:'',amountPaid:''}))}}/>{fieldErrors.discount&&<small className="field-error">{fieldErrors.discount}</small>}</Field>
     <Field label="Amount paid"><input type="number" min="0" max={final} step="0.01" aria-invalid={!!fieldErrors.amountPaid} value={f.amountPaid} onChange={e=>setField('amountPaid',Math.min(Math.max(0,Number(e.target.value)||0),final))}/><small className={fieldErrors.amountPaid?'field-error':'field-help'}>{fieldErrors.amountPaid|| (balance>0?money(balance)+' remaining':'Fully paid')}</small></Field>
    </div>
    <div className="calculation"><Summary title="Price" value={money(Number(f.price||0))}/><Summary title="Final" value={money(final)}/><Summary title="Paid" value={money(Number(f.amountPaid||0))}/><Summary title="Balance" value={money(balance)}/></div>
    <div className="status-preview-card"><div><b>Membership status</b><span>Calculated automatically from the dates and cancellation choice.</span></div>{derivedStatus?<StatusTag value={derivedStatus}/>:<span className="muted">Enter dates</span>}</div>
    {f.membershipStatus==='cancelled'&&<div className="warning-card"><b>Membership marked cancelled</b><span>This will remain cancelled regardless of the expiry date.</span></div>}
    <label className="checkbox-row status-check"><input type="checkbox" checked={f.membershipStatus==='cancelled'} onChange={e=>setField('membershipStatus',e.target.checked?'cancelled':'active')}/><span>Mark this membership as cancelled</span></label>
    {Number(f.amountPaid)>0&&<div className="payment-block">
     <div className="payment-block-head"><div><b>Historical payment</b><span>Record the amount already collected for this membership.</span></div></div>
     {!methods.length&&<div className="warning-card"><b>No payment methods enabled</b><span>Enable at least one payment method in Settings before recording a historical payment.</span></div>}
     <div className="form-grid">
      <Field label="Payment date *"><input type="date" min={f.joinDate} max={gymToday} required aria-invalid={!!fieldErrors.paymentDate} value={f.paymentDate} onChange={e=>setField('paymentDate',e.target.value)}/><small className={fieldErrors.paymentDate?'field-error':'field-help'}>{fieldErrors.paymentDate||'Date the payment was actually received.'}</small></Field>
      <Field label="Payment method *"><select required disabled={!methods.length} value={f.paymentMethod} onChange={e=>setField('paymentMethod',e.target.value)}>{methods.map(x=><option key={x}>{String(x).replaceAll('_',' ')}</option>)}</select></Field>
      <Field label="Transaction reference"><input maxLength={120} value={f.reference} onChange={e=>setField('reference',e.target.value)}/></Field>
     </div>
     <Field label="Payment notes"><textarea maxLength={500} value={f.paymentNotes} onChange={e=>setField('paymentNotes',e.target.value)}/></Field>
    </div>}
   </div>}
  </div>
  <div className="import-savebar">
   <div className="save-state"><span className={saveState==='saving'?'saving-dot':saveState==='success'?'success-dot':''}></span><div><b>{saveState==='saving'?'Saving…':'Ready to import'}</b><small>{saveState==='saving'?(saveStage||'Please keep this window open while your record is being saved.'):(noMethods?'A payment method is required for a paid import.':'Review the details, then import this member.')}</small></div></div>
   <div className="form-actions"><button type="button" className="secondary" disabled={busy} onClick={onClose}>Cancel</button><button className="primary import-submit" disabled={busy||duplicateBlocked||noMethods}>{busy?<><span className="button-spinner"/>Saving…</>:noMethods?'Enable a payment method first':'Import old member'}</button></div>
  </div>
 </form></Sheet>
}
export function MemberForm({gymId,isAdmin,onClose,onSaved,prefill}:{gymId:string;isAdmin:boolean;onClose:()=>void;onSaved:(memberId?:string)=>void;prefill?:any}){
 const[packages,setPackages]=useState<Package[]>([]),[staff,setStaff]=useState<Staff[]>([]),[methods,setMethods]=useState<string[]>(METHODS),[dup,setDup]=useState<any[]>([]),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const[f,setF]=useState<any>({...{name:'',phone:'',email:'',dob:'',gender:'',address:'',emergencyContact:'',emergencyPhone:'',memberMode:'auto',memberId:'',packageId:'',duration:1,joinDate:today(),startDate:today(),price:0,discount:0,amountPaid:0,paymentMethod:'cash',reference:'',notes:'',endDate:'',coach:'',allowDuplicate:false,photo:null},...(prefill||{}),joinDate:prefill?.joinDate||today(),startDate:prefill?.startDate||today()});
 useEffect(()=>{Promise.all([loadPackages(gymId,false),loadStaff(gymId),loadPaymentMethodSettings(gymId)]).then(([p,s,ms])=>{setPackages(p);setStaff(s);const enabled=ms.filter((m:any)=>m.enabled).map((m:any)=>m.payment_method);setMethods(enabled);setF((old:any)=>({...old,paymentMethod:enabled.includes(old.paymentMethod)?old.paymentMethod:(enabled[0]||old.paymentMethod),packageId:p.some((x:any)=>x.id===old.packageId)?old.packageId:'',coach:s.some((x:any)=>x.id===old.coach&&x.status==='active')?old.coach:''}));setError('')}).catch((x:any)=>setError(humanError(x)))},[gymId]);
 const pkg=packages.find(x=>x.id===f.packageId),price=pkg?Number(pkg.price):Number(f.price||0),duration=pkg?pkg.duration_months:Number(f.duration||1),final=Math.max(price-Number(f.discount||0),0),balance=Math.max(final-Number(f.amountPaid||0),0);
 const blur=async()=>{if(!f.phone.trim())return;try{setDup(await findMemberByPhone(gymId,f.phone.trim()))}catch{}};
 const save=async(e:React.FormEvent)=>{e.preventDefault();setBusy(true);setError('');try{const id=await createMember({gymId,name:f.name,phone:f.phone,email:f.email,dob:f.dob||null,gender:f.gender||null,address:f.address||null,emergencyContact:f.emergencyContact||null,emergencyPhone:f.emergencyPhone||null,memberId:f.memberMode==='manual'?f.memberId:null,packageId:f.packageId||null,durationMonths:f.packageId?null:duration,joinDate:f.joinDate,startDate:f.startDate,price:f.packageId?null:price,discount:Number(f.discount),amountPaid:Number(f.amountPaid),paymentMethod:f.paymentMethod,transactionReference:f.reference||null,paymentNotes:f.notes||null,manualEndDate:f.endDate||null,assignedCoachId:f.coach||null,allowDuplicatePhone:f.allowDuplicate});if(f.photo)await uploadMemberPhoto(gymId,id,f.photo);onSaved(id)}catch(x:any){setError(humanError(x))}finally{setBusy(false)}};
 return <Sheet title="Add member" onClose={onClose}><form className="form" onSubmit={save}>
 <div className="form-section"><h3>Personal details</h3><div className="form-grid"><Field label="Full name *"><input required value={f.name} onChange={e=>setF({...f,name:e.target.value})}/></Field><Field label="Mobile *"><input required inputMode="tel" value={f.phone} onBlur={blur} onChange={e=>setF({...f,phone:e.target.value})}/></Field><Field label="Email"><input type="email" value={f.email} onChange={e=>setF({...f,email:e.target.value})}/></Field><Field label="DOB"><input type="date" value={f.dob} onChange={e=>setF({...f,dob:e.target.value})}/></Field><Field label="Gender"><select value={f.gender} onChange={e=>setF({...f,gender:e.target.value})}><option value="">Select</option><option>Male</option><option>Female</option><option>Other</option></select></Field><Field label="Emergency contact"><input value={f.emergencyContact} onChange={e=>setF({...f,emergencyContact:e.target.value})}/></Field><Field label="Emergency phone"><input value={f.emergencyPhone} onChange={e=>setF({...f,emergencyPhone:e.target.value})}/></Field><Field label="Assigned coach"><select value={f.coach} onChange={e=>setF({...f,coach:e.target.value})}><option value="">Unassigned</option>{staff.map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select></Field></div><Field label="Address"><textarea value={f.address} onChange={e=>setF({...f,address:e.target.value})}/></Field><Field label="Profile photo (max 5 MB)"><input type="file" accept="image/jpeg,image/png,image/webp" onChange={e=>{const file=e.target.files?.[0]||null;if(file&&file.size>5*1024*1024){setError('Profile photo must be 5 MB or smaller.');setF({...f,photo:null})}else{setError('');setF({...f,photo:file})}}}/></Field>{dup.length>0&&<div className="warning-card"><b>Existing member found</b><span>{dup.map(x=>x.name+' · #'+x.member_id).join(' | ')}</span>{isAdmin&&<label><input type="checkbox" checked={f.allowDuplicate} onChange={e=>setF({...f,allowDuplicate:e.target.checked})}/> Continue with duplicate mobile</label>}</div>}</div>
 <div className="form-section"><h3>Member ID</h3><div className="toggle-choice"><button type="button" className={f.memberMode==='auto'?'selected':''} onClick={()=>setF({...f,memberMode:'auto'})}>Automatic</button><button type="button" className={f.memberMode==='manual'?'selected':''} onClick={()=>setF({...f,memberMode:'manual'})}>Manual</button></div>{f.memberMode==='manual'&&<Field label="Member ID *"><input required value={f.memberId} onChange={e=>setF({...f,memberId:e.target.value})}/></Field>}</div>
 <div className="form-section"><h3>Membership + payment</h3><div className="package-choice-grid">{packages.map(p=><button type="button" className={f.packageId===p.id?'package-choice selected':'package-choice'} key={p.id} onClick={()=>setF({...f,packageId:p.id,price:p.price,duration:p.duration_months})}><b>{p.name}</b><span>{money(p.price)}</span></button>)}<button type="button" className={!f.packageId?'package-choice selected':'package-choice'} onClick={()=>setF({...f,packageId:''})}><b>Custom</b><span>Any duration</span></button></div><div className="form-grid"><Field label="Joining date"><input type="date" value={f.joinDate} onChange={e=>setF({...f,joinDate:e.target.value})}/></Field><Field label="Membership start"><input type="date" value={f.startDate} onChange={e=>setF({...f,startDate:e.target.value})}/></Field>{!f.packageId&&<><Field label="Custom price *"><input required type="number" min="0" step="0.01" value={f.price} onChange={e=>setF({...f,price:Number(e.target.value)})}/></Field><Field label="Duration (months)"><input required type="number" min="1" value={f.duration} onChange={e=>setF({...f,duration:Number(e.target.value)})}/></Field></>}{isAdmin&&<Field label="Manual end date"><input type="date" value={f.endDate} onChange={e=>setF({...f,endDate:e.target.value})}/></Field>}<Field label="Discount"><input type="number" min="0" value={f.discount} onChange={e=>setF({...f,discount:Number(e.target.value)})}/></Field><Field label="Amount paid"><input type="number" min="0" max={final} value={f.amountPaid} onChange={e=>setF({...f,amountPaid:Number(e.target.value)})}/></Field><Field label="Payment method"><select value={f.paymentMethod} onChange={e=>setF({...f,paymentMethod:e.target.value})}>{methods.map(x=><option key={x}>{x}</option>)}</select></Field><Field label="Reference"><input value={f.reference} onChange={e=>setF({...f,reference:e.target.value})}/></Field></div><div className="calculation"><Summary title="Price" value={money(price)}/><Summary title="Final" value={money(final)}/><Summary title="Paid" value={money(f.amountPaid)}/><Summary title="Balance" value={money(balance)}/></div><Field label="Payment notes"><textarea value={f.notes} onChange={e=>setF({...f,notes:e.target.value})}/></Field></div>{error&&<div className="error-inline">{error}</div>}<button className="primary full" disabled={busy||(!methods.length&&Number(f.amountPaid)>0)}>{busy?'Saving…':methods.length?'Save member + membership + payment':'Configure at least one payment method or set payment to 0'}</button></form></Sheet>
}

function MemberClasses({gymId,member,onRefresh}:{gymId:string;member:Member;onRefresh:()=>void}){
 const[rows,setRows]=useState<any[]>([]),[error,setError]=useState('');
 const load=async()=>{try{setRows(await loadMemberClassBookings(gymId,member.id,new Date().toISOString()));setError('')}catch(x:any){setError(humanError(x))}};
 useEffect(()=>{load()},[gymId,member.id]);
 return <div className="member-class-panel"><div className="section-title"><h3>Upcoming class bookings</h3><button type="button" className="primary small" onClick={()=>window.dispatchEvent(new CustomEvent('gym:class_book',{detail:member}))}><CalendarDays size={14}/> Book class</button></div>{error&&<div className="error-inline">{humanError(error)}</div>}{!rows.length?<Empty title="No class bookings" text="Book this member into a scheduled class or join a waitlist."/>:<DataTable rows={rows.filter(x=>x.session_status!=='cancelled').map((x:any)=>({_id:x.id,Class:x.class_name,Start:x.start_at,Instructor:x.instructor_name,Status:x.status,Waitlist:x.waitlist_position||'—'}))} actions={(r:any)=>{const booking=rows.find((x:any)=>x.id===r._id);return booking&&['booked','waitlisted'].includes(booking.status)?<button type="button" className="danger-action small" onClick={async()=>{try{const result=await cancelClassBooking(gymId,booking.id);if(result.promoted)alert('Booking cancelled and the next waitlisted member was promoted.');await load();onRefresh()}catch(x:any){setError(humanError(x))}}}>Cancel</button>:null}}/>}</div>
}

export function MemberProfile({gymId,member,onClose,onRefresh,isAdmin}:{gymId:string;member:Member;onClose:()=>void;onRefresh:()=>void;isAdmin:boolean}){
 const[data,setData]=useState<any>(),[tab,setTab]=useState('overview'),[edit,setEdit]=useState(false),[draft,setDraft]=useState<any>(member),[error,setError]=useState(''),[attendanceBusy,setAttendanceBusy]=useState(false);
 useEffect(()=>{
  let live=true;
  setData(undefined);
  loadMemberDetail(gymId,member.id).then(x=>live&&setData(x)).catch(x=>live&&setError(humanError(x)));
  return()=>{live=false};
 },[gymId,member.id]);
 if(!data)return <Sheet title={member.name} onClose={onClose}><div className="skeleton"/><div className="skeleton"/></Sheet>;
 const m=data.member as Member;
 const openSession=(data.attendance||[]).find((x:any)=>!x.check_out);
 const checkedIn=!!openSession;
 const checkIn=async()=>{
  setAttendanceBusy(true);setError('');
  try{
   await recordAttendance(gymId,m.id);
   const fresh=await loadMemberDetail(gymId,m.id);
   setData(fresh);
   onRefresh();
  }catch(x:any){setError(humanError(x))}
  finally{setAttendanceBusy(false)}
 };
 const checkOut=async()=>{
  if(!openSession)return;
  setAttendanceBusy(true);setError('');
  try{
   await checkoutAttendance(gymId,openSession.id);
   const fresh=await loadMemberDetail(gymId,m.id);
   setData(fresh);
   onRefresh();
  }catch(x:any){setError(humanError(x))}
  finally{setAttendanceBusy(false)}
 };
 const removeMember=async()=>{
  const confirmed=window.confirm('Delete this member? Members with financial or attendance history will be archived instead of permanently deleted.');
  if(!confirmed)return;
  setAttendanceBusy(true);setError('');
  try{
   const result=await deleteMember(gymId,m.id);
   onRefresh();
   if(result==='deleted') onClose();
   else setError('Member has historical records, so it was archived and removed from the active member list.');
  }catch(x:any){setError(humanError(x))}
  finally{setAttendanceBusy(false)}
 };
 return <Sheet title={m.name} onClose={onClose}>
  <div className="profile-hero"><div className="avatar xlarge">{initials(m.name)}</div><div><h2>{m.name}</h2><span>#{m.member_id} · {m.phone}</span><div><StatusTag value={m.membership_status||m.member_status}/></div></div></div>
  <div className="action-grid">
   <button type="button" className="primary" onClick={()=>window.dispatchEvent(new CustomEvent('gym:renew',{detail:m}))}><RefreshCw size={16}/> Renew</button>
   <button type="button" className="secondary" onClick={()=>window.dispatchEvent(new CustomEvent('gym:payment',{detail:m}))}><CircleDollarSign size={16}/> Payment</button>
   <button type="button" className="secondary" disabled={checkedIn||attendanceBusy} onClick={checkIn}><UserCheck size={16}/> {attendanceBusy&&!checkedIn?'Checking in…':checkedIn?'Checked in':'Check in'}</button>
   {checkedIn&&<button type="button" className="secondary" disabled={attendanceBusy} onClick={checkOut}><UserCheck size={16}/> {attendanceBusy?'Checking out…':'Check out'}</button>}
   <button type="button" className="secondary" onClick={()=>window.open('https://wa.me/'+m.phone.replace(/\D/g,''),'_blank','noopener,noreferrer')}><MessageCircle size={16}/> WhatsApp</button>
   <a className="secondary" href={'tel:'+m.phone}><Phone size={16}/> Call</a>
   <button type="button" className="secondary" disabled={!m.membership_uuid} onClick={()=>window.dispatchEvent(new CustomEvent('gym:freeze',{detail:m}))}><Snowflake size={16}/> Freeze</button>
   <button type="button" className="secondary" disabled={!m.membership_uuid} onClick={()=>window.dispatchEvent(new CustomEvent('gym:cancel',{detail:m}))}><Trash2 size={16}/> Cancel</button>
   {isAdmin&&<button type="button" className="danger-action" disabled={attendanceBusy} onClick={removeMember}><Trash2 size={16}/> Delete member</button>}
  </div>
  <div className="tab-row">{['overview','payments','membership','classes','attendance','notifications','activity'].map(x=><button type="button" key={x} className={tab===x?'active':''} onClick={()=>setTab(x)}>{x}</button>)}</div>
  {tab==='overview'&&<>
   <div className="section-title"><h3>Personal information</h3><button type="button" className="text-button" onClick={()=>{setDraft(m);setEdit(true)}}><Edit3 size={15}/> Edit</button></div>
   {edit?<div className="form"><div className="form-grid"><Field label="Name"><input value={draft.name} onChange={e=>setDraft({...draft,name:e.target.value})}/></Field><Field label="Phone"><input value={draft.phone} onChange={e=>setDraft({...draft,phone:e.target.value})}/></Field><Field label="Email"><input value={draft.email||''} onChange={e=>setDraft({...draft,email:e.target.value})}/></Field><Field label="DOB"><input type="date" value={draft.dob||''} onChange={e=>setDraft({...draft,dob:e.target.value})}/></Field><Field label="Gender"><input value={draft.gender||''} onChange={e=>setDraft({...draft,gender:e.target.value})}/></Field><Field label="Emergency phone"><input value={draft.emergency_phone||''} onChange={e=>setDraft({...draft,emergency_phone:e.target.value})}/></Field></div><Field label="Address"><textarea value={draft.address||''} onChange={e=>setDraft({...draft,address:e.target.value})}/></Field><div className="row-actions"><button type="button" className="primary" onClick={async()=>{try{await (await import('../data')).updateMember(gymId,m.id,{name:draft.name,phone:draft.phone,email:draft.email||null,dob:draft.dob||null,gender:draft.gender||null,address:draft.address||null,emergency_contact:draft.emergency_contact||null,emergency_phone:draft.emergency_phone||null,assigned_coach_id:draft.assigned_coach_id||null});setEdit(false);const fresh=await loadMemberDetail(gymId,m.id);setData(fresh);onRefresh()}catch(x:any){setError(humanError(x))}}}>Save</button><button type="button" className="secondary" onClick={()=>setEdit(false)}>Cancel</button></div></div>:<div className="detail-grid"><Detail label="Member ID" value={m.member_id}/><Detail label="Mobile" value={m.phone}/><Detail label="Email" value={m.email||'—'}/><Detail label="DOB" value={m.dob||'—'}/><Detail label="Gender" value={m.gender||'—'}/><Detail label="Emergency" value={m.emergency_contact||'—'}/><Detail label="Address" value={m.address||'—'}/><Detail label="Coach" value={m.assigned_coach_name||'Unassigned'}/></div>}
   <div className="current-membership"><div><b>{m.package_name||'Custom package'}</b><span>{m.start_date||'—'} → {m.end_date||'—'}</span></div><div><strong>{money(Number(m.final_amount||0))}</strong><span>Paid {money(Number(m.paid_amount||0))} · Balance {money(Number(m.balance_amount||0))}</span></div></div>
  </>}
  {tab==='payments'&&<DataTable rows={(data.payments||[]).map((p:any)=>({Date:p.payment_date,Amount:money(Number(p.amount)),Refunded:money(Number(p.refund_amount||0)),Net:money(Number(p.net_amount||0)),Method:p.payment_method,Reference:p.transaction_reference,Status:p.status}))}/>}
  {tab==='membership'&&<DataTable rows={(data.memberships||[]).map((x:any)=>({Package:x.membership_packages?.name||'Custom',Type:x.membership_type,Start:x.start_date,End:x.end_date,Amount:money(Number(x.final_amount||0)),Status:x.status}))}/>}
  {tab==='classes'&&<MemberClasses gymId={gymId} member={m} onRefresh={onRefresh}/>}
  {tab==='attendance'&&<DataTable rows={(data.attendance||[]).map((x:any)=>({Date:x.check_in,CheckIn:x.check_in,CheckOut:x.check_out,Method:x.method}))}/>}
  {tab==='notifications'&&<DataTable rows={(data.notifications||[]).map((n:any)=>({Type:n.notification_type,Channel:n.channel,Status:n.status,Sent:n.sent_at,Message:n.message_body}))}/>}
  {tab==='activity'&&<DataTable rows={(data.audit||[]).map((x:any)=>({Action:x.action,Entity:x.entity_type,When:x.created_at}))}/>}
  {error&&<div className="error-inline">{error}</div>}
 </Sheet>
}
