import { calculatePricing } from "./modules/pricing.js";
import { authorizationContext, authorizeRoute } from "./modules/authorization.js";
import { inviteAuthUser, createAuthUser, deleteAuthUser, sendPasswordRecovery } from "./modules/user-administration.js";
import { accessToken, authApi } from "./modules/session-auth.js";

const response = (data, status = 200) => new Response(JSON.stringify(data), {
  status,
  headers: { "content-type": "application/json; charset=utf-8", "cache-control": "private, no-store" }
});

const clean = (value, max = 240) => typeof value === "string" ? value.trim().slice(0, max) : "";
const cents = value => Math.round(Number(value) * 100);
const today = () => new Date().toISOString().slice(0, 10);

function publicError(error) {
  if (error?.status === 401) return { status: 401, message: "Autenticação necessária." };
  if (error?.status === 403) return { status: 403, message: "Você não tem permissão para esta operação." };
  if (error?.status === 404) return { status: 404, message: "Registro não encontrado." };
  if (error?.status === 409) return { status: 409, message: "A operação conflita com os dados atuais." };
  if (error?.status === 413) return { status: 413, message: "A solicitação excede o tamanho permitido." };
  if (error?.status === 422) return { status: 422, message: "Os dados informados são inválidos." };
  if (error?.status === 429) return { status: 429, message: "Limite de e-mails do Supabase atingido (2 por hora no provedor padrão). Aguarde até 1 hora e tente novamente." };
  if (error?.status === 503) return { status: 503, message: "Serviço temporariamente indisponível." };
  return { status: 500, message: "Falha interna no servidor." };
}

function applicationOrigin(env) {
  if (!env.APP_URL) throw Object.assign(new Error("APP_URL não configurada no servidor."), { status: 503 });
  const url = new URL(env.APP_URL);
  if (url.protocol !== "https:" && url.hostname !== "localhost") throw Object.assign(new Error("APP_URL inválida."), { status: 503 });
  return url.origin;
}

function credentials(request, env) {
  const token = accessToken(request);
  if (!token) throw Object.assign(new Error("Autenticação necessária."), { status: 401 });
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) throw Object.assign(new Error("Supabase não configurado no ambiente."), { status: 503 });
  return { token, headers: { apikey: env.SUPABASE_PUBLISHABLE_KEY, authorization: `Bearer ${token}` } };
}

async function call(request, env, path, options = {}) {
  const { headers } = credentials(request, env);
  const result = await fetch(`${env.SUPABASE_URL}${path}`, {
    ...options,
    headers: { ...headers, "content-type": "application/json", prefer: "return=representation", ...(options.headers || {}) }
  });
  const body = await result.json().catch(() => null);
  if (!result.ok) {
    const message = body?.message || body?.msg || body?.error_description || body?.error || "Falha na operação.";
    throw Object.assign(new Error(message), { status: result.status });
  }
  return body;
}

const rest = (request, env, resource, query = "") => call(request, env, `/rest/v1/${resource}${query ? `?${query}` : ""}`);
const rpc = (request, env, name, body) => call(request, env, `/rest/v1/rpc/${name}`, { method: "POST", body: JSON.stringify(body) });

async function privilegedRest(env, resource, query = "", options = {}) {
  if (!env.SUPABASE_SECRET_KEY) throw Object.assign(new Error("SUPABASE_SECRET_KEY não configurada no servidor."), { status: 503 });
  const result = await fetch(`${env.SUPABASE_URL}/rest/v1/${resource}${query ? `?${query}` : ""}`, {
    ...options,
    headers: { apikey: env.SUPABASE_SECRET_KEY, authorization: `Bearer ${env.SUPABASE_SECRET_KEY}`, "content-type": "application/json", prefer: "return=minimal,resolution=merge-duplicates", ...(options.headers || {}) }
  });
  if (!result.ok) throw Object.assign(new Error("Falha ao sincronizar notificações."), { status: result.status });
}

async function signedImage(request,env,key){
  if(!key)return null;
  const result=await call(request,env,`/storage/v1/object/sign/product-images/${key.split("/").map(encodeURIComponent).join("/")}`,{method:"POST",body:JSON.stringify({expiresIn:3600})});
  return result?.signedURL ? `${env.SUPABASE_URL}/storage/v1${result.signedURL}` : null;
}

async function currentAccess(request, env) {
  const access=await rpc(request,env,"current_access_context",{});
  if(!access?.user)throw Object.assign(new Error("Sessão inválida ou usuário inativo."),{status:403});
  return authorizationContext(access);
}

