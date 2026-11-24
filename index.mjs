// Standalone domain layer. A trusted server must bind tenant and actor to auth.
const channels = new Set(['email','sms','ads','portal']);
const kinds = new Set(['visit','purchase','offer_redeemed']);
const DAY = 86400000;
function str(v, label) { if(typeof v !== 'string' || !v.trim() || v.length>200) throw new Error('Invalid '+label); return v; }
function date(v) { const n=Date.parse(v); if (!Number.isFinite(n)) throw new Error('Invalid timestamp'); return n; }
function validChannel(v){if(!channels.has(v)) throw new Error('Unknown channel'); return v;}
// In-memory reference adapter; NOT a production datastore or authentication system.
export class Connect {
 #tenants=new Map();
 #clock;
 constructor({clock=()=>new Date().toISOString()}={}){this.#clock=clock;}
 #tenant(id){str(id,'tenant'); if(!this.#tenants.has(id)) this.#tenants.set(id,{customers:new Map(),events:new Map(),consents:[],network:new Map()}); return this.#tenants.get(id);}
 #customer(tenant,id){const t=this.#tenant(tenant); const c=t.customers.get(str(id,'customer')); if(!c)throw new Error('Unknown customer'); return c;}
 #now(){const v=this.#clock(); date(v); return v;}
 register(tenant,{id,emailVerified=false,phoneVerified=false,adultConfirmed=false}){const t=this.#tenant(tenant); str(id,'customer'); if(t.customers.has(id))throw new Error('Customer already exists'); const c={id,adultConfirmed:adultConfirmed===true,emailVerified:emailVerified===true,phoneVerified:phoneVerified===true,analytics:false,channels:{email:false,sms:false,ads:false,portal:false}}; t.customers.set(id,c); return structuredClone(c);}
 // Flags and evidence must be populated from verified enrollment, never client assertions.
 consent(tenant,id,{purpose,granted,noticeVersion,evidenceId}){const t=this.#tenant(tenant);const c=this.#customer(tenant,id); str(noticeVersion,'notice version');str(evidenceId,'evidence ID');if(typeof granted!=='boolean')throw new Error('Invalid consent');if(purpose!=='analytics')validChannel(purpose);if(granted&&!c.adultConfirmed)throw new Error('Adult eligibility required for profiling or marketing');if(purpose==='analytics'){c.analytics=granted;if(!granted){for(const [key,e] of t.events)if(e.customerId===id)t.events.delete(key);}}else{c.channels[purpose]=granted;}const record={customerId:id,purpose,granted,noticeVersion,evidenceId,at:this.#now()};t.consents.push(record);return structuredClone(record);}
 // Network data is anonymous aggregate input; no MAC, IP, hostnames, or user linkage.
 networkAggregate(tenant,{site,windowStart,connections,bytes}){const t=this.#tenant(tenant);str(site,'site');const start=date(windowStart);for(const v of [connections,bytes])if(!Number.isSafeInteger(v)||v<0)throw new Error('Invalid count');if(start>date(this.#now()))throw new Error('Future window');const row={site,windowStart:new Date(start).toISOString(),connections,bytes};t.network.set(JSON.stringify([site,row.windowStart]),row);return structuredClone(row);}
 // Only allowlisted first-party events for opted-in customers. No arbitrary metadata.
 event(tenant,{id,customerId,kind,site,at}){const t=this.#tenant(tenant);const c=this.#customer(tenant,customerId);if(!c.analytics||!c.adultConfirmed)return {accepted:false,reason:'consent_required'};str(id,'event');str(site,'site');if(!kinds.has(kind))throw new Error('Invalid event kind');const ms=date(at), now=date(this.#now());if(ms>now||ms<now-90*DAY)throw new Error('Event outside retention window');const row={id,customerId,kind,site,at:new Date(ms).toISOString()};if(t.events.has(id)){const old=t.events.get(id);if(JSON.stringify(old)!==JSON.stringify(row))throw new Error('Event ID conflict');return {accepted:true,duplicate:true};}t.events.set(id,row);return {accepted:true,duplicate:false};}
 prune(tenant){const t=this.#tenant(tenant);const cutoff=date(this.#now())-90*DAY;let removed=0;for(const [id,e] of t.events)if(date(e.at)<cutoff){t.events.delete(id);removed++;}for(const [id,e] of t.network)if(date(e.windowStart)<cutoff){t.network.delete(id);removed++;}return removed;}
 segments(tenant,id){this.prune(tenant);const t=this.#tenant(tenant);const c=this.#customer(tenant,id);if(!c.analytics||!c.adultConfirmed)return [];const events=[...t.events.values()].filter(e=>e.customerId===id);const visits=events.filter(e=>e.kind==='visit');const recent=visits.filter(e=>date(e.at)>=date(this.#now())-30*DAY);const result=[];if(recent.length>=3)result.push('frequent_visitor');if(visits.length&&recent.length===0)result.push('returning_offer_candidate');if(events.some(e=>e.kind==='purchase'))result.push('existing_customer');return result;}
 // Returns customer IDs for review, never contact data or provider uploads.
 audience(tenant,{channel,segment}){validChannel(channel);if(!['frequent_visitor','returning_offer_candidate','existing_customer'].includes(segment))throw new Error('Unknown segment');const t=this.#tenant(tenant);return [...t.customers.values()].filter(c=>c.adultConfirmed&&c.analytics&&c.channels[channel]&&(channel!=='email'||c.emailVerified)&&(channel!=='sms'||c.phoneVerified)&&(channel!=='ads'||c.emailVerified||c.phoneVerified)&&this.segments(tenant,c.id).includes(segment)).map(c=>c.id);}
 erase(tenant,id){const t=this.#tenant(tenant);this.#customer(tenant,id);t.customers.delete(id);for(const [key,e] of t.events)if(e.customerId===id)t.events.delete(key);t.consents=t.consents.filter(e=>e.customerId!==id);}
 summary(tenant){this.prune(tenant);const t=this.#tenant(tenant);return {registeredCustomers:t.customers.size,analyticsOptIns:[...t.customers.values()].filter(c=>c.analytics).length,events:t.events.size,networkWindows:t.network.size};}
}
