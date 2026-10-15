CREATE TABLE financial_accounts (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, account_type TEXT NOT NULL CHECK(account_type IN ('cash','bank','wallet')),
  opening_balance_cents INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1)),
  created_by TEXT NOT NULL REFERENCES profiles(id), created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE financial_categories (
  id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL CHECK(kind IN ('revenue','expense','merchandise','transfer')),
  affects_result INTEGER NOT NULL CHECK(affects_result IN (0,1))
);
INSERT INTO financial_categories(id,name,kind,affects_result) VALUES
 ('sales','Vendas','revenue',1),('merchandise','Mercadorias','merchandise',0),
 ('freight','Frete','expense',1),('packaging','Embalagem','expense',1),('marketing','Marketing','expense',1),
 ('payment-fees','Taxas de pagamento','expense',1),('taxes','Impostos','expense',1),
 ('tools','Ferramentas','expense',1),('operations','Operacional','expense',1),('other','Outros','expense',1),
 ('transfer','Transferência','transfer',0);

CREATE TABLE financial_transactions (
  id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES financial_accounts(id),
  direction TEXT NOT NULL CHECK(direction IN ('inflow','outflow')), amount_cents INTEGER NOT NULL CHECK(amount_cents>0),
  transaction_date TEXT NOT NULL, category_id TEXT NOT NULL REFERENCES financial_categories(id), description TEXT NOT NULL,
  source_type TEXT, source_id TEXT, transfer_group_id TEXT,
  reconciled_at TEXT, reconciled_by TEXT REFERENCES profiles(id),
  created_by TEXT NOT NULL REFERENCES profiles(id), created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(source_type,source_id)
);
CREATE INDEX idx_financial_transactions_account_date ON financial_transactions(account_id,transaction_date DESC);