async function notificationsApi(request, env, url, ctx) {
  if (url.pathname === "/api/notifications" && request.method === "GET") {
    const userId = ctx.user.id;
    const existing = await rest(request, env, "user_notifications", "select=source_key,read_at,active");
    const prior = new Map(existing.map(item => [item.source_key, item]));
    const items = [], add = item => items.push({ user_id: userId, active: true, read_at: prior.get(item.source_key)?.active ? prior.get(item.source_key).read_at : null, last_seen_at: new Date().toISOString(), ...item });
    if (ctx.can("inventory.view")) {
      const stock = await rpc(request, env, "operator_inventory", {});
      stock.filter(item => Number(item.available) <= Number(item.minimum_stock)).slice(0, 30).forEach(item => add({ source_key: `stock:${item.variant_id}`, kind: "stock", severity: Number(item.available) <= 0 ? "urgent" : "attention", title: `Estoque crítico: ${item.name}`, message: `${item.sku} tem ${item.available} unidade(s) disponível(is); mínimo ${item.minimum_stock}.`, target_page: "Estoque", target_id: item.variant_id }));
    }
    if (ctx.can("purchases.view")) {
      const purchases = await rest(request, env, "purchase_orders", "select=id,number,receipt_status,expected_date&receipt_status=neq.received&order_status=neq.cancelled&order=expected_date.asc&limit=30");
      purchases.forEach(item => add({ source_key: `purchase:${item.id}`, kind: "purchase", severity: item.expected_date && item.expected_date < today() ? "urgent" : "attention", title: `Compra ${item.number} aguardando recebimento`, message: item.expected_date ? `Previsão de entrega: ${item.expected_date}.` : "Compra confirmada sem previsão de entrega.", target_page: "Recebimentos", target_id: item.id }));
    }
    if (ctx.can("sales.view") || ctx.can("sales.ship")) {
      const sales = await rpc(request, env, "operator_sales", {});
      sales.filter(item => ["pending", "separated"].includes(item.shipping_status)).slice(0, 30).forEach(item => add({ source_key: `shipping:${item.id}`, kind: "shipping", severity: item.shipping_status === "separated" ? "urgent" : "attention", title: `Venda ${item.number} aguardando envio`, message: item.shipping_status === "separated" ? "Pedido separado e pronto para despacho." : "Pedido aguardando separação.", target_page: "Vendas", target_id: item.id }));
    }
    if (ctx.can("finance.view")) {
      const horizon = new Date(Date.now() + 7 * 86400000).toISOString().slice(0, 10);
      const [payable, receivable] = await Promise.all([
        rest(request, env, "accounts_payable", `select=id,description,due_date,status&status=in.(pending,partial)&due_date=lte.${horizon}&order=due_date.asc&limit=30`),
        rest(request, env, "accounts_receivable", `select=id,description,due_date,status&status=in.(pending,partial)&due_date=lte.${horizon}&order=due_date.asc&limit=30`)
      ]);
      [...payable.map(item => ({ ...item, direction: "pagar" })), ...receivable.map(item => ({ ...item, direction: "receber" }))].forEach(item => add({ source_key: `finance:${item.direction}:${item.id}`, kind: "finance", severity: item.due_date < today() ? "urgent" : "attention", title: `Conta a ${item.direction}: ${item.description}`, message: item.due_date < today() ? `Vencida em ${item.due_date}.` : `Vence em ${item.due_date}.`, target_page: "Financeiro", target_id: item.id }));
    }
    await privilegedRest(env, "user_notifications", `user_id=eq.${encodeURIComponent(userId)}&active=eq.true`, { method: "PATCH", body: JSON.stringify({ active: false }) });
    if (items.length) await privilegedRest(env, "user_notifications", "on_conflict=user_id,source_key", { method: "POST", body: JSON.stringify(items) });
    const notifications = await rest(request, env, "user_notifications", "select=id,kind,severity,title,message,target_page,target_id,read_at,created_at,last_seen_at&active=eq.true&order=read_at.asc.nullsfirst,last_seen_at.desc&limit=80");
    return response({ items: notifications, unread: notifications.filter(item => !item.read_at).length });
  }
  const readOne = url.pathname.match(/^\/api\/notifications\/([^/]+)\/read$/);
  if (readOne && request.method === "PATCH") {
    await privilegedRest(env, "user_notifications", `id=eq.${encodeURIComponent(readOne[1])}&user_id=eq.${encodeURIComponent(ctx.user.id)}`, { method: "PATCH", body: JSON.stringify({ read_at: new Date().toISOString() }) });
    return response({ ok: true });
  }
  if (url.pathname === "/api/notifications/read-all" && request.method === "PATCH") {
    await privilegedRest(env, "user_notifications", `user_id=eq.${encodeURIComponent(ctx.user.id)}&active=eq.true&read_at=is.null`, { method: "PATCH", body: JSON.stringify({ read_at: new Date().toISOString() }) });
    return response({ ok: true });
  }
  return null;
}

async function safeProjectionApi(request, env, url, ctx) {
  if (url.pathname === "/api/categories" && request.method === "GET") {
    return response({ items: await rest(request, env, "categories", "select=id,name&active=eq.true&order=name") });
  }
  if (url.pathname === "/api/products" && request.method === "GET" && !ctx.can("products.cost.view")) {
    const items = await rpc(request, env, "operator_catalog", { p_query: clean(url.searchParams.get("q"), 80), p_category: url.searchParams.get("category") || null });
    for (const item of items) item.image_key = await signedImage(request, env, item.image_key);
    return response({ items });
  }
  if (url.pathname === "/api/inventory" && request.method === "GET" && !ctx.can("inventory.cost.view")) return response({ items: await rpc(request, env, "operator_inventory", {}) });
  if (url.pathname === "/api/sales" && request.method === "GET" && !ctx.can("dashboard.admin.view")) return response({ items: await rpc(request, env, "operator_sales", {}) });
  if (url.pathname === "/api/sales" && request.method === "POST" && !ctx.can("sales.discount")) {
    const b = await request.json();
    const result = await rpc(request, env, "create_sale", { p_customer_name:b.customerName, p_order_date:b.orderDate||today(), p_discount_cents:0, p_shipping_cents:Math.max(0,cents(b.shipping)||0), p_notes:b.notes||null, p_items:(b.items||[]).map(x=>({variantId:x.variantId,quantity:Math.trunc(Number(x.quantity))})) });
    return response(result, 201);
  }
  const items = url.pathname.match(/^\/api\/sales\/([^/]+)\/items$/);
  if (items && request.method === "GET" && !ctx.can("dashboard.admin.view")) return response({ items: await rpc(request, env, "operator_sale_items", { p_sale_id: items[1] }) });
  const payment = url.pathname.match(/^\/api\/sales\/([^/]+)\/payments$/);
  if (payment && request.method === "POST") { const b=await request.json(); const id=await rpc(request,env,"record_sale_payment",{p_sale_id:payment[1],p_account_id:b.accountId,p_amount_cents:cents(b.amount),p_date:b.date||today(),p_method:b.method||"Outro"}); return response({ok:true,id}); }
  const separate = url.pathname.match(/^\/api\/sales\/([^/]+)\/separate$/);
  if (separate && request.method === "POST") { await rpc(request,env,"separate_sale",{p_sale_id:separate[1]}); return response({ok:true}); }
  const shipment = url.pathname.match(/^\/api\/sales\/([^/]+)\/shipments$/);
  if (shipment && request.method === "POST") { const b=await request.json(); const id=await rpc(request,env,"ship_sale",{p_sale_id:shipment[1],p_tracking_code:b.trackingCode||null}); return response({ok:true,id}); }
  if (url.pathname === "/api/payment-accounts" && request.method === "GET") return response({ items: await rpc(request,env,"operator_payment_accounts",{}) });
  if ((url.pathname === "/api/dashboard" && !ctx.can("dashboard.admin.view") || url.pathname === "/api/operator/dashboard") && request.method === "GET") return response(await rpc(request,env,"operator_dashboard",{}));
  return null;
}

