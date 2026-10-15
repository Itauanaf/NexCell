import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql=await readFile(new URL("../supabase/migrations/20261015000800_user_groups_permissions.sql",import.meta.url),"utf8");
const hardening=await readFile(new URL("../supabase/migrations/20261015000900_security_hardening.sql",import.meta.url),"utf8");
const notifications=await readFile(new URL("../supabase/migrations/20261015233341_user_notifications.sql",import.meta.url),"utf8");
for(const table of ["permission_groups","permissions","group_permissions","user_groups","user_invitations"]){
  assert.match(sql,new RegExp(`create table public\\.${table}\\b`));
  assert.match(sql,new RegExp(`alter table public\\.%I enable row level security|alter table public\\.${table} enable row level security`));
}
for(const code of ["dashboard.admin.view","products.cost.view","inventory.adjust","sales.discount","finance.view","users.invite","groups.manage","audit.view"])assert.ok(sql.includes(`'${code}'`),`missing permission ${code}`);
assert.match(sql,/last_active_administrator/);
assert.match(sql,/private\.has_permission_for\(\(select auth\.uid\(\)\),'groups\.manage'\)/);
assert.match(sql,/permission_guard_not_replaced/);
assert.match(sql,/user\.group_assigned/);
assert.match(sql,/user\.group_removed/);
assert.match(sql,/status='accepted'/);
assert.match(sql,/private\.has_permission_for/);
assert.match(sql,/set search_path=''/);
assert.match(sql,/revoke execute on function public\.current_access_context\(\) from public,anon/);
assert.match(sql,/revoke all on public\.%I from anon,authenticated/);
assert.doesNotMatch(sql,/service_role|SUPABASE_SECRET_KEY/);
assert.match(hardening,/public\.has_permission\(''groups\.view''\)/);
assert.match(hardening,/pg_advisory_xact_lock/);
assert.match(hardening,/dashboard\.admin\.view/);
assert.match(hardening,/candidate\.id<>p_user_id/);
assert.doesNotMatch(hardening,/g\.name='Administrador'/);
assert.match(hardening,/revoke all privileges on all tables in schema public from anon/);
assert.match(hardening,/revoke insert,update,delete,truncate,references,trigger on all tables in schema public from authenticated/);
assert.match(hardening,/invitation_for_resend/);
assert.match(hardening,/private\.require_active_administrator/);
for(const table of ["profiles","user_groups","group_permissions","permission_groups","permissions"]){
  assert.match(hardening,new RegExp(`create constraint trigger ${table}_require_active_administrator`));
}
assert.match(notifications,/create table public\.user_notifications/);
assert.match(notifications,/alter table public\.user_notifications enable row level security/);
assert.match(notifications,/using \(\(select auth\.uid\(\)\) = user_id\)/);
assert.match(notifications,/grant select on public\.user_notifications to authenticated/);
assert.doesNotMatch(notifications,/grant .*update.*authenticated/);
console.log("permission schema: catalog, RLS, last-admin guard and function grants ok");
