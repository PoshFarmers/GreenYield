-- ============================================================
-- Complete Recurring Orders Implementation
-- ============================================================

-- 1. Add end_date to recurring_schedule
alter table recurring_schedule add column end_date timestamptz;

-- 2. Update fulfill_recurring_order RPC to create real orders grouped by farmer and handle end_date
create or replace function fulfill_recurring_order(p_recurring_order_id uuid)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_ro record;
  v_rs record;
  v_item record;
  v_listing record;
  v_wallet record;
  v_total_charge numeric := 0;
  v_matched_lines jsonb := '[]'::jsonb;
  v_unfulfilled_count int := 0;
  v_farmer_id uuid;
  v_charge numeric;
  v_order_id uuid;
  v_checkout_group_id uuid := gen_random_uuid();
  v_farmer_total numeric := 0;
  v_line record;
begin
  -- 1. Load the order and schedule
  select * into v_ro from recurring_order where id = p_recurring_order_id for update;
  if v_ro.id is null or v_ro.status != 'active' then
    return jsonb_build_object('status', 'skipped', 'reason', 'not_active_or_not_found');
  end if;

  select * into v_rs from recurring_schedule where id = v_ro.schedule_id;
  
  -- Check if schedule has expired
  if v_rs.end_date is not null and v_rs.end_date < now() then
     update recurring_schedule set status = 'cancelled' where id = v_rs.id;
     update recurring_order set status = 'cancelled' where schedule_id = v_rs.id;
     return jsonb_build_object('status', 'skipped', 'reason', 'schedule_expired');
  end if;

  -- 2. Match each item
  for v_item in select * from recurring_order_item where recurring_order_id = p_recurring_order_id
  loop
    v_listing := null;
    
    if v_item.preferred_farmer_id is not null then
      select id, price_per_kg into v_listing from produce_listing
      where farmer_profile_id = v_item.preferred_farmer_id
        and crop_id = v_item.crop_id
        and status = 'active'
      limit 1;
    end if;

    -- Fallback or auto-match if no preferred farmer or preferred farmer inactive
    if v_listing is null then
      select id, farmer_profile_id, price_per_kg into v_listing from produce_listing
      where crop_id = v_item.crop_id
        and status = 'active'
      order by 
        price_per_kg asc,
        ST_Distance(location, v_ro.delivery_location) asc
      limit 1;
    end if;

    if v_listing is null then
      v_unfulfilled_count := v_unfulfilled_count + 1;
    else
      -- Add to total and groups
      v_charge := v_listing.price_per_kg * v_item.quantity_kg;
      v_total_charge := v_total_charge + v_charge;
      
      v_matched_lines := v_matched_lines || jsonb_build_object(
        'crop_id', v_item.crop_id,
        'farmer_id', coalesce(v_item.preferred_farmer_id, v_listing.farmer_profile_id),
        'listing_id', v_listing.id,
        'quantity_kg', v_item.quantity_kg,
        'price_per_kg', v_listing.price_per_kg,
        'charge', v_charge,
        'is_substituted', (v_item.preferred_farmer_id is not null and v_listing.farmer_profile_id != v_item.preferred_farmer_id)
      );
    end if;
  end loop;

  -- 3. If nothing matched at all
  if jsonb_array_length(v_matched_lines) = 0 then
    -- Advance next_run_at
    update recurring_order set next_run_at = next_run_at + 
      case v_ro.frequency 
        when 'weekly' then interval '7 days' 
        when 'biweekly' then interval '14 days'
        when 'monthly' then interval '1 month' 
      end
    where id = v_ro.id;

    perform send_notification(
      v_rs.buyer_profile_id,
      'recurring_unfulfilled',
      'Scheduled order unfulfilled',
      'None of the items in your schedule could be matched to active farmers today.',
      jsonb_build_object('schedule_id', v_rs.id),
      'recurring_schedule',
      v_rs.id
    );
    
    return jsonb_build_object('status', 'fully_unfulfilled');
  end if;

  -- 4. Check wallet balance
  select * into v_wallet from wallet where profile_id = v_rs.buyer_profile_id for update;
  if v_wallet is null or v_wallet.balance < v_total_charge then
    -- Advance next_run_at anyway
    update recurring_order set next_run_at = next_run_at + 
      case v_ro.frequency 
        when 'weekly' then interval '7 days' 
        when 'biweekly' then interval '14 days'
        when 'monthly' then interval '1 month' 
      end
    where id = v_ro.id;

    perform send_notification(
      v_rs.buyer_profile_id,
      'recurring_skipped_low_balance',
      'Scheduled order skipped: Low Balance',
      format('Wallet balance is insufficient for scheduled order "%s". Please top up.', v_rs.label),
      jsonb_build_object('schedule_id', v_rs.id, 'required_amount', v_total_charge, 'current_balance', coalesce(v_wallet.balance, 0)),
      'recurring_schedule',
      v_rs.id
    );

    return jsonb_build_object('status', 'skipped_low_balance');
  end if;

  -- 5. Deduct wallet
  update wallet set balance = balance - v_total_charge, updated_at = now() where id = v_wallet.id;
  
  insert into wallet_transaction (wallet_id, type, amount, description)
  values (v_wallet.id, 'debit', v_total_charge, format('Recurring order payment for %s', v_rs.label));

  -- 6. Create orders per farmer
  for v_farmer_id in select distinct (value->>'farmer_id')::uuid from jsonb_array_elements(v_matched_lines)
  loop
    v_farmer_total := 0;
    
    -- calculate totals for this farmer
    for v_line in select * from jsonb_array_elements(v_matched_lines) where (value->>'farmer_id')::uuid = v_farmer_id
    loop
      v_farmer_total := v_farmer_total + (v_line.value->>'charge')::numeric;
    end loop;
    
    -- create order (status is 'placed')
    insert into orders (
      checkout_group_id, buyer_profile_id, farmer_profile_id, status, source,
      subtotal_amount, delivery_fee_amount, total_amount,
      delivery_address, delivery_location
    ) values (
      v_checkout_group_id, v_rs.buyer_profile_id, v_farmer_id, 'placed', 'recurring',
      v_farmer_total, 0, v_farmer_total,
      v_ro.delivery_address, v_ro.delivery_location
    ) returning id into v_order_id;
    
    -- insert items
    for v_line in select * from jsonb_array_elements(v_matched_lines) where (value->>'farmer_id')::uuid = v_farmer_id
    loop
      insert into order_item (
        order_id, produce_listing_id, crop_id, quantity_kg, price_per_kg
      ) values (
        v_order_id, (v_line.value->>'listing_id')::uuid, (v_line.value->>'crop_id')::uuid, 
        (v_line.value->>'quantity_kg')::numeric, (v_line.value->>'price_per_kg')::numeric
      );
    end loop;
  end loop;

  -- Advance next_run_at
  update recurring_order set next_run_at = next_run_at + 
    case v_ro.frequency 
      when 'weekly' then interval '7 days' 
      when 'biweekly' then interval '14 days'
      when 'monthly' then interval '1 month' 
    end
  where id = v_ro.id;

  perform send_notification(
    v_rs.buyer_profile_id,
    'recurring_fulfilled',
    'Scheduled order placed',
    format('Your scheduled order "%s" has been successfully placed.', v_rs.label),
    jsonb_build_object('schedule_id', v_rs.id, 'total_charged', v_total_charge),
    'recurring_schedule',
    v_rs.id
  );

  return jsonb_build_object('status', 'fulfilled', 'total_charged', v_total_charge);
end;
$$;

-- 3. Add skip_next_recurring_order RPC
create or replace function skip_next_recurring_order(p_recurring_order_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_ro record;
begin
  select * into v_ro from recurring_order where id = p_recurring_order_id for update;
  if v_ro.id is not null then
    update recurring_order set next_run_at = next_run_at + 
      case v_ro.frequency 
        when 'weekly' then interval '7 days' 
        when 'biweekly' then interval '14 days'
        when 'monthly' then interval '1 month' 
      end
    where id = v_ro.id;
  end if;
end;
$$;
