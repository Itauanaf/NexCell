const routes = [
  ["GET",/^\/api\/dashboard$/,ctx=>ctx.can("dashboard.admin.view")?"dashboard.admin.view":"dashboard.operator.view"],
  ["GET",/^\/api\/operator\/dashboard$/,"dashboard.operator.view"],
  ["GET",/^\/api\/categories$/,"products.view"],
  ["GET",/^\/api\/products$/,"products.view"],
  ["POST",/^\/api\/products$/,"products.create"],
  ["PATCH",/^\/api\/products\/[^/]+$/,"products.edit"],
  ["POST",/^\/api\/products\/[^/]+\/duplicate$/,"products.create"],
  ["PUT",/^\/api\/products\/[^/]+\/image$/,"products.edit"],
  ["GET",/^\/api\/suppliers$/,"suppliers.view"],["POST",/^\/api\/suppliers$/,"suppliers.create"],["PATCH",/^\/api\/suppliers\/[^/]+$/,"suppliers.edit"],
  ["GET",/^\/api\/purchases(\/[^/]+\/items)?$/,"purchases.view"],["POST",/^\/api\/purchases$/,"purchases.create"],
  ["POST",/^\/api\/purchases\/[^/]+\/payments$/,"purchases.payment.record"],["POST",/^\/api\/purchases\/[^/]+\/receipts$/,"purchases.receive"],
  ["GET",/^\/api\/inventory$/,"inventory.view"],["GET",/^\/api\/inventory\/movements$/,"inventory.movements.view"],
  ["GET",/^\/api\/sales$/,"sales.view"],["POST",/^\/api\/sales$/,"sales.create"],["GET",/^\/api\/sales\/[^/]+\/items$/,"sales.view"],
  ["POST",/^\/api\/sales\/[^/]+\/payments$/,"sales.create"],["POST",/^\/api\/sales\/[^/]+\/separate$/,"sales.ship"],["POST",/^\/api\/sales\/[^/]+\/shipments$/,"sales.ship"],
  ["POST",/^\/api\/sales\/[^/]+\/cancel$/,"sales.cancel"],["POST",/^\/api\/sales\/[^/]+\/returns$/,"sales.refund"],
  ["GET",/^\/api\/payment-accounts$/,"sales.create"],
  ["GET",/^\/api\/finance(\/categories|\/obligations)?$/,"finance.view"],["POST",/^\/api\/finance\/accounts$/,"finance.accounts.manage"],
  ["POST",/^\/api\/finance\/transactions$/,"finance.transactions.create"],["POST",/^\/api\/finance\/transfers$/,"finance.transactions.create"],["POST",/^\/api\/finance\/transactions\/[^/]+\/reconcile$/,"finance.transactions.edit"],
  ["POST",/^\/api\/pricing\/calculate$/,"pricing.view"],["POST",/^\/api\/pricing\/variants\/[^/]+\/apply$/,"pricing.apply"],
  ["GET",/^\/api\/reports$/,(ctx,url)=>["result","margin-sku","inventory-value","expenses-category","cash-flow"].includes(url.searchParams.get("type"))?"reports.financial.view":"reports.operational.view"],
  ["GET",/^\/api\/settings$/,"dashboard.admin.view"],["PUT",/^\/api\/settings$/,"dashboard.admin.view"],
  ["GET",/^\/api\/admin\/overview$/,"users.view"],["GET",/^\/api\/admin\/users$/,"users.view"],["POST",/^\/api\/admin\/users\/invite$/,"users.invite"],
  ["POST",/^\/api\/admin\/invitations\/[^/]+\/resend$/,"users.invite"],
  ["DELETE",/^\/api\/admin\/users\/[^/]+$/,"users.delete"],
  ["PATCH",/^\/api\/admin\/users\/[^/]+$/,"users.edit"],["GET",/^\/api\/admin\/groups$/,"groups.view"],["POST",/^\/api\/admin\/groups$/,"groups.manage"],
  ["PATCH",/^\/api\/admin\/groups\/[^/]+$/,"groups.manage"],["POST",/^\/api\/admin\/groups\/[^/]+\/duplicate$/,"groups.manage"],
  ["GET",/^\/api\/admin\/permissions$/,"groups.view"],["GET",/^\/api\/admin\/audit$/,"audit.view"]
];

export function authorizationContext(access) {
  const permissions=new Set(access?.permissions||[]);
  return { user:access.user, groups:access.groups||[], permissions:[...permissions], can:code=>permissions.has(code), require(code){if(!permissions.has(code))throw Object.assign(new Error("Você não possui permissão para esta operação."),{status:403,code:"permission_denied"});} };
}

export function requiredPermission(request,url,ctx) {
  const route=routes.find(([method,pattern])=>method===request.method&&pattern.test(url.pathname));
  if(!route)return null;
  return typeof route[2]==="function"?route[2](ctx,url):route[2];
}

export function authorizeRoute(request,url,ctx) {
  const permission=requiredPermission(request,url,ctx);
  if(!permission)throw Object.assign(new Error("Rota não autorizada."),{status:403,code:"route_denied"});
  ctx.require(permission);
  return permission;
}
