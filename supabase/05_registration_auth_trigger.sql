-- ScoutFem: crear solicitudes de club/agencia al crear la cuenta Auth,
-- aunque Supabase exija confirmar el correo y todavía no exista una sesión.
-- Ejecutar en Supabase SQL Editor después de 04_club_agency_registration.sql.

create or replace function public.create_account_registration_request_from_auth()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text;
  v_org text;
  v_contact text;
  v_phone text;
begin
  v_type := new.raw_user_meta_data ->> 'account_type';
  v_org := trim(coalesce(new.raw_user_meta_data ->> 'organization_name', ''));
  v_contact := coalesce(new.raw_user_meta_data ->> 'contact_name', '');
  v_phone := coalesce(new.raw_user_meta_data ->> 'phone', '');

  if v_type in ('club', 'agency') and length(v_org) >= 2 then
    insert into public.account_registration_requests
      (user_id, email, account_type, organization_name, contact_name, phone, status)
    values
      (new.id, coalesce(new.email, ''), v_type, v_org, v_contact, v_phone, 'pending')
    on conflict (user_id) do nothing;
  end if;

  return new;
end;
$$;

revoke all on function public.create_account_registration_request_from_auth() from public;

drop trigger if exists scoutfem_create_registration_request on auth.users;
create trigger scoutfem_create_registration_request
after insert on auth.users
for each row
execute function public.create_account_registration_request_from_auth();

-- Recupera también las cuentas club/agencia creadas antes de instalar el trigger.
insert into public.account_registration_requests
  (user_id, email, account_type, organization_name, contact_name, phone, status)
select
  u.id,
  coalesce(u.email, ''),
  u.raw_user_meta_data ->> 'account_type',
  trim(u.raw_user_meta_data ->> 'organization_name'),
  coalesce(u.raw_user_meta_data ->> 'contact_name', ''),
  coalesce(u.raw_user_meta_data ->> 'phone', ''),
  'pending'
from auth.users u
where u.raw_user_meta_data ->> 'account_type' in ('club', 'agency')
  and length(trim(coalesce(u.raw_user_meta_data ->> 'organization_name', ''))) >= 2
on conflict (user_id) do nothing;
