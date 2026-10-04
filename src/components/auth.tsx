import React,{useState}from'react';
import { ArrowRight, Mail, LockKeyhole, Smartphone } from 'lucide-react';
import { supabase } from '../supabase';
import { Brand,Field } from './ui';

export function AuthScreen(){
 const[mode,setMode]=useState<'signin'|'signup'|'forgot'>('signin'); const[method,setMethod]=useState<'email'|'phone'>('email');
 const[email,setEmail]=useState(''),[password,setPassword]=useState(''),[name,setName]=useState(''),[phone,setPhone]=useState(''),[otp,setOtp]=useState(''),[otpSent,setOtpSent]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[error,setError]=useState('');
 async function submit(e:React.FormEvent){e.preventDefault();setBusy(true);setError('');setMessage('');
  try{
   if(mode==='forgot'){const r=await supabase!.auth.resetPasswordForEmail(email,{redirectTo:window.location.origin});if(r.error)throw r.error;setMessage('Password reset email sent.');return}
   if(method==='phone'){if(!otpSent){const r=await supabase!.auth.signInWithOtp({phone});if(r.error)throw r.error;setOtpSent(true);setMessage('OTP sent.');}else{const r=await supabase!.auth.verifyOtp({phone,token:otp,type:'sms'});if(r.error)throw r.error;}}
   else{const r=mode==='signin'?await supabase!.auth.signInWithPassword({email,password}):await supabase!.auth.signUp({email,password,options:{data:{full_name:name}}});if(r.error)throw r.error;if(mode==='signup'&&!r.data.session)setMessage('Account created. Check your email to confirm.');}
  }catch(x:any){setError(x?.message||'Something went wrong. Please try again.')}finally{setBusy(false)}
 }
 return <div className="auth-page"><div className="auth-card"><Brand/><div className="eyebrow">SECURE ACCESS</div><h1>{mode==='forgot'?'Reset password':mode==='signin'?'Welcome back':'Create owner account'}</h1><p>{mode==='forgot'?'Receive a secure reset link.':'Access your real gym data, transactions and reports.'}</p>
 {mode!=='forgot'&&<div className="toggle-choice"><button type="button" className={method==='email'?'selected':''} onClick={()=>{setMethod('email');setOtpSent(false)}}><Mail size={15}/> Email</button><button type="button" className={method==='phone'?'selected':''} onClick={()=>{setMethod('phone');setOtpSent(false)}}><Smartphone size={15}/> Mobile OTP</button></div>}
 <form className="form" onSubmit={submit}>{mode==='signup'&&method==='email'&&<Field label="Your name"><input required value={name} onChange={e=>setName(e.target.value)}/></Field>}
 {method==='phone'&&mode!=='forgot'?<><Field label="Mobile number"><input required inputMode="tel" value={phone} onChange={e=>setPhone(e.target.value)} placeholder="+91…"/></Field>{otpSent&&<Field label="One-time code"><input required inputMode="numeric" value={otp} onChange={e=>setOtp(e.target.value)}/></Field>}</>:<Field label="Email"><input required type="email" value={email} onChange={e=>setEmail(e.target.value)}/></Field>}
 {mode!=='forgot'&&method==='email'&&<Field label="Password"><input required minLength={6} type="password" value={password} onChange={e=>setPassword(e.target.value)}/></Field>}
 {error&&<div className="error-inline">{error}</div>}{message&&<div className="success-banner">{message}</div>}
 <button className="primary full" disabled={busy}>{busy?'Please wait…':mode==='forgot'?'Send reset email':method==='phone'?(otpSent?'Verify OTP':'Send OTP'):mode==='signin'?'Sign in':'Create account'} <ArrowRight size={16}/></button></form>
 {mode==='signin'&&<button className="text-button centered" onClick={()=>setMode('forgot')}>Forgot password?</button>}
 {mode==='forgot'&&<button className="text-button centered" onClick={()=>setMode('signin')}>Back to sign in</button>}
 {mode!=='forgot'&&<button className="text-button centered" onClick={()=>{setMode(mode==='signin'?'signup':'signin');setOtpSent(false)}}>{mode==='signin'?'First time? Create your account':'Already have an account? Sign in'}</button>}
 </div></div>
}
export function ResetPassword({onDone}:{onDone:()=>void}){const[p,setP]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 return <div className="auth-page"><div className="auth-card"><Brand/><h1>Set new password</h1><p>Use at least 8 characters.</p><form className="form" onSubmit={async e=>{e.preventDefault();setBusy(true);try{const r=await supabase!.auth.updateUser({password:p});if(r.error)throw r.error;await supabase!.auth.signOut();onDone()}catch(x:any){setError(x.message)}finally{setBusy(false)}}}><Field label="New password"><input required minLength={8} type="password" value={p} onChange={e=>setP(e.target.value)}/></Field>{error&&<div className="error-inline">{error}</div>}<button className="primary full" disabled={busy}>{busy?'Saving…':'Update password'}</button></form></div></div>}
export function SetupScreen({user,onDone}:{user:any;onDone:()=>Promise<void>}){const[gym,setGym]=useState(''),[name,setName]=useState(user.user_metadata?.full_name||''),[phone,setPhone]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 return <div className="auth-page"><div className="auth-card"><Brand/><div className="eyebrow">FIRST-TIME SETUP</div><h1>Set up your gym</h1><p>This creates your tenant and seeds standard packages, payment methods and reminder templates.</p><form className="form" onSubmit={async e=>{e.preventDefault();setBusy(true);try{await (await import('../data')).bootstrapGym(name,user.email||'',phone,gym);await onDone()}catch(x:any){setError(x.message)}finally{setBusy(false)}}}><Field label="Gym name"><input required value={gym} onChange={e=>setGym(e.target.value)} placeholder="FitCore Fitness"/></Field><Field label="Owner name"><input required value={name} onChange={e=>setName(e.target.value)}/></Field><Field label="Phone"><input value={phone} onChange={e=>setPhone(e.target.value)}/></Field>{error&&<div className="error-inline">{error}</div>}<button className="primary full" disabled={busy}>{busy?'Creating…':'Create gym'}</button></form></div></div>}