CREATE TABLE accounts_payable (
  id TEXT PRIMARY KEY, purchase_order_id TEXT UNIQUE REFERENCES purchase_orders(id), supplier_id TEXT REFERENCES suppliers(id),
  description TEXT NOT NULL, original_cents INTEGER NOT NULL CHECK(original_cents>0), paid_cents INTEGER NOT NULL DEFAULT 0 CHECK(paid_cents>=0 AND paid_cents<=original_cents),
  due_date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','partial','paid','cancelled')),
  created_by TEXT NOT NULL REFERENCES profiles(id), created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE accounts_receivable (
  id TEXT PRIMARY KEY, sales_order_id TEXT UNIQUE REFERENCES sales_orders(id), customer_id TEXT REFERENCES customers(id), customer_name TEXT,
  description TEXT NOT NULL, original_cents INTEGER NOT NULL CHECK(original_cents>0), received_cents INTEGER NOT NULL DEFAULT 0 CHECK(received_cents>=0 AND received_cents<=original_cents),
  due_date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','partial','received','cancelled')),
  created_by TEXT NOT NULL REFERENCES profiles(id), created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE purchase_payments ADD COLUMN account_id TEXT REFERENCES financial_accounts(id);
ALTER TABLE sales_payments ADD COLUMN account_id TEXT REFERENCES financial_accounts(id);

INSERT INTO accounts_payable(id,purchase_order_id,supplier_id,description,original_cents,paid_cents,due_date,status,created_by)
SELECT lower(hex(randomblob(16))),po.id,po.supplier_id,'Compra '||po.number,po.total_cents,
 COALESCE((SELECT SUM(amount_cents) FROM purchase_payments pp WHERE pp.purchase_order_id=po.id),0),COALESCE(po.expected_date,po.order_date),
 CASE po.payment_status WHEN 'paid' THEN 'paid' WHEN 'partial' THEN 'partial' ELSE 'pending' END,po.created_by
FROM purchase_orders po WHERE po.total_cents>0;
INSERT INTO accounts_receivable(id,sales_order_id,customer_id,customer_name,description,original_cents,received_cents,due_date,status,created_by)
SELECT lower(hex(randomblob(16))),so.id,so.customer_id,so.customer_name,'Venda '||so.number,so.total_cents,
 COALESCE((SELECT SUM(amount_cents) FROM sales_payments sp WHERE sp.sales_order_id=so.id),0),so.order_date,
 CASE so.payment_status WHEN 'paid' THEN 'received' WHEN 'partial' THEN 'partial' ELSE 'pending' END,so.created_by
FROM sales_orders so WHERE so.total_cents>0;

CREATE TRIGGER purchase_payable_create AFTER INSERT ON purchase_orders WHEN NEW.total_cents>0 BEGIN
 INSERT INTO accounts_payable(id,purchase_order_id,supplier_id,description,original_cents,due_date,created_by)
 VALUES(lower(hex(randomblob(16))),NEW.id,NEW.supplier_id,'Compra '||NEW.number,NEW.total_cents,COALESCE(NEW.expected_date,NEW.order_date),NEW.created_by);
END;
CREATE TRIGGER sale_receivable_create AFTER INSERT ON sales_orders WHEN NEW.total_cents>0 BEGIN
 INSERT INTO accounts_receivable(id,sales_order_id,customer_id,customer_name,description,original_cents,due_date,created_by)
 VALUES(lower(hex(randomblob(16))),NEW.id,NEW.customer_id,NEW.customer_name,'Venda '||NEW.number,NEW.total_cents,NEW.order_date,NEW.created_by);
END;
CREATE TRIGGER purchase_payment_finance_guard BEFORE INSERT ON purchase_payments WHEN NEW.account_id IS NULL BEGIN
 SELECT RAISE(ABORT,'financial_account_required');
END;
CREATE TRIGGER sale_payment_finance_guard BEFORE INSERT ON sales_payments WHEN NEW.account_id IS NULL BEGIN
 SELECT RAISE(ABORT,'financial_account_required');
END;
CREATE TRIGGER purchase_payment_finance AFTER INSERT ON purchase_payments BEGIN
 INSERT INTO financial_transactions(id,account_id,direction,amount_cents,transaction_date,category_id,description,source_type,source_id,created_by)
 SELECT lower(hex(randomblob(16))),NEW.account_id,'outflow',NEW.amount_cents,NEW.payment_date,'merchandise','Pagamento '||po.number,'purchase_payment',NEW.id,NEW.created_by FROM purchase_orders po WHERE po.id=NEW.purchase_order_id;
 UPDATE accounts_payable SET paid_cents=paid_cents+NEW.amount_cents,status=CASE WHEN paid_cents+NEW.amount_cents>=original_cents THEN 'paid' ELSE 'partial' END WHERE purchase_order_id=NEW.purchase_order_id;
END;
CREATE TRIGGER sale_payment_finance AFTER INSERT ON sales_payments BEGIN
 INSERT INTO financial_transactions(id,account_id,direction,amount_cents,transaction_date,category_id,description,source_type,source_id,created_by)
 SELECT lower(hex(randomblob(16))),NEW.account_id,'inflow',NEW.amount_cents,NEW.payment_date,'sales','Recebimento '||so.number,'sales_payment',NEW.id,NEW.created_by FROM sales_orders so WHERE so.id=NEW.sales_order_id;
 UPDATE accounts_receivable SET received_cents=received_cents+NEW.amount_cents,status=CASE WHEN received_cents+NEW.amount_cents>=original_cents THEN 'received' ELSE 'partial' END WHERE sales_order_id=NEW.sales_order_id;
END;

CREATE VIEW financial_account_balances AS
SELECT a.*,a.opening_balance_cents+COALESCE(SUM(CASE t.direction WHEN 'inflow' THEN t.amount_cents ELSE -t.amount_cents END),0) balance_cents
FROM financial_accounts a LEFT JOIN financial_transactions t ON t.account_id=a.id GROUP BY a.id;
