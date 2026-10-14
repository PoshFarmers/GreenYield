-- Task 4 part B: order_status_changed notifications restored, payout_received
-- notifications, submit_farmer_review accepts completed, hourly completion cron.

-- ------------------------------------------------------------------
-- transition_order_status: copied from 20260915000000 (latest: 'packed' in the state
-- machine) + the notification block from 20260829050340 (dropped by 20260915000000).
-- Notification errors never block a transition.
-- ------------------------------------------------------------------
create or replace function transition_order_status(
  p_order_id    uuid,
  p_new_status  order_status,
  p_changed_by  uuid default null,
  p_note        text default null
)
returns orders as $$
declare
  v_order   orders;
  v_allowed order_status[];
  v_display text;
  v_label   text;
begin
  select * into v_order from orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'Order % not found', p_order_id;
  end if;

  v_allowed := case v_order.status
    when 'placed'     then array['confirmed','cancelled']::order_status[]
    when 'confirmed'  then array['assigned','packed','cancelled']::order_status[]
    when 'assigned'   then array['packed','cancelled']::order_status[]
    when 'packed'     then array['picked_up','cancelled']::order_status[]
    when 'picked_up'  then array['in_transit']::order_status[]
    when 'in_transit' then array['delivered']::order_status[]
    when 'delivered'  then array['completed']::order_status[]
    else array[]::order_status[]
  end;

  if not (p_new_status = any(v_allowed)) then
    raise exception 'Invalid transition from % to % for order %',
      v_order.status, p_new_status, p_order_id
      using errcode = 'P0001';
  end if;

  update orders
     set status     = p_new_status,
         updated_at = now()
   where id = p_order_id
  returning * into v_order;

  insert into order_status_history (order_id, status, changed_by, note)
  values (p_order_id, p_new_status, p_changed_by, p_note);

  -- Notify both sides (restored; type 'order_status_changed' as before).
  v_display := 'GY-' || upper(substr(replace(p_order_id::text, '-', ''), 1, 6));
  v_label   := replace(p_new_status::text, '_', ' ');
  begin
    perform send_notification(
      v_order.buyer_profile_id,
      'order_status_changed',
      format('Order %s: %s', v_display, v_label),
      format('Your order %s is now %s.', v_display, v_label),
      jsonb_build_object('order_id', v_order.id, 'status', p_new_status::text),
      'orders',
      v_order.id
    );
    perform send_notification(
      v_order.farmer_profile_id,
      'order_status_changed',
      format('Order %s: %s', v_display, v_label),
      format('Order %s is now %s.', v_display, v_label),
      jsonb_build_object('order_id', v_order.id, 'status', p_new_status::text),
      'orders',
      v_order.id
    );
  exception when others then
    raise warning 'order notification failed for order %: %', p_order_id, sqlerrm;
  end;

  return v_order;
end;
$$ language plpgsql security definer;

revoke all on function transition_order_status(uuid, order_status, uuid, text) from public, anon, authenticated;
grant execute on function transition_order_status(uuid, order_status, uuid, text) to service_role;

