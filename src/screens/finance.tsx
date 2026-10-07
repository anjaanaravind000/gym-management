import React,{useEffect,useState}from'react';
import{Edit3,Plus,RefreshCw,Trash2}from'lucide-react';
import{loadExpenses,loadFinanceSummary,loadPaymentMethodSettings,saveExpense,voidExpense,localDateOffset,localToday,money}from'../data';
import{DataTable,Empty,Field,Metric,Panel,PageHeader,Pagination,Sheet,humanError}from'../components/ui';

const CATEGORIES=['Rent','Utilities','Salaries','Equipment','Maintenance','Marketing','Cleaning','Supplies','Taxes','Other'];

function presetDates(preset:string){
 const today=localToday();
 if(preset==='today')return{from:today,to:today};
 if(preset==='week')return{from:localDateOffset(today,-6),to:today};
 if(preset==='month')return{from:today.slice(0,7)+'-01',to:today};
 if(preset==='last'){
  const firstThis=today.slice(0,7)+'-01';
  const last=localDateOffset(firstThis,-1);
  return{from:last.slice(0,7)+'-01',to:last};
 }
 return{from:today.slice(0,4)+'-01-01',to:today};
}

export function Finance({gymId,refresh}:{gymId:string;refresh:number}){
 const[preset,setPreset]=useState('month');
 const[from,setFrom]=useState(presetDates('month').from);
 const[to,setTo]=useState(localToday());
 const[summary,setSummary]=useState<any>(null);
 const[rows,setRows]=useState<any[]>([]);
 const[page,setPage]=useState(0);
 const[count,setCount]=useState(0);
 const[q,setQ]=useState('');
 const[status,setStatus]=useState('posted');
 const[editing,setEditing]=useState<any|null>(null);
 const[busy,setBusy]=useState(true);
 const[error,setError]=useState('');
 const size=25;

 useEffect(()=>{
  const d=preset==='custom'?{from,to}:presetDates(preset);
  setFrom(d.from);
  setTo(d.to);
  setPage(0);
 },[preset]);

 const load=async()=>{
  setBusy(true);
  try{
   const[s,e]=await Promise.all([
    loadFinanceSummary(gymId,from,to),
    loadExpenses({gymId,page,pageSize:size,from,to,q,status})
   ]);
   setSummary(s);
   setRows(e.rows);
   setCount(e.count);
   setError('');
  }catch(x:any){
   setError(humanError(x));
  }finally{
   setBusy(false);
  }
 };

 useEffect(()=>{load()},[gymId,from,to,q,status,page,refresh]);

 return <div>
  <PageHeader
   title="Finance"
   subtitle="Track operating expenses, net revenue and real profit."
   action={
    <div className="toolbar-actions">
     <select className="compact-select" value={preset} onChange={e=>setPreset(e.target.value)}>
      <option value="today">Today</option>
      <option value="week">Last 7 days</option>
      <option value="month">This Month</option>
      <option value="last">Last Month</option>
      <option value="year">This Year</option>
      <option value="custom">Custom</option>
     </select>
     <button className="icon-button" onClick={load} title="Refresh"><RefreshCw size={17}/></button>
     <button
      className="primary"
      onClick={()=>setEditing({id:null,expense_date:localToday(),category:'Rent',description:'',amount:0,payment_method:'cash',vendor:'',reference:'',notes:''})}
     >
      <Plus size={16}/> Add expense
     </button>
    </div>
   }
  />

  {error&&<div className="error-banner">{error}</div>}

  {preset==='custom'&&
   <div className="filters-row">
    <Field label="From"><input type="date" value={from} onChange={e=>{setFrom(e.target.value);setPage(0)}}/></Field>
    <Field label="To"><input type="date" value={to} onChange={e=>{setTo(e.target.value);setPage(0)}}/></Field>
   </div>
  }

  <div className="kpi-grid">
   <Metric title="Gross revenue" value={busy?'—':money(Number(summary?.gross_revenue||0))}/>
   <Metric title="Refunds" value={busy?'—':money(Number(summary?.refunds||0))}/>
   <Metric title="Operating expenses" value={busy?'—':money(Number(summary?.expenses||0))}/>
   <Metric title="Net profit" value={busy?'—':money(Number(summary?.profit||0))} warning={Number(summary?.profit||0)<0}/>
  </div>

  <Panel title={status==='voided'?'Voided expenses':'Expense ledger'} extra={<span className="muted">{count} records</span>}>
   <div className="filters-row">
    <input placeholder="Search category, description, vendor or reference" value={q} onChange={e=>{setQ(e.target.value);setPage(0)}}/>
    <select value={status} onChange={e=>{setStatus(e.target.value);setPage(0)}}>
     <option value="posted">Posted</option>
     <option value="voided">Voided</option>
     <option value="all">All</option>
    </select>
   </div>

   {!busy&&!rows.length?
    <Empty title="No expenses" text="Operating expenses entered for this period will appear here."/>
    :
    <DataTable
     rows={rows.map((x:any)=>({
      _id:x.id,
      Date:x.expense_date,
      Category:x.category,
      Description:x.description,
      Vendor:x.vendor||'—',
      Method:x.payment_method,
      Amount:money(Number(x.amount)),
      Status:x.status
     }))}
     actions={(row:any)=>{
      const original=rows.find((x:any)=>x.id===row._id);
      return <div className="row-actions">
       {row.Status==='posted'&&original&&<>
        <button className="icon-button mini" title="Edit" onClick={()=>setEditing(original)}><Edit3 size={13}/></button>
        <button
         className="danger-action small"
         onClick={async()=>{
          if(!window.confirm('Void this expense?'))return;
          try{await voidExpense(gymId,row._id,'Voided from Finance');await load()}
          catch(x:any){setError(humanError(x))}
         }}
        >
         <Trash2 size={13}/> Void
        </button>
       </>}
      </div>
     }}
    />
   }
  </Panel>

  <Pagination page={page} pages={Math.max(1,Math.ceil(count/size))} onPage={setPage}/>

  {editing&&
   <ExpenseEditor
    gymId={gymId}
    initial={editing}
    onClose={()=>setEditing(null)}
    onSaved={()=>{setEditing(null);load()}}
   />
  }
 </div>;
}

