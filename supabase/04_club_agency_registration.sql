-- ScoutFem: registro de clubes y agencias con aprobación administrativa.
-- Ejecutar manualmente en Supabase SQL Editor antes de probar el formulario.
begin;

create table if not exists public.account_registration_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  email text not null,
  account_type text not null check (account_type in ('club','agency')),
  organization_name text not null check (length(trim(organization_name)) >= 2),
  contact_name text not null default '',
  phone text not null default '',
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null
);

alter table public.account_registration_requests enable row level security;

drop policy if exists "registration user inserts own request" on public.account_registration_requests;
create policy "registration user inserts own request"
on public.account_registration_requests for insert to authenticated
with check (user_id = (select auth.uid()) and status = 'pending' and reviewed_at is null and reviewed_by is null);

drop policy if exists "registration user reads own request or admin reads all" on public.account_registration_requests;
create policy "registration user reads own request or admin reads all"
on public.account_registration_requests for select to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1 from public.scout_users su
    where su.id = (select auth.uid()) and su.role = 'admin'
  )
);

drop policy if exists "registration admin updates requests" on public.account_registration_requests;
create policy "registration admin updates requests"
on public.account_registration_requests for update to authenticated
using (
  exists (
    select 1 from public.scout_users su
    where su.id = (select auth.uid()) and su.role = 'admin'
  )
)
with check (
  exists (
    select 1 from public.scout_users su
    where su.id = (select auth.uid()) and su.role = 'admin'
  )
);

revoke all on public.account_registration_requests from anon;
grant select, insert, update on public.account_registration_requests to authenticated;


-- Comprobación explícita de correo duplicado antes del alta.
-- Solo devuelve true/false; no expone datos de la cuenta.
create or replace function public.email_is_registered(p_email text)
returns boolean
language sql
security definer
set search_path = ''
as $
  select exists (
    select 1
    from auth.users u
    where lower(u.email) = lower(trim(p_email))
  );
$;

revoke all on function public.email_is_registered(text) from public;
grant execute on function public.email_is_registered(text) to anon, authenticated;

commit;
