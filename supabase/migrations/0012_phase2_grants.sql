-- EZ POS - Phase 2 - 0012: privileges for the new functions (same rules as the end of 0004).
revoke all on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
grant usage on schema app to authenticated;
grant execute on all functions in schema app to authenticated;