function ExpenseEditor({gymId,initial,onClose,onSaved}:{gymId:string;initial:any;onClose:()=>void;onSaved:()=>void}){
 const[f,setF]=useState(initial);
 const[methods,setMethods]=useState<string[]>([]);
 const[error,setError]=useState('');
 const[busy,setBusy]=useState(false);

 useEffect(()=>{
  loadPaymentMethodSettings(gymId)
   .then(x=>setMethods(x.filter((m:any)=>m.enabled).map((m:any)=>m.payment_method)))
   .catch((x:any)=>setError(humanError(x)));
 },[gymId]);

 async function submit(e:React.FormEvent){
  e.preventDefault();
  setBusy(true);
  setError('');
  try{
   await saveExpense({
    gymId,id:f.id,expenseDate:f.expense_date,category:f.category,description:f.description,
    amount:Number(f.amount),paymentMethod:f.payment_method,vendor:f.vendor,reference:f.reference,notes:f.notes
   });
   onSaved();
  }catch(x:any){
   setError(humanError(x));
  }finally{
   setBusy(false);
  }
 }

 return <Sheet title={f.id?'Edit expense':'Add expense'} onClose={onClose}>
  <form className="form" onSubmit={submit}>
   <div className="form-grid">
    <Field label="Date"><input required type="date" value={f.expense_date} onChange={e=>setF({...f,expense_date:e.target.value})}/></Field>
    <Field label="Category"><select value={f.category} onChange={e=>setF({...f,category:e.target.value})}>{CATEGORIES.map(x=><option key={x}>{x}</option>)}</select></Field>
    <Field label="Description"><input required value={f.description} onChange={e=>setF({...f,description:e.target.value})}/></Field>
    <Field label="Amount"><input required min="0.01" step="0.01" type="number" value={f.amount} onChange={e=>setF({...f,amount:Number(e.target.value)})}/></Field>
    <Field label="Payment method"><select value={f.payment_method} onChange={e=>setF({...f,payment_method:e.target.value})}>{methods.map(x=><option key={x}>{x}</option>)}</select></Field>
    <Field label="Vendor"><input value={f.vendor||''} onChange={e=>setF({...f,vendor:e.target.value})}/></Field>
    <Field label="Reference"><input value={f.reference||''} onChange={e=>setF({...f,reference:e.target.value})}/></Field>
   </div>
   <Field label="Notes"><textarea value={f.notes||''} onChange={e=>setF({...f,notes:e.target.value})}/></Field>
   {!methods.length&&<div className="warning-card">Enable at least one payment method in Settings before recording an expense.</div>}
   {error&&<div className="error-inline">{error}</div>}
   <button className="primary full" disabled={busy||!methods.length}>{busy?'Saving…':'Save expense'}</button>
  </form>
 </Sheet>;
}
