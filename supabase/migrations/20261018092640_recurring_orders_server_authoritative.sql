-- ============================================================
-- Recurring orders: server-authoritative writes, "tomorrow" placed
-- immediately, and a scheduler that actually runs a day ahead.
--
-- Contract (unchanged): recurring_order.next_run_at is the DELIVERY date
-- (Asia/Colombo); fulfill_recurring_order() places that occurrence and is
-- idempotent per (recurring_order, occurrence date) via last_processed_date.
--
-- Fixes:
-- 1. Scheduler picked `next_run_at <= now()`, i.e. it placed an order on
--    its delivery day instead of the night before. process_due_recurring_
--    orders() places occurrences due TODAY or TOMORROW (Colombo).
-- 2. No scheduler was defined in migrations. pg_cron jobs are created
--    here: 00:00 Colombo (main run) + hourly retry of orders waiting for
--    funds/stock.
-- 3. Schedule create/edit/pause/resume/skip were client-side PowerSync
--    writes, but the recurring sync streams are invalid (they join on a
--    dropped buyer_profile_id), so after a re-login the rows aren't local:
--    edits hit 0 rows or duplicated orders, and skip ran a Postgres
--    function against SQLite. They are now atomic RPCs.
-- 4. A schedule whose next delivery is TOMORROW is placed immediately by
--    save/resume (the midnight run for it has already passed).
-- 5. skip_next_recurring_order had no ownership check.
-- ============================================================

-- ---- helpers ----------------------------------------------------------------

-- Today in the business timezone.
create or replace function recurring_today()
returns date
language sql
stable
as $$
  select (now() at time zone 'Asia/Colombo')::date;
$$;

-- Next date strictly AFTER p_after that falls on p_day_of_week (0 = Sun).
create or replace function recurring_next_weekday(p_day_of_week int, p_after date)
returns date
language sql
immutable
as $$
  select p_after + (((p_day_of_week - extract(dow from p_after)::int + 6) % 7) + 1);
$$;

-- Midnight (Colombo) of a date, as the timestamptz stored in next_run_at.
create or replace function recurring_run_at(p_date date)
returns timestamptz
language sql
immutable
as $$
  select (p_date::timestamp at time zone 'Asia/Colombo');
$$;

create or replace function recurring_interval(p_frequency recurring_frequency)
returns interval
language sql
immutable
as $$
  select case p_frequency
    when 'weekly'   then interval '7 days'
    when 'biweekly' then interval '14 days'
    when 'monthly'  then interval '1 month'
  end;
$$;

