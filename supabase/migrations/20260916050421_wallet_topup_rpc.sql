-- ============================================================
-- Sprint 3 — Task 15.3 (cont.): self-service wallet top-up.
--
-- Lets any authenticated user credit their own wallet directly —
-- replaces the manual `apply_wallet_transaction(...)` SQL-editor
-- workaround used for testing. In production this would sit behind
-- a real payment gateway (card/bank) confirming funds before
-- crediting; for this app's scope, the RPC IS the "gateway" — it
-- credits immediately, matching how wallet payments are already
-- instant elsewhere in the app.
-- ============================================================

create or replace function topup_wallet(
  p_amount numeric
)
returns wallet_transaction
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_txn wallet_transaction;
begin
  if v_uid is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Top-up amount must be greater than 0' using errcode = '22023';
  end if;
  if p_amount > 1000000 then
    raise exception 'Top-up amount exceeds the allowed limit' using errcode = '22023';
  end if;

  v_txn := apply_wallet_transaction(v_uid, 'topup', p_amount, null, null);
  return v_txn;
end;
$$;

revoke all on function topup_wallet(numeric) from public, anon;
grant execute on function topup_wallet(numeric) to authenticated;