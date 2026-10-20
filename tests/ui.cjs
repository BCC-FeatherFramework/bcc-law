// MDT browser logic with a minimal DOM; visual acceptance stays in-game.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
// The real locale tables, read from the Lua files.
function locale(path){
 const strings={};
 for(const m of fs.readFileSync(path,'utf8').matchAll(/\['([^']+)'\]\s*=\s*'((?:[^'\\]|\\.)*)'/g))strings[m[1]]=m[2].replace(/\\'/g,"'");
 return strings;
}
const en=locale('locales/en.lua'),ro=locale('locales/ro.lua');
class Node{constructor(tag){this.tag=tag;this.children=[];this.value='';this.textContent='';}append(n){this.children.push(n);}replaceChildren(){this.children=[];}}
const nodes=new Map();
const document={getElementById(id){if(!nodes.has(id))nodes.set(id,new Node(id));return nodes.get(id);},createElement:tag=>new Node(tag),
 addEventListener(){},querySelector(){return null;},querySelectorAll(){return [];},documentElement:{lang:''}};
let response={ok:true,value:{items:[]}},requests=[],reject=false,resolveFetch;
const listeners={};
const context={document,window:{addEventListener(name,fn){listeners[name]=fn;}},GetParentResourceName:()=> 'bcc-law',crypto:{randomUUID:()=> 'test-id'},
 fetch:async(url,opts)=>{requests.push(JSON.parse(opts.body));if(resolveFetch)return new Promise(resolve=>{resolveFetch.value=()=>resolve({json:async()=>response});});
  if(reject)throw Error('network');return {json:async()=>response};},console,Event:class{constructor(type){this.type=type;}}};
vm.createContext(context);
vm.runInContext(fs.readFileSync('ui/app.js','utf8')+'\nglobalThis.test={state,api,retry,el,run,restraint,t,label,form,span,money};',context);
const tick=()=>new Promise(resolve=>setTimeout(resolve,0));
(async()=>{
 const t=context.test;
 listeners.message({data:{type:'open',epoch:4,mode:'officer',department:'new_hanover',locale:'en',strings:en,
  session:{departments:[{key:'new_hanover',label:'New Hanover'}],caseTypes:['criminal']}}});
 await tick();
 assert.equal(t.state.department,'new_hanover');assert.equal(requests.at(-1).operation,'cases.list');
 assert.equal(requests.at(-1).payload.department,'new_hanover');assert.equal(requests.at(-1).epoch,4);
 assert.equal(document.getElementById('close').textContent,'Close · Esc');
 assert.equal(document.documentElement.lang,'en');
 assert.equal(t.t('case.meta',{id:'c1',revision:2,type:'Criminal',status:'open',opened:'now'}),'Case c1 · revision 2 · Criminal · open · opened now');
 assert.equal(t.label('recordStatus','pending_hearing'),'pending hearing');assert.equal(t.label('recordStatus','unknown'),'unknown');
 assert.equal(t.t('missing.key'),'missing.key');
 assert.equal(t.span(3725),'1h 2m 5s');assert.equal(t.span(0),'0s');assert.equal(t.money(2550,'dollars'),'25.50 dollars');
 const hostile='<img src=x onerror=alert(1)>';assert.equal(t.el('p',hostile).textContent,hostile);

 // Mutations keep one request ID until the server gives a definitive answer.
 reject=true;await assert.rejects(t.api('cases.open',{title:'Case',summary:'Text'},true));
 assert.equal(t.state.pending.payload.requestId,'test-id');const first=JSON.stringify(requests.at(-1).payload);const count=requests.length;
 await assert.rejects(t.api('cases.open',{title:'Duplicate',summary:'Text'},true),/Recover the last operation first/);assert.equal(requests.length,count);
 reject=false;response={ok:false,code:'rate_limited'};await assert.rejects(t.retry());assert.notEqual(t.state.pending,null);
 response={ok:true,value:{kind:'case',recordId:'c1',caseId:'c1',revision:1,status:'open',title:'Case',summary:'Text'}};
 await t.retry();assert.equal(JSON.stringify(requests.find(r=>r.operation==='cases.open'&&requests.indexOf(r)>=count).payload),first);assert.equal(t.state.pending,null);
 assert.equal(requests.at(-1).operation,'cases.get');
 response={ok:false,code:'invalid_input'};await assert.rejects(t.api('cases.open',{title:'Case',summary:'Text'},true),/Check the entered data/);assert.equal(t.state.pending,null);
 response={ok:false,code:'revision_conflict'};t.state.pending={operation:'cases.update',payload:{department:'new_hanover',requestId:'old'}};
 await assert.rejects(t.retry(),/record changed/);assert.equal(t.state.pending,null,'a definitive retry answer releases the request ID');

 // A reply that arrives after the MDT session changed is fenced.
 resolveFetch={};const waiting=t.api('cases.list');await Promise.resolve();t.state.generation++;resolveFetch.value();
 await assert.rejects(waiting,/session changed/);resolveFetch=null;

 // Own fines: no department, no actor fields; an uncertain payment keeps its ID.
 t.state.pending=null;t.state.mode='debtor';response={ok:false,code:'settlement_pending'};
 await assert.rejects(t.api('debts.settle',{obligationId:'0aeb8b93-76d2-4ab9-b459-20522c39d59c'},true));
 assert.equal(t.state.pending.operation,'debts.settle');assert.equal('department' in requests.at(-1).payload,false);
 const payment=JSON.stringify(t.state.pending.payload);response={ok:false,code:'rate_limited'};await assert.rejects(t.retry());
 assert.equal(JSON.stringify(t.state.pending.payload),payment);

 // Physical interactions carry no request ID and wait for a pending mutation.
 t.state.pending=null;t.state.mode='officer';response={ok:true,value:{restrained:true}};
 await t.restraint('apply',{targetSource:7,warrantId:'b40c6ec5-e747-46bb-9ff5-67c172222711'});
 assert.equal(requests.at(-1).operation,'restraints.apply');assert.equal('requestId' in requests.at(-1).payload,false);assert.equal(t.state.pending,null);
 t.state.pending={operation:'cases.open',payload:{}};const before=requests.length;
 await assert.rejects(t.restraint('release',{targetSource:7}));assert.equal(requests.length,before);t.state.pending=null;

 // A committed collection with a pending link stays retryable with the same transfer ID.
 response={ok:false,code:'evidence_link_pending'};
 await assert.rejects(t.api('evidence.collect',{caseId:'b40c6ec5-e747-46bb-9ff5-67c172222711',itemId:20,itemRevision:3},true));
 const collection=JSON.stringify(t.state.pending.payload);response={ok:false,code:'internal'};await assert.rejects(t.retry());
 assert.equal(JSON.stringify(t.state.pending.payload),collection);
 response={ok:true,value:{transfer:{itemId:20},link:{evidenceLinkId:'l1'}}};await t.retry();assert.equal(t.state.pending,null);

 // Forms convert dollars to minor units and minutes to seconds; empty optional fields are left out.
 const root=new Node('section');let submitted;
 const f=t.form(root,'Test',[['Amount','amount',{number:true,step:'0.01',scale:100}],['Minutes','term',{number:true,scale:60}],
  ['Note','note',{optional:true}]],async values=>{submitted=values;});
 const inputs=f.children.filter(n=>n.tag==='label').map(l=>l.children[0]);
 inputs[0].value='25.50';inputs[1].value='15';inputs[2].value='';
 f.onsubmit({preventDefault(){}});await tick();
 assert.deepEqual(JSON.parse(JSON.stringify(submitted)),{amount:2550,term:900});

 // The language follows the account setting while the MDT is open.
 listeners.message({data:{type:'locale',locale:'ro',strings:ro}});
 assert.equal(t.t('nav.cases'),'Dosare');assert.equal(document.getElementById('close').textContent,'Închide · Esc');assert.equal(document.documentElement.lang,'ro');
 response={ok:false,code:'duty_required'};await assert.rejects(t.api('cases.list'),/Trebuie să fii în tură/);

 // A run started before a session change cannot release the newer session's busy flag.
 let release;const oldRun=t.run(()=>new Promise(resolve=>{release=resolve;}));t.state.generation++;t.state.busy=true;release();await oldRun;
 assert.equal(t.state.busy,true);
 console.log('PASS MDT browser logic: locale text, safe text, stable mutation retry, definitive rejection, stale response fencing, form units');
})().catch(error=>{console.error(error);process.exitCode=1;});
