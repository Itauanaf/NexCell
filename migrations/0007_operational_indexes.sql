CREATE INDEX idx_sales_orders_date_status ON sales_orders(order_date,order_status);
CREATE INDEX idx_sales_orders_shipping ON sales_orders(shipping_status,order_date);
CREATE INDEX idx_purchase_orders_expected_receipt ON purchase_orders(receipt_status,expected_date);
CREATE INDEX idx_financial_transactions_date_direction ON financial_transactions(transaction_date,direction);
CREATE INDEX idx_accounts_payable_status_due ON accounts_payable(status,due_date);
CREATE INDEX idx_accounts_receivable_status_due ON accounts_receivable(status,due_date);
CREATE INDEX idx_audit_entity_date ON audit_logs(entity_type,entity_id,created_at DESC);
