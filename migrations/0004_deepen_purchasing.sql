CREATE VIEW purchase_order_summary AS
WITH item_totals AS (
  SELECT purchase_order_id, COUNT(*) item_count,
         COALESCE(SUM(quantity),0) ordered_quantity,
         COALESCE(SUM(received_quantity),0) received_quantity
  FROM purchase_order_items GROUP BY purchase_order_id
), payment_totals AS (
  SELECT purchase_order_id, COALESCE(SUM(amount_cents),0) paid_cents
  FROM purchase_payments GROUP BY purchase_order_id
)
SELECT po.*, s.name supplier_name,
       COALESCE(i.item_count,0) item_count,
       COALESCE(i.ordered_quantity,0) ordered_quantity,
       COALESCE(i.received_quantity,0) received_quantity,
       COALESCE(p.paid_cents,0) paid_cents
FROM purchase_orders po
JOIN suppliers s ON s.id=po.supplier_id
LEFT JOIN item_totals i ON i.purchase_order_id=po.id
LEFT JOIN payment_totals p ON p.purchase_order_id=po.id;

CREATE TRIGGER purchase_payment_guard
BEFORE INSERT ON purchase_payments
BEGIN
  SELECT CASE WHEN
    COALESCE((SELECT SUM(amount_cents) FROM purchase_payments WHERE purchase_order_id=NEW.purchase_order_id),0) + NEW.amount_cents
    > (SELECT total_cents FROM purchase_orders WHERE id=NEW.purchase_order_id)
  THEN RAISE(ABORT,'payment_exceeds_order_total') END;
END;

CREATE TRIGGER purchase_payment_status
AFTER INSERT ON purchase_payments
BEGIN
  UPDATE purchase_orders SET payment_status=CASE
    WHEN (SELECT COALESCE(SUM(amount_cents),0) FROM purchase_payments WHERE purchase_order_id=NEW.purchase_order_id) >= total_cents THEN 'paid'
    ELSE 'partial' END,
    updated_at=CURRENT_TIMESTAMP
  WHERE id=NEW.purchase_order_id;
END;

CREATE TRIGGER receipt_quantity_guard
BEFORE INSERT ON goods_receipt_items
BEGIN
  SELECT CASE WHEN NEW.received_quantity > (
    SELECT quantity-received_quantity FROM purchase_order_items WHERE id=NEW.purchase_order_item_id
  ) THEN RAISE(ABORT,'receipt_exceeds_pending') END;
END;

CREATE TRIGGER receipt_apply_inventory
AFTER INSERT ON goods_receipt_items
BEGIN
  UPDATE purchase_order_items
  SET received_quantity=received_quantity+NEW.received_quantity,
      damaged_quantity=damaged_quantity+NEW.damaged_quantity
  WHERE id=NEW.purchase_order_item_id;

  UPDATE inventory_balances
  SET physical=physical+(NEW.received_quantity-NEW.damaged_quantity),
      updated_at=CURRENT_TIMESTAMP
  WHERE variant_id=NEW.variant_id;

  INSERT INTO inventory_movements(
    id,variant_id,movement_type,quantity,physical_after,reserved_after,
    reason,reference_type,reference_id,created_by
  )
  SELECT lower(hex(randomblob(16))),NEW.variant_id,'receipt',
         NEW.received_quantity-NEW.damaged_quantity,b.physical,b.reserved,
         'Recebimento de compra','goods_receipt',NEW.goods_receipt_id,r.created_by
  FROM inventory_balances b JOIN goods_receipts r ON r.id=NEW.goods_receipt_id
  WHERE b.variant_id=NEW.variant_id AND NEW.received_quantity>NEW.damaged_quantity;

  UPDATE purchase_orders SET receipt_status=CASE
    WHEN NOT EXISTS (
      SELECT 1 FROM purchase_order_items
      WHERE purchase_order_id=(SELECT purchase_order_id FROM goods_receipts WHERE id=NEW.goods_receipt_id)
        AND received_quantity<quantity
    ) THEN 'received' ELSE 'partial' END,
    updated_at=CURRENT_TIMESTAMP
  WHERE id=(SELECT purchase_order_id FROM goods_receipts WHERE id=NEW.goods_receipt_id);
END;
