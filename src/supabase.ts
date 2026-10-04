import { createClient } from '@supabase/supabase-js';

const url = (import.meta.env.VITE_SUPABASE_URL || '').trim();
const key = (
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ||
  import.meta.env.VITE_SUPABASE_ANON_KEY ||
  ''
).trim();

export const supabaseConfig = {
  urlConfigured: Boolean(url),
  keyConfigured: Boolean(key),
};

export const supabase = url && key ? createClient(url, key) : null;
