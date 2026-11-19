// EZ POS - Edge Function: owner creates a team member (or resets a member's password).
// Deploy: supabase functions deploy create-staff
// The service role key never leaves the server; the caller must be an active owner.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    const caller = createClient(url, anon, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json({ error: 'Please sign in again.' }, 401);

    const admin = createClient(url, service);
    const { data: me } = await admin
      .from('business_members').select('business_id, role, is_active, branch_id')
      .eq('user_id', user.id).maybeSingle();
    if (!me || !me.is_active || me.role !== 'owner') {
      return json({ error: 'Only the business owner can manage team accounts.' }, 403);
    }

    const body = await req.json();
    const action = body.action ?? 'create';

    if (action === 'reset_password') {
      const password = String(body.password ?? '');
      if (password.length < 8) return json({ error: 'Password must be at least 8 characters.' }, 400);
      const { data: member } = await admin.from('business_members').select('user_id, business_id')
        .eq('id', body.member_id).maybeSingle();
      if (!member || member.business_id !== me.business_id) return json({ error: 'Team member not found.' }, 404);
      const { error } = await admin.auth.admin.updateUserById(member.user_id, { password });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    const email = String(body.email ?? '').trim().toLowerCase();
    const password = String(body.password ?? '');
    const fullName = String(body.full_name ?? '').trim();
    const role = String(body.role ?? '');
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: 'Enter a valid email address.' }, 400);
    if (password.length < 8) return json({ error: 'Password must be at least 8 characters.' }, 400);
    if (!fullName) return json({ error: 'Full name is required.' }, 400);
    if (!['manager', 'cashier', 'storekeeper'].includes(role)) return json({ error: 'Invalid role.' }, 400);

    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email, password, email_confirm: true, user_metadata: { full_name: fullName },
    });
    if (createErr || !created.user) return json({ error: createErr?.message ?? 'Could not create the account.' }, 400);

    const { count } = await admin.from('business_members').select('id', { count: 'exact', head: true })
      .eq('business_id', me.business_id);
    const { error: memberErr } = await admin.from('business_members').insert({
      business_id: me.business_id,
      user_id: created.user.id,
      full_name: fullName,
      phone: body.phone ?? null,
      email,
      role,
      branch_id: body.branch_id ?? me.branch_id,
      employee_code: `E-${String((count ?? 0) + 1).padStart(4, '0')}`,
    });
    if (memberErr) {
      await admin.auth.admin.deleteUser(created.user.id);
      return json({ error: memberErr.message }, 400);
    }
    return json({ ok: true, user_id: created.user.id });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
