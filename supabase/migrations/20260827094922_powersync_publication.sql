-- PowerSync publication for GreenYield.
-- Run this after all schema tables are created.

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
  public.harvest,
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