begin;

create table public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  source_key text not null,
  kind text not null check (kind in ('stock','finance','shipping','purchase')),
  severity text not null default 'attention' check (severity in ('info','attention','urgent')),
  title text not null check (char_length(title) between 1 and 160),
  message text not null check (char_length(message) between 1 and 320),
  target_page text not null,
  target_id uuid,
  read_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique (user_id, source_key)
);

create index user_notifications_unread_idx
  on public.user_notifications(user_id, active, read_at, last_seen_at desc);

alter table public.user_notifications enable row level security;
revoke all on public.user_notifications from public, anon, authenticated;
grant select on public.user_notifications to authenticated;

create policy user_notifications_own_read
  on public.user_notifications for select to authenticated
  using ((select auth.uid()) = user_id);

commit;
