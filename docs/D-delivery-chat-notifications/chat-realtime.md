
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

## 3. Data model

| Table | Columns | Notes |
|---|---|---|
| `conversation` | `id`, `context_type conversation_context` (`order`, `journey`, `general`), `order_id`, `journey_id` (FKs added `20260827094812`), `title`, `created_at`, `updated_at` (added `20260906092841`), mirror `context_type_text` | `order`/`journey` contexts are allowed by RLS but nothing creates them and `get_chat_threads` hides them. |
| `conversation_participant` | `id`, `conversation_id`, `profile_id` (unique together), `joined_at`, `last_read_at`, `display_name`, `avatar_url` (`20260830121221`), `role` (`20260906092841`, check in buyer/farmer/driver) | |
| `message` | `id`, `conversation_id`, `sender_id`, `body`, `attachment_url` (storage path), `attachment_type` (`'image'`), `created_at` | Index `(conversation_id, created_at)` plus later lookup indexes. |
| Storage bucket `message-attachments` | private; object path `<conversation_id>/<uuid>.<ext>` | `20260830104327_message_attachment_storage` |

Indexes added for unread/thread queries: `idx_message_unread_lookup`, `idx_conversation_participant_profile_role_conversation`, `idx_message_conversation_created_sender`.
