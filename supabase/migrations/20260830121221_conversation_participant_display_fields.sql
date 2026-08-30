-- ============================================================
-- GreenYield -- messaging fix: denormalize participant display info
--
-- watchConversations() needs each participant's name/avatar to render
-- the chat list. Joining the local `profile` table for that doesn't
-- work offline-first: buyers can't read farmer profile rows under RLS
-- (same reason the marketplace listing RPC exists instead of a local
-- join — see MarketplaceListing's doc comment), so the join silently
-- drops the whole conversation for whichever side lacks read access.
--
-- Fix: each participant snapshots their OWN name/avatar (which they
-- always have permission to read) onto their own row when the
-- conversation is created.
-- ============================================================

alter table conversation_participant
  add column display_name text,
  add column avatar_url   text;
