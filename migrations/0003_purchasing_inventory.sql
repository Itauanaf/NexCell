CREATE TABLE purchase_orders (
  id TEXT PRIMARY KEY,
  number TEXT NOT NULL UNIQUE,
  supplier_id TEXT NOT NULL REFERENCES suppliers(id),
  order_date TEXT NOT NULL,
  expected_date TEXT,
  order_status TEXT NOT NULL DEFAULT 'draft' CHECK (order_status IN ('draft','confirmed','cancelled')),
  payment_status TEXT NOT NULL DEFAULT 'pending' CHECK (payment_status IN ('pending','partial','paid')),
  receipt_status TEXT NOT NULL DEFAULT 'pending' CHECK (receipt_status IN ('pending','partial','received')),
  discount_cents INTEGER NOT NULL DEFAULT 0 CHECK (discount_cents >= 0),
  freight_cents INTEGER NOT NULL DEFAULT 0 CHECK (freight_cents >= 0),
  other_costs_cents INTEGER NOT NULL DEFAULT 0 CHECK (other_costs_cents >= 0),
  total_cents INTEGER NOT NULL CHECK (total_cents >= 0),
  notes TEXT,
  created_by TEXT NOT NULL REFERENCES profiles(id),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_purchase_supplier_date ON purchase_orders(supplier_id, order_date DESC);

CREATE TABLE purchase_order_items (
  id TEXT PRIMARY KEY,
  purchase_order_id TEXT NOT NULL REFERENCES purchase_orders(id),
  variant_id TEXT NOT NULL REFERENCES product_variants(id),
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_cost_cents INTEGER NOT NULL CHECK (unit_cost_cents >= 0),
  received_quantity INTEGER NOT NULL DEFAULT 0 CHECK (received_quantity >= 0 AND received_quantity <= quantity),
  damaged_quantity INTEGER NOT NULL DEFAULT 0 CHECK (damaged_quantity >= 0),
  UNIQUE(purchase_order_id, variant_id)
);

CREATE TABLE purchase_payments (
  id TEXT PRIMARY KEY,
  purchase_order_id TEXT NOT NULL REFERENCES purchase_orders(id),
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  payment_date TEXT NOT NULL,
  method TEXT NOT NULL,
  notes TEXT,
  created_by TEXT NOT NULL REFERENCES profiles(id),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE goods_receipts (
  id TEXT PRIMARY KEY,
  purchase_order_id TEXT NOT NULL REFERENCES purchase_orders(id),
  idempotency_key TEXT NOT NULL UNIQUE,
  receipt_date TEXT NOT NULL,
  notes TEXT,
  created_by TEXT NOT NULL REFERENCES profiles(id),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE goods_receipt_items (
  id TEXT PRIMARY KEY,
  goods_receipt_id TEXT NOT NULL REFERENCES goods_receipts(id),
  purchase_order_item_id TEXT NOT NULL REFERENCES purchase_order_items(id),
  variant_id TEXT NOT NULL REFERENCES product_variants(id),
  received_quantity INTEGER NOT NULL CHECK (received_quantity > 0),
  damaged_quantity INTEGER NOT NULL DEFAULT 0 CHECK (damaged_quantity >= 0 AND damaged_quantity <= received_quantity)
);
CREATE INDEX idx_receipt_purchase ON goods_receipts(purchase_order_id, created_at DESC);
