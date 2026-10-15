export function createInventoryModule(db){
  return {
    async balances(){
      const result=await db.prepare(`SELECT ib.variant_id,ib.physical,ib.reserved,
        (ib.physical-ib.reserved) available,p.name product_name,pv.sku,pv.color,
        pv.compatible_model,pv.minimum_stock,pv.cost_cents
        FROM inventory_balances ib
        JOIN product_variants pv ON pv.id=ib.variant_id
        JOIN products p ON p.id=pv.product_id
        WHERE p.active=1 AND pv.active=1 ORDER BY p.name,pv.sku`).all();
      return result.results||[];
    },
    async recentMovements(limit=100){
      const safeLimit=Math.max(1,Math.min(250,Number(limit)||100));
      const result=await db.prepare(`SELECT im.*,p.name product_name,pv.sku,pr.full_name actor_name
        FROM inventory_movements im
        JOIN product_variants pv ON pv.id=im.variant_id
        JOIN products p ON p.id=pv.product_id
        JOIN profiles pr ON pr.id=im.created_by
        ORDER BY im.created_at DESC LIMIT ?`).bind(safeLimit).all();
      return result.results||[];
    }
  }
}
