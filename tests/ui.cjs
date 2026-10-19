// Browser logic contract checks with a minimal DOM; visual acceptance remains in-game.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
class Node {constructor(tag){this.tag=tag;this.children=[];this.value='';}append(n){this.children.push(n);}replaceChildren(){this.children=[];}}
const nodes=new Map();const document={getElementById(id){if(!nodes.has(id))nodes.set(id,new Node(id));return nodes.get(id);},createElement:tag=>new Node(tag),addEventListener(){},querySelector(){return null;}};
let response={ok:true,value:{}},requests=[],reject=false,resolveFetch;
const context={document,window:{addEventListener(){}},GetParentResourceName:()=> 'bcc-law',crypto:{randomUUID:()=> 'test-id'},fetch:async(url,opts)=>{requests.push(JSON.parse(opts.body));if(resolveFetch)return new Promise(resolve=>{resolveFetch.value=()=>resolve({json:async()=>response});});if(reject)throw Error('network');return {json:async()=>response};},console};
vm.createContext(context);vm.runInContext(fs.readFileSync('ui/app.js','utf8')+'\nglobalThis.test={state,api,retry,el,run,restraintAction};',context);
(async()=>{const t=context.test;t.state.department='new_hanover';t.state.epoch=4;
 const hostile='<img src=x onerror=alert(1)>';assert.equal(t.el('p',hostile).textContent,hostile);
 reject=true;await assert.rejects(t.api('cases.open',{title:'Case',summary:'Text'},true));assert.equal(t.state.pending.payload.requestId,'test-id');const first=JSON.stringify(requests[0].payload);
 await assert.rejects(t.api('cases.open',{title:'Duplicate',summary:'Text'},true));assert.equal(requests.length,1);
 reject=false;response={ok:false,code:'rate_limited'};await assert.rejects(t.retry());assert.notEqual(t.state.pending,null);response={ok:true,value:{}};await t.retry();assert.equal(JSON.stringify(requests[2].payload),first);assert.equal(t.state.pending,null);
 response={ok:false,code:'invalid_input'};await assert.rejects(t.api('cases.open',{title:'Case',summary:'Text'},true));assert.equal(t.state.pending,null);
 resolveFetch={};const waiting=t.api('cases.list');await Promise.resolve();t.state.generation++;resolveFetch.value();await assert.rejects(waiting,/Sesiunea/);
 resolveFetch=null;t.state.pending=null;t.state.mode='debtor';response={ok:false,code:'settlement_pending'};
 await assert.rejects(t.api('debts.settle',{obligationId:'0aeb8b93-76d2-4ab9-b459-20522c39d59c'},true));
 assert.equal(t.state.pending.operation,'debts.settle');assert.equal('department' in requests.at(-1).payload,false);assert.equal('actorCharacterId' in requests.at(-1).payload,false);
 const payment=JSON.stringify(t.state.pending.payload);response={ok:false,code:'rate_limited'};await assert.rejects(t.retry());assert.equal(JSON.stringify(t.state.pending.payload),payment);
 t.state.pending=null;t.state.mode='officer';response={ok:false,code:'transaction_failed'};
 await assert.rejects(t.api('custody.confirm',{caseId:'b40c6ec5-e747-46bb-9ff5-67c172222711',recordId:'1b09b649-b814-4d45-bd8e-b6b12ff801ad',expectedRevision:1},true));
 const custodyRequest=t.state.pending.payload.requestId;response={ok:true,value:{}};await t.retry();
 assert.equal(requests.at(-1).operation,'operations.get');assert.equal(requests.at(-1).payload.requestId,custodyRequest);assert.equal(t.state.pending,null);
 t.state.pending=null;response={ok:true,value:{restrained:true}};await t.restraintAction('apply',{targetSource:7,warrantId:'b40c6ec5-e747-46bb-9ff5-67c172222711'});assert.equal(requests.at(-1).operation,'restraints.apply');assert.equal('requestId' in requests.at(-1).payload,false);assert.equal(t.state.pending,null);
 t.state.pending={operation:'cases.open'};const before=requests.length;await assert.rejects(t.restraintAction('release',{targetSource:7}));assert.equal(requests.length,before);t.state.pending=null;
 t.state.pending=null;response={ok:false,code:'evidence_link_pending'};await assert.rejects(t.api('evidence.collect',{caseId:'b40c6ec5-e747-46bb-9ff5-67c172222711',itemId:20,itemRevision:3},true));const collection=JSON.stringify(t.state.pending.payload);assert.equal(t.state.pending.operation,'evidence.collect');response={ok:false,code:'internal'};await assert.rejects(t.retry());assert.equal(JSON.stringify(t.state.pending.payload),collection);response={ok:true,value:{transfer:{itemId:20},link:{recordId:'linked'}}};await t.retry();assert.equal(t.state.pending,null);
 let release;const oldRun=t.run(()=>new Promise(resolve=>{release=resolve;}));t.state.generation++;t.state.busy=true;release();await oldRun;assert.equal(t.state.busy,true);
 console.log('PASS MDT browser logic: safe text, stable mutation retry, duplicate blocking, definitive rejection, stale response fencing');
})().catch(error=>{console.error(error);process.exitCode=1;});
