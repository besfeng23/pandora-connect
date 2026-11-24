import test from 'node:test';import assert from 'node:assert/strict';import {parseStations,delta,measure} from './station-window.mjs';
const before='Station 02:00:00:00:00:01 (on wlan0)\n\trx bytes: 100\n\ttx bytes: 50\n';
test('delta only counts measured increases for same station and interface',()=>{const old=parseStations(before,'wlan0');const next=parseStations(before.replace('100','140').replace('50','75'),'wlan0');assert.equal(delta(old,next),65n);assert.equal(delta(old,parseStations(before,'wlan1')),0n);});
test('counter reset never becomes negative or inflated',()=>{assert.equal(delta(parseStations(before,'wlan0'),parseStations(before.replace('100','2').replace('50','1'),'wlan0')),0n);});
test('new station has no fabricated historical delta',()=>{assert.equal(delta(new Map(),parseStations(before,'wlan0')),0n);});
test('measurement returns aggregate only',async()=>{let t=300000,n=0;const r=await measure({ifaces:['wlan0'],now:()=>t,wait:async ms=>{t+=ms},read:async()=>parseStations(before.replace('100',String(100+n++*10)),'wlan0')});assert.equal(r.connections,1);assert.equal(r.bytes,100);assert.equal(r.samples,11);assert.equal(JSON.stringify(r).includes('02:00'),false);});