async function administration(request,env,url,ctx){
  if(url.pathname==="/api/admin/overview"&&request.method==="GET")return response(await rpc(request,env,"admin_access_overview",{}));
  if(url.pathname==="/api/admin/users"&&request.method==="GET")return response({items:await rpc(request,env,"admin_users",{})});
  if(url.pathname==="/api/admin/users"&&request.method==="POST"){
    ctx.require("users.invite");
    const b=await request.json(),email=clean(b.email,254).toLowerCase(),fullName=clean(b.fullName,120),password=String(b.password||""),groupIds=Array.isArray(b.groupIds)?b.groupIds:[];
    const strong=/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{12,}$/.test(password);
    if(!/^\S+@\S+\.\S+$/.test(email)||!fullName||!groupIds.length||!strong)return response({error:"Informe nome, e-mail, grupo e uma senha forte com 12 caracteres, maiúscula, minúscula, número e símbolo."},422);
    const user=await createAuthUser(env,{email,fullName,password});
    try { await rpc(request,env,"record_created_user",{p_user_id:user.id,p_email:email,p_group_ids:groupIds}); return response({id:user.id},201); }
    catch(error){ await deleteAuthUser(env,user.id).catch(()=>false); throw error; }
  }
  if(url.pathname==="/api/admin/users/invite"&&request.method==="POST"){
    ctx.require("groups.manage");
    const b=await request.json(),email=clean(b.email,254).toLowerCase(),fullName=clean(b.fullName,120),groupIds=Array.isArray(b.groupIds)?b.groupIds:[];
    if(!/^\S+@\S+\.\S+$/.test(email)||!fullName||!groupIds.length)return response({error:"Informe nome, e-mail e ao menos um grupo."},422);
    const origin=applicationOrigin(env),user=await inviteAuthUser(env,{email,fullName,redirectTo:`${origin}/`});
    try { const invitationId=await rpc(request,env,"record_user_invitation",{p_user_id:user.id,p_email:email,p_group_ids:groupIds}); return response({id:user.id,invitationId},201); }
    catch(error){ await deleteAuthUser(env,user.id).catch(()=>false); throw error; }
  }
  const resend=url.pathname.match(/^\/api\/admin\/invitations\/([^/]+)\/resend$/);
  if(resend&&request.method==="POST"){
    const invitation=await rpc(request,env,"invitation_for_resend",{p_invitation_id:resend[1]}),origin=applicationOrigin(env);
    try { await inviteAuthUser(env,{email:invitation.email,fullName:clean(invitation.full_name,120),redirectTo:`${origin}/`}); }
    catch(error){ if(![400,422].includes(error.status))throw error; await sendPasswordRecovery(env,{email:invitation.email,redirectTo:`${origin}/`}); }
    await rpc(request,env,"mark_invitation_resent",{p_invitation_id:resend[1]}); return response({ok:true});
  }
  const user=url.pathname.match(/^\/api\/admin\/users\/([^/]+)$/);
  if(user&&request.method==="DELETE"){
    ctx.require("users.delete");
    let target;
    try { target=await rpc(request,env,"authorize_user_deletion",{p_user_id:user[1]}); }
    catch(error){
      if(error.message.includes("cannot_delete_self"))return response({error:"Você não pode excluir a própria conta."},409);
      if(error.message.includes("last_active_administrator"))return response({error:"Não é possível excluir o último administrador ativo."},409);
      throw error;
    }
    const deleted=await deleteAuthUser(env,user[1]);
    if(!deleted)return response({error:"Este usuário possui histórico operacional e não pode ser excluído. Desative o acesso em Editar."},409);
    await rpc(request,env,"record_user_deletion",{p_user_id:user[1],p_email:target.email,p_name:target.name});
    return response({ok:true});
  }
  if(user&&request.method==="PATCH"){
    const b=await request.json();
    if(b.active===false)ctx.require("users.disable");
    await rpc(request,env,"set_user_access",{p_user_id:user[1],p_full_name:clean(b.fullName,120),p_active:Boolean(b.active),p_group_ids:Array.isArray(b.groupIds)?b.groupIds:[]});
    return response({ok:true});
  }
  if(url.pathname==="/api/admin/groups"&&request.method==="GET")return response({items:await rpc(request,env,"admin_permission_groups",{})});
  if(url.pathname==="/api/admin/groups"&&request.method==="POST"){
    const b=await request.json(),id=await rpc(request,env,"save_permission_group",{p_id:null,p_name:b.name,p_description:b.description||null,p_is_active:b.active!==false,p_permission_codes:b.permissions||[]}); return response({id},201);
  }
  const group=url.pathname.match(/^\/api\/admin\/groups\/([^/]+)$/);
  if(group&&request.method==="PATCH"){
    const b=await request.json(),id=await rpc(request,env,"save_permission_group",{p_id:group[1],p_name:b.name,p_description:b.description||null,p_is_active:b.active!==false,p_permission_codes:b.permissions||[]}); return response({ok:true,id});
  }
  const duplicate=url.pathname.match(/^\/api\/admin\/groups\/([^/]+)\/duplicate$/);
  if(duplicate&&request.method==="POST")return response({id:await rpc(request,env,"duplicate_permission_group",{p_group_id:duplicate[1]})},201);
  if(url.pathname==="/api/admin/permissions"&&request.method==="GET")return response({items:await rpc(request,env,"admin_permissions",{})});
  if(url.pathname==="/api/admin/audit"&&request.method==="GET")return response({items:await rpc(request,env,"admin_audit_logs",{p_actor:url.searchParams.get("actor")||null,p_action:url.searchParams.get("action")||null,p_entity:url.searchParams.get("entity")||null,p_from:url.searchParams.get("from")||null,p_to:url.searchParams.get("to")||null})});
  return null;
}

