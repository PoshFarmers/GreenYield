-- Internal money/state functions must be service_role only. `revoke ... from public`
-- does not remove Supabase's default anon/authenticated grants, so revoke explicitly
-- for every overload. Idempotent; nested calls from SECURITY DEFINER functions are unaffected.
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname in (
        'apply_wallet_transaction', 'process_refund', 'transition_order_status',
        'send_notification', 'refresh_market_price_analytics',
        'decrement_listing_quantity', 'restock_listing_quantity', 'expire_stale_listings'
      ) or p.proname like 'mockgw\_%')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
    execute format('grant execute on function %s to service_role', r.sig);
  end loop;
end;
$$;
