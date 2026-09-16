-- ============================================================
-- Add 'packed' to the order_status ENUM and wire it into the
-- state machine. Also creates the client-callable
-- mark_order_packed() RPC that lets a farmer signal their order
-- is ready for driver pickup.
-- ============================================================

-- Step 1: Extend the enum.
-- IF NOT EXISTS is not supported for ALTER TYPE ADD VALUE in
-- older Postgres versions, so we guard with a DO block.
do $$
begin
  if not exists (
    select 1 from pg_enum
    where enumtypid = 'order_status'::regtype
      and enumlabel = 'packed'
  ) then
    alter type order_status add value 'packed' after 'assigned';
  end if;
end;
$$;

-- Step 2: Replace transition_order_status to recognise the new
-- 'packed' value.  Replacing the function is safe because enum
-- values are committed by the DO block above before this runs.
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

  return v_order;
end;
$$ language plpgsql security definer;

-- Keep the same grants as the original.
revoke execute on function transition_order_status(uuid, order_status, uuid, text) from public;
grant  execute on function transition_order_status(uuid, order_status, uuid, text) to service_role;

-- ============================================================
-- Client-callable RPC: farmer marks their sub-order as packed.
-- Visible to the assigned driver so they know it is ready for
-- pickup.
-- ============================================================
create or replace function mark_order_packed(
  p_order_id  uuid,
  p_note      text default null
)
returns orders as $$
declare
  v_order orders;
begin
  select * into v_order from orders where id = p_order_id;

  if v_order.id is null then
    raise exception 'Order % not found', p_order_id using errcode = 'P0001';
  end if;

  -- Only the farmer on this order may call this.
  if auth.uid() is distinct from v_order.farmer_profile_id then
    raise exception 'Not authorized to mark order % as packed', p_order_id
      using errcode = '42501';
  end if;

  -- Valid source statuses: confirmed or assigned.
  if v_order.status not in ('confirmed', 'assigned') then
    raise exception 'Order % cannot be packed from status %',
      p_order_id, v_order.status
      using errcode = 'P0001';
  end if;

  return transition_order_status(p_order_id, 'packed', auth.uid(), coalesce(p_note, 'farmer: marked packed'));
end;
$$ language plpgsql security definer;

revoke execute on function mark_order_packed(uuid, text) from public;
grant  execute on function mark_order_packed(uuid, text) to authenticated;

-- ============================================================
-- Also update transition_delivery_status so that the order-side
-- mirror starts from 'packed' correctly.  The delivery's OWN
-- status enum does not include 'packed', so we only touch the
-- order mirror mapping.  The existing mapping already handles
-- picked_up → in_transit → delivered correctly; this replaces
-- the whole function to be safe.
-- ============================================================
create or replace function transition_delivery_status(
  p_delivery_id  uuid,
  p_new_status   delivery_status
)
returns delivery as $$
declare
  v_delivery      delivery;
  v_order_status  order_status;
  v_caller        uuid := auth.uid();
begin
  -- auth.uid() is null for service-role callers. A non-null caller
  -- must be the driver currently assigned to this delivery.
  if v_caller is not null and not exists (
    select 1 from delivery_assignment da
    where da.delivery_id = p_delivery_id
      and da.driver_profile_id = v_caller
      and da.is_current
  ) then
    raise exception 'Not authorized to change status of delivery %', p_delivery_id
      using errcode = '42501';
  end if;

  update delivery
     set status       = p_new_status,
         assigned_at  = case when p_new_status = 'assigned'   then now() else assigned_at  end,
         picked_up_at = case when p_new_status = 'picked_up'  then now() else picked_up_at end,
         delivered_at = case when p_new_status = 'delivered'  then now() else delivered_at end,
         updated_at   = now()
   where id = p_delivery_id
  returning * into v_delivery;

  if v_delivery.id is null then
    raise exception 'Delivery % not found', p_delivery_id;
  end if;

  -- Map delivery status → matching order status.
  v_order_status := case p_new_status
    when 'assigned'   then 'assigned'::order_status
    when 'picked_up'  then 'picked_up'::order_status
    when 'in_transit' then 'in_transit'::order_status
    when 'delivered'  then 'delivered'::order_status
    else null
  end;

  if v_order_status is not null then
    perform transition_order_status(
      v_delivery.order_id, v_order_status, null, 'auto: delivery status sync'
    );
  end if;

  return v_delivery;
end;
$$ language plpgsql security definer;

revoke execute on function transition_delivery_status(uuid, delivery_status) from public;
grant  execute on function transition_delivery_status(uuid, delivery_status) to authenticated, service_role;
