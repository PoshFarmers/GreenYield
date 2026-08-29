-- ============================================================
-- GreenYield — notification wiring
-- Builds on the `notification` table from 20260827092248_notifications.sql.
-- Adds: the missing delete policy, a reusable send_notification() helper
-- (the "Notification Service" any trigger/Edge Function calls), and the
-- actual event hooks — order status changes, delivery assignment,
-- payments, refunds, and new messages — that raise notifications.
-- ============================================================

-- Clients can already select/update (mark read) their own notifications;
-- the original migration didn't grant delete, which the UI needs for
-- swipe-to-dismiss.
create policy "notification_delete_own" on notification
  for delete using (auth.uid() = profile_id);

-- ------------------------------------------------------------
-- Reusable notification sender. Runs as the table owner
-- (security definer) so it can insert regardless of caller, but is
-- granted to service_role only — client code must never call this
-- directly, only trusted backend code (this migration's triggers,
-- Edge Functions, or other security-definer functions).
-- ------------------------------------------------------------
create or replace function send_notification(
  p_profile_id    uuid,
  p_type          text,
  p_title         text,
  p_body          text default null,
  p_payload       jsonb default '{}'::jsonb,
  p_source_table  text default null,
  p_source_id     uuid default null
) returns notification
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row notification;
begin
  insert into notification (
    profile_id, type, title, body, payload, source_table, source_id
  )
  values (
    p_profile_id, p_type, p_title, p_body, p_payload, p_source_table, p_source_id
  )
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function send_notification(uuid, text, text, text, jsonb, text, uuid)
  from public, anon, authenticated;
grant execute on function send_notification(uuid, text, text, text, jsonb, text, uuid)
  to service_role;

-- ------------------------------------------------------------
-- Order status changes -> notify both sides.
-- Replaces the function from 20260827093223_orders.sql, adding a
-- notification after the status/history write. Behaviour is otherwise
-- unchanged, so every existing caller (cancel_order,
-- transition_delivery_status) keeps working as-is.
-- ------------------------------------------------------------
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
begin
  select * into v_order from orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'Order % not found', p_order_id;
  end if;

  v_allowed := case v_order.status
    when 'placed'     then array['confirmed','cancelled']::order_status[]
    when 'confirmed'  then array['assigned','cancelled']::order_status[]
    when 'assigned'   then array['picked_up','cancelled']::order_status[]
    when 'picked_up'  then array['in_transit']::order_status[]
    when 'in_transit' then array['delivered']::order_status[]
    when 'delivered'  then array['completed']::order_status[]
    else array[]::order_status[]
  end;

  if not (p_new_status = any(v_allowed)) then
    raise exception 'Invalid transition from % to % for order %', v_order.status, p_new_status, p_order_id
      using errcode = 'P0001';
  end if;

  update orders set status = p_new_status, updated_at = now() where id = p_order_id
  returning * into v_order;

  insert into order_status_history (order_id, status, changed_by, note)
  values (p_order_id, p_new_status, p_changed_by, p_note);

  -- Both sides watch the same order; each gets a copy addressed to them.
  perform send_notification(
    v_order.buyer_profile_id,
    'order_status_changed',
    format('Order update: %s', p_new_status),
    format('Your order is now %s.', p_new_status),
    jsonb_build_object('order_id', v_order.id, 'status', p_new_status),
    'orders',
    v_order.id
  );
  perform send_notification(
    v_order.farmer_profile_id,
    'order_status_changed',
    format('Order update: %s', p_new_status),
    format('Order %s is now %s.', v_order.id, p_new_status),
    jsonb_build_object('order_id', v_order.id, 'status', p_new_status),
    'orders',
    v_order.id
  );

  return v_order;
end;
$$ language plpgsql security definer;

revoke execute on function transition_order_status(uuid, order_status, uuid, text) from public;
grant execute on function transition_order_status(uuid, order_status, uuid, text) to service_role;

-- ------------------------------------------------------------
-- Delivery assignment -> notify the driver they've got a pickup.
-- ------------------------------------------------------------
create or replace function notify_delivery_assignment() returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_current then
    perform send_notification(
      new.driver_profile_id,
      'delivery_assigned',
      'New pickup assigned',
      'A delivery has been assigned to you. Check the details before heading out.',
      jsonb_build_object('delivery_id', new.delivery_id),
      'delivery',
      new.delivery_id
    );
  end if;
  return new;
end;
$$;

create trigger trg_notify_delivery_assignment
  after insert on delivery_assignment
  for each row execute function notify_delivery_assignment();

-- ------------------------------------------------------------
-- Payment captured -> notify the buyer their payment succeeded.
-- ------------------------------------------------------------
create or replace function notify_payment_status() returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'captured' and old.status is distinct from 'captured' then
    perform send_notification(
      new.buyer_profile_id,
      'payment_received',
      'Payment successful',
      format('Your payment of %s has been processed.', new.amount),
      jsonb_build_object('payment_id', new.id, 'order_id', new.order_id, 'amount', new.amount),
      'payment',
      new.id
    );
  elsif new.status = 'failed' and old.status is distinct from 'failed' then
    perform send_notification(
      new.buyer_profile_id,
      'payment_failed',
      'Payment failed',
      'Your payment could not be processed. Please try again.',
      jsonb_build_object('payment_id', new.id, 'order_id', new.order_id),
      'payment',
      new.id
    );
  end if;
  return new;
end;
$$;

create trigger trg_notify_payment_status
  after update on payment
  for each row execute function notify_payment_status();

-- ------------------------------------------------------------
-- Refund processed -> notify the buyer.
-- ------------------------------------------------------------
create or replace function notify_refund() returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_buyer_profile_id uuid;
begin
  select buyer_profile_id into v_buyer_profile_id
  from payment where id = new.payment_id;

  if v_buyer_profile_id is not null then
    perform send_notification(
      v_buyer_profile_id,
      'refund_processed',
      'Refund processed',
      format('A refund of %s has been issued to your wallet.', new.amount),
      jsonb_build_object('refund_id', new.id, 'payment_id', new.payment_id, 'amount', new.amount),
      'refund',
      new.id
    );
  end if;
  return new;
end;
$$;

create trigger trg_notify_refund
  after insert on refund
  for each row execute function notify_refund();

-- ------------------------------------------------------------
-- New message -> notify every other participant in the conversation.
-- ------------------------------------------------------------
create or replace function notify_new_message() returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recipient record;
begin
  for v_recipient in
    select profile_id from conversation_participant
    where conversation_id = new.conversation_id
      and profile_id <> new.sender_id
  loop
    perform send_notification(
      v_recipient.profile_id,
      'new_message',
      'New message',
      left(coalesce(new.body, 'Sent an attachment'), 140),
      jsonb_build_object('conversation_id', new.conversation_id, 'message_id', new.id),
      'message',
      new.id
    );
  end loop;
  return new;
end;
$$;

create trigger trg_notify_new_message
  after insert on message
  for each row execute function notify_new_message();