-- ------------------------------------------------------------------
-- Payout notification helper (internal; swallows errors).
-- ------------------------------------------------------------------
create or replace function notify_payout(
  p_profile_id   uuid,
  p_amount       numeric,
  p_display      text,
  p_order_id     uuid,
  p_source_table text,
  p_source_id    uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform send_notification(
    p_profile_id,
    'payout_received',
    'Payout received',
    format('LKR %s was added to your wallet for order %s.',
           to_char(p_amount, 'FM999,999,990.00'), p_display),
    jsonb_build_object('order_id', p_order_id, 'amount', p_amount),
    p_source_table,
    p_source_id
  );
exception when others then
  raise warning 'payout notification failed for order %: %', p_order_id, sqlerrm;
end;
$$;

revoke all on function notify_payout(uuid, numeric, text, uuid, text, uuid) from public, anon, authenticated;
grant execute on function notify_payout(uuid, numeric, text, uuid, text, uuid) to service_role;

-- ------------------------------------------------------------------
-- settle_order: from 20261014130000 + payout notifications + p_backfill
-- (backfill = no notifications, metadata flag). One signature only.
-- ------------------------------------------------------------------
drop function if exists settle_order(uuid);

create or replace function settle_order(p_order_id uuid, p_backfill boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order      orders;
  v_payment    payment;
  v_delivery   delivery;
  v_driver_id  uuid;
  v_rate       numeric;
  v_commission numeric;
  v_net        numeric;
  v_display    text;
  v_result     jsonb := jsonb_build_object('settled', true);
begin
  select * into v_order from orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'Order % not found', p_order_id;
  end if;
  if v_order.status not in ('delivered', 'completed') then
    raise exception 'Order % is not delivered', p_order_id using errcode = 'P0001';
  end if;

  -- Never block a delivery: orders without a captured payment are simply not settled.
  select * into v_payment from payment where order_id = p_order_id;
  if v_payment.id is null or v_payment.status <> 'captured' then
    return jsonb_build_object('settled', false, 'reason', 'payment_not_captured');
  end if;

  v_display := 'GY-' || upper(substr(replace(p_order_id::text, '-', ''), 1, 6));
  v_rate := coalesce((select value from platform_config where key = 'farmer_commission_rate'), 0.03);
  v_commission := round(v_order.subtotal_amount * v_rate, 2);
  v_net := v_order.subtotal_amount - v_commission;

  -- Farmer: subtotal - commission.
  if v_net > 0 and not exists (
    select 1 from wallet_transaction wt join wallet w on w.id = wt.wallet_id
    where w.profile_id = v_order.farmer_profile_id and wt.type = 'payout'
      and wt.reference_table = 'orders' and wt.reference_id = p_order_id
  ) then
    perform apply_wallet_transaction(
      v_order.farmer_profile_id, 'payout', v_net, 'orders', p_order_id,
      'Order payout',
      jsonb_build_object(
        'order_id', p_order_id, 'order_display_id', v_display,
        'gross', v_order.subtotal_amount, 'commission', v_commission,
        'commission_rate', v_rate, 'net', v_net
      ) || case when p_backfill then jsonb_build_object('backfill', true) else '{}'::jsonb end
    );
    insert into platform_ledger (order_id, kind, amount) values (p_order_id, 'commission', v_commission)
    on conflict (order_id, kind) do nothing;
    if v_order.tax_amount > 0 then
      insert into platform_ledger (order_id, kind, amount) values (p_order_id, 'tax', v_order.tax_amount)
      on conflict (order_id, kind) do nothing;
    end if;
    if not p_backfill then
      perform notify_payout(v_order.farmer_profile_id, v_net, v_display, p_order_id, 'orders', p_order_id);
    end if;
    v_result := v_result || jsonb_build_object('farmer_net', v_net, 'commission', v_commission);
  end if;

  -- Driver: the delivery fee (same reference as the legacy inline payout: 'delivery' + delivery id,
  -- so already-paid drivers are never paid twice).
  select * into v_delivery from delivery where order_id = p_order_id;
  if v_delivery.id is not null and coalesce(v_order.delivery_fee_amount, 0) > 0 then
    select driver_profile_id into v_driver_id
    from delivery_assignment where delivery_id = v_delivery.id and is_current limit 1;

    if v_driver_id is not null and not exists (
      select 1 from wallet_transaction wt join wallet w on w.id = wt.wallet_id
      where w.profile_id = v_driver_id and wt.type = 'payout'
        and wt.reference_table = 'delivery' and wt.reference_id = v_delivery.id
    ) then
      perform apply_wallet_transaction(
        v_driver_id, 'payout', v_order.delivery_fee_amount, 'delivery', v_delivery.id,
        'Delivery payout',
        jsonb_build_object('order_id', p_order_id, 'order_display_id', v_display, 'delivery_id', v_delivery.id)
          || case when p_backfill then jsonb_build_object('backfill', true) else '{}'::jsonb end
      );
      if not p_backfill then
        perform notify_payout(v_driver_id, v_order.delivery_fee_amount, v_display, p_order_id, 'delivery', v_delivery.id);
      end if;
      v_result := v_result || jsonb_build_object('driver_fee', v_order.delivery_fee_amount);
    end if;
  end if;

  return v_result;
end;
$$;

revoke all on function settle_order(uuid, boolean) from public, anon, authenticated;
grant execute on function settle_order(uuid, boolean) to service_role;

-- ------------------------------------------------------------------
-- submit_farmer_review: copied from the farmer_review migration (only definition).
-- Only change: delivered OR completed.
-- ------------------------------------------------------------------
create or replace function submit_farmer_review(
  p_order_id uuid,
  p_rating smallint,
  p_comment text
)
returns farmer_review as $$
declare
  v_order orders%rowtype;
  v_review farmer_review%rowtype;
begin
  if p_rating < 1 or p_rating > 5 then
    raise exception 'rating must be between 1 and 5';
  end if;

  select * into v_order from orders where id = p_order_id;
  if v_order.id is null then
    raise exception 'order not found';
  end if;
  if auth.uid() <> v_order.buyer_profile_id then
    raise exception 'not authorized to review this order';
  end if;
  if v_order.status not in ('delivered', 'completed') then
    raise exception 'order is not yet delivered';
  end if;

  insert into farmer_review (order_id, buyer_profile_id, farmer_profile_id, rating, comment)
  values (p_order_id, v_order.buyer_profile_id, v_order.farmer_profile_id, p_rating, p_comment)
  on conflict (order_id) do update
    set rating = excluded.rating, comment = excluded.comment, updated_at = now()
  returning * into v_review;

  return v_review;
end;
$$ language plpgsql security definer set search_path = public;

revoke all on function submit_farmer_review(uuid, smallint, text) from public, anon;
grant execute on function submit_farmer_review(uuid, smallint, text) to authenticated;

-- ------------------------------------------------------------------
-- Hourly delivered -> completed (UTC). Safe to enable now: reviews accept completed.
-- ------------------------------------------------------------------
do $$
begin
  if to_regnamespace('cron') is null then
    raise warning 'pg_cron is not installed: schedule public.complete_delivered_orders() manually';
    return;
  end if;
  if exists (select 1 from cron.job where jobname = 'complete_delivered_orders') then
    perform cron.unschedule('complete_delivered_orders');
  end if;
  perform cron.schedule('complete_delivered_orders', '0 * * * *',
                        'select public.complete_delivered_orders()');
end;
$$;
