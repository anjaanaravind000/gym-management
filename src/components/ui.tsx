import React,{useEffect} from 'react';
import type { LucideIcon } from 'lucide-react';
import { Bell, Check, ChevronLeft, ChevronRight, Dumbbell, FileText, LogOut, MoreHorizontal, X } from 'lucide-react';
import { money } from '../data';
const formatLabel=(value:string)=>String(value||'').replaceAll('_',' ').replace(/\b\w/g,c=>c.toUpperCase());

export { money };

export function Brand(){return <div className="brand"><div className="brand-mark"><Dumbbell size={19}/></div><div><b>FitCore</b><span>Gym Management</span></div></div>}
export function PageHeader({title,subtitle,action}:{title:string;subtitle:string;action?:React.ReactNode}){return <header className="topbar"><div><div className="eyebrow">GYM MANAGEMENT</div><h1>{title}</h1><p>{subtitle}</p></div>{action}</header>}
export function Panel({title,extra,children}:{title:string;extra?:React.ReactNode;children:React.ReactNode}){return <section className="panel"><div className="section-title"><div><h2>{title}</h2></div>{extra}</div>{children}</section>}
export function Sheet({title,onClose,children}:{title:string;onClose:()=>void;children:React.ReactNode}){
 useEffect(()=>{
  const previous=document.body.style.overflow;
  document.body.style.overflow='hidden';
  const onKey=(e:KeyboardEvent)=>{if(e.key==='Escape')onClose()};
  window.addEventListener('keydown',onKey);
  return()=>{document.body.style.overflow=previous;window.removeEventListener('keydown',onKey)};
 },[onClose]);
 return <div className="sheet-backdrop" role="presentation" onMouseDown={e=>e.currentTarget===e.target&&onClose()}>
  <div className="sheet" role="dialog" aria-modal="true" aria-label={title}>
   <div className="sheet-handle"/>
   <div className="sheet-head"><h2>{title}</h2><button type="button" className="icon-button" onClick={onClose} aria-label="Close"><X size={18}/></button></div>
   {children}
  </div>
 </div>
}
export function Field({label,children}:{label:string;children:React.ReactNode}){return <label className="field"><span>{label}</span>{children}</label>}
export function Toggle({label,checked,onChange}:{label?:string;checked:boolean;onChange:(v:boolean)=>void}){return <label className="toggle-row">{label&&<span>{label}</span>}<button type="button" className={checked?'switch on':'switch'} onClick={()=>onChange(!checked)} aria-pressed={checked}><i/></button></label>}
export function Metric({title,value,detail,warning}:{title:string;value:React.ReactNode;detail?:string;warning?:boolean}){return <div className={warning?'metric-card warn':'metric-card'}><span>{title}</span><strong>{value}</strong>{detail&&<small>{detail}</small>}</div>}
export function Quick({label,icon:Icon,onClick}:{label:string;icon:LucideIcon;onClick:()=>void}){return <button className="quick" onClick={onClick}><span><Icon size={20}/></span><b>{label}</b><ChevronRight size={15}/></button>}
export function StatusTag({value}:{value:string}){return <span className={'status-tag '+value}><i/>{formatLabel(value)}</span>}
export function Empty({title,text,action}:{title:string;text:string;action?:React.ReactNode}){return <div className="empty"><FileText size={27}/><h3>{title}</h3><p>{text}</p>{action}</div>}
export function Pagination({page,pages,onPage}:{page:number;pages:number;onPage:(p:number)=>void}){return <div className="pagination"><button className="secondary small" disabled={page<=0} onClick={()=>onPage(page-1)}><ChevronLeft size={15}/> Previous</button><span>{page+1} / {pages}</span><button className="secondary small" disabled={page>=pages-1} onClick={()=>onPage(page+1)}>Next <ChevronRight size={15}/></button></div>}
export function Summary({title,value}:{title:string;value:React.ReactNode}){return <div className="summary-item"><span>{title}</span><b>{value}</b></div>}
export function Detail({label,value}:{label:string;value:string}){return <div className="detail"><span>{label}</span><b>{value}</b></div>}
export function DataTable({rows}:{rows:any[]}){if(!rows.length)return <Empty title="No data" text="Nothing to show yet."/>;const cols=Object.keys(rows[0]);return <div className="table-wrap"><table><thead><tr>{cols.map(c=><th key={c}>{formatLabel(c)}</th>)}</tr></thead><tbody>{rows.map((r,i)=><tr key={i}>{cols.map(c=><td key={c}>{renderCell(c,r[c])}</td>)}</tr>)}</tbody></table></div>}
export function renderCell(key:string,value:any){if(value===null||value===undefined||value==='')return '—';const k=key.toLowerCase();if(k.includes('amount')||k.includes('revenue')||k.includes('balance')||k.includes('price')||k==='net_amount'||k==='refund_amount'||k==='total_amount')return money(Number(value));if(k.includes('date')||k.endsWith('_at')||k==='check_in'||k==='check_out')return String(value).includes('T')?new Date(value).toLocaleString('en-IN'):new Date(String(value)+'T00:00:00').toLocaleDateString('en-IN');return formatLabel(String(value))}
export function initials(name:string){return name.split(/\s+/).filter(Boolean).slice(0,2).map(x=>x[0]).join('').toUpperCase()||'GM'}
export function humanError(error:any){const s=error?.message||error?.error_description||'Something went wrong. Please try again.';const map:any={'Unauthorized':'You do not have permission to perform this action.','Member ID already exists':'That Member ID already exists.','Transaction reference already exists':'That transaction reference is already in use.','Payment amount must be greater than zero':'Enter a valid payment amount.','An existing member with this mobile number was found':'An existing member with this mobile number was found.'};return map[s]||s}
export function Skeleton(){return <div className="skeleton"/>}
export function LogoutButton(){return <button className="icon-button mini" title="Sign out" onClick={()=>undefined}><LogOut size={15}/></button>}
