-- Recurring-order processing contract:
-- - next_run_at is the delivery/occurrence date.
-- - last_processed_date is written only after an occurrence is completed.
-- - insufficient funds or stock remain retryable and do not advance the date.

alter table recurring_schedule
  add column if not exists end_date timestamptz;

alter table recurring_order
  add column if not exists last_processed_date date,
  add column if not exists processing_status text not null default 'pending',
  add column if not exists last_attempt_at timestamptz,
  add column if not exists last_error text,
  add column if not exists last_low_balance_notice_date date;

alter table recurring_order
  drop constraint if exists recurring_order_processing_status_check;

alter table recurring_order
  add constraint recurring_order_processing_status_check
  check (processing_status in ('pending', 'fulfilled', 'awaiting_funds', 'awaiting_inventory', 'cancelled'));

create index if not exists idx_recurring_order_due
  on recurring_order (next_run_at, status, last_processed_date);

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
  v_wallet wallet;
  v_line jsonb;
  v_total numeric := 0;
  v_charge numeric;
  v_matched_lines jsonb := '[]'::jsonb;
  v_farmer_id uuid;
  v_farmer_total numeric;
  v_order_id uuid;
  v_checkout_group_id uuid := gen_random_uuid();
  v_occurrence_date date;
  v_occurrence_day text;
  v_business_timezone text := coalesce(nullif(current_setting('app.business_timezone', true), ''), 'Asia/Colombo');
