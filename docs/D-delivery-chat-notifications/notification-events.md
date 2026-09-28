# In-App Notifications (Events & Client)

**Owner:** Author D (Delivery, driver, chat, notifications)
**Reviewers:** Author C (order/payment events), Author A (sync)
**Last verified against:** migrations up to `20260927093935_recurring_orders_rpc.sql`

## 1. Purpose

Backend-generated in-app notifications: which events create rows, what they contain, how they reach the device, and how the client lists and clears them. Only in-app rows exist: no push, SMS or email is sent by anything in the dump.

## 2. Key concepts

| Concept | Meaning |
|---|---|
| Notification row | One `notification` per recipient per event. |
| Producer | A trigger or RPC running as SECURITY DEFINER. Clients never insert. |
| `send_notification(...)` | Helper that inserts a row; `service_role` only. |
| Category | Client-side grouping derived from `type` (no column). |
| Preferences | Table `notification_preference` (channel enum) exists but nothing reads it. |

## 3. Data model

`notification`: `id`, `profile_id` (FK profile, cascade), `type text`, `title text NOT NULL`, `body`, `payload jsonb NOT NULL default '{}'`, `source_table text`, `source_id uuid`, `read_at`, `created_at`. Indexes `(profile_id, created_at desc)` and a partial unread index. Enum `notification_channel`: `in_app`, `push`, `sms`, `email` (used only by `notification_preference`, with mirror `channel_text`).

Locally, `payload` is stored as text; `NotificationItem.fromMap` decodes it, and the upload path decodes it back (`jsonbColumns: {'payload'}` in `tableRegistry`).
