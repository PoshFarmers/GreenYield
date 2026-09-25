
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

## 4. Flow

```mermaid
sequenceDiagram
    participant A as Sender app
    participant S as Storage message-attachments
    participant DB as Postgres
    participant RT as Realtime
    participant B as Recipient app
    A->>DB: rpc get_or_create_conversation
    DB-->>A: conversation id
    opt image attached
        A->>S: upload conversation_id/uuid.ext
    end
    A->>DB: INSERT message
    DB->>DB: trigger touch_conversation_on_message
    DB->>DB: trigger notify_new_message
    DB-->>RT: change on message
    RT-->>B: streamMessages emits
    B->>DB: UPDATE own last_read_at
    DB-->>RT: change on conversation_participant
    RT-->>A: streamPeerLastReadAt emits
```

1. **Open/start a thread.** Entry points (e.g. "Message Farmer") call `get_or_create_conversation(callerRole, otherUserId, otherRole)`.
2. **List threads.** `watchChatThreads(activeRole)` calls RPC `get_chat_threads(p_active_role)` and re-runs it when the `conversation` stream or the caller's own `conversation_participant` stream fires (200 ms debounce, request-version guard so an older slow response never overwrites a newer one).
3. **Open a room.** `streamMessages(conversationId)` streams the latest 100 messages (`order created_at desc`, `limit 100`), so the list is newest first. `streamPeerLastReadAt` streams the participant rows of the conversation and returns the other participant's `last_read_at`; the UI derives "seen" by comparing message time to it.
4. **Send.** `sendMessage` optionally uploads the image, then inserts a `message` row (body or attachment required; empty sends return without writing).
5. **Mark read.** `markMessagesAsRead` updates the caller's own `last_read_at` to now (UTC).
6. **Show an image.** `resolveAttachmentUrl` creates a 1-hour signed URL, cached in a static in-memory map.

Provider wiring is in `chat_providers.dart` (`chatThreadsProvider`, `unreadConversationCountProvider`, `chatMessagesProvider`, `peerLastReadAtProvider`; role-keyed families).
