// Node 20+ on a trusted gateway bridge. Sends only a site-level aggregate.
const PROJECT='https://xyefkykwuppbweabvvmk.supabase.co';
const {NEXT_PUBLIC_SUPABASE_URL:url,NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:key,CONNECT_GATEWAY_ACCESS_TOKEN:token,CONNECT_TENANT_ID:tenant,CONNECT_SITE_ID:site}=process.env;
const [connectionsArg,bytesArg]=process.argv.slice(2);
const connections=Number(connectionsArg),bytes=Number(bytesArg);
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
if(url!==PROJECT||!key?.startsWith('sb_publishable_')||!token||!uuid.test(tenant||'')||!uuid.test(site||'')||!connectionsArg||!bytesArg||!Number.isSafeInteger(connections)||connections<0||connections>1000000||!Number.isSafeInteger(bytes)||bytes<0||bytes>1000000000000000){console.error('Gateway configuration or counts invalid');process.exit(2);}
const window=new Date(Math.floor(Date.now()/300000)*300000).toISOString();
try{const r=await fetch(url+'/rest/v1/rpc/pandora_connect_ingest_network',{method:'POST',headers:{apikey:key,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({p_tenant:tenant,p_site:site,p_window:window,p_connections:connections,p_bytes:bytes}),signal:AbortSignal.timeout(12000)});if(!r.ok){console.error('Aggregate rejected: HTTP '+r.status);process.exitCode=1;}else console.log('Aggregate accepted for '+window);}catch{console.error('Aggregate transport unavailable');process.exitCode=1;}
