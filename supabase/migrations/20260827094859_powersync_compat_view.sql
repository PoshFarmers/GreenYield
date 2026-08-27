-- PowerSync replicates most reliably with plain scalar columns. These
-- triggers mirror enum/geography columns into text/GeoJSON columns used
-- by publication streams and local SQLite schemas.

create or replace function set_profile_powersync_mirrors()
returns trigger as $$
begin
  new.active_role_text := new.active_role::text;
  new.preferred_language_text := new.preferred_language::text;
  new.location_geojson := case
    when new.location_point is null then null
    else ST_AsGeoJSON(new.location_point)
  end;
  return new;
end;
$$ language plpgsql;

create or replace function set_crop_powersync_mirrors()
returns trigger as $$
begin
  new.category_text := new.category::text;
  return new;
end;
$$ language plpgsql;

create or replace function set_buyer_profile_powersync_mirrors()
returns trigger as $$
begin
  new.buyer_type_text := new.buyer_type::text;
  return new;
end;
$$ language plpgsql;

create or replace function set_vehicle_powersync_mirrors()
returns trigger as $$
begin
  new.vehicle_type_text := new.vehicle_type::text;
  return new;
end;
$$ language plpgsql;

create or replace function set_conversation_powersync_mirrors()
returns trigger as $$
begin
  new.context_type_text := new.context_type::text;
  return new;
end;
$$ language plpgsql;

create or replace function set_notification_preference_powersync_mirrors()
returns trigger as $$
begin
  new.channel_text := new.channel::text;
  return new;
end;
$$ language plpgsql;

create or replace function set_produce_listing_powersync_mirrors()
returns trigger as $$
begin
  new.status_text := new.status::text;
  return new;
end;
$$ language plpgsql;

create or replace function set_orders_powersync_mirrors()
returns trigger as $$
begin
  new.status_text := new.status::text;
  new.delivery_location_geojson := case
    when new.delivery_location is null then null
    else ST_AsGeoJSON(new.delivery_location)
  end;
  return new;
end;
$$ language plpgsql;

create or replace function set_order_status_history_powersync_mirrors()
returns trigger as $$
begin
  new.status_text := new.status::text;
  return new;
end;
$$ language plpgsql;

create or replace function set_recurring_order_powersync_mirrors()
returns trigger as $$
begin
  new.frequency_text := new.frequency::text;
  new.status_text := new.status::text;
  new.delivery_location_geojson := case
    when new.delivery_location is null then null
    else ST_AsGeoJSON(new.delivery_location)
  end;
  return new;
end;
$$ language plpgsql;

create or replace function set_journey_powersync_mirrors()
returns trigger as $$
begin
  new.status_text := new.status::text;
  return new;
end;
$$ language plpgsql;

create or replace function set_route_stop_powersync_mirrors()
returns trigger as $$
begin
  new.stop_type_text := new.stop_type::text;
  new.location_geojson := case
    when new.location_point is null then null
    else ST_AsGeoJSON(new.location_point)
  end;
  return new;
end;
$$ language plpgsql;

create or replace function set_delivery_powersync_mirrors()
returns trigger as $$
begin
  new.status_text := new.status::text;
  new.pickup_location_geojson := case
    when new.pickup_location_point is null then null
    else ST_AsGeoJSON(new.pickup_location_point)
  end;
  new.dropoff_location_geojson := case
    when new.dropoff_location_point is null then null
    else ST_AsGeoJSON(new.dropoff_location_point)
  end;
  return new;
end;
$$ language plpgsql;

create or replace function set_delivery_tracking_powersync_mirrors()
returns trigger as $$
begin
  new.location_geojson := case
    when new.location_point is null then null
    else ST_AsGeoJSON(new.location_point)
  end;
  return new;
end;
$$ language plpgsql;

create or replace function set_wallet_transaction_powersync_mirrors()
returns trigger as $$
begin
  new.type_text := new.type::text;
  return new;