-- fulfill_recurring_order, but never aborts the caller: any error rolls
-- back only this occurrence (sub-transaction) and is reported.
create or replace function fulfill_recurring_order_safe(p_recurring_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return fulfill_recurring_order(p_recurring_order_id);
exception when others then
  update recurring_order
     set last_attempt_at = now(), last_error = left(sqlerrm, 500)
   where id = p_recurring_order_id;
  return jsonb_build_object('status', 'error', 'reason', sqlerrm);
end;
$$;

-- Places every active order of a schedule whose occurrence is tomorrow.
-- Returns [{recurring_order_id, day_of_week, status, reason}].
create or replace function place_tomorrows_recurring_orders(p_schedule_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ro record;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_tomorrow date := recurring_today() + 1;
begin
  for v_ro in
    select ro.id, ro.day_of_week
      from recurring_order ro
      join recurring_schedule rs on rs.id = ro.schedule_id
     where ro.schedule_id = p_schedule_id
       and ro.status = 'active' and rs.status = 'active'
       and (ro.next_run_at at time zone 'Asia/Colombo')::date = v_tomorrow
       and (ro.last_processed_date is null or ro.last_processed_date < v_tomorrow)
  loop
    v_result := fulfill_recurring_order_safe(v_ro.id);
    v_results := v_results || jsonb_build_object(
      'recurring_order_id', v_ro.id,
      'day_of_week', v_ro.day_of_week,
      'status', v_result->>'status',
      'reason', v_result->>'reason'
    );
  end loop;
  return v_results;
end;
$$;

revoke all on function fulfill_recurring_order_safe(uuid) from public, anon, authenticated;
revoke all on function place_tomorrows_recurring_orders(uuid) from public, anon, authenticated;

-- ---- create / edit ----------------------------------------------------------

-- p_days: [{ "day_of_week": 0-6,
--            "items": [{ "crop_id", "quantity_kg", "preferred_farmer_id"? }] }]
-- Creates the schedule (p_schedule_id null) or replaces its days/items.
-- next_run_at is computed here (next matching weekday after today,
-- Colombo). On edit, a day that was already placed for its next
-- occurrence keeps that, so editing never double-charges.
-- Returns { schedule_id, tomorrow: [...] }.
create or replace function save_recurring_schedule(
  p_schedule_id      uuid,
  p_label            text,
  p_frequency        text,
  p_end_date         timestamptz,
  p_delivery_address jsonb,
  p_days             jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_buyer uuid := auth.uid();
  v_schedule recurring_schedule;
  v_schedule_id uuid;
  v_frequency recurring_frequency := p_frequency::recurring_frequency;
  v_location geography;
  v_previous jsonb := '{}'::jsonb; -- day_of_week -> last_processed_date
  v_day jsonb;
  v_item jsonb;
  v_dow int;
  v_occurrence date;
  v_last_processed date;
  v_next_run timestamptz;
  v_order_id uuid;
  v_today date := recurring_today();
begin
  if v_buyer is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if coalesce(trim(p_label), '') = '' then
    raise exception 'A schedule label is required' using errcode = '22023';
  end if;
  if p_days is null or jsonb_array_length(p_days) = 0 then
    raise exception 'Choose at least one delivery day' using errcode = '22023';
  end if;

  select location_point into v_location from profile where id = v_buyer;

  if p_schedule_id is null then
    insert into recurring_schedule (buyer_profile_id, label, status, end_date)
    values (v_buyer, trim(p_label), 'active', p_end_date)
    returning * into v_schedule;
  else
    select * into v_schedule from recurring_schedule
     where id = p_schedule_id for update;
    if not found or v_schedule.buyer_profile_id <> v_buyer then
      raise exception 'Schedule not found' using errcode = 'P0002';
    end if;

    select coalesce(jsonb_object_agg(day_of_week::text, last_processed_date), '{}'::jsonb)
      into v_previous
      from recurring_order
     where schedule_id = v_schedule.id and last_processed_date is not null;

    update recurring_schedule
       set label = trim(p_label), end_date = p_end_date
     where id = v_schedule.id
     returning * into v_schedule;

    delete from recurring_order where schedule_id = v_schedule.id; -- items cascade
  end if;
  v_schedule_id := v_schedule.id;

  for v_day in select value from jsonb_array_elements(p_days)
  loop
    v_dow := (v_day->>'day_of_week')::int;
    if v_dow is null or v_dow not between 0 and 6 then
      raise exception 'Invalid day_of_week' using errcode = '22023';
    end if;
    if jsonb_array_length(coalesce(v_day->'items', '[]'::jsonb)) = 0 then
      continue;
    end if;

    v_occurrence := recurring_next_weekday(v_dow, v_today);
    v_last_processed := (v_previous->>v_dow::text)::date;
    -- Already placed for that occurrence before the edit: start from the
    -- one after, so it isn't placed (and charged) twice.
    if v_last_processed is not null and v_last_processed >= v_occurrence then
      v_next_run := recurring_run_at(v_occurrence) + recurring_interval(v_frequency);
    else
      v_next_run := recurring_run_at(v_occurrence);
    end if;

    insert into recurring_order (
      schedule_id, frequency, day_of_week, next_run_at,
      delivery_address, delivery_location, status,
      last_processed_date, processing_status
    ) values (
      v_schedule_id, v_frequency, v_dow, v_next_run,
      p_delivery_address, v_location, v_schedule.status,
      v_last_processed, 'pending'
    ) returning id into v_order_id;

    for v_item in select value from jsonb_array_elements(v_day->'items')
    loop
      if coalesce((v_item->>'quantity_kg')::numeric, 0) <= 0 then
        raise exception 'Quantities must be greater than zero' using errcode = '22023';
      end if;
      insert into recurring_order_item (
        recurring_order_id, crop_id, quantity_kg, preferred_farmer_id
      ) values (
        v_order_id,
        (v_item->>'crop_id')::uuid,
        (v_item->>'quantity_kg')::numeric,
        nullif(v_item->>'preferred_farmer_id', '')::uuid
      );
    end loop;
  end loop;

  return jsonb_build_object(
    'schedule_id', v_schedule_id,
    'tomorrow', place_tomorrows_recurring_orders(v_schedule_id)
  );
end;
$$;

revoke all on function save_recurring_schedule(uuid, text, text, timestamptz, jsonb, jsonb)
  from public, anon;
grant execute on function save_recurring_schedule(uuid, text, text, timestamptz, jsonb, jsonb)
  to authenticated;

-- ---- pause / resume ---------------------------------------------------------

-- p_status: 'active' (resume) | 'paused'. Resuming rolls any occurrence
-- that passed while paused forward to the next matching weekday, then
-- places tomorrow's straight away. Returns { status, tomorrow: [...] }.
create or replace function set_recurring_schedule_status(
  p_schedule_id uuid,
  p_status      text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_schedule recurring_schedule;
  v_status recurring_order_status := p_status::recurring_order_status;
  v_today date := recurring_today();
begin
  if v_status = 'cancelled' then
    raise exception 'Use delete to cancel a schedule' using errcode = '22023';
  end if;

  select * into v_schedule from recurring_schedule where id = p_schedule_id for update;
  if not found or v_schedule.buyer_profile_id is distinct from auth.uid() then
    raise exception 'Schedule not found' using errcode = 'P0002';
  end if;

  update recurring_schedule set status = v_status where id = p_schedule_id;

  if v_status = 'paused' then
    update recurring_order set status = 'paused' where schedule_id = p_schedule_id;
    return jsonb_build_object('status', 'paused', 'tomorrow', '[]'::jsonb);
  end if;

  update recurring_order
     set status = 'active',
         processing_status = 'pending',
         last_error = null,
         next_run_at = case
           when (next_run_at at time zone 'Asia/Colombo')::date <= v_today
             then recurring_run_at(recurring_next_weekday(day_of_week, v_today))
           else next_run_at
         end
   where schedule_id = p_schedule_id;

  return jsonb_build_object(
    'status', 'active',
    'tomorrow', place_tomorrows_recurring_orders(p_schedule_id)
  );
end;
$$;

revoke all on function set_recurring_schedule_status(uuid, text) from public, anon;
grant execute on function set_recurring_schedule_status(uuid, text) to authenticated;

-- ---- skip next ----------------------------------------------------------------

-- Was missing an ownership check. Returns the new next delivery date
-- (return type changed from void, hence the drop).
drop function if exists skip_next_recurring_order(uuid);
create function skip_next_recurring_order(p_recurring_order_id uuid)
returns date
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ro recurring_order;
  v_owner uuid;
  v_next timestamptz;
begin
  select ro.* into v_ro from recurring_order ro
   where ro.id = p_recurring_order_id for update;
  select buyer_profile_id into v_owner from recurring_schedule where id = v_ro.schedule_id;
  if v_ro.id is null or v_owner is distinct from auth.uid() then
    raise exception 'Recurring order not found' using errcode = 'P0002';
  end if;

  update recurring_order
     set next_run_at = next_run_at + recurring_interval(frequency),
         processing_status = 'pending',
         last_error = null
   where id = v_ro.id
   returning next_run_at into v_next;

  return (v_next at time zone 'Asia/Colombo')::date;
end;
$$;

revoke all on function skip_next_recurring_order(uuid) from public, anon;
grant execute on function skip_next_recurring_order(uuid) to authenticated;

-- ---- scheduler ------------------------------------------------------------------

-- Places occurrences due today or tomorrow (Colombo) that haven't been
-- placed yet. Occurrences already in the past are rolled forward (a late
-- order is useless; the buyer was notified when it failed).
-- p_retry_only: only retry occurrences waiting for funds/stock.
create or replace function process_due_recurring_orders(p_retry_only boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := recurring_today();
  v_ro record;
  v_result jsonb;
  v_rolled int := 0;
  v_counts jsonb := '{}'::jsonb;
  v_status text;
begin
  if not p_retry_only then
    begin
      perform notify_upcoming_recurring_low_balance();
    exception when others then
      raise warning 'notify_upcoming_recurring_low_balance failed: %', sqlerrm;
    end;

    with stale as (
      update recurring_order ro
         set next_run_at = recurring_run_at(recurring_next_weekday(ro.day_of_week, v_today - 1)),
             processing_status = 'pending',
             last_error = 'missed_occurrence'
        from recurring_schedule rs
       where rs.id = ro.schedule_id
         and ro.status = 'active' and rs.status = 'active'
         and (ro.next_run_at at time zone 'Asia/Colombo')::date < v_today
      returning 1
    )
    select count(*) into v_rolled from stale;
  end if;

  for v_ro in
    select ro.id
      from recurring_order ro
      join recurring_schedule rs on rs.id = ro.schedule_id
     where ro.status = 'active' and rs.status = 'active'
       and (ro.next_run_at at time zone 'Asia/Colombo')::date between v_today and v_today + 1
       and (ro.last_processed_date is null
            or ro.last_processed_date < (ro.next_run_at at time zone 'Asia/Colombo')::date)
       and (not p_retry_only
            or ro.processing_status in ('awaiting_funds', 'awaiting_inventory'))
     order by ro.next_run_at
  loop
    v_result := fulfill_recurring_order_safe(v_ro.id);
    v_status := coalesce(v_result->>'status', 'unknown');
    v_counts := jsonb_set(
      v_counts, array[v_status],
      to_jsonb(coalesce((v_counts->>v_status)::int, 0) + 1)
    );
  end loop;

  return jsonb_build_object(
    'ran_at', now(),
    'retry_only', p_retry_only,
    'rolled_forward', v_rolled,
    'results', v_counts
  );
end;
$$;

revoke all on function process_due_recurring_orders(boolean) from public, anon, authenticated;
grant execute on function process_due_recurring_orders(boolean) to service_role;

-- pg_cron runs in UTC; 18:30 UTC = 00:00 Asia/Colombo.
do $$
begin
  if to_regnamespace('cron') is null then
    raise warning 'pg_cron is not installed: schedule public.process_due_recurring_orders() manually';
    return;
  end if;
  if exists (select 1 from cron.job where jobname = 'process_due_recurring_orders') then
    perform cron.unschedule('process_due_recurring_orders');
  end if;
  perform cron.schedule('process_due_recurring_orders', '30 18 * * *',
    'select public.process_due_recurring_orders(false)');

  -- Hourly: retry today's/tomorrow's occurrences waiting for funds or
  -- stock, so a top-up or new listing is picked up within the hour.
  if exists (select 1 from cron.job where jobname = 'retry_waiting_recurring_orders') then
    perform cron.unschedule('retry_waiting_recurring_orders');
  end if;
  perform cron.schedule('retry_waiting_recurring_orders', '0 * * * *',
    'select public.process_due_recurring_orders(true)');
end;
$$;
