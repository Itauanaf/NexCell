import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";

const db = new DatabaseSync(":memory:");
db.exec("PRAGMA foreign_keys=ON");
for (const name of ["0001_foundation.sql", "0002_catalog.sql", "0003_purchasing_inventory.sql", "0004_deepen_purchasing.sql", "0005_sales.sql", "0006_finance.sql", "0007_operational_indexes.sql"]) {
  db.exec(readFileSync(new URL(`../migrations/${name}`, import.meta.url), "utf8"));
}

db.exec(`
  INSERT INTO profiles(id,email,full_name,role_id) VALUES('u1','admin@nexcell.local','Admin','admin');
  INSERT INTO suppliers(id,name,created_by) VALUES('s1','Fornecedor','u1');
  INSERT INTO products(id,name,category_id,supplier_id,created_by) VALUES('p1','Capa Premium','cases','s1','u1');
  INSERT INTO product_variants(id,product_id,sku,color,cost_cents,sale_price_cents,created_at) VALUES('v1','p1','CAPA-01','Azul',2500,5000,CURRENT_TIMESTAMP);
  INSERT INTO inventory_balances(variant_id,physical,reserved) VALUES('v1',15,0);
`);

const createSale = (id, item, qty) => db.exec(`
  INSERT INTO sales_orders(id,number,customer_name,order_date,subtotal_cents,total_cents,created_by) VALUES('${id}','${id.toUpperCase()}','Cliente','2026-10-14',${qty * 5000},${qty * 5000},'u1');
  INSERT INTO sales_order_items(id,sales_order_id,variant_id,quantity,unit_price_cents,historical_cost_cents) VALUES('${item}','${id}','v1',${qty},5000,2500);
  INSERT INTO inventory_reservations(id,sales_order_id,sales_order_item_id,variant_id,quantity) VALUES('r-${id}','${id}','${item}','v1',${qty});
`);

createSale("sale1", "item1", 3);
assert.deepEqual({ ...db.prepare("SELECT physical,reserved,physical-reserved available FROM inventory_balances").get() }, { physical: 15, reserved: 3, available: 12 });
db.exec("UPDATE product_variants SET cost_cents=3100 WHERE id='v1'");
assert.equal(db.prepare("SELECT historical_cost_cents FROM sales_order_items WHERE id='item1'").get().historical_cost_cents, 2500);

db.exec("INSERT INTO shipments(id,sales_order_id,shipped_at,created_by) VALUES('ship1','sale1',CURRENT_TIMESTAMP,'u1')");
assert.deepEqual({ ...db.prepare("SELECT physical,reserved,physical-reserved available FROM inventory_balances").get() }, { physical: 12, reserved: 0, available: 12 });
assert.throws(() => db.exec("INSERT INTO shipments(id,sales_order_id,shipped_at,created_by) VALUES('ship2','sale1',CURRENT_TIMESTAMP,'u1')"));
assert.equal(db.prepare("SELECT physical FROM inventory_balances").get().physical, 12);

db.exec("INSERT INTO sales_returns(id,sales_order_id,checked_by) VALUES('ret1','sale1','u1')");
db.exec("INSERT INTO sales_return_items(id,sales_return_id,sales_order_item_id,variant_id,quantity) VALUES('reti1','ret1','item1','v1',2)");
assert.equal(db.prepare("SELECT physical FROM inventory_balances").get().physical, 14);
assert.throws(() => db.exec("INSERT INTO sales_return_items(id,sales_return_id,sales_order_item_id,variant_id,quantity) VALUES('reti2','ret1','item1','v1',2)"));

createSale("sale2", "item2", 2);
assert.equal(db.prepare("SELECT reserved FROM inventory_balances").get().reserved, 2);
db.exec("INSERT INTO sales_cancellations(id,sales_order_id,reason,created_by) VALUES('cancel1','sale2','Cliente desistiu','u1')");
assert.equal(db.prepare("SELECT reserved FROM inventory_balances").get().reserved, 0);

console.log("sales invariants: ok");
