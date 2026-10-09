import React,{useState}from'react';
import{Database,Download,ShieldCheck,AlertTriangle,CheckCircle2,Clock3}from'lucide-react';
import{exportGymBackup}from'../data';
import{Empty,Panel,PageHeader,humanError}from'../components/ui';

const labels:Record<string,string>={
 gyms:'Gym profile',gym_settings:'Gym settings',payment_method_settings:'Payment methods',users:'Staff profiles',user_permissions:'Staff permissions',login_accounts:'Login usernames',
 membership_packages:'Membership packages',members:'Members',memberships:'Membership history',membership_freezes:'Membership freezes',membership_cancellations:'Membership cancellations',
 payments:'Payments',refunds:'Refunds',attendance:'Attendance',expenses:'Expenses',leads:'Leads & CRM',gym_classes:'Classes',class_sessions:'Class sessions',class_bookings:'Class bookings',
 notification_templates:'Notification templates',notifications:'Notifications',notification_logs:'Notification delivery logs',audit_logs:'Audit history'
};

export function DataBackup({gymId,isAdmin}:{gymId:string;isAdmin:boolean}){
 const[busy,setBusy]=useState(false),[error,setError]=useState(''),[lastExport,setLastExport]=useState<{at:string;name:string;counts:Record<string,number>;total:number}|null>(null);
 const download=async()=>{
  setBusy(true);setError('');
  try{
   const backup=await exportGymBackup(gymId);
   if(backup?.format!=='gym-management-backup'||!backup?.data)throw new Error('The backup export returned an unexpected format.');
   const counts:Record<string,number>={};let total=0;
   for(const[key,value]of Object.entries(backup.data as Record<string,unknown>)){const n=Array.isArray(value)?value.length:0;counts[key]=n;total+=n}
   const filename='gym-management-backup-'+String(backup.exported_at||new Date().toISOString()).slice(0,10)+'-'+gymId.slice(0,8)+'.json';
   const blob=new Blob([JSON.stringify(backup,null,2)],{type:'application/json;charset=utf-8'});
   const href=URL.createObjectURL(blob),a=document.createElement('a');
   a.href=href;a.download=filename;document.body.appendChild(a);a.click();a.remove();URL.revokeObjectURL(href);
   setLastExport({at:String(backup.exported_at||new Date().toISOString()),name:filename,counts,total});
  }catch(e:any){setError(humanError(e))}
  finally{setBusy(false)}
 };
 if(!isAdmin)return <><PageHeader title="Data backup" subtitle="Protect your gym records."/><Empty title="Admin access required" text="Only a gym admin can export member and financial records."/></>;
 return <>
  <PageHeader title="Data backup" subtitle="Export a copy of the gym's business records that you can store securely outside this Supabase project."/>
  {error&&<div className="error-banner" role="alert">{error}</div>}
  <Panel title="Download gym data" extra={<span className="connected-badge"><ShieldCheck size={13}/> Admin only</span>}>
   <div className="backup-intro"><span className="backup-icon"><Database size={24}/></span><div><b>Portable JSON data export</b><p>Downloads a snapshot of business records for this gym using a permission-checked database function. It does not change or delete any live records.</p></div></div>
   <div className="backup-warning"><AlertTriangle size={17}/><div><b>Contains confidential information</b><span>The file includes member contact details and financial records. Store it in an encrypted, access-controlled location. Do not commit it to GitHub or share it publicly.</span></div></div>
   <button className="primary" disabled={busy} onClick={download}><Download size={16}/>{busy?'Preparing backup…':'Download data backup (.json)'}</button>
  </Panel>
  {lastExport&&<Panel title="Last export on this screen" extra={<span className="connected-badge"><CheckCircle2 size={13}/> Download generated</span>}>
   <div className="backup-last"><Clock3 size={17}/><div><b>{lastExport.name}</b><span>Generated {new Date(lastExport.at).toLocaleString()}</span><span>{lastExport.total.toLocaleString()} records across the included datasets</span></div></div>
   <div className="backup-count-grid">{Object.entries(lastExport.counts).filter(([,n])=>n>0).map(([key,n])=><div key={key}><span>{labels[key]||key}</span><b>{n.toLocaleString()}</b></div>)}</div>
  </Panel>}
  <Panel title="What is—and isn't—included">
   <div className="backup-scope"><b>Included</b><span>Gym settings, staff profiles and permission assignments, member records, memberships/freezes/cancellations, payment and refund history, attendance, expenses, leads, classes/bookings, notifications, delivery logs, templates, and audit history.</span></div>
   <div className="backup-scope"><b>Excluded for security</b><span>Password hashes, active login sessions, WhatsApp access tokens, Meta App Secret, webhook verification token, and worker secrets.</span></div>
   <div className="backup-scope"><b>Stored files</b><span>Member photo paths are included in the records, but the actual image/file binaries in Supabase Storage are not part of this JSON export.</span></div>
   <div className="backup-scope"><b>Restore limitation</b><span>This file is a portable data export, not an automatic restore file. Restoring requires a reviewed import process, and excluded credentials/integration secrets must be recreated.</span></div>
  </Panel>
 </>;
}
