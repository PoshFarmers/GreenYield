
**Owner:** Author D (Delivery, driver, chat, notifications)
**Reviewers:** Author A (sync/RLS/storage)
**Last verified against:** migrations up to `20260927093935_recurring_orders_rpc.sql`

## 1. Purpose

Direct one-to-one messaging between buyer, farmer and driver, with role-aware threads, image attachments, unread badges and a read cursor. The app deliberately reads chat through Supabase Realtime and RPCs (not the PowerSync mirror) for sub-second delivery. Chat needs a connection.

## 2. Key concepts

| Concept | Meaning |
|---|---|
| Direct thread | A `conversation` with `context_type = 'general'`, `order_id` and `journey_id` null, exactly two participants. Only these are listed. |
| Role snapshot | `conversation_participant.role` (`buyer`/`farmer`/`driver`), display name and avatar copied at creation, so a user with several roles gets a separate thread per role pair. |
| Active role | The role the user is currently acting as; passed as `p_active_role` to list/count RPCs. |
| Read cursor | `conversation_participant.last_read_at`; unread = messages from others created after it. There is no per-message read flag. |
| Realtime-only | Reads use `supabase.from(...).stream(primaryKey: ['id'])` and RPCs. |