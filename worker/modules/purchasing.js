const text=(value,max=240)=>typeof value==="string"?value.trim().slice(0,max):"";
const toCents=value=>Math.round(Number(value)*100);

export class PurchasingError extends Error{
  constructor(code,message,status=422){super(message);this.code=code;this.status=status}
}

export function createPurchasingModule(db){
  return {
    async summaries(){
      const result=await db.prepare("SELECT * FROM purchase_order_summary ORDER BY created_at DESC").all();
      return result.results||[];
    },
    async recordPayment(orderId,input,actorId){
      const order=await db.prepare("SELECT id FROM purchase_orders WHERE id=? AND order_status<>'cancelled'").bind(orderId).first();
      if(!order)throw new PurchasingError("not_found","Compra não encontrada.",404);
      const amount=toCents(input?.amount);
      if(!Number.isFinite(amount)||amount<=0)throw new PurchasingError("invalid_amount","Informe um pagamento válido.");
      const account=await db.prepare("SELECT id FROM financial_accounts WHERE id=? AND active=1").bind(text(input?.accountId,80)).first();
      if(!account)throw new PurchasingError("account_required","Selecione a conta usada no pagamento.");
      const paymentId=crypto.randomUUID();
      try{
        await db.batch([
          db.prepare("INSERT INTO purchase_payments(id,purchase_order_id,amount_cents,payment_date,method,notes,created_by,account_id) VALUES(?,?,?,?,?,?,?,?)").bind(paymentId,orderId,amount,text(input.date,10)||new Date().toISOString().slice(0,10),text(input.method,40)||"Outro",text(input.notes,500)||null,actorId,account.id),
          db.prepare("INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,metadata_json) VALUES(?,'purchase.payment_recorded','purchase_order',?,?)").bind(actorId,orderId,JSON.stringify({paymentId,amountCents:amount}))
        ]);
      }catch(error){
        if(String(error).includes("payment_exceeds_order_total"))throw new PurchasingError("payment_exceeds_total","Pagamento supera o saldo da compra.");
        throw error;
      }
      return await db.prepare("SELECT payment_status FROM purchase_orders WHERE id=?").bind(orderId).first();
    },
    async confirmReceipt(orderId,input,actorId){
      const key=text(input?.idempotencyKey,100);
      if(!key||!Array.isArray(input.items)||!input.items.length)throw new PurchasingError("invalid_receipt","Recebimento inválido.");
      const prior=await db.prepare("SELECT id FROM goods_receipts WHERE idempotency_key=?").bind(key).first();
      if(prior)throw new PurchasingError("duplicate_receipt","Este recebimento já foi processado.",409);
      const order=await db.prepare("SELECT id FROM purchase_orders WHERE id=? AND order_status<>'cancelled'").bind(orderId).first();
      if(!order)throw new PurchasingError("unavailable_order","Compra indisponível para recebimento.");
      const receiptId=crypto.randomUUID();
      const statements=[db.prepare("INSERT INTO goods_receipts(id,purchase_order_id,idempotency_key,receipt_date,notes,created_by) VALUES(?,?,?,?,?,?)").bind(receiptId,orderId,key,text(input.date,10)||new Date().toISOString().slice(0,10),text(input.notes,800)||null,actorId)];
      for(const raw of input.items){
        const item=await db.prepare("SELECT id,variant_id FROM purchase_order_items WHERE id=? AND purchase_order_id=?").bind(text(raw.itemId,80),orderId).first();
        const received=Math.trunc(Number(raw.received)),damaged=Math.trunc(Number(raw.damaged)||0);
        if(!item||received<=0||damaged<0||damaged>received)throw new PurchasingError("invalid_quantity","Quantidade recebida ou avaria inválida.");
        statements.push(db.prepare("INSERT INTO goods_receipt_items(id,goods_receipt_id,purchase_order_item_id,variant_id,received_quantity,damaged_quantity) VALUES(?,?,?,?,?,?)").bind(crypto.randomUUID(),receiptId,item.id,item.variant_id,received,damaged));
      }
      statements.push(db.prepare("INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,metadata_json) VALUES(?,'receipt.confirmed','goods_receipt',?,?)").bind(actorId,receiptId,JSON.stringify({purchaseOrderId:orderId})));
      try{await db.batch(statements)}catch(error){const message=String(error);if(message.includes("UNIQUE"))throw new PurchasingError("duplicate_receipt","Este recebimento já foi processado.",409);if(message.includes("receipt_exceeds_pending"))throw new PurchasingError("exceeds_pending","Quantidade recebida excede o saldo pendente.");throw error}
      const updated=await db.prepare("SELECT receipt_status FROM purchase_orders WHERE id=?").bind(orderId).first();
      return {id:receiptId,status:updated.receipt_status};
    }
  }
}
