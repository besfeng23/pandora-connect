// Aggregate-only planning; not an identity model or campaign execution engine.
const count=v=>Number.isSafeInteger(Number(v))&&Number(v)>=0?Number(v):0;
export function planInsights(t){
 const opted=count(t.analyticsOptIns),frequent=count(t.frequentVisitors),inactive=count(t.inactiveVisitors),purchasers=count(t.purchasingCustomers);
 if(opted<20)return [{title:'Build a usable baseline',detail:'Collect more permissioned first-party activity before interpreting customer segments.'}];
 const rows=[];
 if(frequent>=10)rows.push({title:'Reward repeat visits',detail:'Consider a loyalty experiment for frequent visitors, subject to separate channel permission. Measure repeat visits against a holdout.'});
 if(inactive>=10)rows.push({title:'Test a win-back offer',detail:'Review the inactive cohort and separately authorized communication channels. Measure incremental returning visits.'});
 if(purchasers>=10)rows.push({title:'Review repeat purchases',detail:'Connect trusted POS or booking events and compare repeat purchases with visit activity. Do not infer revenue without amounts.'});
 if(!rows.length)rows.push({title:'Improve measurement',detail:'Continue gathering consent-qualified events before choosing a retention campaign.'});
 return rows;
}
// Only coarse aggregate counts from the authorized server-fetched overview.
// No identifiers, free text, tenant names, timestamps, contacts, network data or user-provided prompts.
export function coarseMetrics(t){
 if(count(t.analyticsOptIns)<50)return null;
 const round=v=>{const n=count(v);return n<10?null:Math.floor(n/10)*10;};
 return Object.fromEntries(['analyticsOptIns','frequentVisitors','inactiveVisitors','purchasingCustomers','visits30d','purchases30d'].map(k=>[k,round(t[k])]));
}
export function geminiConfigured(env){return env.CONNECT_GEMINI_ENABLED==='true'&&Boolean(env.GEMINI_API_KEY)&&/^gemini-[a-z0-9.-]{1,80}$/.test(env.GEMINI_MODEL||'');}
export async function generateAggregatePlan({tenant,env,request=fetch}){
 const metrics=coarseMetrics(tenant);
 if(!geminiConfigured(env)||!metrics)return null;
 const prompt='Provide up to three concise, cautious retention experiment ideas from these approximate aggregate counts. Null means suppressed small counts. Do not infer identities, sensitive attributes, individual behavior, revenue or predicted performance. Do not suggest uploading contact data or launching ads automatically. Include a measurement method and uncertainty. Plain text only. Metrics: '+JSON.stringify(metrics);
 const r=await request('https://generativelanguage.googleapis.com/v1beta/models/'+env.GEMINI_MODEL+':generateContent',{method:'POST',headers:{'Content-Type':'application/json','x-goog-api-key':env.GEMINI_API_KEY},body:JSON.stringify({contents:[{parts:[{text:prompt}]}],generationConfig:{maxOutputTokens:500,temperature:0.2}}),signal:AbortSignal.timeout(12000)});
 if(!r.ok)throw Error('AI provider unavailable');
 const j=await r.json(),value=j.candidates?.[0]?.content?.parts?.filter(x=>!x.thought&&typeof x.text==='string').map(x=>x.text).join('\n').trim();
 if(!value)throw Error('No AI response');return value.slice(0,3000);
}
