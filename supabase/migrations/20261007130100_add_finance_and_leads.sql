create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id),
  expense_date date not null default current_date,
  category text not null,
  description text not null,
  amount numeric not null check (amount > 0),
  payment_method public.payment_method not null default 'cash',
  vendor text,
  reference text,
  notes text,
  status text not null default 'posted' check (status in ('posted','voided')),
  created_by uuid references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists expenses_gym_date_idx on public.expenses(gym_id, expense_date desc);
create index if not exists expenses_gym_status_idx on public.expenses(gym_id, status);
create index if not exists expenses_created_by_idx on public.expenses(created_by);
alter table public.expenses enable row level security;
grant select on public.expenses to anon, authenticated;
drop policy if exists expenses_select on public.expenses;
create policy expenses_select on public.expenses for select to anon, authenticated using (private.has_permission(gym_id,'expenses.view'));
revoke insert, update, delete, truncate, references, trigger on public.expenses from anon, authenticated;

create table if not exists public.leads (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id),
  name text not null,
  phone text,
  email text,
  source text not null default 'walk_in',
  status text not null default 'new' check (status in ('new','contacted','trial','won','lost')),
  interested_package_id uuid references public.membership_packages(id),
  assigned_to uuid references public.users(id),
  follow_up_date date,
  notes text,
  converted_member_id uuid references public.members(id),
  lost_reason text,
  created_by uuid references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(trim(name)) >= 2)
);
create index if not exists leads_gym_status_idx on public.leads(gym_id, status, updated_at desc);
create index if not exists leads_gym_follow_up_idx on public.leads(gym_id, follow_up_date);
create index if not exists leads_assigned_to_idx on public.leads(assigned_to);
create index if not exists leads_phone_idx on public.leads(gym_id, phone);
create index if not exists leads_converted_member_id_idx on public.leads(converted_member_id);
create index if not exists leads_created_by_idx on public.leads(created_by);
create index if not exists leads_interested_package_id_idx on public.leads(interested_package_id);
alter table public.leads enable row level security;
grant select on public.leads to anon, authenticated;
drop policy if exists leads_select on public.leads;
create policy leads_select on public.leads for select to anon, authenticated using (private.has_permission(gym_id,'leads.view'));
revoke insert, update, delete, truncate, references, trigger on public.leads from anon, authenticated;

insert into public.permissions(key,description) values
 ('expenses.view','View expenses and profit reports'),
 ('expenses.manage','Create and void expenses'),
 ('leads.view','View sales leads and follow-ups'),
 ('leads.manage','Create and manage sales leads')
on conflict(key) do update set description=excluded.description;

create or replace function public.save_expense(
  p_gym_id uuid, p_expense_id uuid default null, p_expense_date date default current_date,
  p_category text default 'General', p_description text default '', p_amount numeric default 0,
  p_payment_method public.payment_method default 'cash', p_vendor text default null,
  p_reference text default null, p_notes text default null
) returns uuid language plpgsql security definer
set search_path to 'public','private','pg_catalog' as $$
declare v_id uuid;
begin
  if not private.has_permission(p_gym_id,'expenses.manage') then raise exception 'Unauthorized'; end if;
  if trim(coalesce(p_category,''))='' then raise exception 'Expense category is required'; end if;
  if trim(coalesce(p_description,''))='' then raise exception 'Expense description is required'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Expense amount must be greater than zero'; end if;
  if not exists(select 1 from public.payment_method_settings where gym_id=p_gym_id and payment_method=p_payment_method and enabled)
    then raise exception 'Selected payment method is disabled'; end if;
  if p_expense_id is null then
    insert into public.expenses(gym_id,expense_date,category,description,amount,payment_method,vendor,reference,notes,created_by)
    values(p_gym_id,p_expense_date,trim(p_category),trim(p_description),p_amount,p_payment_method,
      nullif(trim(p_vendor),''),nullif(trim(p_reference),''),nullif(trim(p_notes),''),private.current_app_user_id())
    returning id into v_id;
  else
    update public.expenses set expense_date=p_expense_date,category=trim(p_category),description=trim(p_description),
      amount=p_amount,payment_method=p_payment_method,vendor=nullif(trim(p_vendor),''),reference=nullif(trim(p_reference),''),
      notes=nullif(trim(p_notes),''),updated_at=now()
      where id=p_expense_id and gym_id=p_gym_id and status='posted';
    if not found then raise exception 'Expense not found or already voided'; end if;
    v_id:=p_expense_id;
  end if;
  return v_id;
end $$;

create or replace function public.void_expense(p_gym_id uuid,p_expense_id uuid,p_reason text) returns void
language plpgsql security definer set search_path to 'public','private','pg_catalog' as $$
begin
  if not private.has_permission(p_gym_id,'expenses.manage') then raise exception 'Unauthorized'; end if;
  if trim(coalesce(p_reason,''))='' then raise exception 'Reason is required'; end if;
  update public.expenses set status='voided',
    notes=concat_ws(E'\n',notes,'VOIDED: '||trim(p_reason)),updated_at=now()
    where id=p_expense_id and gym_id=p_gym_id and status='posted';
  if not found then raise exception 'Expense not found or already voided'; end if;
