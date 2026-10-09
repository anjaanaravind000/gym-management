-- Remove the legacy WhatsApp connection RPC that omitted Meta App Secret validation.
drop function if exists public.save_whatsapp_connection(uuid,text,text,text,text,text);

-- Restrict member photo access to real members and the caller's member-view/edit permission.
create or replace function private.can_access_member_photo(p_path text,p_permission permission_key)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public','private','pg_catalog'
as $$
declare v_gym_id uuid;v_member_id uuid;
begin
 if p_path is null or array_length(string_to_array(p_path,'/'),1) < 3 then return false; end if;
 begin
   v_gym_id:=split_part(p_path,'/',1)::uuid;
   v_member_id:=split_part(p_path,'/',2)::uuid;
 exception when invalid_text_representation then
   return false;
 end;
 if not private.has_permission(v_gym_id,p_permission) then return false; end if;
 return exists(select 1 from public.members m where m.id=v_member_id and m.gym_id=v_gym_id);
end
$$;
revoke all on function private.can_access_member_photo(text,permission_key) from public;
grant execute on function private.can_access_member_photo(text,permission_key) to anon,authenticated;

drop policy if exists "member photos select" on storage.objects;
drop policy if exists "member photos insert" on storage.objects;
drop policy if exists "member photos update" on storage.objects;
drop policy if exists "member photos delete" on storage.objects;

create policy "member photos select" on storage.objects for select to anon,authenticated
using (bucket_id='member-photos' and private.can_access_member_photo(name,'members.view'::permission_key));
create policy "member photos insert" on storage.objects for insert to anon,authenticated
with check (bucket_id='member-photos' and private.can_access_member_photo(name,'members.edit'::permission_key));
create policy "member photos update" on storage.objects for update to anon,authenticated
using (bucket_id='member-photos' and private.can_access_member_photo(name,'members.edit'::permission_key))
with check (bucket_id='member-photos' and private.can_access_member_photo(name,'members.edit'::permission_key));
create policy "member photos delete" on storage.objects for delete to anon,authenticated
using (bucket_id='member-photos' and private.can_access_member_photo(name,'members.edit'::permission_key));