begin
  select *
    into v_ro
    from recurring_order
   where id = p_recurring_order_id
   for update;

  if not found or v_ro.status <> 'active' then
    return jsonb_build_object('status', 'skipped', 'reason', 'not_active_or_not_found');
  end if;

  v_occurrence_date := (v_ro.next_run_at at time zone v_business_timezone)::date;
  v_occurrence_day := case extract(dow from v_occurrence_date)
    when 0 then 'Sunday'
    when 1 then 'Monday'
    when 2 then 'Tuesday'
    when 3 then 'Wednesday'
    when 4 then 'Thursday'
    when 5 then 'Friday'
    when 6 then 'Saturday'
  end;

  if v_ro.last_processed_date = v_occurrence_date then
    return jsonb_build_object('status', 'skipped', 'reason', 'already_processed', 'occurrence_date', v_occurrence_date);
  end if;

  select *
    into v_rs
    from recurring_schedule
   where id = v_ro.schedule_id
   for update;

  if not found or v_rs.status <> 'active' then
    update recurring_order
       set processing_status = 'cancelled',
           last_attempt_at = now(),
           last_error = 'schedule_not_active'
     where id = v_ro.id;
    return jsonb_build_object('status', 'skipped', 'reason', 'schedule_not_active');
  end if;

  if auth.uid() is not null and auth.uid() is distinct from v_rs.buyer_profile_id then
    raise exception 'Not authorized to fulfill recurring order %', p_recurring_order_id
      using errcode = '42501';
  end if;

  if v_rs.end_date is not null and (v_rs.end_date at time zone v_business_timezone)::date < v_occurrence_date then
    update recurring_schedule set status = 'cancelled' where id = v_rs.id;
    update recurring_order
       set status = 'cancelled',
           processing_status = 'cancelled',
           last_attempt_at = now(),
           last_error = 'schedule_expired'
     where schedule_id = v_rs.id;
    return jsonb_build_object('status', 'skipped', 'reason', 'schedule_expired');
  end if;

  update recurring_order
     set last_attempt_at = now(), last_error = null
   where id = v_ro.id;

  for v_item in
    select *
      from recurring_order_item
     where recurring_order_id = v_ro.id
  loop
    v_listing := null;

    if v_item.preferred_farmer_id is not null then
      select pl.id, pl.farmer_profile_id, pl.price_per_kg, pl.available_quantity_kg
        into v_listing
        from produce_listing pl
       where pl.farmer_profile_id = v_item.preferred_farmer_id
         and pl.crop_id = v_item.crop_id
         and pl.status = 'active'
         and pl.available_quantity_kg >= v_item.quantity_kg
         and (pl.expires_at is null or pl.expires_at > now())
       order by pl.published_at asc
       limit 1;
    end if;

    if not found then
      select pl.id, pl.farmer_profile_id, pl.price_per_kg, pl.available_quantity_kg
        into v_listing
        from produce_listing pl
        join profile farmer on farmer.id = pl.farmer_profile_id
       where pl.crop_id = v_item.crop_id
         and pl.status = 'active'
         and pl.available_quantity_kg >= v_item.quantity_kg
         and (pl.expires_at is null or pl.expires_at > now())
       order by
         case when v_ro.delivery_location is null or farmer.location_point is null
              then null
              else st_distance(farmer.location_point, v_ro.delivery_location)
          end asc nulls last,
         pl.available_quantity_kg desc,
         pl.price_per_kg asc,
         pl.published_at asc
       limit 1;
    end if;

    if not found then
      update recurring_order
         set processing_status = 'awaiting_inventory',
             last_error = format('No listing has sufficient stock for crop %s', v_item.crop_id)
       where id = v_ro.id;
      perform send_notification(
        v_rs.buyer_profile_id,
        'recurring_unfulfilled',
        format('"%s" %s order is waiting for stock', v_rs.label, v_occurrence_day),
        format('Your "%s" %s order is waiting for available stock. We will retry it when stock becomes available.',
          v_rs.label, v_occurrence_day),
        jsonb_build_object('schedule_id', v_rs.id, 'schedule_label', v_rs.label,
          'occurrence_day', v_occurrence_day, 'occurrence_date', v_occurrence_date),
        'recurring_schedule',
        v_rs.id
      );
      return jsonb_build_object('status', 'awaiting_inventory', 'occurrence_date', v_occurrence_date);
    end if;

    v_charge := v_listing.price_per_kg * v_item.quantity_kg;
    v_total := v_total + v_charge;
    v_matched_lines := v_matched_lines || jsonb_build_object(
      'crop_id', v_item.crop_id,
      'farmer_id', v_listing.farmer_profile_id,
      'listing_id', v_listing.id,
      'quantity_kg', v_item.quantity_kg,
      'price_per_kg', v_listing.price_per_kg,
      'charge', v_charge
    );
  end loop;

  select *
    into v_wallet
    from wallet
   where profile_id = v_rs.buyer_profile_id
   for update;

  if not found or v_wallet.balance < v_total then
    update recurring_order
       set processing_status = 'awaiting_funds',
           last_error = format('Wallet balance %.2f is below required amount %.2f',
                               coalesce(v_wallet.balance, 0), v_total)
     where id = v_ro.id;
    perform send_notification(
      v_rs.buyer_profile_id,
      'recurring_skipped_low_balance',
      format('"%s" %s order needs wallet funds', v_rs.label, v_occurrence_day),
      format('Your "%s" %s order is waiting for wallet funds. Please top up %.2f to place it.',
        v_rs.label, v_occurrence_day, greatest(v_total - coalesce(v_wallet.balance, 0), 0)),
      jsonb_build_object(
        'schedule_id', v_rs.id,
        'schedule_label', v_rs.label,
        'occurrence_day', v_occurrence_day,
        'occurrence_date', v_occurrence_date,
        'required_amount', v_total,
        'current_balance', coalesce(v_wallet.balance, 0)
      ),
      'recurring_schedule',
      v_rs.id
    );
    return jsonb_build_object('status', 'awaiting_funds', 'occurrence_date', v_occurrence_date);
  end if;

  for v_line in select value from jsonb_array_elements(v_matched_lines)
  loop
    perform decrement_listing_quantity(
      (v_line->>'listing_id')::uuid,
      (v_line->>'quantity_kg')::numeric
    );
  end loop;

  perform apply_wallet_transaction(
    v_rs.buyer_profile_id,
    'payment',
    -v_total,
    'recurring_order',
    v_ro.id
  );

  for v_farmer_id in
    select distinct (value->>'farmer_id')::uuid
      from jsonb_array_elements(v_matched_lines)
  loop
    select coalesce(sum((value->>'charge')::numeric), 0)
      into v_farmer_total
      from jsonb_array_elements(v_matched_lines)
     where (value->>'farmer_id')::uuid = v_farmer_id;

    insert into orders (
      checkout_group_id, buyer_profile_id, farmer_profile_id, status, source,
      subtotal_amount, delivery_fee_amount, total_amount,
      delivery_address, delivery_location
    )
    values (
      v_checkout_group_id, v_rs.buyer_profile_id, v_farmer_id, 'placed', 'recurring',
      v_farmer_total, 0, v_farmer_total,
      (select delivery_address from recurring_order where id = v_ro.id),
      (select delivery_location from recurring_order where id = v_ro.id)
    )
    returning id into v_order_id;

    insert into order_item (order_id, produce_listing_id, crop_id, quantity_kg, price_per_kg)
    select
      v_order_id,
      (value->>'listing_id')::uuid,
      (value->>'crop_id')::uuid,
      (value->>'quantity_kg')::numeric,
      (value->>'price_per_kg')::numeric
      from jsonb_array_elements(v_matched_lines)
     where (value->>'farmer_id')::uuid = v_farmer_id;

    insert into order_status_history (order_id, status, note)
    values (v_order_id, 'placed', 'Created by recurring order fulfillment');

    -- Use the same dispatch path as normal cart checkout. The assignment
    -- function leaves the order placed when no eligible driver exists.
    perform assign_nearest_driver(v_order_id);
  end loop;

  update recurring_order
     set last_processed_date = v_occurrence_date,
         processing_status = 'fulfilled',
         last_attempt_at = now(),
         last_error = null,
         next_run_at = case frequency
           when 'weekly' then next_run_at + interval '7 days'
           when 'biweekly' then next_run_at + interval '14 days'
           when 'monthly' then next_run_at + interval '1 month'
         end
   where id = v_ro.id;

  perform send_notification(
    v_rs.buyer_profile_id,
    'recurring_fulfilled',
    format('"%s" %s order placed', v_rs.label, v_occurrence_day),
    format('Your "%s" %s order has been placed successfully!', v_rs.label, v_occurrence_day),
    jsonb_build_object('schedule_id', v_rs.id, 'schedule_label', v_rs.label,
      'occurrence_day', v_occurrence_day, 'occurrence_date', v_occurrence_date, 'total_charged', v_total),
    'recurring_schedule',
    v_rs.id
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

create or replace function notify_upcoming_recurring_low_balance()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ro recurring_order;
  v_rs recurring_schedule;
  v_item record;
  v_listing_price numeric;
  v_listing_found boolean;
  v_wallet wallet;
  v_total numeric;
  v_occurrence_date date;
  v_occurrence_day text;
  v_notified integer := 0;
  v_business_timezone text := coalesce(nullif(current_setting('app.business_timezone', true), ''), 'Asia/Colombo');
begin
  for v_ro in
    select *
      from recurring_order
     where status = 'active'
       and processing_status in ('pending', 'awaiting_funds')
  loop
    v_occurrence_date := (v_ro.next_run_at at time zone v_business_timezone)::date;
    v_occurrence_day := case extract(dow from v_occurrence_date)
      when 0 then 'Sunday'
      when 1 then 'Monday'
      when 2 then 'Tuesday'
      when 3 then 'Wednesday'
      when 4 then 'Thursday'
      when 5 then 'Friday'
      when 6 then 'Saturday'
    end;
    if v_occurrence_date not between
       (now() at time zone v_business_timezone)::date + 2
       and (now() at time zone v_business_timezone)::date + 3 then
      continue;
    end if;

    if v_ro.last_low_balance_notice_date = v_occurrence_date then
      continue;
    end if;

    select * into v_rs from recurring_schedule where id = v_ro.schedule_id;
    if not found or v_rs.status <> 'active' then
      continue;
    end if;

    v_total := 0;
    for v_item in select * from recurring_order_item where recurring_order_id = v_ro.id
    loop
      v_listing_price := null;
      v_listing_found := false;
      if v_item.preferred_farmer_id is not null then
        select pl.price_per_kg into v_listing_price
          from produce_listing pl
         where pl.farmer_profile_id = v_item.preferred_farmer_id
           and pl.crop_id = v_item.crop_id
           and pl.status = 'active'
           and pl.available_quantity_kg >= v_item.quantity_kg
           and (pl.expires_at is null or pl.expires_at > now())
         order by pl.published_at asc
         limit 1;
        v_listing_found := found;
      end if;

      if not v_listing_found then
        select pl.price_per_kg into v_listing_price
          from produce_listing pl
         where pl.crop_id = v_item.crop_id
           and pl.status = 'active'
           and pl.available_quantity_kg >= v_item.quantity_kg
           and (pl.expires_at is null or pl.expires_at > now())
         order by pl.price_per_kg asc, pl.published_at asc
         limit 1;
        v_listing_found := found;
      end if;

      if v_listing_found then
        v_total := v_total + v_listing_price * v_item.quantity_kg;
      end if;
    end loop;

    select * into v_wallet from wallet where profile_id = v_rs.buyer_profile_id;
    if v_total > 0 and (not found or v_wallet.balance < v_total) then
      perform send_notification(
        v_rs.buyer_profile_id,
        'recurring_low_balance_reminder',
        format('"%s" %s order is coming up', v_rs.label, v_occurrence_day),
        format('Your "%s" %s order is scheduled for %s. Please top up your wallet before it is placed.',
          v_rs.label, v_occurrence_day, to_char(v_occurrence_date, 'FMDay, DD Mon')),
        jsonb_build_object(
          'schedule_id', v_rs.id,
          'schedule_label', v_rs.label,
          'occurrence_day', v_occurrence_day,
          'occurrence_date', v_occurrence_date,
          'required_amount', v_total,
          'current_balance', coalesce(v_wallet.balance, 0)
        ),
        'recurring_schedule',
        v_rs.id
      );
      update recurring_order
         set last_low_balance_notice_date = v_occurrence_date
       where id = v_ro.id;
      v_notified := v_notified + 1;
    end if;
  end loop;

  return v_notified;
end;
$$;

revoke execute on function notify_upcoming_recurring_low_balance() from public;
grant execute on function notify_upcoming_recurring_low_balance() to service_role;
alter table wallet_transaction
  add column if not exists description text;

create or replace function apply_wallet_transaction(
  p_profile_id uuid,
  p_type wallet_txn_type,
  p_amount numeric,
  p_reference_table text default null,
  p_reference_id uuid default null
)
returns wallet_transaction
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wallet wallet;
  v_txn wallet_transaction;
  v_description text;
begin
  select * into v_wallet from wallet where profile_id = p_profile_id for update;
  if v_wallet.id is null then
    insert into wallet (profile_id) values (p_profile_id) returning * into v_wallet;
  end if;
  if v_wallet.balance + p_amount < 0 then
    raise exception 'Insufficient wallet balance for profile %', p_profile_id using errcode = 'P0001';
  end if;
  if p_reference_table = 'recurring_order' and p_reference_id is not null then
    select format('Recurring Order: %s (%s)', rs.label,
      to_char((ro.next_run_at at time zone 'Asia/Colombo')::date, 'FMDay'))
      into v_description
      from recurring_order ro
      join recurring_schedule rs on rs.id = ro.schedule_id
      where ro.id = p_reference_id;
  elsif p_reference_table = 'orders' and p_reference_id is not null then
    v_description := format('Cart Checkout #%s', left(p_reference_id::text, 8));
  end if;
  v_description := coalesce(v_description, initcap(replace(p_type::text, '_', ' ')));
  update wallet set balance = balance + p_amount, updated_at = now()
   where id = v_wallet.id returning * into v_wallet;
  insert into wallet_transaction
    (wallet_id, type, amount, balance_after, reference_table, reference_id, description)
  values
    (v_wallet.id, p_type, p_amount, v_wallet.balance, p_reference_table, p_reference_id, v_description)
  returning * into v_txn;
  return v_txn;
end;
$$;

grant execute on function apply_wallet_transaction(uuid, wallet_txn_type, numeric, text, uuid)
  to service_role;
