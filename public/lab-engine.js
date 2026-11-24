// Synthetic product walkthrough. In-memory only; no storage, network, identifiers or delivery.
export const scenarios=Object.freeze({cafe:{name:'Café',offer:'A complimentary upgrade on your next visit',visits:3},resort:{name:'Resort',offer:'A returning-guest reservation benefit',visits:3},retail:{name:'Retail',offer:'A reward on your next purchase',visits:3}});
export function initial(scenario='cafe'){if(!Object.hasOwn(scenarios,scenario))throw Error('Unknown scenario');return {scenario,connected:false,enrolled:false,analytics:false,portal:false,visits:0,purchases:0,draft:false,previewed:false};}
export function transition(s,action){
 const n={...s};switch(action){
 case 'connect':n.connected=true;break;
 case 'enroll':if(!s.connected)throw Error('Connect first');n.enrolled=true;break;
 case 'analytics':if(!s.enrolled)throw Error('Enroll first');n.analytics=!s.analytics;if(!n.analytics){n.visits=0;n.purchases=0;n.previewed=false;}break;
 case 'portal':if(!s.enrolled)throw Error('Enroll first');n.portal=!s.portal;if(!n.portal)n.previewed=false;break;
 case 'visit':if(!s.analytics)throw Error('Analytics permission required');n.visits++;n.previewed=false;break;
 case 'purchase':if(!s.analytics)throw Error('Analytics permission required');n.purchases++;break;
 case 'draft':n.draft=true;break;
 case 'preview':if(!eligible(s)||!s.draft)throw Error('Eligible cohort and draft required');n.previewed=true;break;
 case 'erase':return {...initial(s.scenario),connected:s.connected,draft:s.draft};
 default:throw Error('Unknown action');}return n;
}
export function eligible(s){return s.enrolled&&s.analytics&&s.portal&&s.visits>=3;}
export function stage(s){return s.previewed?5:s.draft?4:s.visits>=3?3:s.enrolled?2:s.connected?1:0;}
