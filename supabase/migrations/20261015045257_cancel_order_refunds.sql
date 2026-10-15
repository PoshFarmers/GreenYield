-- Task 5: cancel_order refunds + restock + driver unassign, refund preview,
-- method-aware refund notification, refund/cancel info in get_order_detail.
do $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'apply_wallet_transaction' and p.pronargs = 7) then
    raise exception 'Task 2 migration missing: 7-arg apply_wallet_transaction';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'mockgw_refund') then
    raise exception 'Task 1 migration missing: mockgw_refund';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'payment' and column_name = 'linked_card_id') then
    raise exception 'Task 3 migration missing: payment.linked_card_id';
  end if;
end;
$$;

-- ------------------------------------------------------------
-- Single source of truth for "what would a cancellation refund?"
-- Used by cancel_order and get_cancellation_preview so they can't diverge.
-- ------------------------------------------------------------
create or replace function order_refund_plan(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_payment payment;
  v_card    linked_card;
begin
  select * into v_payment from payment where order_id = p_order_id;

  if v_payment.id is null then
    return jsonb_build_object('refundable', false, 'amount', 0, 'destination', 'none', 'reason', 'no_payment');
  end if;
  if v_payment.status = 'refunded' then
    return jsonb_build_object('refundable', false, 'amount', 0, 'destination', 'none', 'reason', 'already_refunded');
  end if;
  if v_payment.status <> 'captured' then
    return jsonb_build_object('refundable', false, 'amount', 0, 'destination', 'none', 'reason', 'payment_not_captured');
  end if;
  if v_payment.amount <= 0 then
    return jsonb_build_object('refundable', false, 'amount', 0, 'destination', 'none', 'reason', 'nothing_to_refund');
  end if;

  if v_payment.method = 'wallet' then
    -- Only refund money that was actually debited from the buyer's wallet.
    if not exists (
      select 1 from wallet_transaction wt join wallet w on w.id = wt.wallet_id
      where w.profile_id = v_payment.buyer_profile_id
        and wt.type = 'payment'
        and wt.reference_id in (p_order_id, v_payment.id)
    ) then
      return jsonb_build_object('refundable', false, 'amount', 0, 'destination', 'none', 'reason', 'no_wallet_debit_found');
    end if;
    return jsonb_build_object('refundable', true, 'amount', v_payment.amount,
                              'destination', 'wallet', 'reason', null);
  end if;

  -- Card: legacy demo captures (no gateway charge) never moved money.
  if v_payment.linked_card_id is null or v_payment.gateway_transaction_id is null then
    return jsonb_build_object('refundable', false, 'amount', 0, 'destination', 'none', 'reason', 'legacy_card_payment');
  end if;
  select * into v_card from linked_card where id = v_payment.linked_card_id;
  return jsonb_build_object('refundable', true, 'amount', v_payment.amount,
                            'destination', 'card', 'reason', null,
                            'card_last4', v_card.last4, 'card_brand', v_card.brand::text);
end;
$$;

revoke all on function order_refund_plan(uuid) from public, anon, authenticated;
grant execute on function order_refund_plan(uuid) to service_role;

-- ------------------------------------------------------------
-- Client preview for the cancel dialog (buyer or farmer of the order).
-- Card details are only returned to the buyer.
-- ------------------------------------------------------------
create or replace function get_cancellation_preview(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_order orders;
  v_plan  jsonb;
begin
  select * into v_order from orders where id = p_order_id;
  if v_order.id is null then
    raise exception 'Order not found' using errcode = 'P0002';
  end if;
  if v_uid is distinct from v_order.buyer_profile_id
     and v_uid is distinct from v_order.farmer_profile_id then
    raise exception 'Access denied' using errcode = '42501';
  end if;

  v_plan := order_refund_plan(p_order_id);
  if v_uid is distinct from v_order.buyer_profile_id then
    v_plan := v_plan - 'card_last4' - 'card_brand';
  end if;
  return v_plan;
end;
$$;

revoke all on function get_cancellation_preview(uuid) from public, anon;
grant execute on function get_cancellation_preview(uuid) to authenticated;

-- ------------------------------------------------------------
-- cancel_order: copied from 20260827093223 (latest, only definition).
-- Kept: buyer/farmer-only authorization, state machine via transition_order_status.
-- Added: restock, refund (wallet or card), pending payment cleanup,
-- delivery unassign, driver notification. Reason goes to the history note.
-- ------------------------------------------------------------
create or replace function cancel_order(
  p_order_id  uuid,
  p_note      text default null
)
returns orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order    orders;
  v_note     text := left(nullif(btrim(coalesce(p_note, '')), ''), 300);
  v_plan     jsonb;
  v_payment  payment;
  v_refund   refund;
  v_gw       gateway_transaction;
  v_item     record;
  v_driver   uuid;
  v_display  text;
begin
  select * into v_order from orders where id = p_order_id;
  if v_order.id is null then
    raise exception 'Order % not found', p_order_id;
  end if;

  if auth.uid() is distinct from v_order.buyer_profile_id
     and auth.uid() is distinct from v_order.farmer_profile_id then
    raise exception 'Not authorized to cancel order %', p_order_id
      using errcode = '42501';
  end if;

  -- Locks the order row and rejects non-cancellable states, so a second
  -- cancel (or a cancel after pickup) fails here before anything moves.
  v_order := transition_order_status(p_order_id, 'cancelled', auth.uid(), v_note);
  v_display := 'GY-' || upper(substr(replace(p_order_id::text, '-', ''), 1, 6));

  -- 1. Stock returns to the listings.
  for v_item in
    select produce_listing_id, quantity_kg
    from order_item where order_id = p_order_id
    order by produce_listing_id
  loop
    perform restock_listing_quantity(v_item.produce_listing_id, v_item.quantity_kg);
  end loop;

  -- 2. Payment: refund what was captured, or fail what never completed.
  select * into v_payment from payment where order_id = p_order_id for update;
  if v_payment.id is not null then
    v_plan := order_refund_plan(p_order_id);

    if (v_plan->>'refundable')::boolean then
      if v_payment.method = 'card' then
        -- order id as request id: a repeat can never refund the card twice.
        v_gw := mockgw_refund(
          v_payment.buyer_profile_id, v_payment.linked_card_id, v_payment.amount,
          'order_cancel', p_order_id, p_order_id
        );
      end if;

      insert into refund (payment_id, amount, refund_type)
      values (v_payment.id, v_payment.amount, 'automatic')
      returning * into v_refund;  -- fires trg_notify_refund

      if v_payment.method = 'wallet' then
        perform apply_wallet_transaction(
          v_payment.buyer_profile_id, 'refund', v_payment.amount, 'refund', v_refund.id,
          'Order refund',
          jsonb_build_object(
            'order_id', p_order_id,
            'order_display_id', v_display,
            'refund_id', v_refund.id,
            'destination', 'wallet',
            'reason', 'order_cancelled'
          )
        );
      else
        insert into payment_transaction (payment_id, attempt_no, status, gateway_response)
        values (
          v_payment.id,
          (select coalesce(max(attempt_no), 0) + 1 from payment_transaction where payment_id = v_payment.id),
          'refunded',
          jsonb_build_object(
            'gateway_transaction_id', v_gw.id,
            'gateway_reference', v_gw.gateway_reference,
            'refund_id', v_refund.id,
            'refund_amount', v_payment.amount,
            'card_last4', v_plan->>'card_last4',
            'card_brand', v_plan->>'card_brand'
          )
        );
      end if;

      update payment set status = 'refunded', updated_at = now() where id = v_payment.id;

    elsif v_payment.status in ('pending', 'authorized') then
      update payment set status = 'failed', updated_at = now() where id = v_payment.id;
    end if;
  end if;

  -- 3. Free the driver. (Buyer/farmer are notified by transition_order_status,
  --    the buyer's refund notice by trg_notify_refund.)
  for v_driver in
    update delivery_assignment da
    set is_current = false, unassigned_at = now()
    from delivery d
    where d.id = da.delivery_id and d.order_id = p_order_id and da.is_current
    returning da.driver_profile_id
  loop
    begin
      perform send_notification(
        v_driver,
        'order_cancelled',
        format('Order %s cancelled', v_display),
        format('Order %s was cancelled. You no longer need to collect it.', v_display),
        jsonb_build_object('order_id', p_order_id),
        'orders',
        p_order_id
      );
    exception when others then
      raise warning 'driver cancel notification failed for order %: %', p_order_id, sqlerrm;
    end;
  end loop;

  return v_order;
end;
$$;

revoke all on function cancel_order(uuid, text) from public, anon;
grant execute on function cancel_order(uuid, text) to authenticated;

-- ------------------------------------------------------------
-- notify_refund: copied from 20260829050340 (latest). Change: text names the
-- card when the refund went to a card; payload gains order_id/destination.
-- ------------------------------------------------------------
create or replace function notify_refund() returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment payment;
  v_card    linked_card;
  v_amount  text := to_char(new.amount, 'FM999,999,990.00');
begin
  select * into v_payment from payment where id = new.payment_id;

  if v_payment.id is not null and v_payment.buyer_profile_id is not null then
    if v_payment.method = 'card' and v_payment.linked_card_id is not null then
      select * into v_card from linked_card where id = v_payment.linked_card_id;
    end if;

    perform send_notification(
      v_payment.buyer_profile_id,
      'refund_processed',
      'Refund processed',
      case when v_card.id is not null
        then format('A refund of LKR %s has been issued to your card ending %s.', v_amount, v_card.last4)
        else format('A refund of LKR %s has been issued to your wallet.', v_amount)
      end,
      jsonb_build_object(
        'refund_id', new.id, 'payment_id', new.payment_id,
        'order_id', v_payment.order_id, 'amount', new.amount,
        'destination', case when v_card.id is not null then 'card' else 'wallet' end
      ),
      'refund',
      new.id
    );
  end if;
  return new;
end;
$$;

-- ------------------------------------------------------------
-- get_order_detail: copied from 20261014130000 (latest). Added:
-- refund_* (buyer only) and cancellation_note (all parties).
-- ------------------------------------------------------------
create or replace function get_order_detail(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid          uuid := auth.uid();
  v_order        orders;
  v_delivery     delivery;
  v_da           delivery_assignment;
  v_farmer       profile;
  v_buyer        profile;
  v_driver       profile;
  v_vehicle      vehicle;
  v_items        jsonb;
  v_payment      payment;
  v_card         linked_card;
  v_commission   numeric;
  v_is_buyer     boolean;
  v_is_farmer    boolean;
  v_refund       refund;
  v_cancel_note  text;
begin
  select * into v_order from orders where id = p_order_id;

  if v_order.id is null then
    raise exception 'Order not found' using errcode = 'P0002';
  end if;

  if v_order.buyer_profile_id <> v_uid
     and v_order.farmer_profile_id <> v_uid then
    if not exists (
      select 1
      from delivery d
      join delivery_assignment da on da.delivery_id = d.id and da.is_current
      where d.order_id = p_order_id and da.driver_profile_id = v_uid
    ) then
      raise exception 'Access denied' using errcode = '42501';
    end if;
  end if;

  v_is_buyer  := v_order.buyer_profile_id = v_uid;
  v_is_farmer := v_order.farmer_profile_id = v_uid;

  select * into v_delivery from delivery where order_id = p_order_id limit 1;

  if v_delivery.id is not null then
    select * into v_da
    from delivery_assignment
    where delivery_id = v_delivery.id and is_current = true
    limit 1;
  end if;

  select * into v_farmer from profile where id = v_order.farmer_profile_id;
  select * into v_buyer  from profile where id = v_order.buyer_profile_id;

  if v_da.driver_profile_id is not null then
    select * into v_driver  from profile where id = v_da.driver_profile_id;
    select * into v_vehicle from vehicle where driver_profile_id = v_da.driver_profile_id limit 1;
  end if;

  select * into v_payment from payment where order_id = p_order_id;
  if v_payment.linked_card_id is not null then
    select * into v_card from linked_card where id = v_payment.linked_card_id;
  end if;
  select amount into v_commission from platform_ledger
  where order_id = p_order_id and kind = 'commission';

  -- Task 5
  if v_is_buyer and v_payment.id is not null then
    select * into v_refund from refund
    where payment_id = v_payment.id
    order by processed_at desc limit 1;
  end if;
  select h.note into v_cancel_note from order_status_history h
  where h.order_id = p_order_id and h.status = 'cancelled'
  order by h.changed_at desc limit 1;

  select jsonb_agg(
    jsonb_build_object(
      'id',            oi.id,
      'crop_id',       oi.crop_id,
      'crop_name',     c.name,
      'quantity_kg',   oi.quantity_kg,
      'price_per_kg',  oi.price_per_kg,
      'image_url',     coalesce(pl.image_url, fc.image_url, c.fallback_image_url)
    )
    order by oi.created_at
  )
  into v_items
  from order_item oi
  join crop c on c.id = oi.crop_id
  left join produce_listing pl on pl.id = oi.produce_listing_id
  left join farmer_crop fc
         on fc.farmer_profile_id = v_order.farmer_profile_id
        and fc.crop_id = oi.crop_id
  where oi.order_id = p_order_id;

  return jsonb_build_object(
    'id',                   v_order.id,
    'checkout_group_id',    v_order.checkout_group_id,
    'status',               v_order.status::text,
    'placed_at',            v_order.placed_at,
    'order_date',           v_order.order_date,
    'subtotal_amount',      v_order.subtotal_amount,
    'delivery_fee_amount',  v_order.delivery_fee_amount,
    'tax_amount',           v_order.tax_amount,
    'total_amount',         v_order.total_amount,
    'delivery_address',     v_order.delivery_address,
    'items',                coalesce(v_items, '[]'::jsonb),
    'farmer_profile_id',    v_order.farmer_profile_id,
    'farmer_name',          trim(coalesce(v_farmer.first_name, '') || ' ' || coalesce(v_farmer.last_name, '')),
    'farmer_phone',         v_farmer.phone,
    'buyer_profile_id',     v_order.buyer_profile_id,
    'buyer_name',           trim(coalesce(v_buyer.first_name, '') || ' ' || coalesce(v_buyer.last_name, '')),
    'buyer_phone',          v_buyer.phone,
    'delivery_id',          v_delivery.id,
    'delivery_status',      v_delivery.status::text,
    'driver_profile_id',    v_da.driver_profile_id,
    'driver_name',          case when v_driver.id is not null
                              then trim(coalesce(v_driver.first_name, '') || ' ' || coalesce(v_driver.last_name, ''))
                              else null end,
    'driver_phone',         v_driver.phone,
    'vehicle_type',         v_vehicle.vehicle_type::text,
    'vehicle_plate',        v_vehicle.plate_number,
    'payment_method',       case when v_is_buyer then v_payment.method::text end,
    'payment_status',       case when v_is_buyer then v_payment.status::text end,
    'payment_card_last4',   case when v_is_buyer then v_card.last4 end,
    'payment_card_brand',   case when v_is_buyer then v_card.brand::text end,
    'commission_amount',    case when v_is_farmer then v_commission end,
    'net_payout',           case when v_is_farmer and v_commission is not null
                              then v_order.subtotal_amount - v_commission end,
    'driver_payout',        case when v_commission is not null and not coalesce(v_is_buyer, false)
                                  and not coalesce(v_is_farmer, false)
                              then v_order.delivery_fee_amount end,
    -- Task 5: refund (buyer only) and cancellation reason (everyone)
    'refund_amount',        case when v_is_buyer then v_refund.amount end,
    'refund_destination',   case when v_is_buyer and v_refund.id is not null
                              then case when v_payment.method = 'card' then 'card' else 'wallet' end end,
    'refund_card_last4',    case when v_is_buyer and v_refund.id is not null and v_payment.method = 'card'
                              then v_card.last4 end,
    'refund_card_brand',    case when v_is_buyer and v_refund.id is not null and v_payment.method = 'card'
                              then v_card.brand::text end,
    'refunded_at',          case when v_is_buyer then v_refund.processed_at end,
    'cancellation_note',    v_cancel_note
  );
end;
$$;

revoke all on function get_order_detail(uuid) from public, anon;
grant execute on function get_order_detail(uuid) to authenticated;