async function catalog(request, env, url) {
  if (url.pathname === "/api/categories" && request.method === "GET") {
    return response({ items: await rest(request, env, "categories", "select=id,name&active=eq.true&order=name") });
  }
  if (url.pathname === "/api/suppliers" && request.method === "GET") {
    const q = clean(url.searchParams.get("q"), 80);
    const filter = q ? `&or=(name.ilike.*${encodeURIComponent(q)}*,email.ilike.*${encodeURIComponent(q)}*)` : "";
    const [suppliers, products] = await Promise.all([
      rest(request, env, "suppliers", `select=*&order=active.desc,name${filter}`),
      rest(request, env, "products", "select=supplier_id")
    ]);
    const counts = products.reduce((map, item) => (map[item.supplier_id] = (map[item.supplier_id] || 0) + 1, map), {});
    return response({ items: suppliers.map(item => ({ ...item, product_count: counts[item.id] || 0 })) });
  }
  if (url.pathname === "/api/suppliers" && request.method === "POST") {
    const id = await rpc(request, env, "create_supplier", { p_data: await request.json() });
    return response({ id }, 201);
  }
  const supplier = url.pathname.match(/^\/api\/suppliers\/([^/]+)$/);
  if (supplier && request.method === "PATCH") {
    await rpc(request, env, "update_supplier", { p_id: supplier[1], p_data: await request.json() });
    return response({ ok: true });
  }
  if (url.pathname === "/api/products" && request.method === "GET") {
    const query = "select=id,name,description,brand,active,category_id,supplier_id,categories(name),suppliers(name),product_variants(id,sku,barcode,compatible_model,color,cost_cents,sale_price_cents,minimum_stock,active,inventory_balances(physical,reserved)),product_images(object_key)&order=active.desc,name";
    const products = await rest(request, env, "products", query);
    const q = clean(url.searchParams.get("q"), 80).toLocaleLowerCase("pt-BR");
    const category = clean(url.searchParams.get("category"), 80);
    const signed=Object.fromEntries(await Promise.all(products.map(async p=>[p.id,await signedImage(request,env,p.product_images?.[0]?.object_key)])));
    const items = products.filter(p => !category || p.category_id === category).flatMap(p => (p.product_variants || [null]).map(v => ({
      id: p.id, name: p.name, description: p.description, brand: p.brand, active: p.active, category_id: p.category_id,
      category_name: p.categories?.name, supplier_id: p.supplier_id, supplier_name: p.suppliers?.name,
      variant_id: v?.id, sku: v?.sku, barcode: v?.barcode, compatible_model: v?.compatible_model, color: v?.color,
      cost_cents: v?.cost_cents, sale_price_cents: v?.sale_price_cents, minimum_stock: v?.minimum_stock,
      variant_active: v?.active, physical: v?.inventory_balances?.physical || 0, reserved: v?.inventory_balances?.reserved || 0,
      image_key: signed[p.id]
    }))).filter(x => !q || `${x.name} ${x.sku || ""}`.toLocaleLowerCase("pt-BR").includes(q));
    return response({ items });
  }
  if (url.pathname === "/api/products" && request.method === "POST") {
    const body = await request.json();
    const variants = (body.variants || []).map(v => ({ sku: v.sku, barcode: v.barcode || null, model: v.model || null, color: v.color || null,
      costCents: cents(v.cost), priceCents: cents(v.price), openingStock: Math.trunc(Number(v.openingStock) || 0), minimumStock: Math.trunc(Number(v.minimumStock) || 0) }));
    const id = await rpc(request, env, "create_product", { p_name: body.name, p_description: body.description || null, p_category_id: body.categoryId || null, p_brand: body.brand || null, p_supplier_id: body.supplierId || null, p_variants: variants });
    return response({ id }, 201);
  }
  const product = url.pathname.match(/^\/api\/products\/([^/]+)$/);
  if (product && request.method === "PATCH") {
    await rpc(request, env, "update_product", { p_id: product[1], p_data: await request.json() });
    return response({ ok: true });
  }
  const duplicate=url.pathname.match(/^\/api\/products\/([^/]+)\/duplicate$/);
  if(duplicate&&request.method==="POST"){const id=await rpc(request,env,"duplicate_product",{p_product_id:duplicate[1]});return response({id},201)}
  const image = url.pathname.match(/^\/api\/products\/([^/]+)\/image$/);
  if(image&&request.method==="PUT"){
    const type=request.headers.get("content-type")||"";if(!["image/jpeg","image/png","image/webp"].includes(type))return response({error:"Use JPG, PNG ou WebP."},415);
    const bytes=await request.arrayBuffer();if(bytes.byteLength>4*1024*1024)return response({error:"A imagem deve ter até 4 MB."},413);
    const extension={"image/jpeg":"jpg","image/png":"png","image/webp":"webp"}[type],key=`products/${image[1]}/${crypto.randomUUID()}.${extension}`,{headers}=credentials(request,env);
    const upload=await fetch(`${env.SUPABASE_URL}/storage/v1/object/product-images/${key}`,{method:"POST",headers:{...headers,"content-type":type,"x-upsert":"false"},body:bytes});
    if(!upload.ok){const issue=await upload.json().catch(()=>null);throw Object.assign(new Error(issue?.message||"Falha no upload."),{status:upload.status})}
    await rpc(request,env,"attach_product_image",{p_product_id:image[1],p_object_key:key,p_content_type:type,p_alt_text:"Foto do produto"});
    return response({key},201);
  }
  return null;
}

