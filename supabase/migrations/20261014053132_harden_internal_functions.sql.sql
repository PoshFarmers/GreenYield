-- Internal money/order functions were executable by `authenticated` because
-- Supabase default privileges grant EXECUTE to anon/authenticated and
-- `revoke ... from public` does not remove those. Revoke explicitly, for every
-- overload, then re-grant to service_role only (SECURITY DEFINER callers still
-- work: they run as the function owner).

do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'apply_wallet_transaction',
        'process_refund',
        'transition_order_status',
        'refresh_market_price_analytics'
      )
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
    execute format('grant execute on function %s to service_role', r.sig);
  end loop;
end;
$$;
