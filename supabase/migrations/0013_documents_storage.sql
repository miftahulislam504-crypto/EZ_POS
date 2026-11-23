-- EZ POS - Phase 2 - 0013: private bucket for NID copies, agreements, supplier bills and receipts (run on Supabase only).
-- Files live under "<business_id>/<entity_type>/<entity_id>/<file>". The bucket is private; the app opens files through
-- short-lived signed URLs, and access follows the permission of the record the file belongs to.
insert into storage.buckets (id, name, public) values ('documents', 'documents', false)
on conflict (id) do nothing;

create or replace function app.can_access_document(p_name text) returns boolean
language sql stable security definer set search_path = public as $$
  select (storage.foldername(p_name))[1] = app.current_business_id()::text
     and case (storage.foldername(p_name))[2]
           when 'customer' then app.has_perm('customers.documents')
           when 'guarantor' then app.has_perm('customers.documents')
           when 'supplier' then app.has_perm('suppliers.view')
           when 'installment' then app.has_perm('installments.view')
           when 'purchase' then app.has_perm('purchases.view')
           when 'expense' then app.has_perm('expenses.view')
           else false end
$$;

create policy "ez_docs_read" on storage.objects for select to authenticated
  using (bucket_id = 'documents' and app.can_access_document(name));
create policy "ez_docs_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'documents' and app.can_access_document(name));
create policy "ez_docs_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'documents' and app.can_access_document(name));