async function operations(request, env, url) {
  if (url.pathname === "/api/purchases" && request.method === "GET") {
    const rows = await rest(request, env, "purchase_orders", "select=*,suppliers(name),purchase_payments(amount_cents)&order=created_at.desc");
    return response({ items: rows.map(x => ({ ...x, supplier_name: x.suppliers?.name, paid_cents: (x.purchase_payments || []).reduce((s,p) => s + Number(p.amount_cents), 0) })) });
  }
  if (url.pathname === "/api/purchases" && request.method === "POST") {
    const b = await request.json();
    const result = await rpc(request, env, "create_purchase", { p_supplier_id: b.supplierId, p_order_date: b.orderDate || today(), p_expected_date: b.expectedDate || null,
      p_discount_cents: Math.max(0,cents(b.discount)||0), p_freight_cents: Math.max(0,cents(b.freight)||0), p_other_costs_cents: Math.max(0,cents(b.otherCosts)||0), p_notes: b.notes || null,
      p_items: (b.items || []).map(x => ({ variantId: x.variantId, quantity: Math.trunc(Number(x.quantity)), unitCostCents: cents(x.unitCost) })) });
    return response(result, 201);
  }
  const purchaseItems = url.pathname.match(/^\/api\/purchases\/([^/]+)\/items$/);
  if (purchaseItems && request.method === "GET") {
    const rows = await rest(request, env, "purchase_order_items", `select=*,product_variants(sku,color,compatible_model,products(name))&purchase_order_id=eq.${purchaseItems[1]}&order=id`);
    return response({ items: rows.map(x => ({ ...x, sku:x.product_variants?.sku, color:x.product_variants?.color, compatible_model:x.product_variants?.compatible_model, product_name:x.product_variants?.products?.name })) });
  }
  const purchasePayment = url.pathname.match(/^\/api\/purchases\/([^/]+)\/payments$/);
  if (purchasePayment && request.method === "POST") {
    const b=await request.json(); const id=await rpc(request,env,"record_purchase_payment",{p_order_id:purchasePayment[1],p_account_id:b.accountId,p_amount_cents:cents(b.amount),p_date:b.date||today(),p_method:b.method||"Outro",p_notes:b.notes||null});
    return response({ok:true,id});
  }
  const receipt = url.pathname.match(/^\/api\/purchases\/([^/]+)\/receipts$/);
  if (receipt && request.method === "POST") {
    const b=await request.json(); const id=await rpc(request,env,"receive_purchase",{p_order_id:receipt[1],p_idempotency_key:b.idempotencyKey,p_date:b.date||today(),p_notes:b.notes||null,p_items:b.items||[]});
    return response({id},201);
  }
  if (url.pathname === "/api/inventory" && request.method === "GET") {
    const rows=await rest(request,env,"inventory_balances","select=physical,reserved,updated_at,product_variants(id,sku,color,compatible_model,cost_cents,sale_price_cents,minimum_stock,products(id,name))&order=updated_at.desc");
    return response({items:rows.map(x=>({variant_id:x.product_variants?.id,sku:x.product_variants?.sku,color:x.product_variants?.color,compatible_model:x.product_variants?.compatible_model,cost_cents:x.product_variants?.cost_cents,sale_price_cents:x.product_variants?.sale_price_cents,minimum_stock:x.product_variants?.minimum_stock,product_id:x.product_variants?.products?.id,name:x.product_variants?.products?.name,physical:x.physical,reserved:x.reserved,available:Number(x.physical)-Number(x.reserved),updated_at:x.updated_at}))});
  }
  if (url.pathname === "/api/inventory/movements" && request.method === "GET") {
    const rows=await rest(request,env,"inventory_movements","select=*,product_variants(sku,products(name))&order=created_at.desc&limit=100");
    return response({items:rows.map(x=>({...x,sku:x.product_variants?.sku,product_name:x.product_variants?.products?.name}))});
  }
  if (url.pathname === "/api/sales" && request.method === "GET") {
    const rows=await rest(request,env,"sales_orders","select=*,sales_payments(amount_cents),sales_order_items(quantity)&order=created_at.desc");
    return response({items:rows.map(x=>({...x,paid_cents:(x.sales_payments||[]).reduce((s,p)=>s+Number(p.amount_cents),0),units:(x.sales_order_items||[]).reduce((s,p)=>s+Number(p.quantity),0)}))});
  }
  if (url.pathname === "/api/sales" && request.method === "POST") {
    const b=await request.json(); const result=await rpc(request,env,"create_sale",{p_customer_name:b.customerName,p_order_date:b.orderDate||today(),p_discount_cents:Math.max(0,cents(b.discount)||0),p_shipping_cents:Math.max(0,cents(b.shipping)||0),p_notes:b.notes||null,p_items:(b.items||[]).map(x=>({variantId:x.variantId,quantity:Math.trunc(Number(x.quantity)),unitPriceCents:x.unitPrice===""||x.unitPrice==null?null:cents(x.unitPrice)}))});
    return response(result,201);
  }
  const saleItems=url.pathname.match(/^\/api\/sales\/([^/]+)\/items$/);
  if(saleItems&&request.method==="GET"){
    const rows=await rest(request,env,"sales_order_items",`select=*,product_variants(sku,color,products(name))&sales_order_id=eq.${saleItems[1]}&order=id`);
    return response({items:rows.map(x=>({...x,sku:x.product_variants?.sku,color:x.product_variants?.color,product_name:x.product_variants?.products?.name}))});
  }
  const salePayment=url.pathname.match(/^\/api\/sales\/([^/]+)\/payments$/); if(salePayment&&request.method==="POST"){const b=await request.json();const id=await rpc(request,env,"record_sale_payment",{p_sale_id:salePayment[1],p_account_id:b.accountId,p_amount_cents:cents(b.amount),p_date:b.date||today(),p_method:b.method||"Outro"});return response({ok:true,id})}
  const shipment=url.pathname.match(/^\/api\/sales\/([^/]+)\/shipments$/); if(shipment&&request.method==="POST"){const b=await request.json();const id=await rpc(request,env,"ship_sale",{p_sale_id:shipment[1],p_tracking_code:b.trackingCode||null});return response({ok:true,id})}
  const cancellation=url.pathname.match(/^\/api\/sales\/([^/]+)\/cancel$/); if(cancellation&&request.method==="POST"){const b=await request.json();const id=await rpc(request,env,"cancel_sale",{p_sale_id:cancellation[1],p_reason:b.reason});return response({ok:true,id})}
  const returned=url.pathname.match(/^\/api\/sales\/([^/]+)\/returns$/); if(returned&&request.method==="POST"){const b=await request.json();const id=await rpc(request,env,"return_sale",{p_sale_id:returned[1],p_notes:b.notes||null,p_items:b.items||[]});return response({id},201)}
  return null;
}

