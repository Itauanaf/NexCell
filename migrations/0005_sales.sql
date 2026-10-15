CREATE TABLE customers (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, email TEXT,
  created_by TEXT NOT NULL REFERENCES profiles(id),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_customers_name ON customers(name);

CREATE TABLE sales_orders (
  id TEXT PRIMARY KEY, number TEXT NOT NULL UNIQUE,
  customer_id TEXT REFERENCES customers(id), customer_name TEXT NOT NULL,
  order_date TEXT NOT NULL,
  order_status TEXT NOT NULL DEFAULT 'created' CHECK(order_status IN ('created','separated','shipped','delivered','cancelled','returned')),
  payment_status TEXT NOT NULL DEFAULT 'pending' CHECK(payment_status IN ('pending','partial','paid','refunded')),
  shipping_status TEXT NOT NULL DEFAULT 'pending' CHECK(shipping_status IN ('pending','separated','shipped','delivered','cancelled')),
  subtotal_cents INTEGER NOT NULL CHECK(subtotal_cents>=0),
  discount_cents INTEGER NOT NULL DEFAULT 0 CHECK(discount_cents>=0),
  shipping_charged_cents INTEGER NOT NULL DEFAULT 0 CHECK(shipping_charged_cents>=0),
  total_cents INTEGER NOT NULL CHECK(total_cents>=0), notes TEXT,
  created_by TEXT NOT NULL REFERENCES profiles(id), created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sales_order_items (
  id TEXT PRIMARY KEY, sales_order_id TEXT NOT NULL REFERENCES sales_orders(id),
  variant_id TEXT NOT NULL REFERENCES product_variants(id), quantity INTEGER NOT NULL CHECK(quantity>0),
  returned_quantity INTEGER NOT NULL DEFAULT 0 CHECK(returned_quantity>=0 AND returned_quantity<=quantity),
  unit_price_cents INTEGER NOT NULL CHECK(unit_price_cents>=0),
  historical_cost_cents INTEGER NOT NULL CHECK(historical_cost_cents>=0),
  discount_cents INTEGER NOT NULL DEFAULT 0 CHECK(discount_cents>=0),
  UNIQUE(sales_order_id,variant_id)
);

CREATE TABLE inventory_reservations (
  id TEXT PRIMARY KEY, sales_order_id TEXT NOT NULL REFERENCES sales_orders(id),
  sales_order_item_id TEXT NOT NULL UNIQUE REFERENCES sales_order_items(id),
  variant_id TEXT NOT NULL REFERENCES product_variants(id), quantity INTEGER NOT NULL CHECK(quantity>0),
  status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','released','consumed')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sales_payments (
  id TEXT PRIMARY KEY, sales_order_id TEXT NOT NULL REFERENCES sales_orders(id),
  amount_cents INTEGER NOT NULL CHECK(amount_cents>0), payment_date TEXT NOT NULL, method TEXT NOT NULL,
  created_by TEXT NOT NULL REFERENCES profiles(id), created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE shipments (
  id TEXT PRIMARY KEY, sales_order_id TEXT NOT NULL UNIQUE REFERENCES sales_orders(id),
  shipped_at TEXT NOT NULL, tracking_code TEXT, created_by TEXT NOT NULL REFERENCES profiles(id),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sales_cancellations (
  id TEXT PRIMARY KEY, sales_order_id TEXT NOT NULL UNIQUE REFERENCES sales_orders(id), reason TEXT NOT NULL,
  created_by TEXT NOT NULL REFERENCES profiles(id), created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sales_returns (
  id TEXT PRIMARY KEY, sales_order_id TEXT NOT NULL REFERENCES sales_orders(id), notes TEXT,
  checked_by TEXT NOT NULL REFERENCES profiles(id), checked_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE sales_return_items (
  id TEXT PRIMARY KEY, sales_return_id TEXT NOT NULL REFERENCES sales_returns(id),
  sales_order_item_id TEXT NOT NULL REFERENCES sales_order_items(id),
  variant_id TEXT NOT NULL REFERENCES product_variants(id), quantity INTEGER NOT NULL CHECK(quantity>0)
);

CREATE TRIGGER reservation_guard BEFORE INSERT ON inventory_reservations BEGIN
  SELECT CASE WHEN NEW.quantity>(SELECT physical-reserved FROM inventory_balances WHERE variant_id=NEW.variant_id)
  THEN RAISE(ABORT,'insufficient_stock') END;
END;
CREATE TRIGGER reservation_apply AFTER INSERT ON inventory_reservations BEGIN
  UPDATE inventory_balances SET reserved=reserved+NEW.quantity,updated_at=CURRENT_TIMESTAMP WHERE variant_id=NEW.variant_id;
  INSERT INTO inventory_movements(id,variant_id,movement_type,quantity,physical_after,reserved_after,reason,reference_type,reference_id,created_by)
  SELECT lower(hex(randomblob(16))),NEW.variant_id,'reservation',NEW.quantity,b.physical,b.reserved,'Reserva de venda','sales_order',NEW.sales_order_id,o.created_by
  FROM inventory_balances b JOIN sales_orders o ON o.id=NEW.sales_order_id WHERE b.variant_id=NEW.variant_id;
END;

CREATE TRIGGER sales_payment_guard BEFORE INSERT ON sales_payments BEGIN
  SELECT CASE WHEN COALESCE((SELECT SUM(amount_cents) FROM sales_payments WHERE sales_order_id=NEW.sales_order_id),0)+NEW.amount_cents>(SELECT total_cents FROM sales_orders WHERE id=NEW.sales_order_id)
  THEN RAISE(ABORT,'payment_exceeds_sale_total') END;
END;
CREATE TRIGGER sales_payment_apply AFTER INSERT ON sales_payments BEGIN
  UPDATE sales_orders SET payment_status=CASE WHEN (SELECT SUM(amount_cents) FROM sales_payments WHERE sales_order_id=NEW.sales_order_id)>=total_cents THEN 'paid' ELSE 'partial' END,updated_at=CURRENT_TIMESTAMP WHERE id=NEW.sales_order_id;
END;

CREATE TRIGGER shipment_apply AFTER INSERT ON shipments BEGIN
  INSERT INTO inventory_movements(id,variant_id,movement_type,quantity,physical_after,reserved_after,reason,reference_type,reference_id,created_by)
  SELECT lower(hex(randomblob(16))),r.variant_id,'shipment',-r.quantity,b.physical-r.quantity,b.reserved-r.quantity,'Expedição de venda','shipment',NEW.id,NEW.created_by
  FROM inventory_reservations r JOIN inventory_balances b ON b.variant_id=r.variant_id WHERE r.sales_order_id=NEW.sales_order_id AND r.status='active';
  UPDATE inventory_balances SET physical=physical-(SELECT quantity FROM inventory_reservations r WHERE r.variant_id=inventory_balances.variant_id AND r.sales_order_id=NEW.sales_order_id AND r.status='active'),reserved=reserved-(SELECT quantity FROM inventory_reservations r WHERE r.variant_id=inventory_balances.variant_id AND r.sales_order_id=NEW.sales_order_id AND r.status='active'),updated_at=CURRENT_TIMESTAMP WHERE variant_id IN(SELECT variant_id FROM inventory_reservations WHERE sales_order_id=NEW.sales_order_id AND status='active');
  UPDATE inventory_reservations SET status='consumed',updated_at=CURRENT_TIMESTAMP WHERE sales_order_id=NEW.sales_order_id AND status='active';
  UPDATE sales_orders SET order_status='shipped',shipping_status='shipped',updated_at=CURRENT_TIMESTAMP WHERE id=NEW.sales_order_id;
END;

CREATE TRIGGER cancellation_apply AFTER INSERT ON sales_cancellations BEGIN
  INSERT INTO inventory_movements(id,variant_id,movement_type,quantity,physical_after,reserved_after,reason,reference_type,reference_id,created_by)
  SELECT lower(hex(randomblob(16))),r.variant_id,'release',-r.quantity,b.physical,b.reserved-r.quantity,'Cancelamento de venda','sales_order',NEW.sales_order_id,NEW.created_by FROM inventory_reservations r JOIN inventory_balances b ON b.variant_id=r.variant_id WHERE r.sales_order_id=NEW.sales_order_id AND r.status='active';
  UPDATE inventory_balances SET reserved=reserved-(SELECT quantity FROM inventory_reservations r WHERE r.variant_id=inventory_balances.variant_id AND r.sales_order_id=NEW.sales_order_id AND r.status='active'),updated_at=CURRENT_TIMESTAMP WHERE variant_id IN(SELECT variant_id FROM inventory_reservations WHERE sales_order_id=NEW.sales_order_id AND status='active');
  UPDATE inventory_reservations SET status='released',updated_at=CURRENT_TIMESTAMP WHERE sales_order_id=NEW.sales_order_id AND status='active';
  UPDATE sales_orders SET order_status='cancelled',shipping_status='cancelled',updated_at=CURRENT_TIMESTAMP WHERE id=NEW.sales_order_id;
END;

CREATE TRIGGER return_guard BEFORE INSERT ON sales_return_items BEGIN
  SELECT CASE WHEN NEW.quantity>(SELECT quantity-returned_quantity FROM sales_order_items WHERE id=NEW.sales_order_item_id)
  THEN RAISE(ABORT,'return_exceeds_shipped_quantity') END;
  SELECT CASE WHEN (SELECT so.shipping_status FROM sales_orders so JOIN sales_order_items si ON si.sales_order_id=so.id WHERE si.id=NEW.sales_order_item_id)!='shipped'
  THEN RAISE(ABORT,'sale_not_shipped') END;
END;
CREATE TRIGGER return_apply AFTER INSERT ON sales_return_items BEGIN
  UPDATE sales_order_items SET returned_quantity=returned_quantity+NEW.quantity WHERE id=NEW.sales_order_item_id;
  UPDATE inventory_balances SET physical=physical+NEW.quantity,updated_at=CURRENT_TIMESTAMP WHERE variant_id=NEW.variant_id;
  INSERT INTO inventory_movements(id,variant_id,movement_type,quantity,physical_after,reserved_after,reason,reference_type,reference_id,created_by)
  SELECT lower(hex(randomblob(16))),NEW.variant_id,'return',NEW.quantity,b.physical,b.reserved,'Devolução conferida','sales_return',NEW.sales_return_id,r.checked_by FROM inventory_balances b JOIN sales_returns r ON r.id=NEW.sales_return_id WHERE b.variant_id=NEW.variant_id;
  UPDATE sales_orders SET order_status='returned',updated_at=CURRENT_TIMESTAMP WHERE id=(SELECT sales_order_id FROM sales_returns WHERE id=NEW.sales_return_id);
END;
