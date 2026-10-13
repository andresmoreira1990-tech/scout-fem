-- ScoutFem: permitir que una cuenta consulte solicitudes asociadas a su propio correo.
-- Necesario para recuperar altas de prueba cuando quedaron vinculadas a otro auth.users
-- con el mismo correo (por registros antiguos o duplicados). No permite consultar otros correos.
begin;

drop policy if exists "registration user reads own request or admin reads all" on public.account_registration_requests;
drop policy if exists "registration user reads own request by id or email or admin reads all" on public.account_registration_requests;

create policy "registration user reads own request by id or email or admin reads all"
on public.account_registration_requests for select to authenticated
using (
  user_id = (select auth.uid())
  or lower(email) = lower(coalesce((select auth.jwt())->>'email',''))
  or exists (
    select 1 from public.scout_users su
    where su.id = (select auth.uid()) and su.role = 'admin'
  )
);

grant select on public.account_registration_requests to authenticated;

commit;
