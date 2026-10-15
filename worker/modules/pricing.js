const text=(value,max=120)=>typeof value==="string"?value.trim().slice(0,max):"";
const moneyToCents=value=>{const raw=String(value??0).trim().replace(",",".");if(!/^-?\d+(\.\d{0,2})?$/.test(raw))throw new PricingError("money","Informe valores monetários com até duas casas decimais.");const [whole,decimal=""]=raw.split(".");return Number(BigInt(whole)*100n+BigInt((decimal+"00").slice(0,2))*(whole.startsWith("-")?-1n:1n))};
const percentToBps=value=>{const raw=String(value??0).trim().replace(",",".");if(!/^\d+(\.\d{0,2})?$/.test(raw))throw new PricingError("percent","Informe percentuais com até duas casas decimais.");const [whole,decimal=""]=raw.split(".");return Number(BigInt(whole)*100n+BigInt((decimal+"00").slice(0,2)))};
const ceilDiv=(a,b)=>Number((BigInt(a)+BigInt(b)-1n)/BigInt(b));
const roundDiv=(a,b)=>Number((BigInt(a)+BigInt(Math.trunc(b/2)))/BigInt(b));
export class PricingError extends Error{constructor(code,message,status=422){super(message);this.code=code;this.status=status}}

export function calculatePricing(input={}){
 const mode=text(input.mode,20)||"profit",fixed=["purchaseCost","acquisitionFreight","packaging","storeFreight","otherCosts"].reduce((sum,key)=>{const value=moneyToCents(input[key]||0);if(value<0)throw new PricingError("cost","Custos não podem ser negativos.");return sum+value},0),rateBps=["paymentRate","commissionRate","taxRate"].reduce((sum,key)=>sum+percentToBps(input[key]||0),0);
 if(rateBps>=10000)throw new PricingError("unfeasible","As taxas proporcionais precisam ser menores que 100%.");
 const breakEvenCents=ceilDiv(fixed*10000,10000-rateBps);let priceCents;
 if(mode==="profit"){const profit=moneyToCents(input.desiredProfit||0);if(profit<0)throw new PricingError("profit","O lucro desejado não pode ser negativo.");priceCents=ceilDiv((fixed+profit)*10000,10000-rateBps)}
 else if(mode==="margin"){const margin=percentToBps(input.desiredMargin||0),denominator=10000-rateBps-margin;if(denominator<=0)throw new PricingError("unfeasible","Taxas e margem somadas precisam ser menores que 100%.");priceCents=ceilDiv(fixed*10000,denominator)}
 else if(mode==="simulation"){priceCents=moneyToCents(input.manualPrice||0);if(priceCents<=0)throw new PricingError("price","Informe um preço de venda válido.")}
 else throw new PricingError("mode","Modo de cálculo inválido.");
 const feesCents=roundDiv(priceCents*rateBps,10000),contributionCents=priceCents-fixed-feesCents,marginBps=priceCents?Math.round(contributionCents*10000/priceCents):0,currentCents=moneyToCents(input.currentPrice||0),base=Math.floor(priceCents/100),nextEnding=ending=>{const same=base*100+ending;return same>=priceCents?same:(base+1)*100+ending};
 return{mode,fixedCostsCents:fixed,rateBps,priceCents,breakEvenCents,feesCents,contributionCents,marginBps,currentPriceCents:currentCents,differenceCents:priceCents-currentCents,commercial90Cents:nextEnding(90),commercial99Cents:nextEnding(99)};
}

export function createPricingModule(db){return{
 async apply(variantId,input,actor){const variant=await db.prepare("SELECT id,sale_price_cents FROM product_variants WHERE id=? AND active=1").bind(variantId).first();if(!variant)throw new PricingError("not_found","SKU não encontrado.",404);const result=calculatePricing(input),selected=moneyToCents(input.selectedPrice);if(selected<result.breakEvenCents)throw new PricingError("below_break_even","O preço escolhido está abaixo do ponto de equilíbrio.");if(selected>999999999)throw new PricingError("price","Preço fora do limite permitido.");await db.batch([db.prepare("UPDATE product_variants SET sale_price_cents=?,updated_at=CURRENT_TIMESTAMP WHERE id=?").bind(selected,variantId),db.prepare("INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,metadata_json) VALUES(?,'pricing.price_applied','product_variant',?,?)").bind(actor,variantId,JSON.stringify({previousPriceCents:variant.sale_price_cents,newPriceCents:selected,calculation:result}))]);return{ok:true,priceCents:selected}}
}}
