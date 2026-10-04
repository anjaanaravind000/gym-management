import React,{useState}from'react';
import { ArrowRight, LockKeyhole, UserRound } from 'lucide-react';
import { loginWithPassword, bootstrapGym, type AppSession } from '../data';
import { Brand,Field } from './ui';

export function AuthScreen({onSignedIn}:{onSignedIn:(session:AppSession)=>Promise<void>|void}){
 const[username,setUsername]=useState(''),[password,setPassword]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 async function submit(e:React.FormEvent){
  e.preventDefault();setBusy(true);setError('');
  try{const session=await loginWithPassword(username,password);await onSignedIn(session);}
  catch(x:any){setError(x?.message||'Invalid username or password')}
  finally{setBusy(false)}
 }
 return <div className="auth-page"><div className="auth-card"><Brand/><div className="eyebrow">SECURE ACCESS</div><h1>Welcome back</h1><p>Sign in with your gym username and password.</p>
  <form className="form" onSubmit={submit}>
   <Field label="Username"><div className="input-with-icon"><UserRound size={16}/><input required autoComplete="username" value={username} onChange={e=>setUsername(e.target.value)} placeholder="Admin"/></div></Field>
   <Field label="Password"><div className="input-with-icon"><LockKeyhole size={16}/><input required type="password" autoComplete="current-password" value={password} onChange={e=>setPassword(e.target.value)} placeholder="Password"/></div></Field>
   {error&&<div className="error-inline">{error}</div>}
   <button className="primary full" disabled={busy}>{busy?'Signing in…':'Sign in'} <ArrowRight size={16}/></button>
  </form>
 </div></div>
}

export function SetupScreen({user,onDone}:{user:AppSession;onDone:()=>Promise<void>}){
 const[gym,setGym]=useState(''),[name,setName]=useState(user.display_name||''),[phone,setPhone]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 return <div className="auth-page"><div className="auth-card"><Brand/><div className="eyebrow">FIRST-TIME SETUP</div><h1>Set up your gym</h1><p>This creates your gym and prepares the standard packages and settings.</p>
  <form className="form" onSubmit={async e=>{e.preventDefault();setBusy(true);setError('');try{await bootstrapGym(name,'',phone,gym);await onDone()}catch(x:any){setError(x?.message||'Unable to create gym')}finally{setBusy(false)}}}>
   <Field label="Gym name"><input required value={gym} onChange={e=>setGym(e.target.value)} placeholder="FitCore Fitness"/></Field>
   <Field label="Owner name"><input required value={name} onChange={e=>setName(e.target.value)}/></Field>
   <Field label="Phone"><input value={phone} onChange={e=>setPhone(e.target.value)}/></Field>
   {error&&<div className="error-inline">{error}</div>}
   <button className="primary full" disabled={busy}>{busy?'Creating…':'Create gym'}</button>
  </form>
 </div></div>
}

export function ResetPassword({onDone}:{onDone:()=>void}){return null}
