-- ============================================================
-- Fix: fulfill_recurring_order failed for every AUTO-MATCH item with
--   record "v_listing" is not assigned yet
--
-- The matching loop used `if not found then <fallback search>` after an
-- OPTIONAL preferred-farmer search. For an item with no preferred farmer
-- that search is skipped, so FOUND still held TRUE from the FOR loop
-- fetching the item: the fallback (nearest / cheapest farmer) search never
-- ran, and reading the empty record raised. Every auto-match schedule
-- failed on every attempt, so the hourly retry could never succeed.
--
-- Changes (everything else identical to 20261016003912):
-- 1. Explicit v_matched flag instead of relying on FOUND.
-- 2. Stock already reserved by earlier items in the same order is
--    subtracted when matching, so two items can't over-commit one listing
--    (which would otherwise fail later in decrement_listing_quantity).
-- ============================================================

create or replace function fulfill_recurring_order(p_recurring_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ro recurring_order;
  v_rs recurring_schedule;
  v_item record;
  v_listing record;
  v_matched boolean;
  v_wallet wallet;
  v_line jsonb;
  v_total numeric := 0;
  v_charge numeric;
  v_matched_lines jsonb := '[]'::jsonb;
  v_reserved jsonb := '{}'::jsonb; -- listing_id -> kg already matched
  v_farmer_id uuid;
  v_farmer_total numeric;
  v_order_id uuid;
  v_checkout_group_id uuid := gen_random_uuid();
  v_occurrence_date date;
  v_occurrence_day text;
  v_business_timezone text := coalesce(
    nullif(current_setting('app.business_timezone', true), ''),
    'Asia/Colombo'
  );
begin
  select * into v_ro from recurring_order
   where id = p_recurring_order_id for update;

  if not found or v_ro.status <> 'active' then
    return jsonb_build_object('status', 'skipped', 'reason', 'not_active_or_not_found');
  end if;

  v_occurrence_date := (v_ro.next_run_at at time zone v_business_timezone)::date;
  v_occurrence_day  := case extract(dow from v_occurrence_date)
    when 0 then 'Sunday'    when 1 then 'Monday'   when 2 then 'Tuesday'
    when 3 then 'Wednesday' when 4 then 'Thursday' when 5 then 'Friday'
    when 6 then 'Saturday'
  end;

  if v_ro.last_processed_date = v_occurrence_date then
    return jsonb_build_object('status', 'skipped', 'reason', 'already_processed',
                              'occurrence_date', v_occurrence_date);
  end if;

  select * into v_rs from recurring_schedule
   where id = v_ro.schedule_id for update;

  if not found or v_rs.status <> 'active' then
    update recurring_order
       set processing_status = 'cancelled', last_attempt_at = now(),
           last_error = 'schedule_not_active'
     where id = v_ro.id;
    return jsonb_build_object('status', 'skipped', 'reason', 'schedule_not_active');
  end if;

  -- Auth: skip check for service_role (auth.uid() is null)
  if auth.uid() is not null and auth.uid() is distinct from v_rs.buyer_profile_id then
    raise exception 'Not authorized to fulfill recurring order %', p_recurring_order_id
      using errcode = '42501';
  end if;

  if v_rs.end_date is not null
     and (v_rs.end_date at time zone v_business_timezone)::date < v_occurrence_date then
    update recurring_schedule set status = 'cancelled' where id = v_rs.id;
    update recurring_order
       set status = 'cancelled', processing_status = 'cancelled',
           last_attempt_at = now(), last_error = 'schedule_expired'
     where schedule_id = v_rs.id;
    return jsonb_build_object('status', 'skipped', 'reason', 'schedule_expired');
  end if;

  update recurring_order set last_attempt_at = now(), last_error = null where id = v_ro.id;

  -- Match each recurring item to an active listing
  for v_item in
    select * from recurring_order_item where recurring_order_id = v_ro.id
  loop
    -- Explicit flag: FOUND is unreliable here (the FOR fetch sets it).
    v_matched := false;

    -- Preferred farmer first
    if v_item.preferred_farmer_id is not null then
      select pl.id, pl.farmer_profile_id, pl.price_per_kg, pl.available_quantity_kg
        into v_listing
        from produce_listing pl
       where pl.farmer_profile_id      = v_item.preferred_farmer_id
         and pl.crop_id                = v_item.crop_id
         and pl.status                 = 'active'
         and pl.available_quantity_kg
             - coalesce((v_reserved->>pl.id::text)::numeric, 0) >= v_item.quantity_kg
         and (pl.expires_at is null or pl.expires_at > now())
       order by pl.published_at asc limit 1;
      v_matched := found;
    end if;

    -- Fallback (auto-match, or preferred farmer has no stock): closest & cheapest
    if not v_matched then
      select pl.id, pl.farmer_profile_id, pl.price_per_kg, pl.available_quantity_kg
        into v_listing
        from produce_listing pl
        join profile farmer on farmer.id = pl.farmer_profile_id
       where pl.crop_id                = v_item.crop_id
         and pl.status                 = 'active'
         and pl.available_quantity_kg
             - coalesce((v_reserved->>pl.id::text)::numeric, 0) >= v_item.quantity_kg
         and (pl.expires_at is null or pl.expires_at > now())
       order by
         case when v_ro.delivery_location is null or farmer.location_point is null then null
              else st_distance(farmer.location_point, v_ro.delivery_location) end asc nulls last,
         pl.available_quantity_kg desc, pl.price_per_kg asc, pl.published_at asc
       limit 1;
      v_matched := found;
    end if;

    if not v_matched then
      update recurring_order
         set processing_status = 'awaiting_inventory',
             last_error = format('No listing has sufficient stock for crop %s', v_item.crop_id)
       where id = v_ro.id;
      perform send_notification(
        v_rs.buyer_profile_id, 'recurring_unfulfilled',
        format('"%s" %s order is waiting for stock', v_rs.label, v_occurrence_day),
        format('Your "%s" %s order is waiting for available stock. We will retry it when stock becomes available.',
          v_rs.label, v_occurrence_day),
        jsonb_build_object('schedule_id', v_rs.id, 'schedule_label', v_rs.label,
          'occurrence_day', v_occurrence_day, 'occurrence_date', v_occurrence_date),
        'recurring_schedule', v_rs.id
      );
      return jsonb_build_object('status', 'awaiting_inventory', 'occurrence_date', v_occurrence_date);
    end if;

    v_reserved := jsonb_set(
      v_reserved, array[v_listing.id::text],
      to_jsonb(coalesce((v_reserved->>v_listing.id::text)::numeric, 0) + v_item.quantity_kg)
    );

    v_charge := v_listing.price_per_kg * v_item.quantity_kg;
    v_total  := v_total + v_charge;
    v_matched_lines := v_matched_lines || jsonb_build_object(
      'crop_id',     v_item.crop_id,
      'farmer_id',   v_listing.farmer_profile_id,
      'listing_id',  v_listing.id,
      'quantity_kg', v_item.quantity_kg,
      'price_per_kg', v_listing.price_per_kg,
      'charge',      v_charge
    );
  end loop;

  -- Wallet check
  select * into v_wallet from wallet where profile_id = v_rs.buyer_profile_id for update;

  if not found or v_wallet.balance < v_total then
    update recurring_order
       set processing_status = 'awaiting_funds',
           last_error = format('Wallet balance %.2f is below required %.2f',
                               coalesce(v_wallet.balance, 0), v_total)
     where id = v_ro.id;
    perform send_notification(
      v_rs.buyer_profile_id, 'recurring_skipped_low_balance',
      format('"%s" %s order needs wallet funds', v_rs.label, v_occurrence_day),
      format('Your "%s" %s order is waiting for wallet funds. Please top up %.2f to place it.',
        v_rs.label, v_occurrence_day, greatest(v_total - coalesce(v_wallet.balance, 0), 0)),
      jsonb_build_object('schedule_id', v_rs.id, 'schedule_label', v_rs.label,
        'occurrence_day', v_occurrence_day, 'occurrence_date', v_occurrence_date,
        'required_amount', v_total, 'current_balance', coalesce(v_wallet.balance, 0)),
      'recurring_schedule', v_rs.id
    );
    return jsonb_build_object('status', 'awaiting_funds', 'occurrence_date', v_occurrence_date);
  end if;

  -- Decrement listing quantities
  for v_line in select value from jsonb_array_elements(v_matched_lines)
  loop
    perform decrement_listing_quantity(
      (v_line->>'listing_id')::uuid,
      (v_line->>'quantity_kg')::numeric
    );
  end loop;

  -- Deduct wallet via standard function
  perform apply_wallet_transaction(
    v_rs.buyer_profile_id, 'payment', -v_total, 'recurring_order', v_ro.id
  );

  -- Create one order per farmer; order_date = occurrence date
  for v_farmer_id in
    select distinct (value->>'farmer_id')::uuid from jsonb_array_elements(v_matched_lines)
  loop
    select coalesce(sum((value->>'charge')::numeric), 0) into v_farmer_total
      from jsonb_array_elements(v_matched_lines)
     where (value->>'farmer_id')::uuid = v_farmer_id;

    insert into orders (
      checkout_group_id, buyer_profile_id, farmer_profile_id,
      status, source,
      subtotal_amount, delivery_fee_amount, total_amount,
      delivery_address, delivery_location,
      order_date,
      placed_at
    )
    values (
      v_checkout_group_id, v_rs.buyer_profile_id, v_farmer_id,
      'placed', 'recurring',
      v_farmer_total, 0, v_farmer_total,
      (select delivery_address from recurring_order where id = v_ro.id),
      (select delivery_location from recurring_order where id = v_ro.id),
      v_occurrence_date,
      now()
    )
    returning id into v_order_id;

    insert into order_item (order_id, produce_listing_id, crop_id, quantity_kg, price_per_kg)
    select v_order_id,
           (value->>'listing_id')::uuid,
           (value->>'crop_id')::uuid,
           (value->>'quantity_kg')::numeric,
           (value->>'price_per_kg')::numeric
      from jsonb_array_elements(v_matched_lines)
     where (value->>'farmer_id')::uuid = v_farmer_id;

    -- Status history row (same as cart checkout)
    insert into order_status_history (order_id, status, note)
    values (v_order_id, 'placed', 'Created by recurring order fulfillment');

    -- Auto-assign driver if available
    perform assign_nearest_driver(v_order_id);
  end loop;

  -- Advance recurring_order to next occurrence
  update recurring_order
     set last_processed_date = v_occurrence_date,
         processing_status   = 'fulfilled',
         last_attempt_at     = now(),
         last_error          = null,
         next_run_at = case frequency
           when 'weekly'   then next_run_at + interval '7 days'
           when 'biweekly' then next_run_at + interval '14 days'
           when 'monthly'  then next_run_at + interval '1 month'
         end
   where id = v_ro.id;

  perform send_notification(
    v_rs.buyer_profile_id, 'recurring_fulfilled',
    format('"%s" %s order placed', v_rs.label, v_occurrence_day),
    format('Your "%s" %s order has been placed successfully!', v_rs.label, v_occurrence_day),
    jsonb_build_object('schedule_id', v_rs.id, 'schedule_label', v_rs.label,
      'occurrence_day', v_occurrence_day, 'occurrence_date', v_occurrence_date,
      'total_charged', v_total),
    'recurring_schedule', v_rs.id
  );

  return jsonb_build_object(
    'status', 'fulfilled',
    'occurrence_date', v_occurrence_date,
    'total_charged', v_total
  );
end;
$$;

revoke execute on function fulfill_recurring_order(uuid) from public;
grant execute on function fulfill_recurring_order(uuid) to service_role, authenticated;

-- ============================================================
-- Scheduler: the hourly retry also retries occurrences whose last
-- attempt ERRORED (last_error set, not waiting for funds/stock). Before,
-- only awaiting_funds / awaiting_inventory were retried hourly, so an
-- errored "tomorrow" order wasn't retried until the midnight run — too
-- late — although the app says "we'll retry automatically".
-- Otherwise identical to 20261018092640_recurring_orders_server_authoritative.
-- ============================================================

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
            or ro.processing_status in ('awaiting_funds', 'awaiting_inventory')
            -- a failed attempt (error) is retried hourly too
            or (ro.last_error is not null
                and ro.last_error <> 'missed_occurrence'
                and ro.processing_status not in ('fulfilled', 'cancelled')))
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
