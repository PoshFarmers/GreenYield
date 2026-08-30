-- ============================================================
-- GreenYield — PowerSync compat/publication fixes
--
-- Fixes three issues found while reviewing the schema against
-- 20260829211154_marketplace_buyer_access.sql (last verified migration
-- was 20260827094740_pricing_and_market_intelligence.sql):
--
--   1. profile_role.role (user_role enum) has never had a PowerSync
--      text mirror, even though it's an enum column PowerSync can't
--      replicate reliably.
--   2. refund.refund_type (refund_type enum) has never had a mirror
--      either — only refund_request.status got one back in
--      20260827094859_powersync_compat_view.sql.
--   3. 20260827094922_powersync_publication.sql still lists
--      public.harvest, which 20260829153627_crop_produce_listing_rework.sql
--      dropped. Harmless while the full migration chain runs in order
--      (Postgres drops publication membership automatically when the
--      table is dropped), but a standalone re-run of the publication
--      migration against an already-migrated database will fail with
--      "relation \"harvest\" does not exist". Fixed here by dropping
--      and recreating the publication without it.
-- ============================================================

-- ------------------------------------------------------------
-- 1. profile_role.role mirror
-- ------------------------------------------------------------

alter table profile_role
  add column if not exists role_text text;

create or replace function set_profile_role_powersync_mirrors()
returns trigger as $$
begin
  new.role_text := new.role::text;
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_profile_role_powersync_mirrors on profile_role;
create trigger trg_profile_role_powersync_mirrors
  before insert or update of role on profile_role
  for each row execute function set_profile_role_powersync_mirrors();

-- Backfill existing rows. Must reassign the exact watched column (role)
-- for the `OF column_list` trigger to fire, per the same caveat noted
-- in 20260823070036_powersync_compat_view.sql.
update profile_role set role = role;


-- ------------------------------------------------------------
-- 2. refund.refund_type mirror
-- ------------------------------------------------------------

alter table refund
  add column if not exists refund_type_text text;

create or replace function set_refund_powersync_mirrors()
returns trigger as $$
begin
  new.refund_type_text := new.refund_type::text;
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_refund_powersync_mirrors on refund;
create trigger trg_refund_powersync_mirrors
  before insert or update of refund_type on refund
  for each row execute function set_refund_powersync_mirrors();

update refund set refund_type = refund_type;


-- ------------------------------------------------------------
-- 3. Publication: drop stale public.harvest reference
--
-- Recreated in full (not ALTER PUBLICATION ... DROP TABLE) so this
-- migration is also correct as a standalone re-run against a fresh
-- database, matching the pattern already established by
-- 20260827094922_powersync_publication.sql.
-- ------------------------------------------------------------

drop publication if exists powersync;

create publication powersync for table
  -- shared profiles/auth domain
  public.profile,
  public.profile_role,
  public.farmer_profile,
  public.farmer_crop,
  public.buyer_profile,
  public.driver_profile,
  public.crop,
  public.vehicle,
  public.driver_route_preference,

  -- cross-cutting comms
  public.conversation,
  public.conversation_participant,
  public.message,
  public.notification,
  public.notification_preference,

  -- component 1
  public.produce_listing,

  -- component 2
  public.cart,
  public.cart_item,
  public.orders,
  public.order_item,
  public.order_status_history,
  public.recurring_order,
  public.recurring_order_item,

  -- component 3
  public.driver_schedule,
  public.journey,
  public.route,
  public.route_stop,
  public.delivery,
  public.delivery_assignment,
  public.delivery_tracking,

  -- component 4
  public.wallet,
  public.wallet_transaction,
  public.payment,
  public.payment_transaction,
  public.refund_request,
  public.refund,
  public.pricing_rule,
  public.price_history,
  public.market_price,
  public.price_trend;