-- One-off: settle orders that were delivered/completed before settlement existed.
-- Farmers get subtotal - commission (current rate). Drivers already paid by the legacy
-- inline payout are skipped by settle_order (same 'delivery' reference). No notifications.
-- Orders without a captured payment (old card orders) are skipped and counted.
do $$
declare
  r record;
  v_res jsonb;
  v_ok int := 0;
  v_skipped int := 0;
  v_failed int := 0;
begin
  for r in
    select o.id
    from orders o
    where o.status in ('delivered', 'completed')
      and not exists (
        select 1 from wallet_transaction wt join wallet w on w.id = wt.wallet_id
        where w.profile_id = o.farmer_profile_id and wt.type = 'payout'
          and wt.reference_table = 'orders' and wt.reference_id = o.id
      )
    order by o.placed_at
  loop
    begin
      v_res := settle_order(r.id, true);
      if (v_res->>'settled')::boolean then
        v_ok := v_ok + 1;
      else
        v_skipped := v_skipped + 1;
      end if;
    exception when others then
      v_failed := v_failed + 1;
      raise warning 'backfill: order % failed: %', r.id, sqlerrm;
    end;
  end loop;
  raise notice 'settlement backfill: settled %, skipped (no captured payment) %, failed %',
    v_ok, v_skipped, v_failed;
end;
$$;