async function finance(request, env, url) {
  if (url.pathname === "/api/finance" && request.method === "GET") {
    const [accounts,transactions,receivables,payables,sales,items,categories]=await Promise.all([
      rest(request,env,"financial_account_balances","select=*&active=eq.true&order=name"),
      rest(request,env,"financial_transactions","select=*,financial_accounts(name),financial_categories(name,affects_result)&order=transaction_date.desc,created_at.desc&limit=60"),
      rest(request,env,"accounts_receivable","select=original_cents,received_cents,status"),rest(request,env,"accounts_payable","select=original_cents,paid_cents,status"),
      rest(request,env,"sales_orders","select=id,total_cents,order_status,shipping_status"),rest(request,env,"sales_order_items","select=sales_order_id,quantity,returned_quantity,historical_cost_cents"),
      rest(request,env,"financial_categories","select=id,affects_result")
    ]);
    const validSales=new Set(sales.filter(x=>x.order_status!=="cancelled").map(x=>x.id)),shipped=new Set(sales.filter(x=>["shipped","delivered"].includes(x.shipping_status)).map(x=>x.id));
    const revenue=sales.filter(x=>validSales.has(x.id)).reduce((s,x)=>s+Number(x.total_cents),0),cogs=items.filter(x=>shipped.has(x.sales_order_id)).reduce((s,x)=>s+(Number(x.quantity)-Number(x.returned_quantity))*Number(x.historical_cost_cents),0);
    const resultCategories=new Set(categories.filter(x=>x.affects_result).map(x=>x.id)),expenses=transactions.filter(x=>x.direction==="outflow"&&resultCategories.has(x.category_id)).reduce((s,x)=>s+Number(x.amount_cents),0);
    const summary={balance_cents:accounts.reduce((s,x)=>s+Number(x.balance_cents),0),inflow_cents:transactions.filter(x=>x.direction==="inflow").reduce((s,x)=>s+Number(x.amount_cents),0),outflow_cents:transactions.filter(x=>x.direction==="outflow").reduce((s,x)=>s+Number(x.amount_cents),0),receivable_cents:receivables.filter(x=>["pending","partial"].includes(x.status)).reduce((s,x)=>s+Number(x.original_cents)-Number(x.received_cents),0),payable_cents:payables.filter(x=>["pending","partial"].includes(x.status)).reduce((s,x)=>s+Number(x.original_cents)-Number(x.paid_cents),0),revenue_cents:revenue,cogs_cents:cogs,expenses_cents:expenses,result_cents:revenue-cogs-expenses};
    return response({accounts,summary,transactions:transactions.map(x=>({...x,account_name:x.financial_accounts?.name,category_name:x.financial_categories?.name}))});
  }
  if(url.pathname==="/api/finance/categories"&&request.method==="GET")return response({items:await rest(request,env,"financial_categories","select=*&order=kind,name")});
  if(url.pathname==="/api/finance/obligations"&&request.method==="GET"){
    const [payables,receivables]=await Promise.all([rest(request,env,"accounts_payable","select=*,suppliers(name)&order=status,due_date"),rest(request,env,"accounts_receivable","select=*,customers(name)&order=status,due_date")]);
    return response({payables:payables.map(x=>({...x,party:x.suppliers?.name})),receivables:receivables.map(x=>({...x,party:x.customer_name||x.customers?.name}))});
  }
  if(url.pathname==="/api/finance/accounts"&&request.method==="POST"){const b=await request.json();const id=await rpc(request,env,"create_financial_account",{p_name:b.name,p_type:b.type,p_opening_balance_cents:cents(b.openingBalance||0)});return response({id},201)}
  if(url.pathname==="/api/finance/transactions"&&request.method==="POST"){const b=await request.json();const id=await rpc(request,env,"create_financial_transaction",{p_account_id:b.accountId,p_direction:b.direction,p_amount_cents:cents(b.amount),p_date:b.date||today(),p_category_id:b.categoryId,p_description:b.description});return response({id},201)}
  if(url.pathname==="/api/finance/transfers"&&request.method==="POST"){const b=await request.json();const id=await rpc(request,env,"transfer_funds",{p_from:b.fromAccountId,p_to:b.toAccountId,p_amount_cents:cents(b.amount),p_date:b.date||today()});return response({id},201)}
  const reconcile=url.pathname.match(/^\/api\/finance\/transactions\/([^/]+)\/reconcile$/);if(reconcile&&request.method==="POST"){await rpc(request,env,"reconcile_transaction",{p_id:reconcile[1]});return response({ok:true})}
  return null;
}

