-- ============================================================
-- MAIN COMPONENT 3: Delivery & Logistics Management
-- Depends on Component 2's `orders` table (run after 02-component-orders).
-- ============================================================

create type delivery_status as enum ('unassigned', 'assigned', 'picked_up', 'in_transit', 'delivered');

create table delivery (
  id                       uuid primary key default gen_random_uuid(),
  order_id                 uuid not null unique references orders(id) on delete restrict,
  journey_id               uuid references journey(id),
  pickup_location_text     text,
  pickup_location_point    geography(Point, 4326),
  dropoff_location_text    text,
  dropoff_location_point   geography(Point, 4326),
  status                   delivery_status not null default 'unassigned',
  assigned_at              timestamptz,
  picked_up_at             timestamptz,
  delivered_at             timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

create index idx_delivery_journey on delivery(journey_id);
create index idx_delivery_status  on delivery(status);

create trigger trg_delivery_updated_at before update on delivery for each row execute function set_updated_at();

alter table route_stop
  add constraint fk_route_stop_delivery foreign key (delivery_id) references delivery(id);

create table delivery_assignment (
  id                 uuid primary key default gen_random_uuid(),
  delivery_id        uuid not null references delivery(id) on delete cascade,
  driver_profile_id  uuid not null references driver_profile(profile_id),
  vehicle_id         uuid not null references vehicle(id),
  assigned_at        timestamptz not null default now(),
  unassigned_at      timestamptz,
  is_current         boolean not null default true
);

create index idx_delivery_assignment_delivery        on delivery_assignment(delivery_id);
create index idx_delivery_assignment_driver_current  on delivery_assignment(driver_profile_id) where is_current;

alter table delivery enable row level security;
alter table delivery_assignment enable row level security;

create policy "delivery_select_related" on delivery for select using (
  exists (select 1 from orders o where o.id = delivery.order_id
          and (auth.uid() = o.buyer_profile_id or auth.uid() = o.farmer_profile_id))
  or exists (select 1 from delivery_assignment da where da.delivery_id = delivery.id
             and da.driver_profile_id = auth.uid() and da.is_current)
);

create policy "delivery_assignment_select_own" on delivery_assignment for select using (auth.uid() = driver_profile_id);

-- Backend-only: transitions delivery status, mirrors the change onto the linked
-- order (via Component 2's transition_order_status), keeping both state machines
-- in sync.
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
  -- auth.uid() is null for service-role callers. A non-null caller must be
  -- the driver currently assigned to this delivery.
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
      assigned_at  = case when p_new_status = 'assigned'  then now() else assigned_at  end,
      picked_up_at = case when p_new_status = 'picked_up' then now() else picked_up_at end,
      delivered_at = case when p_new_status = 'delivered' then now() else delivered_at end,
      updated_at   = now()
  where id = p_delivery_id
  returning * into v_delivery;

  if v_delivery.id is null then
    raise exception 'Delivery % not found', p_delivery_id;
  end if;

  v_order_status := case p_new_status
    when 'assigned'   then 'assigned'
    when 'picked_up'  then 'picked_up'
    when 'in_transit' then 'in_transit'
    when 'delivered'  then 'delivered'
    else null
  end;

  if v_order_status is not null then
    perform transition_order_status(v_delivery.order_id, v_order_status, null, 'auto: delivery status sync');
  end if;

  return v_delivery;
end;
$$ language plpgsql security definer;

-- The assigned driver calls this directly from the field (marking picked_up /
-- in_transit / delivered); the ownership check above restricts it to them.
revoke execute on function transition_delivery_status(uuid, delivery_status) from public;
grant execute on function transition_delivery_status(uuid, delivery_status) to authenticated, service_role;