end;
$$ language plpgsql;

create or replace function set_payment_powersync_mirrors()
returns trigger as $$
begin
  new.method_text := new.method::text;
  new.status_text := new.status::text;
  return new;
end;
$$ language plpgsql;

create or replace function set_refund_request_powersync_mirrors()
returns trigger as $$
begin
  new.status_text := new.status::text;
  return new;
end;
$$ language plpgsql;

do $$
begin
  if to_regclass('public.profile') is not null then
    alter table profile
      add column if not exists active_role_text text,
      add column if not exists preferred_language_text text,
      add column if not exists location_geojson text;

    drop trigger if exists trg_profile_powersync_mirrors on profile;
    create trigger trg_profile_powersync_mirrors
      before insert or update of active_role, preferred_language, location_point on profile
      for each row execute function set_profile_powersync_mirrors();

    update profile
    set active_role = active_role,
        preferred_language = preferred_language,
        location_point = location_point;
  end if;

  if to_regclass('public.crop') is not null then
    alter table crop add column if not exists category_text text;
    drop trigger if exists trg_crop_powersync_mirrors on crop;
    create trigger trg_crop_powersync_mirrors
      before insert or update of category on crop
      for each row execute function set_crop_powersync_mirrors();
    update crop set category = category;
  end if;

  if to_regclass('public.buyer_profile') is not null then
    alter table buyer_profile add column if not exists buyer_type_text text;
    drop trigger if exists trg_buyer_profile_powersync_mirrors on buyer_profile;
    create trigger trg_buyer_profile_powersync_mirrors
      before insert or update of buyer_type on buyer_profile
      for each row execute function set_buyer_profile_powersync_mirrors();
    update buyer_profile set buyer_type = buyer_type;
  end if;

  if to_regclass('public.vehicle') is not null then
    alter table vehicle add column if not exists vehicle_type_text text;
    drop trigger if exists trg_vehicle_powersync_mirrors on vehicle;
    create trigger trg_vehicle_powersync_mirrors
      before insert or update of vehicle_type on vehicle
      for each row execute function set_vehicle_powersync_mirrors();
    update vehicle set vehicle_type = vehicle_type;
  end if;

  if to_regclass('public.conversation') is not null then
    alter table conversation add column if not exists context_type_text text;
    drop trigger if exists trg_conversation_powersync_mirrors on conversation;
    create trigger trg_conversation_powersync_mirrors
      before insert or update of context_type on conversation
      for each row execute function set_conversation_powersync_mirrors();
    update conversation set context_type = context_type;
  end if;

  if to_regclass('public.notification_preference') is not null then
    alter table notification_preference add column if not exists channel_text text;
    drop trigger if exists trg_notification_preference_powersync_mirrors on notification_preference;
    create trigger trg_notification_preference_powersync_mirrors
      before insert or update of channel on notification_preference
      for each row execute function set_notification_preference_powersync_mirrors();
    update notification_preference set channel = channel;
  end if;

  if to_regclass('public.produce_listing') is not null then
    alter table produce_listing add column if not exists status_text text;
    drop trigger if exists trg_produce_listing_powersync_mirrors on produce_listing;
    create trigger trg_produce_listing_powersync_mirrors
      before insert or update of status on produce_listing
      for each row execute function set_produce_listing_powersync_mirrors();
    update produce_listing set status = status;
  end if;

  if to_regclass('public.orders') is not null then
    alter table orders
      add column if not exists status_text text,
      add column if not exists delivery_location_geojson text;
    drop trigger if exists trg_orders_powersync_mirrors on orders;
    create trigger trg_orders_powersync_mirrors
      before insert or update of status, delivery_location on orders
      for each row execute function set_orders_powersync_mirrors();
    update orders
    set status = status,
        delivery_location = delivery_location;
  end if;

  if to_regclass('public.order_status_history') is not null then
    alter table order_status_history add column if not exists status_text text;
    drop trigger if exists trg_order_status_history_powersync_mirrors on order_status_history;
    create trigger trg_order_status_history_powersync_mirrors
      before insert or update of status on order_status_history
      for each row execute function set_order_status_history_powersync_mirrors();
    update order_status_history set status = status;
  end if;

  if to_regclass('public.recurring_order') is not null then
    alter table recurring_order
      add column if not exists frequency_text text,
      add column if not exists status_text text,
      add column if not exists delivery_location_geojson text;
    drop trigger if exists trg_recurring_order_powersync_mirrors on recurring_order;
    create trigger trg_recurring_order_powersync_mirrors
      before insert or update of frequency, status, delivery_location on recurring_order
      for each row execute function set_recurring_order_powersync_mirrors();
    update recurring_order
    set frequency = frequency,
        status = status,
        delivery_location = delivery_location;
  end if;

  if to_regclass('public.journey') is not null then
    alter table journey add column if not exists status_text text;
    drop trigger if exists trg_journey_powersync_mirrors on journey;
    create trigger trg_journey_powersync_mirrors
      before insert or update of status on journey
      for each row execute function set_journey_powersync_mirrors();
    update journey set status = status;
  end if;

  if to_regclass('public.route_stop') is not null then
    alter table route_stop
      add column if not exists stop_type_text text,
      add column if not exists location_geojson text;
    drop trigger if exists trg_route_stop_powersync_mirrors on route_stop;
    create trigger trg_route_stop_powersync_mirrors
      before insert or update of stop_type, location_point on route_stop
      for each row execute function set_route_stop_powersync_mirrors();
    update route_stop
    set stop_type = stop_type,
        location_point = location_point;
  end if;

  if to_regclass('public.delivery') is not null then
    alter table delivery
      add column if not exists status_text text,
      add column if not exists pickup_location_geojson text,
      add column if not exists dropoff_location_geojson text;
    drop trigger if exists trg_delivery_powersync_mirrors on delivery;
    create trigger trg_delivery_powersync_mirrors
      before insert or update of status, pickup_location_point, dropoff_location_point on delivery
      for each row execute function set_delivery_powersync_mirrors();
    update delivery
    set status = status,
        pickup_location_point = pickup_location_point,
        dropoff_location_point = dropoff_location_point;
  end if;

  if to_regclass('public.delivery_tracking') is not null then
    alter table delivery_tracking add column if not exists location_geojson text;
    drop trigger if exists trg_delivery_tracking_powersync_mirrors on delivery_tracking;
    create trigger trg_delivery_tracking_powersync_mirrors
      before insert or update of location_point on delivery_tracking
      for each row execute function set_delivery_tracking_powersync_mirrors();
    update delivery_tracking set location_point = location_point;
  end if;

  if to_regclass('public.wallet_transaction') is not null then
    alter table wallet_transaction add column if not exists type_text text;
    drop trigger if exists trg_wallet_transaction_powersync_mirrors on wallet_transaction;
    create trigger trg_wallet_transaction_powersync_mirrors
      before insert or update of type on wallet_transaction
      for each row execute function set_wallet_transaction_powersync_mirrors();
    update wallet_transaction set type = type;
  end if;

  if to_regclass('public.payment') is not null then
    alter table payment
      add column if not exists method_text text,
      add column if not exists status_text text;
    drop trigger if exists trg_payment_powersync_mirrors on payment;
    create trigger trg_payment_powersync_mirrors
      before insert or update of method, status on payment
      for each row execute function set_payment_powersync_mirrors();
    update payment set method = method, status = status;
  end if;

  if to_regclass('public.refund_request') is not null then
    alter table refund_request add column if not exists status_text text;
    drop trigger if exists trg_refund_request_powersync_mirrors on refund_request;
    create trigger trg_refund_request_powersync_mirrors
      before insert or update of status on refund_request
      for each row execute function set_refund_request_powersync_mirrors();
    update refund_request set status = status;
  end if;
end;
$$;