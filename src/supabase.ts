import { createClient } from '@supabase/supabase-js';

const url=(import.meta.env.VITE_SUPABASE_URL||'').trim();
const key=(import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY||import.meta.env.VITE_SUPABASE_ANON_KEY||'').trim();

export const supabaseConfig={urlConfigured:Boolean(url),keyConfigured:Boolean(key)};
const SESSION_KEY='gym_app_session';

function storedToken(){try{return localStorage.getItem(SESSION_KEY)}catch{return null}}

function buildClient(token:string|null){
 if(!url||!key)return null;
 return createClient(url,key,{global:{headers:token?{'x-gym-session':token}:{}}});
}

export let supabase=buildClient(storedToken());

export function setAppSession(token:string|null){
 try{if(token)localStorage.setItem(SESSION_KEY,token);else localStorage.removeItem(SESSION_KEY)}catch{}
 supabase=buildClient(token);
}

export function getStoredAppSession(){return storedToken()}
