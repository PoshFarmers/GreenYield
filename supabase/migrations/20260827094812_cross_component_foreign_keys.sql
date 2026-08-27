-- ============================================================
-- Adds the cross-component FK constraints that couldn't be declared at
-- table-creation time because the referenced table didn't exist yet.
-- ============================================================

alter table orders
  add constraint fk_orders_delivery foreign key (delivery_id) references delivery(id);

alter table orders
  add constraint fk_orders_payment foreign key (payment_id) references payment(id);

alter table conversation
  add constraint fk_conversation_order foreign key (order_id) references orders(id);

alter table conversation
  add constraint fk_conversation_journey foreign key (journey_id) references journey(id);

-- ------------------------------------------------------------
-- Tighten conversation creation: 0005 could only check auth.uid() is not
-- null, because orders/journey didn't exist yet at that point in the
-- migration order. Now that they do, replace it with a real ownership
-- check so a user can't spin up a conversation against someone else's
-- order or journey.
-- ------------------------------------------------------------
drop policy if exists "conversation_insert_authenticated" on conversation;

create policy "conversation_insert_participant_context" on conversation
  for insert with check (
    auth.uid() is not null
    and (
      context_type = 'general'
      or (
        context_type = 'order' and order_id is not null and exists (
          select 1 from orders o
          where o.id = order_id
            and (o.buyer_profile_id = auth.uid() or o.farmer_profile_id = auth.uid())
        )
      )
      or (
        context_type = 'journey' and journey_id is not null and exists (
          select 1 from journey j
          where j.id = journey_id and j.driver_profile_id = auth.uid()
        )
      )
    )
  );

-- ------------------------------------------------------------
-- A farmer deleting a produce_listing currently cascade-deletes it out of
-- every buyer's cart_item silently. Notify affected buyers instead of
-- letting it vanish without explanation.
-- ------------------------------------------------------------
create or replace function notify_cart_items_on_listing_delete()
returns trigger as $$
begin
  insert into notification (profile_id, type, title, body, source_table, source_id, payload)
  select c.buyer_profile_id,
         'listing_removed_from_cart',
         'An item in your cart is no longer available',
         'A farmer removed a listing that was in your cart.',
         'produce_listing',
         old.id,
         jsonb_build_object('produce_listing_id', old.id)
  from cart_item ci
  join cart c on c.id = ci.cart_id
  where ci.produce_listing_id = old.id;

  return old;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_notify_cart_items_on_listing_delete on produce_listing;
create trigger trg_notify_cart_items_on_listing_delete
  before delete on produce_listing
  for each row execute function notify_cart_items_on_listing_delete();