end $$;

create or replace function public.save_lead(
  p_gym_id uuid,p_lead_id uuid default null,p_name text default '',p_phone text default null,
  p_email text default null,p_source text default 'walk_in',p_status text default 'new',
  p_interested_package_id uuid default null,p_assigned_to uuid default null,p_follow_up_date date default null,
  p_notes text default null,p_lost_reason text default null
) returns uuid language plpgsql security definer
set search_path to 'public','private','pg_catalog' as $$
declare v_id uuid;
begin
  if not private.has_permission(p_gym_id,'leads.manage') then raise exception 'Unauthorized'; end if;
  if length(trim(coalesce(p_name,'')))<2 then raise exception 'Please enter a valid lead name'; end if;
  if p_status not in ('new','contacted','trial','won','lost') then raise exception 'Invalid lead status'; end if;
  if p_assigned_to is not null and not exists(select 1 from public.users where id=p_assigned_to and gym_id=p_gym_id and status='active')
    then raise exception 'Invalid assigned staff member'; end if;
  if p_interested_package_id is not null and not exists(select 1 from public.membership_packages where id=p_interested_package_id and gym_id=p_gym_id)
    then raise exception 'Invalid package'; end if;
  if p_lead_id is null then
    insert into public.leads(gym_id,name,phone,email,source,status,interested_package_id,assigned_to,follow_up_date,notes,lost_reason,created_by)
    values(p_gym_id,trim(p_name),nullif(trim(p_phone),''),nullif(trim(p_email),''),
      coalesce(nullif(trim(p_source),''),'walk_in'),p_status,p_interested_package_id,p_assigned_to,p_follow_up_date,
      nullif(trim(p_notes),''),nullif(trim(p_lost_reason),''),private.current_app_user_id())
    returning id into v_id;
  else
    update public.leads set name=trim(p_name),phone=nullif(trim(p_phone),''),email=nullif(trim(p_email),''),
      source=coalesce(nullif(trim(p_source),''),'walk_in'),status=p_status,interested_package_id=p_interested_package_id,
      assigned_to=p_assigned_to,follow_up_date=p_follow_up_date,notes=nullif(trim(p_notes),''),
      lost_reason=nullif(trim(p_lost_reason),''),updated_at=now()
      where id=p_lead_id and gym_id=p_gym_id;
    if not found then raise exception 'Lead not found'; end if;
    v_id:=p_lead_id;
  end if;
  return v_id;
end $$;

create or replace function public.delete_lead(p_gym_id uuid,p_lead_id uuid) returns void
language plpgsql security definer set search_path to 'public','private','pg_catalog' as $$
begin
  if not private.has_permission(p_gym_id,'leads.manage') then raise exception 'Unauthorized'; end if;
  update public.leads set status='lost',lost_reason=coalesce(lost_reason,'Archived by staff'),updated_at=now()
    where id=p_lead_id and gym_id=p_gym_id;
  if not found then raise exception 'Lead not found'; end if;
end $$;

create or replace function public.get_finance_summary(p_gym_id uuid,p_from date,p_to date) returns jsonb
language plpgsql security definer set search_path to 'public','private','pg_catalog' as $$
declare v_revenue numeric:=0;v_refunds numeric:=0;v_expenses numeric:=0;
begin
  if not private.has_permission(p_gym_id,'expenses.view') or not private.has_permission(p_gym_id,'payments.view')
    then raise exception 'Unauthorized'; end if;
  select coalesce(sum(amount),0),coalesce(sum(refund_amount),0) into v_revenue,v_refunds
    from public.revenue_report where gym_id=p_gym_id and payment_date >= p_from and payment_date < (p_to + 1);
  select coalesce(sum(amount),0) into v_expenses
    from public.expenses where gym_id=p_gym_id and expense_date between p_from and p_to and status='posted';
  return jsonb_build_object('gross_revenue',round(v_revenue,2),'refunds',round(v_refunds,2),
    'net_revenue',round(v_revenue-v_refunds,2),'expenses',round(v_expenses,2),'profit',round(v_revenue-v_refunds-v_expenses,2));
end $$;

grant execute on function public.save_expense(uuid,uuid,date,text,text,numeric,public.payment_method,text,text,text) to anon,authenticated;
grant execute on function public.void_expense(uuid,uuid,text) to anon,authenticated;
grant execute on function public.save_lead(uuid,uuid,text,text,text,text,text,uuid,uuid,date,text,text) to anon,authenticated;
grant execute on function public.delete_lead(uuid,uuid) to anon,authenticated;
grant execute on function public.get_finance_summary(uuid,date,date) to anon,authenticated;