async function reports(request,env,url){
  if(url.pathname!=="/api/reports"||request.method!=="GET")return null;
  const type=clean(url.searchParams.get("type"),40),from=url.searchParams.get("from")||"0001-01-01",to=url.searchParams.get("to")||"9999-12-31",product=url.searchParams.get("product")||"",category=url.searchParams.get("category")||"",supplier=url.searchParams.get("supplier")||"",status=url.searchParams.get("status")||"";
  const [sales,items,purchases,inventory,transactions,variants]=await Promise.all([
    rest(request,env,"sales_orders",`select=id,order_date,order_status,total_cents&order_date=gte.${from}&order_date=lte.${to}`),
    rest(request,env,"sales_order_items","select=*,sales_orders(order_date,order_status),product_variants(id,sku,product_id,products(id,name,category_id,supplier_id))"),
    rest(request,env,"purchase_orders",`select=id,order_date,order_status,total_cents,supplier_id,suppliers(name),purchase_payments(amount_cents)&order_date=gte.${from}&order_date=lte.${to}`),
    rest(request,env,"inventory_balances","select=physical,reserved,product_variants(id,sku,cost_cents,product_id,products(id,name,category_id,supplier_id))"),
    rest(request,env,"financial_transactions",`select=transaction_date,direction,amount_cents,category_id,financial_categories(name,affects_result)&transaction_date=gte.${from}&transaction_date=lte.${to}`),
    rest(request,env,"product_variants","select=id,sku,active,product_id,products(id,name,category_id,supplier_id),sales_order_items(quantity,returned_quantity,sales_orders(order_date,order_status))")
  ]);
  const validSales=sales.filter(x=>(!status||x.order_status===status)&&x.order_status!=="cancelled"),validIds=new Set(validSales.map(x=>x.id));let rows=[];
  const validItem=x=>{const p=x.product_variants?.products;return validIds.has(x.sales_order_id)&&(!product||p?.id===product)&&(!category||p?.category_id===category)};
  if(type==="revenue"){const m={};for(const x of sales.filter(x=>(!status||x.order_status===status)))m[x.order_date]??={data:x.order_date,vendas:0,faturamento_cents:0},m[x.order_date].vendas++,m[x.order_date].faturamento_cents+=Number(x.total_cents);rows=Object.values(m).sort((a,b)=>a.data.localeCompare(b.data))}
  else if(["sales-product","top-products","margin-sku"].includes(type)){const m={};for(const x of items.filter(validItem)){const v=x.product_variants,p=v?.products,key=v?.id;if(!key)continue;m[key]??={produto:p.name,sku:v.sku,quantidade:0,receita_cents:0,cmv_cents:0,contribuicao_cents:0};const qty=Number(x.quantity)-Number(x.returned_quantity),revenue=qty*Number(x.unit_price_cents)-Number(x.discount_cents),cost=qty*Number(x.historical_cost_cents);m[key].quantidade+=qty;m[key].receita_cents+=revenue;m[key].cmv_cents+=cost;m[key].contribuicao_cents+=revenue-cost}rows=Object.values(m);if(type!=="margin-sku")rows=rows.map(({produto,sku,quantidade,receita_cents})=>({produto,sku,quantidade,faturamento_cents:receita_cents}));rows.sort((a,b)=>type==="top-products"?b.quantidade-a.quantidade:String(a.produto).localeCompare(String(b.produto)))}
  else if(type==="result"){const faturamento_cents=validSales.reduce((s,x)=>s+Number(x.total_cents),0),cmv_cents=items.filter(validItem).reduce((s,x)=>s+(Number(x.quantity)-Number(x.returned_quantity))*Number(x.historical_cost_cents),0),despesas_cents=transactions.filter(x=>x.direction==="outflow"&&x.financial_categories?.affects_result).reduce((s,x)=>s+Number(x.amount_cents),0);rows=[{faturamento_cents,cmv_cents,despesas_cents,resultado_cents:faturamento_cents-cmv_cents-despesas_cents}]}
  else if(type==="purchases-supplier"){const m={};for(const x of purchases.filter(x=>x.order_status!=="cancelled"&&(!supplier||x.supplier_id===supplier))){m[x.supplier_id]??={fornecedor:x.suppliers?.name,compras:0,total_cents:0,pendente_cents:0};const paid=(x.purchase_payments||[]).reduce((s,p)=>s+Number(p.amount_cents),0);m[x.supplier_id].compras++;m[x.supplier_id].total_cents+=Number(x.total_cents);m[x.supplier_id].pendente_cents+=Number(x.total_cents)-paid}rows=Object.values(m).sort((a,b)=>b.total_cents-a.total_cents)}
  else if(type==="slow-products"){rows=variants.filter(v=>v.active&&(!product||v.product_id===product)&&(!category||v.products?.category_id===category)).map(v=>{const matching=(v.sales_order_items||[]).filter(i=>i.sales_orders?.order_status!=="cancelled"&&i.sales_orders?.order_date>=from&&i.sales_orders?.order_date<=to);return{produto:v.products?.name,sku:v.sku,quantidade:matching.reduce((s,i)=>s+Number(i.quantity)-Number(i.returned_quantity),0),ultima_venda:matching.map(i=>i.sales_orders?.order_date).sort().at(-1)||null}}).sort((a,b)=>a.quantidade-b.quantidade)}
  else if(type==="inventory-value"){rows=inventory.filter(x=>{const p=x.product_variants?.products;return(!product||p?.id===product)&&(!category||p?.category_id===category)&&(!supplier||p?.supplier_id===supplier)}).map(x=>({produto:x.product_variants?.products?.name,sku:x.product_variants?.sku,physical:x.physical,reserved:x.reserved,disponivel:Number(x.physical)-Number(x.reserved),custo_cents:x.product_variants?.cost_cents,valor_cents:Number(x.physical)*Number(x.product_variants?.cost_cents)})).sort((a,b)=>b.valor_cents-a.valor_cents)}
  else if(type==="expenses-category"){const m={};for(const x of transactions.filter(x=>x.direction==="outflow"&&x.financial_categories?.affects_result)){m[x.category_id]??={categoria:x.financial_categories?.name,lancamentos:0,total_cents:0};m[x.category_id].lancamentos++;m[x.category_id].total_cents+=Number(x.amount_cents)}rows=Object.values(m).sort((a,b)=>b.total_cents-a.total_cents)}
  else if(type==="cash-flow"){const m={};for(const x of transactions){m[x.transaction_date]??={data:x.transaction_date,entradas_cents:0,saidas_cents:0,fluxo_cents:0};const amount=Number(x.amount_cents);if(x.direction==="inflow")m[x.transaction_date].entradas_cents+=amount;else m[x.transaction_date].saidas_cents+=amount;m[x.transaction_date].fluxo_cents+=x.direction==="inflow"?amount:-amount}rows=Object.values(m).sort((a,b)=>a.data.localeCompare(b.data))}
  else return response({error:"Relatório inválido."},422);
  return response({type,filters:{from,to,product,category,supplier,status},rows});
}

