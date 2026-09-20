-- Public PG enquiry submissions
create table if not exists public.enquiries (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text not null,
  room_preference text,
  message text not null,
  status text not null default 'new',
  created_at timestamptz not null default now()
);

alter table public.enquiries enable row level security;

alter table public.enquiries drop constraint if exists enquiries_status_check;
alter table public.enquiries add constraint enquiries_status_check check (status in ('new','contacted','closed'));

drop policy if exists "public_can_submit_enquiries" on public.enquiries;
create policy "public_can_submit_enquiries" on public.enquiries
for insert to anon, authenticated
with check (true);

drop policy if exists "admins_can_read_enquiries" on public.enquiries;
create policy "admins_can_read_enquiries" on public.enquiries
for select to authenticated
using (public.is_admin());

drop policy if exists "admins_can_update_enquiries" on public.enquiries;
create policy "admins_can_update_enquiries" on public.enquiries
for update to authenticated
using (public.is_admin())
with check (public.is_admin());

grant insert on public.enquiries to anon, authenticated;
grant select, update on public.enquiries to authenticated;
