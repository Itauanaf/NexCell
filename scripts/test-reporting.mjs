import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { createReportingModule } from "../worker/modules/reporting.js";

const sqlite=new DatabaseSync(":memory:");sqlite.exec("PRAGMA foreign_keys=ON");
for(const name of ["0001_foundation.sql","0002_catalog.sql","0003_purchasing_inventory.sql","0004_deepen_purchasing.sql","0005_sales.sql","0006_finance.sql","0007_operational_indexes.sql"])sqlite.exec(readFileSync(new URL(`../migrations/${name}`,import.meta.url),"utf8"));
const today=new Date().toISOString().slice(0,10);
sqlite.exec(`
 INSERT INTO profiles(id,email,role_id) VALUES('u1','admin@nexcell.local','admin');
 INSERT INTO suppliers(id,name,created_by) VALUES('sup1','Fornecedor','u1');
 INSERT INTO products(id,name,category_id,supplier_id,created_by) VALUES('p1','Produto','cases','sup1','u1');
 INSERT INTO product_variants(id,product_id,sku,cost_cents,sale_price_cents,minimum_stock) VALUES('v1','p1','SKU-1',2500,5000,8);
 INSERT INTO inventory_balances(variant_id,physical,reserved) VALUES('v1',10,0);
 INSERT INTO financial_accounts(id,name,account_type,opening_balance_cents,created_by) VALUES('bank','Banco','bank',10000,'u1');
 INSERT INTO purchase_orders(id,number,supplier_id,order_date,expected_date,order_status,total_cents,created_by) VALUES('po1','CMP-1','sup1','${today}','${today}','confirmed',10000,'u1');
 INSERT INTO purchase_order_items(id,purchase_order_id,variant_id,quantity,unit_cost_cents) VALUES('poi1','po1','v1',4,2500);
 INSERT INTO purchase_payments(id,purchase_order_id,amount_cents,payment_date,method,created_by,account_id) VALUES('pp1','po1',4000,'${today}','PIX','u1','bank');
 INSERT INTO sales_orders(id,number,customer_name,order_date,subtotal_cents,total_cents,created_by) VALUES('so1','VND-1','Cliente','${today}',15000,15000,'u1');
 INSERT INTO sales_order_items(id,sales_order_id,variant_id,quantity,unit_price_cents,historical_cost_cents) VALUES('soi1','so1','v1',3,5000,2500);
 INSERT INTO inventory_reservations(id,sales_order_id,sales_order_item_id,variant_id,quantity) VALUES('res1','so1','soi1','v1',3);
 INSERT INTO sales_payments(id,sales_order_id,amount_cents,payment_date,method,created_by,account_id) VALUES('sp1','so1',9000,'${today}','PIX','u1','bank');
 INSERT INTO shipments(id,sales_order_id,shipped_at,created_by) VALUES('ship1','so1',CURRENT_TIMESTAMP,'u1');
 INSERT INTO financial_transactions(id,account_id,direction,amount_cents,transaction_date,category_id,description,source_type,source_id,created_by) VALUES('expense1','bank','outflow',1000,'${today}','marketing','Anúncios','manual','expense1','u1');
`);
const adapter={prepare(sql){const statement=sqlite.prepare(sql);let values=[];return{bind(...next){values=next;return this},first(){return statement.get(...values)},all(){return{results:statement.all(...values)}}}}};
const reporting=createReportingModule(adapter),dashboard=await reporting.dashboard();
assert.equal(dashboard.metrics.revenue_cents,15000);
assert.equal(dashboard.metrics.result_cents,6500);
assert.equal(dashboard.metrics.sales_count,1);
assert.equal(dashboard.metrics.inventory_value_cents,17500);
assert.equal(dashboard.metrics.critical_count,1);
assert.equal(dashboard.topProducts[0].units,3);
const types=["revenue","sales-product","result","purchases-supplier","margin-sku","top-products","slow-products","inventory-value","expenses-category","cash-flow"];
for(const type of types){const output=await reporting.report(type,{from:today,to:today});assert.equal(output.type,type);assert.ok(Array.isArray(output.rows));assert.ok(output.rows.length>0,`${type} should return rows`)}
const result=await reporting.report("result",{from:today,to:today});assert.equal(result.rows[0].resultado_cents,6500);
const filtered=await reporting.report("sales-product",{from:today,to:today,product:"p1"});assert.equal(filtered.rows[0].quantidade,3);
console.log("dashboard and reports: ok");
