-- ============================================================
-- GreenYield — Fix chat Realtime & PowerSync publications
--
-- The three chat tables (conversation, conversation_participant,
-- message) were previously toggled OFF in both the Supabase Realtime
-- publication (supabase_realtime) and the PowerSync publication
-- (powersync). This meant:
--
--   • Supabase Realtime WebSocket: .stream() subscriptions on these
--     tables never fired — so the thread list and message stream
--     never updated live, and unread badges were stale.
--
--   • PowerSync: offline-first reads from the local SQLite mirror
--     were also stale, since no WAL changes were being replicated.
--
-- Fix strategy
-- ─────────────
-- 1. supabase_realtime — ALTER PUBLICATION ... ADD TABLE for each
--    chat table. Supabase manages this publication automatically;
--    we never drop/recreate it (doing so would break other features).
--
-- 2. powersync — Recreate from scratch (same pattern established by
--    earlier powersync migrations) so that all three tables are back
--    in the list. We also keep every other table that was already
--    present, so no other feature loses its sync.
-- ============================================================

-- ---------------------------------------------------------------
-- 1. supabase_realtime: add the three chat tables
--
-- Supabase creates and owns this publication; never DROP it.
-- "ADD TABLE IF NOT EXISTS" would be ideal but ALTER PUBLICATION
-- ADD TABLE errors on duplicate; use DO blocks to guard idempotency.
-- ---------------------------------------------------------------

do $$
begin
  -- conversation
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'conversation'
  ) then
    alter publication supabase_realtime add table public.conversation;
  end if;

  -- conversation_participant
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'conversation_participant'
  ) then
    alter publication supabase_realtime add table public.conversation_participant;
  end if;

  -- message
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message'
  ) then
    alter publication supabase_realtime add table public.message;
  end if;
end;
$$;

-- ---------------------------------------------------------------
-- 2. powersync: recreate publication including the chat tables
--
-- Follows the identical drop-and-recreate pattern used by
-- 20260827094922_powersync_publication.sql and
-- 20260830035655_powersync_compat_publication_updates.sql.
-- ---------------------------------------------------------------

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

  -- cross-cutting comms (restored — were toggled off)
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
