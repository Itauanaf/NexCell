import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql=await readFile(new URL("../supabase/migrations/20261015000800_user_groups_permissions.sql",import.meta.url),"utf8");
for(const table of ["permission_groups","permissions","group_permissions","user_groups","user_invitations"]){
  assert.match(sql,new RegExp(`create table public\\.${table}\\b`));
  assert.match(sql,new RegExp(`alter table public\\.%I enable row level security|alter table public\\.${table} enable row level security`));
}
for(const code of ["dashboard.admin.view","products.cost.view","inventory.adjust","sales.discount","finance.view","users.invite","groups.manage","audit.view"])assert.ok(sql.includes(`'${code}'`),`missing permission ${code}`);
assert.match(sql,/last_active_administrator/);
assert.match(sql,/private\.has_permission_for/);
assert.match(sql,/set search_path=''/);
assert.match(sql,/revoke execute on function public\.current_access_context\(\) from public,anon/);
assert.match(sql,/revoke all on public\.%I from anon,authenticated/);
assert.doesNotMatch(sql,/service_role|SUPABASE_SECRET_KEY/);
console.log("permission schema: catalog, RLS, last-admin guard and function grants ok");
