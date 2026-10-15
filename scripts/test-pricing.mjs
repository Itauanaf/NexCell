import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { calculatePricing, createPricingModule, PricingError } from "../worker/modules/pricing.js";

const base={purchaseCost:"100.00",acquisitionFreight:"0",packaging:"0",storeFreight:"0",otherCosts:"0",paymentRate:"10",commissionRate:"0",taxRate:"0",currentPrice:"120"};
const profit=calculatePricing({...base,mode:"profit",desiredProfit:"20"});
assert.equal(profit.priceCents,13334);
assert.equal(profit.breakEvenCents,11112);
assert.equal(profit.commercial90Cents,13390);
assert.equal(profit.commercial99Cents,13399);

const margin=calculatePricing({...base,mode:"margin",desiredMargin:"30"});
assert.equal(margin.priceCents,16667);
assert.equal(margin.contributionCents,5000);
assert.equal(margin.marginBps,3000);

const simulation=calculatePricing({...base,mode:"simulation",manualPrice:"150"});
assert.equal(simulation.feesCents,1500);
assert.equal(simulation.contributionCents,3500);
assert.equal(simulation.marginBps,2333);
assert.throws(()=>calculatePricing({...base,mode:"margin",paymentRate:"70",desiredMargin:"30"}),PricingError);
assert.throws(()=>calculatePricing({...base,mode:"profit",purchaseCost:"10.999",desiredProfit:"5"}),PricingError);

const sqlite=new DatabaseSync(":memory:");sqlite.exec("PRAGMA foreign_keys=ON");
for(const name of ["0001_foundation.sql","0002_catalog.sql","0003_purchasing_inventory.sql","0004_deepen_purchasing.sql","0005_sales.sql","0006_finance.sql"])sqlite.exec(readFileSync(new URL(`../migrations/${name}`,import.meta.url),"utf8"));
sqlite.exec(`INSERT INTO profiles(id,email,role_id) VALUES('u1','admin@nexcell.local','admin'); INSERT INTO products(id,name,category_id,created_by) VALUES('p1','Produto','cases','u1'); INSERT INTO product_variants(id,product_id,sku,cost_cents,sale_price_cents) VALUES('v1','p1','SKU-1',10000,12000); INSERT INTO sales_orders(id,number,customer_name,order_date,subtotal_cents,total_cents,created_by) VALUES('s1','VND-1','Cliente','2026-10-14',12000,12000,'u1'); INSERT INTO sales_order_items(id,sales_order_id,variant_id,quantity,unit_price_cents,historical_cost_cents) VALUES('i1','s1','v1',1,12000,10000);`);
const adapter={prepare(sql){const statement=sqlite.prepare(sql);let values=[];return{bind(...next){values=next;return this},first(){return statement.get(...values)},run(){return statement.run(...values)}}},batch(items){sqlite.exec("BEGIN");try{const result=items.map(item=>item.run());sqlite.exec("COMMIT");return result}catch(error){sqlite.exec("ROLLBACK");throw error}}};
await createPricingModule(adapter).apply("v1",{...base,mode:"profit",desiredProfit:"20",selectedPrice:"133.99"},"u1");
assert.equal(sqlite.prepare("SELECT sale_price_cents FROM product_variants WHERE id='v1'").get().sale_price_cents,13399);
assert.deepEqual({...sqlite.prepare("SELECT unit_price_cents,historical_cost_cents FROM sales_order_items WHERE id='i1'").get()},{unit_price_cents:12000,historical_cost_cents:10000});
console.log("pricing calculations: ok");
