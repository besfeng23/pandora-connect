// Raw station identifiers stay in process memory; only aggregate totals leave.
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {setTimeout as sleep} from 'node:timers/promises';
import {pathToFileURL} from 'node:url';
const exec=promisify(execFile);
const WINDOW=300000;
export function parseStations(text,iface){
 const map=new Map();let current=null;
 for(const line of text.split(/\r?\n/)){
  const station=line.match(/^\s*Station\s+([\da-f]{2}(?::[\da-f]{2}){5})\b/i);
  if(station){current={rx:null,tx:null};map.set(iface+':'+station[1].toLowerCase(),current);continue;}
  const v=line.match(/^\s*(rx|tx) bytes:\s*(\d+)\s*$/);
  if(current&&v)current[v[1]]=BigInt(v[2]);
 }
 return map;
}
export function delta(previous,current){
 let bytes=0n;
 for(const [id,now] of current){
  const old=previous.get(id);if(!old)continue;
  for(const key of ['rx','tx'])if(now[key]!==null&&old[key]!==null&&now[key]>=old[key])bytes+=now[key]-old[key];
 }
 return bytes;
}
async function snapshot(ifaces){const all=new Map();for(const iface of ifaces){const {stdout}=await exec('iw',['dev',iface,'station','dump'],{timeout:8000,maxBuffer:2*1024*1024});for(const [id,counters] of parseStations(stdout,iface))all.set(id,counters);}return all;}
export async function measure({ifaces,now=Date.now,read=snapshot,wait=sleep}){
 if(!Array.isArray(ifaces)||!ifaces.length||ifaces.length>16||ifaces.some(i=>typeof i!=='string'||!/^[-a-zA-Z0-9_.]{1,32}$/.test(i)))throw Error('Invalid interface configuration');
 const begin=now(),start=Math.floor(begin/WINDOW)*WINDOW,end=start+WINDOW;if(begin-start>15000)throw Error('Start measurement within 15 seconds of a five-minute boundary');
 let previous=await read(ifaces),bytes=0n,samples=1;
 while(now()<end){await wait(Math.min(30000,end-now()));const current=await read(ifaces);bytes+=delta(previous,current);previous=current;samples++;}
 if(bytes>1000000000000000n||previous.size>1000000)throw Error('Measured aggregate exceeds supported bounds');
 return {windowStart:new Date(start).toISOString(),connections:previous.size,bytes:Number(bytes),samples,measurement:'station_counter_deltas'};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const ifaces=(process.env.CONNECT_WIFI_INTERFACES||'').split(',').filter(Boolean);
 try{console.log(JSON.stringify(await measure({ifaces})));}catch{console.error('Station measurement unavailable; check local interfaces, privileges and window timing');process.exitCode=1;}
}
