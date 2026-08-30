-- message attachment storage bucket
-- Private bucket, keyed by <conversation_id>/<file>. Unlike avatars/
-- crop-photos (owner-only access), any participant of the conversation
-- may read an attachment — so policies check conversation membership
-- via is_conversation_participant() (defined in messaging.sql) rather
-- than auth.uid() folder ownership.


insert into storage.buckets (id, name, public)
values ('message-attachments', 'message-attachments', false)
on conflict (id) do nothing;

create policy "message_attachment_insert_participant"
  on storage.objects for insert
  with check (
    bucket_id = 'message-attachments'
    and is_conversation_participant((storage.foldername(name))[1]::uuid)
  );

create policy "message_attachment_select_participant"
  on storage.objects for select
  using (
    bucket_id = 'message-attachments'
    and is_conversation_participant((storage.foldername(name))[1]::uuid)
  );