async function supporting(request,env,url){
  if(url.pathname==="/api/dashboard"&&request.method==="GET"){
    const now=new Date(),from=`${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,"0")}-01`,to=today();
    const [sales,inventory,transactions,receivables,payables,purchases]=await Promise.all([
      rest(request,env,"sales_orders",`select=id,number,customer_name,order_date,total_cents,order_status,shipping_status,sales_order_items(quantity,returned_quantity,historical_cost_cents,unit_price_cents,product_variants(sku,products(name,product_images(object_key))))&order_date=gte.${from}&order_date=lte.${to}`),
      rest(request,env,"inventory_balances","select=physical,reserved,product_variants(sku,cost_cents,minimum_stock,products(name))"),
      rest(request,env,"financial_transactions",`select=direction,amount_cents,transaction_date,category_id,financial_categories(affects_result)&transaction_date=gte.${from}&transaction_date=lte.${to}`),
      rest(request,env,"accounts_receivable","select=description,due_date,original_cents,received_cents,status"),rest(request,env,"accounts_payable","select=description,due_date,original_cents,paid_cents,status"),
      rest(request,env,"purchase_orders","select=id,number,receipt_status,expected_date&receipt_status=neq.received&order_status=neq.cancelled")
    ]);
    const valid=sales.filter(x=>x.order_status!=="cancelled"),revenue=valid.reduce((s,x)=>s+Number(x.total_cents),0),shipped=valid.filter(x=>["shipped","delivered"].includes(x.shipping_status));
    const cogs=shipped.flatMap(x=>x.sales_order_items||[]).reduce((s,x)=>s+(Number(x.quantity)-Number(x.returned_quantity))*Number(x.historical_cost_cents),0),expenses=transactions.filter(x=>x.direction==="outflow"&&x.financial_categories?.affects_result).reduce((s,x)=>s+Number(x.amount_cents),0);
    const grouped={};for(const sale of valid)grouped[sale.order_date]=(grouped[sale.order_date]||0)+Number(sale.total_cents);
    const ranked={};for(const sale of valid)for(const item of sale.sales_order_items||[]){const sku=item.product_variants?.sku||"",key=sku||"sem-sku",units=Number(item.quantity)-Number(item.returned_quantity);ranked[key]??={name:item.product_variants?.products?.name||"Produto",sku,units:0,revenue_cents:0,image_key:item.product_variants?.products?.product_images?.[0]?.object_key};ranked[key].units+=units;ranked[key].revenue_cents+=units*Number(item.unit_price_cents)}
    const due=[...receivables.filter(x=>["pending","partial"].includes(x.status)).map(x=>({...x,amount_cents:Number(x.original_cents)-Number(x.received_cents)})),...payables.filter(x=>["pending","partial"].includes(x.status)).map(x=>({...x,amount_cents:Number(x.original_cents)-Number(x.paid_cents)}))].sort((a,b)=>String(a.due_date).localeCompare(String(b.due_date))).slice(0,6);
    const topProducts=Object.values(ranked).sort((a,b)=>b.units-a.units).slice(0,5);for(const item of topProducts)item.image_key=await signedImage(request,env,item.image_key);
    return response({period:{from,to},metrics:{revenue_cents:revenue,result_cents:revenue-cogs-expenses,sales_count:valid.length,balance_cents:transactions.reduce((s,x)=>s+(x.direction==="inflow"?1:-1)*Number(x.amount_cents),0),inventory_value_cents:inventory.reduce((s,x)=>s+Number(x.physical)*Number(x.product_variants?.cost_cents||0),0),critical_count:inventory.filter(x=>Number(x.physical)-Number(x.reserved)<=Number(x.product_variants?.minimum_stock||0)).length},daily:Object.entries(grouped).sort().map(([date,revenue_cents])=>({date,revenue_cents})),finance:{inflow_cents:transactions.filter(x=>x.direction==="inflow").reduce((s,x)=>s+Number(x.amount_cents),0),outflow_cents:transactions.filter(x=>x.direction==="outflow").reduce((s,x)=>s+Number(x.amount_cents),0),receivable_cents:receivables.filter(x=>["pending","partial"].includes(x.status)).reduce((s,x)=>s+Number(x.original_cents)-Number(x.received_cents),0),payable_cents:payables.filter(x=>["pending","partial"].includes(x.status)).reduce((s,x)=>s+Number(x.original_cents)-Number(x.paid_cents),0)},alerts:{critical:inventory.filter(x=>Number(x.physical)-Number(x.reserved)<=Number(x.product_variants?.minimum_stock||0)).map(x=>({name:x.product_variants?.products?.name,sku:x.product_variants?.sku,available:Number(x.physical)-Number(x.reserved),minimum_stock:x.product_variants?.minimum_stock})).slice(0,6),purchases:purchases.slice(0,6),shipping:valid.filter(x=>["pending","separated"].includes(x.shipping_status)).slice(0,6),due},topProducts});
  }
  if(url.pathname==="/api/pricing/calculate"&&request.method==="POST")return response(calculatePricing(await request.json()));
  const price=url.pathname.match(/^\/api\/pricing\/variants\/([^/]+)\/apply$/);if(price&&request.method==="POST"){const b=await request.json(),calculation=calculatePricing(b),selected=cents(b.selectedPrice);if(selected<calculation.breakEvenCents)return response({error:"O preço escolhido está abaixo do ponto de equilíbrio."},422);const value=await rpc(request,env,"apply_variant_price",{p_variant_id:price[1],p_price_cents:selected,p_calculation:calculation});return response({ok:true,priceCents:value})}
  if(url.pathname==="/api/settings"&&request.method==="GET"){const rows=await rest(request,env,"settings","select=key,value_json,updated_at&order=key");return response({settings:rows.map(x=>({...x,value:x.value_json}))})}
  if(url.pathname==="/api/settings"&&request.method==="PUT"){const b=await request.json();await rpc(request,env,"upsert_setting",{p_key:b.key,p_value:b.value});return response({ok:true})}
  return null;
}

export async function supabaseApi(request, env, url) {
  try {
    if (url.pathname === "/api/config" && request.method === "GET") {
      if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) return response({ error: "Supabase não configurado no ambiente." }, 503);
      return response({ url: env.SUPABASE_URL, publishableKey: env.SUPABASE_PUBLISHABLE_KEY });
    }
    const authResult = await authApi(request, env, url);
    if (authResult) return authResult;
    const ctx = await currentAccess(request, env);
    const notificationResult = await notificationsApi(request, env, url, ctx);
    if (notificationResult) return notificationResult;
    if (url.pathname === "/api/session" && request.method === "GET") { const role=ctx.can("dashboard.admin.view")?"Administrador":"Operacional"; return response({ user:{...ctx.user,role}, groups:ctx.groups, permissions:ctx.permissions, role }); }
    authorizeRoute(request,url,ctx);
    const adminResult=await administration(request,env,url,ctx);
    if(adminResult)return adminResult;
    const safeResult=await safeProjectionApi(request,env,url,ctx);
    if(safeResult)return safeResult;
    const catalogResult = await catalog(request, env, url);
    if (catalogResult) return catalogResult;
    const operationsResult = await operations(request, env, url);
    if (operationsResult) return operationsResult;
    const financeResult = await finance(request, env, url);
    if (financeResult) return financeResult;
    const reportResult = await reports(request,env,url);
    if(reportResult)return reportResult;
    const supportingResult = await supporting(request, env, url);
    if (supportingResult) return supportingResult;
    return response({ error: "Rota ainda não migrada para o Supabase." }, 501);
  } catch (error) {
    console.error("NexCell API request failed", { status: error?.status, message: error?.message });
    const issue = publicError(error);
    return response({ error: issue.message }, issue.status);
  }
}
