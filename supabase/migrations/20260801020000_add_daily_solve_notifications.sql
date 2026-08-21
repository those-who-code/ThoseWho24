-- Records which friends have already been notified about a daily solve. The
-- composite foreign key makes these rows follow the existing daily-attempt
-- retention policy automatically.
create table if not exists public.daily_solve_notifications (
  solver_id uuid not null,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  puzzle_date date not null,
  created_at timestamptz not null default now(),
  primary key (solver_id, recipient_id, puzzle_date),
  foreign key (solver_id, puzzle_date)
    references public.daily_puzzle_attempts(user_id, puzzle_date)
    on delete cascade,
  constraint daily_solve_notification_not_self
    check (solver_id <> recipient_id)
);
alter table public.daily_solve_notifications enable row level security;
-- Only the service-role Edge Function reads and writes this internal delivery
-- ledger. App users do not receive table policies.
revoke all on table public.daily_solve_notifications from anon, authenticated;
