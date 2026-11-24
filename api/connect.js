import {planInsights,coarseMetrics,geminiConfigured,generateAggregatePlan} from '../insights.mjs';
const PROJECT='https://xyefkykwuppbweabvvmk.supabase.co';
export function createHandler({env=process.env,request=fetch}={}){
 return async function handler(req,res){
  res.setHeader('Cache-Control','no-store');
  res.setHeader('X-Content-Type-Options','nosniff');
  const reply=(status,body)=>res.status(status).json(body);
  if(req.method==='GET')return reply(200,{module:'pandora-connect',configured:env.NEXT_PUBLIC_SUPABASE_URL===PROJECT&&Boolean(env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY),collectionEnabled:false});
  if(req.method!=='POST'){res.setHeader('Allow','GET, POST');return reply(405,{error:'Method not allowed'});}
  if(!String(req.headers['content-type']||'').toLowerCase().startsWith('application/json'))return reply(415,{error:'JSON required'});
  const url=env.NEXT_PUBLIC_SUPABASE_URL,key=env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if(url!==PROJECT||!key||!key.startsWith('sb_publishable_'))return reply(503,{error:'Database configuration unavailable'});
  const b=req.body;if(!b||typeof b!=='object'||Array.isArray(b))return reply(400,{error:'Invalid request'});
  const headers={apikey:key,'Content-Type':'application/json'};
  try{
   if(b.action==='login'){
    if(typeof b.email!=='string'||b.email.length>254||typeof b.password!=='string'||!b.password||b.password.length>1024)return reply(400,{error:'Valid credentials required'});
    const r=await request(url+'/auth/v1/token?grant_type=password',{method:'POST',headers,body:JSON.stringify({email:b.email.trim(),password:b.password}),signal:AbortSignal.timeout(12000)});
    if(!r.ok)return reply(r.status===429?429:401,{error:r.status===429?'Try again later':'Unable to sign in'});
    const data=await r.json();if(!data.access_token||data.user?.is_anonymous)return reply(401,{error:'Authorized account required'});
    return reply(200,{accessToken:data.access_token});
   }
   if(b.action==='insights'){
    const bearer=req.headers.authorization;
    if(typeof bearer!=='string'||!/^Bearer [A-Za-z0-9._-]{20,8192}$/.test(bearer))return reply(401,{error:'Sign in required'});
    if(typeof b.tenantId!=='string'||!/^[0-9a-f-]{36}$/i.test(b.tenantId)||!['rules','gemini'].includes(b.mode))return reply(400,{error:'Invalid analysis request'});
    const r=await request(url+'/rest/v1/rpc/pandora_connect_overview',{method:'POST',headers:{...headers,Authorization:bearer},body:'{}',signal:AbortSignal.timeout(12000)});
    if(!r.ok)return reply(r.status===401||r.status===403?401:503,{error:'Workspace unavailable'});
    const rows=await r.json(),tenant=Array.isArray(rows)?rows.find(t=>t.id===b.tenantId):null;
    if(!tenant)return reply(403,{error:'Workspace permission required'});
    const rules=planInsights(tenant),eligible=tenant.role==='owner'&&Boolean(coarseMetrics(tenant))&&geminiConfigured(env);
    if(b.mode==='rules')return reply(200,{rules,geminiAvailable:eligible});
    if(!eligible||b.allowAggregateAnalysis!==true)return reply(403,{error:'Owner approval, provider configuration and sufficient data required'});
    try{const analysis=await generateAggregatePlan({tenant,env,request});return reply(200,{rules,analysis,source:'gemini'});}catch{return reply(503,{error:'AI provider unavailable; local recommendations remain available'});}
   }
   const commissionActions=['status','site_create','guest_invite','guest_disable','gateway_bind','gateway_revoke','writer_bind','writer_revoke'];
   if(b.action==='commission'){
    const bearer=req.headers.authorization;
    if(typeof bearer!=='string'||!/^Bearer [A-Za-z0-9._-]{20,8192}$/.test(bearer))return reply(401,{error:'Sign in required'});
    const uuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
    if(!commissionActions.includes(b.operation)||!uuid(b.tenantId))return reply(400,{error:'Invalid setup action'});
    const data={tenantId:b.tenantId};
    if(b.operation==='site_create'){
      if(!uuid(b.siteId)||typeof b.name!=='string'||b.name.trim().length<1||b.name.trim().length>80)return reply(400,{error:'Valid location required'});
      Object.assign(data,{siteId:b.siteId,name:b.name.trim()});
    }else if(b.operation!=='status'){
      if(!uuid(b.userId))return reply(400,{error:'Verified account ID required'});data.userId=b.userId;
      if(b.operation==='guest_invite'){if(b.adultVerified!==true)return reply(400,{error:'Independent adult verification required'});data.adultVerified=true;}
      if(b.operation.startsWith('gateway_')||b.operation.startsWith('writer_')){
        if(!uuid(b.siteId))return reply(400,{error:'Select a location'});data.siteId=b.siteId;
        if(b.operation.endsWith('_bind')){if(b.dedicatedAccount!==true)return reply(400,{error:'Dedicated account required'});data.dedicatedAccount=true;}
      }
    }
    const r=await request(url+'/rest/v1/rpc/pandora_connect_commission',{method:'POST',headers:{...headers,Authorization:bearer},body:JSON.stringify({p_action:b.operation,p_data:data}),signal:AbortSignal.timeout(12000)});
    if(!r.ok)return reply(r.status===401?401:r.status===403?403:r.status===400||r.status===409?400:503,{error:r.status===401?'Session expired':r.status===403?'Owner permission or verified account required':r.status===400||r.status===409?'Setup request rejected':'Setup unavailable'});
    const result=await r.json();if(!result||typeof result!=='object'||Array.isArray(result))return reply(502,{error:'Unexpected response'});
    return reply(200,result);
   }
   if(b.action==='guest_erase'){
    const bearer=req.headers.authorization;
    if(typeof bearer!=='string'||!/^Bearer [A-Za-z0-9._-]{20,8192}$/.test(bearer))return reply(401,{error:'Sign in required'});
    if(typeof b.tenant!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(b.tenant)||b.confirm!==true)return reply(400,{error:'Explicit confirmation required'});
    const r=await request(url+'/rest/v1/rpc/pandora_connect_erase_guest',{method:'POST',headers:{...headers,Authorization:bearer},body:JSON.stringify({p_tenant:b.tenant,p_confirm:true}),signal:AbortSignal.timeout(12000)});
    if(!r.ok)return reply(r.status===401?401:r.status===403?403:503,{error:'Guest erasure unavailable'});
    const j=await r.json();if(j.erased!==true)return reply(502,{error:'Unexpected response'});return reply(200,{erased:true});
   }
   if(b.action==='audience_preview'){
    const bearer=req.headers.authorization;
    if(typeof bearer!=='string'||!/^Bearer [A-Za-z0-9._-]{20,8192}$/.test(bearer))return reply(401,{error:'Sign in required'});
    const uuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
    if(!uuid(b.tenant)||!uuid(b.id))return reply(400,{error:'Valid draft required'});
    const r=await request(url+'/rest/v1/rpc/pandora_connect_audience_preview',{method:'POST',headers:{...headers,Authorization:bearer},body:JSON.stringify({p_tenant:b.tenant,p_campaign:b.id}),signal:AbortSignal.timeout(12000)});
    if(!r.ok)return reply(r.status===401?401:r.status===403?403:503,{error:'Audience preview unavailable'});
    const j=await r.json();if(!['blocked','preview_only'].includes(j.status))return reply(502,{error:'Unexpected response'});
    return reply(200,{status:j.status,eligibleCount:j.status==='preview_only'?j.eligibleCount:null,reason:j.reason});
   }
   const guestAction=['guest_options','guest_save'].includes(b.action);
   const campaignAction=['campaign_list','campaign_create','campaign_archive'].includes(b.action);
   if(guestAction||campaignAction){
    const bearer=req.headers.authorization;
    if(typeof bearer!=='string'||!/^Bearer [A-Za-z0-9._-]{20,8192}$/.test(bearer))return reply(401,{error:'Sign in required'});
    headers.Authorization=bearer;
    const uuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
    let rpc,params={};
    if(guestAction){
     rpc='pandora_connect_guest_preferences';
     if(b.action==='guest_save'){
      if(!uuid(b.tenant)||typeof b.analytics!=='boolean'||typeof b.portal!=='boolean')return reply(400,{error:'Explicit consent choices required'});
      params={p_tenant:b.tenant,p_analytics:b.analytics,p_portal:b.portal};
     }
    }else{
     rpc='pandora_connect_campaigns';
     if(!uuid(b.tenant))return reply(400,{error:'Business selection required'});
     params={p_tenant:b.tenant,p_action:b.action.slice(9)};
     if(b.action!=='campaign_list'){
      if(!uuid(b.id))return reply(400,{error:'Draft ID required'});
      params.p_id=b.id;
     }
     if(b.action==='campaign_create'){
      if(typeof b.title!=='string'||!b.title.trim()||b.title.trim().length>100||!['welcome','loyalty','winback'].includes(b.objective)||!['email','sms','ads','portal'].includes(b.channel))return reply(400,{error:'Invalid campaign draft'});
      Object.assign(params,{p_title:b.title.trim(),p_objective:b.objective,p_channel:b.channel});
     }
    }
    const r=await request(url+'/rest/v1/rpc/'+rpc,{method:'POST',headers,body:JSON.stringify(params),signal:AbortSignal.timeout(12000)});
    if(!r.ok)return reply(r.status===401?401:r.status===403?403:r.status===400?400:503,{error:r.status===401?'Session expired':r.status===403?'Invitation or workspace permission required':r.status===400?'Request rejected':'Service unavailable'});
    const data=await r.json();if(!Array.isArray(data))return reply(502,{error:'Unexpected response'});
    return reply(200,guestAction?{options:data}:{drafts:data});
   }
   if(b.action==='overview'||b.action==='logout'){
    const bearer=req.headers.authorization;if(typeof bearer!=='string'||!/^Bearer [A-Za-z0-9._-]{20,8192}$/.test(bearer))return reply(401,{error:'Sign in required'});
    headers.Authorization=bearer;
    if(b.action==='logout'){
      await request(url+'/auth/v1/logout?scope=local',{method:'POST',headers,signal:AbortSignal.timeout(12000)});
      return reply(200,{signedOut:true});
    }
    const r=await request(url+'/rest/v1/rpc/pandora_connect_overview',{method:'POST',headers,body:'{}',signal:AbortSignal.timeout(12000)});
    if(!r.ok)return reply(r.status===401||r.status===403?401:503,{error:r.status===401||r.status===403?'Session expired or access denied':'Overview unavailable'});
    const data=await r.json();if(!Array.isArray(data))return reply(502,{error:'Unexpected response'});
    return reply(200,{tenants:data});
   }
   return reply(400,{error:'Unknown action'});
  }catch{return reply(503,{error:'Service temporarily unavailable'});}
 };
}
export default createHandler();
