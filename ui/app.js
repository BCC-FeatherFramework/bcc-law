// BCC Law MDT. Every record shown comes from Justice through a versioned Law route;
// the browser never chooses an actor, resource or authority. All text comes from
// the locale table the client sends (locales/*.lua).
const $=id=>document.getElementById(id);
const state={epoch:0,generation:0,department:null,case:null,busy:false,pending:null,mode:'officer',strings:{},locale:'en',session:{}};
const uuidPattern='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';
const tokenPattern='[A-Za-z0-9][A-Za-z0-9_.:\\-]*';
const has=key=>Object.prototype.hasOwnProperty.call(state.strings,key);
function t(key,vars={}){
 let text=has(key)?state.strings[key]:key;
 for(const [name,value] of Object.entries(vars))text=text.split(`{${name}}`).join(String(value??''));
 return text;
}
function label(group,value){const key=`${group}.${value}`;return has(key)?state.strings[key]:String(value??'—');}
function el(tag,text,parent){const node=document.createElement(tag);if(text!==undefined)node.textContent=text;if(parent)parent.append(node);return node;}
function button(text,handler,parent){const b=el('button',text,parent);b.type='button';b.onclick=()=>run(handler);return b;}
function notice(text=''){$('notice').textContent=text;}
function when(ms){return typeof ms==='number'?new Date(ms).toLocaleString(state.locale):'—';}
function amount(minor){return (minor/100).toFixed(2);}
function money(minor,currency){return typeof minor==='number'?`${amount(minor)} ${currency||''}`.trim():'—';}
function span(seconds){
 if(typeof seconds!=='number')return '—';
 const parts=[[Math.floor(seconds/86400),'format.days'],[Math.floor(seconds%86400/3600),'format.hours'],
  [Math.floor(seconds%3600/60),'format.minutes'],[Math.floor(seconds%60),'format.seconds']].filter(([n])=>n>0).map(([n,key])=>t(key,{n}));
 return parts.length?parts.join(' '):t('format.seconds',{n:0});
}
function range(r,format){return r&&typeof r.min==='number'&&typeof r.max==='number'?`${format(r.min)} – ${format(r.max)}`:null;}

// Transport -------------------------------------------------------------------------
const uncertain=new Set(['operation_failed','transaction_failed','timeout','rpc_timeout','dependency_unavailable','session_expired',
 'settlement_pending','internal_error','internal','evidence_link_pending','operation_pending']);
// Transport refusals say nothing about an earlier attempt, so a retry keeps its ID.
const transport=new Set(['rate_limited','client_unavailable']);
function errorText(code){return has(`error.${code}`)?state.strings[`error.${code}`]:t('error.unconfirmed');}
async function post(name,data){
 const response=await fetch(`https://${GetParentResourceName()}/${name}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
 return response.json();
}
const unscoped=['debts.','execution.','service.'];
async function api(operation,payload={},mutation=false){
 const generation=state.generation;
 const scoped=unscoped.some(prefix=>operation.startsWith(prefix))?{...payload}:{...payload,department:state.department};
 if(mutation){
  if(state.pending)throw Error(t('retry.first'));
  scoped.requestId=crypto.randomUUID();state.pending={operation,payload:{...scoped}};
 }
 let result;
 try{result=await post('request',{epoch:state.epoch,operation,payload:scoped});}catch{result={ok:false,code:'operation_failed'};}
 if(generation!==state.generation)throw Error(t('error.session_expired'));
 // A definitive answer releases the request ID; an uncertain one keeps it for an exact retry.
 if(mutation&&(result.ok||!uncertain.has(result.code)))state.pending=null;
 if(!result.ok)throw Error(errorText(result.code)+(state.pending?' '+t('retry.hint'):''));
 return result.value;
}
async function run(fn){
 if(state.busy)return;
 const generation=state.generation;state.busy=true;notice();
 try{await fn();}catch(error){if(generation===state.generation)notice(error.message);}
 finally{if(generation===state.generation)state.busy=false;}
}
async function retry(){
 if(!state.pending){notice(t('retry.none'));return;}
 const generation=state.generation,pending=state.pending;
 let result;
 try{result=await post('request',{epoch:state.epoch,...pending});}catch{throw Error(t('retry.unconfirmed'));}
 if(generation!==state.generation)return;
 if(!result.ok){if(!uncertain.has(result.code)&&!transport.has(result.code))state.pending=null;throw Error(errorText(result.code));}
 state.pending=null;notice(t('retry.confirmed'));
 if(state.mode==='debtor'){await debts();return;}
 const value=result.value||{};
 if(value.kind==='case')await showCase(value.recordId);else if(value.caseId)await showCase(value.caseId);
}

// Layout helpers ------------------------------------------------------------------
function heading(title){const root=$('content');root.replaceChildren();el('h2',title,root);return root;}
function field(form,text,name,o={}){
 const row=el('label',text,form);let input;
 if(o.choices){input=el('select',undefined,row);for(const [value,caption] of o.choices){const option=el('option',caption,input);option.value=value;}}
 else input=el(o.multiline?'textarea':'input',undefined,row);
 input.name=name;input.required=!o.optional;
 if(o.number){input.type='number';input.min=o.min;input.max=o.max;input.step=o.step||'1';}
 else if(o.max&&!o.choices)input.maxLength=o.max;
 if(o.uuid){input.pattern=uuidPattern;input.placeholder=t('field.uuidPlaceholder');}
 if(o.pattern)input.pattern=o.pattern;
 if(o.value!==undefined&&o.value!==null)input.value=String(o.value);
 return input;
}
// Number fields may carry a scale: money in dollars → minor units (100), durations
// in minutes/hours/days → seconds. Empty optional fields are left out of the payload.
function form(root,title,fields,submit,submitText){
 const f=el('form',undefined,root);el('h3',title,f);
 const inputs=fields.map(([text,name,o])=>[name,o||{},field(f,text,name,o||{})]);
 const save=el('button',submitText||t('ui.save'),f);save.type='submit';
 f.onsubmit=event=>{event.preventDefault();run(async()=>{
  const values={};
  for(const [name,o,input] of inputs){
   const raw=input.value;if(o.optional&&raw==='')continue;
   values[name]=o.number?Math.round(Number(raw)*(o.scale||1)):raw;
  }
  await submit(values);
 });};
 return f;
}
function pageButton(root,cursor,load){if(cursor)button(t('ui.nextPage'),()=>load(cursor),root);}
function confirmAction(message){return new Promise(resolve=>{
 const dialog=el('dialog',undefined,document.body);el('p',message,dialog);
 const finish=value=>{dialog.close();dialog.remove();resolve(value);};
 const yes=el('button',t('ui.confirm'),dialog);yes.type='button';yes.onclick=()=>finish(true);
 const no=el('button',t('ui.cancel'),dialog);no.type='button';no.onclick=()=>finish(false);
 dialog.oncancel=event=>{event.preventDefault();finish(false);};dialog.showModal();
});}
function nav(){
 const root=$('nav');root.replaceChildren();
 if(state.mode==='inmate'){button(t('nav.status'),ownStatus,root);return;}
 if(state.mode==='debtor'){button(t('nav.fines'),()=>debts(),root);button(t('nav.retry'),retry,root);return;}
 button(t('nav.cases'),()=>cases(),root);button(t('nav.newCase'),newCase,root);button(t('nav.activeWarrants'),()=>activeWarrants(),root);
 button(t('nav.penalCode'),()=>statutes(),root);button(t('nav.field'),fieldActions,root);button(t('nav.armory'),armoryStations,root);
 button(t('nav.retry'),retry,root);
}

// Cases --------------------------------------------------------------------------------
const caseStatuses=['draft','open','filed','pending_hearing','adjudicated','closed','dismissed','sealed'];
const transitions={draft:['open','dismissed'],open:['filed','dismissed'],filed:['pending_hearing','closed','dismissed'],
 pending_hearing:['filed','dismissed'],adjudicated:['closed']};
async function cases(cursor,status){
 state.case=null;
 const data=await api('cases.list',{...(cursor?{cursor}:{}),...(status?{status}:{})});
 const root=heading(t('nav.cases'));
 const filter=el('select',undefined,root);filter.title=t('cases.filter');
 for(const value of ['',...caseStatuses]){const option=el('option',value?label('recordStatus',value):t('cases.allStatuses'),filter);option.value=value;}
 filter.value=status||'';filter.onchange=()=>run(()=>cases(undefined,filter.value||undefined));
 if(!data.items.length)el('p',t('cases.empty'),root);
 for(const item of data.items){
  const card=el('article',undefined,root);el('h3',item.title,card);
  el('p',`${label('caseType',item.caseType)} · ${label('recordStatus',item.status)} · ${when(item.openedAt)}`,card);
  button(t('ui.open'),()=>showCase(item.caseId),card);
 }
 pageButton(root,data.nextCursor,next=>cases(next,status));
}
function newCase(){
 const root=heading(t('nav.newCase'));
 const types=(state.session.caseTypes||['criminal']).map(type=>[type,label('caseType',type)]);
 form(root,t('case.details'),[[t('case.type'),'caseType',{choices:types}],[t('case.titleField'),'title',{max:180}],
  [t('case.summary'),'summary',{multiline:true,max:4000}],
  [t('case.start'),'start',{choices:[['open',t('case.startOpen')],['draft',t('case.startDraft')]]}]],async values=>{
  const {start,...payload}=values;
  const item=await api('cases.open',{...payload,draft:start==='draft'},true);
  await showCase(item.caseId||item.recordId);
 });
}
async function loadCase(id){state.case=await api('cases.get',{caseId:id});return state.case;}
async function fresh(){if(!state.case)throw Error(t('case.openFirst'));return loadCase(state.case.caseId);}
function related(kind){const r=state.case&&state.case.related;return (r&&r[kind]&&r[kind].items)||[];}
async function showCase(id){
 const c=await loadCase(id);
 const root=heading(c.title);
 el('small',t('case.meta',{id:c.caseId,revision:c.revision,type:label('caseType',c.caseType),status:label('recordStatus',c.status),opened:when(c.openedAt)}),root);
 el('p',c.summary,root);
 const actions=el('div',undefined,root);actions.className='actions';
 for(const [key,view] of [['parties',parties],['charges',charges],['warrants',warrants],['citations',citations],['custody',custody],
  ['evidence',evidence],['rulings',rulings],['sentences',sentences],['privacy',privacy]])button(t(`case.tab.${key}`),()=>view(),actions);
 button(t('ui.reload'),()=>showCase(id),actions);
 if(['draft','open','filed','pending_hearing'].includes(c.status))form(root,t('case.updateSummary'),[[t('case.titleField'),'title',{max:180,value:c.title}],
  [t('case.summary'),'summary',{multiline:true,max:4000,value:c.summary}]],async p=>{
  await api('cases.update',{...p,caseId:id,expectedRevision:c.revision},true);await showCase(id);
 });
 for(const status of transitions[c.status]||[])button(t('case.transition',{status:label('recordStatus',status)}),async()=>{
  if(!await confirmAction(t('case.transitionConfirm',{status:label('recordStatus',status)})))return;
  await api('cases.transition',{caseId:id,expectedRevision:c.revision,status},true);await showCase(id);
 },root);
}
function caseRoot(title){
 if(!state.case)throw Error(t('case.openFirst'));
 const root=heading(title);el('small',state.case.title,root);
 button(t('ui.backToCase'),()=>showCase(state.case.caseId),root);
 return root;
}

// Parties ----------------------------------------------------------------------------
const roles=['suspect','defendant','victim','witness','reporting_officer','investigating_officer','prosecutor','defense_counsel','judge'];
async function parties(cursor){
 const c=state.case;const data=await api('parties.list',{caseId:c.caseId,...(cursor?{cursor}:{})});
 const root=caseRoot(t('case.tab.parties'));
 if(!data.items.length)el('p',t('parties.empty'),root);
 for(const item of data.items){
  const card=el('article',undefined,root);
  el('h3',`${label('role',item.partyRole)} · ${label('recordStatus',item.status)}`,card);
  el('small',`${label('partyType',item.partyType)} · ${item.partyIdReference}`,card);
  if(item.status==='active')button(t('parties.remove'),async()=>{
   if(!await confirmAction(t('parties.removeConfirm')))return;
   await api('parties.remove',{caseId:c.caseId,partyId:item.partyId,expectedRevision:item.revision},true);await fresh();await parties();
  },card);
 }
 pageButton(root,data.nextCursor,parties);
 form(root,t('parties.add'),[[t('parties.type'),'partyType',{choices:['character','organization'].map(v=>[v,label('partyType',v)])}],
  [t('parties.reference'),'partyIdReference',{uuid:true}],[t('parties.role'),'partyRole',{choices:roles.map(r=>[r,label('role',r)])}]],async p=>{
  await api('parties.add',{...p,caseId:c.caseId,expectedCaseRevision:c.revision},true);await fresh();await parties();
 });
}

// Charges and the penal code ------------------------------------------------------
function statuteText(s){
 const m=s.metadata||{};const parts=[s.title,label('severity',s.severityClass)];
 const fine=range(m.recommendedFine,amount),custodyRange=range(m.recommendedCustodySeconds,span);
 if(fine)parts.push(t('statutes.fineRange',{range:fine}));if(custodyRange)parts.push(t('statutes.custodyRange',{range:custodyRange}));
 return parts.join(' · ');
}
// Up to four pages (100 statutes) for a selection list.
async function statuteChoices(){
 const choices=[];let cursor;
 for(let page=0;page<4;page++){
  const data=await api('statutes.list',{status:'active',...(cursor?{cursor}:{})});
  for(const s of data.items)choices.push([s.statuteId,statuteText(s)]);
  cursor=data.nextCursor;if(!cursor)break;
 }
 return choices;
}
async function charges(cursor){
 const c=state.case;const data=await api('charges.list',{caseId:c.caseId,...(cursor?{cursor}:{})});
 const root=caseRoot(t('case.tab.charges'));
 button(t('charges.propose'),chargeForm,root);
 if(!data.items.length)el('p',t('charges.empty'),root);
 for(const item of data.items){
  const s=item.statuteSnapshot||{};const card=el('article',undefined,root);
  el('h3',`${s.title||item.statuteId} · ${label('severity',s.severityClass)}`,card);
  el('p',t('charges.line',{count:item.count,status:label('recordStatus',item.status)}),card);
  el('small',t('charges.defendant',{id:item.defendantCharacterId}),card);
  const change=async(operation,disposition)=>{
   if(!await confirmAction(t('charges.changeConfirm')))return;
   await api(operation,{caseId:c.caseId,chargeId:item.chargeId,expectedRevision:item.revision,...(disposition?{disposition}:{})},true);
   await fresh();await charges();
  };
  if(item.status==='proposed')button(t('charges.file'),()=>change('charges.file'),card);
  if(['proposed','filed'].includes(item.status)){button(t('charges.withdraw'),()=>change('charges.dispose','withdrawn'),card);button(t('charges.amend'),()=>amendForm(item),card);}
  if(item.status==='filed')button(t('charges.dismiss'),()=>change('charges.dispose','dismissed'),card);
 }
 pageButton(root,data.nextCursor,charges);
}
async function chargeForm(){
 const c=state.case;const choices=await statuteChoices();const root=caseRoot(t('charges.propose'));
 if(!choices.length){el('p',t('statutes.none'),root);return;}
 form(root,t('charges.select'),[[t('charges.defendantField'),'defendantCharacterId',{uuid:true}],[t('charges.statute'),'statuteId',{choices}],
  [t('charges.count'),'count',{number:true,min:1,max:100,value:1}]],async p=>{
  await api('charges.propose',{...p,caseId:c.caseId,expectedCaseRevision:c.revision},true);await fresh();await charges();
 });
}
async function amendForm(item){
 const c=state.case;const choices=await statuteChoices();const root=caseRoot(t('charges.amend'));
 if(!choices.some(([id])=>id===item.statuteId))choices.unshift([item.statuteId,t('charges.currentStatute',{title:(item.statuteSnapshot||{}).title||item.statuteId})]);
 form(root,t('charges.amendTitle'),[[t('charges.statute'),'statuteId',{choices,value:item.statuteId}],
  [t('charges.count'),'count',{number:true,min:1,max:100,value:item.count}]],async p=>{
  const change={};if(p.statuteId!==item.statuteId)change.statuteId=p.statuteId;if(p.count!==item.count)change.count=p.count;
  if(!Object.keys(change).length)throw Error(t('charges.noChange'));
  await api('charges.amend',{caseId:c.caseId,chargeId:item.chargeId,expectedRevision:item.revision,...change},true);await fresh();await charges();
 });
}
async function statutes(cursor,status='active'){
 const data=await api('statutes.list',{status,...(cursor?{cursor}:{})});
 const root=heading(t('nav.penalCode'));el('p',t('statutes.note'),root);
 const filter=el('select',undefined,root);filter.title=t('statutes.filter');
 for(const value of ['active','retired']){const option=el('option',label('recordStatus',value),filter);option.value=value;}
 filter.value=status;filter.onchange=()=>run(()=>statutes(undefined,filter.value));
 button(t('statutes.register'),()=>statuteForm(),root);
 if(!data.items.length)el('p',t('statutes.none'),root);
 for(const s of data.items){
  const card=el('article',undefined,root);el('h3',s.title,card);
  el('p',`${label('severity',s.severityClass)} · ${s.category} · ${label('recordStatus',s.status)}`,card);
  el('small',t('statutes.key',{key:s.statuteKey,version:s.definitionVersion}),card);
  const m=s.metadata||{};const fine=range(m.recommendedFine,amount),custodyRange=range(m.recommendedCustodySeconds,span);
  if(fine)el('p',t('statutes.fineRange',{range:fine}),card);if(custodyRange)el('p',t('statutes.custodyRange',{range:custodyRange}),card);
  if(s.description)el('p',s.description,card);
  button(t('statutes.revise'),()=>statuteForm(s),card);
 }
 pageButton(root,data.nextCursor,next=>statutes(next,status));
}
function statuteForm(s){
 const root=heading(s?t('statutes.revise'):t('statutes.register'));button(t('ui.back'),()=>statutes(),root);
 el('p',t('statutes.advisory'),root);
 const m=(s&&s.metadata)||{},fine=m.recommendedFine||{},custodyRange=m.recommendedCustodySeconds||{};
 const moneyField={number:true,min:0,max:10000000,step:'0.01',scale:100,optional:true};
 const fields=[];
 if(!s)fields.push([t('statutes.name'),'statuteName',{max:48,pattern:'[a-z][a-z0-9_.]*'}]);
 fields.push([t('statutes.titleField'),'title',{max:180,value:s?.title}],
  [t('statutes.description'),'description',{multiline:true,max:4000,optional:true,value:s?.description}],
  [t('statutes.category'),'category',{max:32,pattern:'[a-z][a-z0-9_]*',value:s?.category}],
  [t('statutes.severity'),'severityClass',{choices:['infraction','misdemeanor','felony'].map(v=>[v,label('severity',v)]),value:s?.severityClass}],
  [t('statutes.fineMin'),'fineMin',{...moneyField,value:typeof fine.min==='number'?amount(fine.min):undefined}],
  [t('statutes.fineMax'),'fineMax',{...moneyField,value:typeof fine.max==='number'?amount(fine.max):undefined}],
  [t('statutes.custodyMin'),'custodyMin',{number:true,min:0,max:525600,scale:60,optional:true,value:typeof custodyRange.min==='number'?custodyRange.min/60:undefined}],
  [t('statutes.custodyMax'),'custodyMax',{number:true,min:0,max:525600,scale:60,optional:true,value:typeof custodyRange.max==='number'?custodyRange.max/60:undefined}]);
 if(s)fields.push([t('statutes.status'),'status',{choices:['active','retired'].map(v=>[v,label('recordStatus',v)]),value:s.status}]);
 form(root,s?s.title:t('statutes.newTitle'),fields,async p=>{
  const pair=(a,b)=>a===undefined&&b===undefined?undefined:{min:a??0,max:b??a};
  const payload={title:p.title,category:p.category,severityClass:p.severityClass};
  if(p.description!==undefined)payload.description=p.description;
  const recommendedFine=pair(p.fineMin,p.fineMax),recommendedCustodySeconds=pair(p.custodyMin,p.custodyMax);
  if(recommendedFine)payload.recommendedFine=recommendedFine;
  if(recommendedCustodySeconds)payload.recommendedCustodySeconds=recommendedCustodySeconds;
  if(s)await api('statutes.revise',{...payload,status:p.status,statuteId:s.statuteId,expectedRevision:s.revision},true);
  else await api('statutes.register',{...payload,statuteName:p.statuteName},true);
  await statutes();
 });
}

// Warrants ---------------------------------------------------------------------------
const warrantActions={draft:['issue'],active:['serve','recall','quash']};
function warrantCards(root,items,refresh){
 for(const item of items){
  const card=el('article',undefined,root);
  el('h3',`${label('warrantType',item.warrantType)} · ${label('recordStatus',item.status)}`,card);
  el('p',item.basisSummary,card);
  el('small',t('warrants.subject',{id:item.subjectCharacterId}),card);
  if(item.expiresAt)el('p',t('warrants.expires',{at:when(item.expiresAt)}),card);
  el('small',t('warrants.id',{id:item.warrantId,revision:item.revision}),card);
  for(const op of warrantActions[item.status]||[])button(t(`warrants.${op}`),async()=>{
   if(!await confirmAction(t(`warrants.${op}Confirm`)))return;
   await api(`warrants.${op}`,{caseId:item.caseId,warrantId:item.warrantId,expectedRevision:item.revision},true);await refresh();
  },card);
 }
}
async function warrants(){
 const c=state.case;const data=await api('warrants.list',{caseId:c.caseId});const root=caseRoot(t('case.tab.warrants'));
 if(!data.items.length)el('p',t('warrants.empty'),root);
 warrantCards(root,data.items,async()=>{await fresh();await warrants();});
 if(data.truncated)el('p',t('ui.truncated'),root);
 form(root,t('warrants.draft'),[[t('warrants.type'),'warrantType',{choices:['arrest','search','seizure','summons'].map(k=>[k,label('warrantType',k)])}],
  [t('warrants.subjectField'),'subjectCharacterId',{uuid:true}],[t('warrants.basis'),'basisSummary',{multiline:true,max:2000}],
  [t('warrants.validHours'),'validForSeconds',{number:true,min:1,max:720,value:24,scale:3600}]],async p=>{
  await api('warrants.draft',{...p,caseId:c.caseId,expectedCaseRevision:c.revision},true);await fresh();await warrants();
 });
}
async function activeWarrants(cursor,subject){
 const data=await api('warrants.active',{...(cursor?{cursor}:{}),...(subject?{subjectCharacterId:subject}:{})});
 const root=heading(t('nav.activeWarrants'));
 form(root,t('warrants.filter'),[[t('warrants.subjectField'),'subject',{uuid:true,optional:true,value:subject||''}]],
  async p=>activeWarrants(undefined,p.subject),t('ui.search'));
 if(!data.items.length)el('p',t('warrants.noneActive'),root);
 warrantCards(root,data.items,()=>activeWarrants(cursor,subject));
 pageButton(root,data.nextCursor,next=>activeWarrants(next,subject));
}

// Citations --------------------------------------------------------------------------
async function citations(cursor){
 const c=state.case;const data=await api('citations.list',{caseId:c.caseId,...(cursor?{cursor}:{})});
 const root=caseRoot(t('case.tab.citations'));el('p',t('citations.note'),root);
 if(!data.items.length)el('p',t('citations.empty'),root);
 for(const item of data.items){
  const card=el('article',undefined,root);
  el('h3',typeof item.amount==='number'?money(item.amount,item.currency):t('citations.warning'),card);
  el('p',`${label('recordStatus',item.status)} · ${item.subjectCharacterId}`,card);el('p',item.basisSummary,card);
  if(item.dueAt)el('small',t('citations.due',{at:when(item.dueAt)}),card);
  if(item.contractsObligationId)el('small',t('citations.obligation',{id:item.contractsObligationId}),card);
 }
 pageButton(root,data.nextCursor,citations);
 if(!['open','filed','pending_hearing'].includes(c.status))return;
 const choices=await statuteChoices();if(!choices.length){el('p',t('statutes.none'),root);return;}
 const common=[[t('citations.subject'),'subjectCharacterId',{uuid:true}],[t('charges.statute'),'statuteId',{choices}],
  [t('citations.basis'),'basisSummary',{multiline:true,max:2000}]];
 const issue=async p=>{await api('citations.issue',{...p,caseId:c.caseId,expectedCaseRevision:c.revision},true);await fresh();await citations();};
 form(root,t('citations.issueWarning'),common,async p=>{if(await confirmAction(t('citations.warningConfirm')))await issue(p);});
 form(root,t('citations.issueFine'),[...common,[t('field.amount'),'amount',{number:true,min:0.01,max:10000000000,step:'0.01',scale:100}],
  [t('field.dueDays'),'dueInSeconds',{number:true,min:1,max:365,value:7,scale:86400}]],async p=>{
  if(await confirmAction(t('citations.fineConfirm',{amount:amount(p.amount)})))await issue(p);
 });
}

// Custody: arrest needs a restrained subject and an authority naming them;
// booking needs officer and subject together at the facility.
const releaseReasons=['released_without_charge','bail','charges_dismissed','time_served','transferred','placement_failed'];
async function custody(){
 const c=state.case;const data=await api('custody.list',{caseId:c.caseId});const root=caseRoot(t('case.tab.custody'));
 el('p',t('custody.note'),root);
 if(!data.items.length)el('p',t('custody.empty'),root);
 const facilities=data.items.some(i=>i.status==='arrested')?(await api('custody.facilities')).items:[];
 for(const item of data.items){
  const card=el('article',undefined,root);
  el('h3',`${label('recordStatus',item.status)} · ${item.subjectCharacterId}`,card);
  el('small',t('custody.authority',{type:label('authority',item.authorityType),id:item.authorityId||'—'}),card);
  el('p',t('custody.times',{started:when(item.startedAt),booked:when(item.bookedAt)}),card);
  if(item.facilityKey)el('p',t('custody.facility',{facility:item.facilityKey}),card);
  if(item.status==='released')el('p',t('custody.released',{at:when(item.releasedAt),reason:label('releaseReason',item.releaseReason)}),card);
  if(item.status==='arrested'&&facilities.length)form(card,t('custody.book'),[[t('custody.facilityField'),'facilityKey',{choices:facilities.map(f=>[f.key,f.label])}]],async p=>{
   if(!await confirmAction(t('custody.bookConfirm')))return;
   await api('custody.book',{caseId:c.caseId,custodyId:item.custodyId,expectedRevision:item.revision,facilityKey:p.facilityKey},true);await fresh();await custody();
  },t('custody.bookSubmit'));
  if(item.status!=='released')form(card,t('custody.release'),[[t('custody.reason'),'releaseReason',{choices:releaseReasons.map(r=>[r,label('releaseReason',r)])}]],async p=>{
   if(!await confirmAction(t('custody.releaseConfirm')))return;
   await api('custody.release',{caseId:c.caseId,custodyId:item.custodyId,expectedRevision:item.revision,releaseReason:p.releaseReason},true);await fresh();await custody();
  },t('custody.releaseSubmit'));
 }
 if(data.truncated)el('p',t('ui.truncated'),root);
 const authorities=[
  ...related('warrant').filter(w=>w.warrantType==='arrest'&&w.status==='active').map(w=>({type:'warrant',id:w.warrantId,revision:w.revision,subject:w.subjectCharacterId})),
  ...related('sentence').filter(s=>s.sentenceType==='custodial'&&s.status==='active').map(s=>({type:'judicial_order',id:s.sentenceId,revision:s.revision,subject:s.defendantCharacterId}))];
 el('h3',t('custody.arrest'),root);
 if(!authorities.length)el('p',t('custody.noAuthority'),root);
 for(const a of authorities)form(root,`${label('authority',a.type)} · ${a.subject}`,[[t('field.player'),'targetSource',{number:true,min:1,max:65535}]],async p=>{
  if(!await confirmAction(t('custody.arrestConfirm')))return;
  await api('custody.arrest',{caseId:c.caseId,targetSource:p.targetSource,authorityType:a.type,authorityId:a.id,expectedAuthorityRevision:a.revision},true);
  await fresh();await custody();
 },t('custody.arrestSubmit'));
}

// Field: restraint, escort and search. These are physical interactions without a
// request ID; each one re-checks the legal authority on the server.
async function restraint(operation,payload){
 if(state.pending)throw Error(t('retry.first'));
 await api(`restraints.${operation}`,payload);notice(t('field.confirmed'));
}
function fieldActions(){
 const root=heading(t('nav.field'));el('p',t('field.note'),root);
 const player=[t('field.player'),'targetSource',{number:true,min:1,max:65535}];
 form(root,t('field.restrainWarrant'),[player,[t('field.arrestWarrant'),'warrantId',{uuid:true}]],async p=>{if(await confirmAction(t('field.restrainConfirm')))await restraint('apply',p);});
 form(root,t('field.restrainCustody'),[player,[t('field.custodyId'),'custodyId',{uuid:true}]],async p=>{if(await confirmAction(t('field.restrainConfirm')))await restraint('apply',p);});
 form(root,t('field.escort'),[player,[t('field.escortAction'),'enabled',{choices:[['on',t('field.escortOn')],['off',t('field.escortOff')]]}]],
  async p=>restraint('escort',{targetSource:p.targetSource,enabled:p.enabled==='on'}));
 form(root,t('field.unrestrain'),[player],async p=>{if(await confirmAction(t('field.unrestrainConfirm')))await restraint('release',p);});
 form(root,t('field.search'),[player,[t('field.searchWarrant'),'warrantId',{uuid:true}]],async p=>searchInventory(p),t('field.searchSubmit'));
}
async function searchInventory(payload,cursor){
 const data=await api('search.inspect',{...payload,...(cursor?{cursor}:{})});
 const root=heading(t('search.title'));
 button(t('ui.back'),fieldActions,root);button(t('search.recheck'),()=>searchInventory(payload),root);
 if(data.warrantRevision)button(t('search.finish'),async()=>{
  if(!await confirmAction(t('search.finishConfirm')))return;
  await api('search.finish',{...payload,expectedRevision:data.warrantRevision},true);fieldActions();notice(t('search.finished'));
 },root);
 el('p',t('search.note'),root);
 if(!data.items.length)el('p',t('search.empty'),root);
 for(const item of data.items){const card=el('article',undefined,root);el('h3',item.label||item.itemName,card);el('small',t('search.item',{id:item.instanceId,revision:item.revision}),card);}
 pageButton(root,data.nextCursor,next=>searchInventory(payload,next));
}

// Evidence ---------------------------------------------------------------------------
async function evidence(cursor){
 const c=state.case;const data=await api('evidence.list',{caseId:c.caseId,...(cursor?{cursor}:{})});
 const root=caseRoot(t('case.tab.evidence'));
 button(t('evidence.collect'),collectEvidence,root);button(t('evidence.receipts'),()=>evidenceReceipts(),root);
 el('p',t('evidence.note'),root);
 if(!data.items.length)el('p',t('evidence.empty'),root);
 for(const item of data.items){
  const card=el('article',undefined,root);
  el('h3',`${item.itemName||label('evidenceType',item.evidenceType)} · ${label('recordStatus',item.status)}`,card);
  el('small',t('evidence.reference',{type:label('evidenceType',item.evidenceType),id:item.evidenceId,relationship:label('relationship',item.relationship)}),card);
  if(item.description)el('p',item.description,card);
  if(item.disposition)el('p',t('evidence.disposition',{disposition:label('disposition',item.disposition)}),card);
  if(item.physicalState)el('p',t('evidence.physical',{state:label('physical',item.physicalState)}),card);
  if(item.status!=='active')continue;
  const remove=async(disposition,question)=>{
   if(!await confirmAction(question))return;
   await api('evidence.remove',{caseId:c.caseId,evidenceLinkId:item.evidenceLinkId,expectedRevision:item.revision,...(disposition?{disposition}:{})},true);
   await fresh();await evidence();
  };
  button(t('evidence.unlink'),()=>remove(undefined,t('evidence.unlinkConfirm')),card);
  for(const disposition of ['returned','destroyed','forfeited'])button(t('evidence.dispose',{disposition:label('disposition',disposition)}),
   ()=>remove(disposition,t(`evidence.disposeConfirm.${disposition}`)),card);
 }
 pageButton(root,data.nextCursor,evidence);
}
async function collectEvidence(){
 const c=state.case;const data=await api('evidence.lockers');const root=caseRoot(t('evidence.collectTitle'));
 if(!data.items.length){el('p',t('evidence.noLockers'),root);return;}
 el('p',t('evidence.collectNote'),root);
 const seizures=related('warrant').filter(w=>w.warrantType==='seizure'&&w.status==='active');
 if(!seizures.length){el('p',t('evidence.noSeizureWarrant'),root);return;}
 form(root,t('evidence.collectForm'),[[t('field.player'),'targetSource',{number:true,min:1,max:65535}],
  [t('evidence.warrant'),'warrantId',{choices:seizures.map(w=>[w.warrantId,`${w.subjectCharacterId} · ${when(w.expiresAt)}`])}],
  [t('evidence.itemId'),'itemId',{number:true,min:1,max:9007199254740990}],[t('evidence.itemRevision'),'itemRevision',{number:true,min:0,max:9007199254740990}],
  [t('evidence.locker'),'lockerKey',{choices:data.items.map(x=>[x.key,x.label])}],[t('evidence.description'),'description',{multiline:true,max:1000,optional:true}]],async p=>{
  if(!await confirmAction(t('evidence.collectConfirm')))return;
  await api('evidence.collect',{...p,caseId:c.caseId,expectedCaseRevision:c.revision},true);await fresh();await evidence();
 });
 button(t('evidence.receipts'),()=>evidenceReceipts(),root);
}
async function evidenceReceipts(cursor){
 const c=state.case;const data=await api('evidence.receipts',{caseId:c.caseId,...(cursor?{cursor}:{})});
 const root=caseRoot(t('evidence.receipts'));button(t('case.tab.evidence'),()=>evidence(),root);
 if(!data.items.length)el('p',t('evidence.noReceipts'),root);
 for(const entry of data.items){
  const r=entry.receipt||{};const card=el('article',undefined,root);
  el('h3',t('evidence.receiptTitle',{item:r.itemName,id:r.itemId}),card);
  el('p',t('evidence.receiptLine',{locker:r.lockerKey,at:entry.createdAt}),card);el('small',t('evidence.transfer',{id:entry.requestId}),card);
  const p=state.pending;
  if(p&&p.payload.caseId===c.caseId&&((p.operation==='evidence.collect'&&entry.requestId.endsWith(':'+p.payload.requestId))
   ||(p.operation==='evidence.attach'&&entry.requestId===p.payload.transferRequestId)))button(t('evidence.recovered'),async()=>{
   if(!await confirmAction(t('evidence.recoveredConfirm')))return;state.pending=null;await evidenceReceipts();
  },card);
  button(t('evidence.attach'),async()=>{
   const latest=await loadCase(c.caseId);
   if(!await confirmAction(t('evidence.attachConfirm',{revision:latest.revision})))return;
   await api('evidence.attach',{caseId:c.caseId,transferRequestId:entry.requestId,expectedCaseRevision:latest.revision},true);await fresh();await evidence();
  },card);
 }
 pageButton(root,data.nextCursor,evidenceReceipts);
}

// Court ------------------------------------------------------------------------------
async function rulings(){
 const c=state.case;const data=await api('rulings.list',{caseId:c.caseId});const root=caseRoot(t('case.tab.rulings'));
 button(t('rulings.record'),rulingForm,root);
 if(!data.items.length)el('p',t('rulings.empty'),root);
 for(const r of data.items){
  const card=el('article',undefined,root);el('h3',`${label('rulingType',r.rulingType)} · ${when(r.issuedAt)}`,card);
  if(r.subjectCharacterId)el('small',t('rulings.subject',{id:r.subjectCharacterId}),card);
  el('p',r.summary,card);if(r.outcome)el('p',t('rulings.outcome',{outcome:r.outcome}),card);
  for(const f of r.findings||[])el('p',`${label('finding',f.finding)} · ${f.chargeId}`,card);
 }
 if(data.truncated)el('p',t('ui.truncated'),root);
}
async function rulingForm(){
 const c=state.case;const data=await api('charges.list',{caseId:c.caseId});const root=caseRoot(t('rulings.new'));
 el('p',t('rulings.note'),root);
 const f=el('form',undefined,root);
 const type=field(f,t('rulings.type'),'rulingType',{choices:['verdict','dismissal','order'].map(v=>[v,label('rulingType',v)])});
 const subject=field(f,t('rulings.subjectField'),'subjectCharacterId',{uuid:true,optional:true});
 const summary=field(f,t('rulings.summary'),'summary',{multiline:true,max:4000});
 const outcome=field(f,t('rulings.outcomeField'),'outcome',{max:64,optional:true,pattern:tokenPattern});
 const findings=[];
 for(const charge of data.items.filter(x=>x.status==='filed')){
  el('p',`${(charge.statuteSnapshot||{}).title||charge.statuteId} · ${charge.defendantCharacterId}`,f);
  findings.push([charge,field(f,t('rulings.finding'),charge.chargeId,{choices:[['skip',t('rulings.skip')],['convicted',label('finding','convicted')],['acquitted',label('finding','acquitted')]]})]);
 }
 if(data.nextCursor)el('p',t('rulings.morePages'),f);
 const save=el('button',t('rulings.submit'),f);save.type='submit';
 f.onsubmit=event=>{event.preventDefault();run(async()=>{
  const p={caseId:c.caseId,expectedCaseRevision:c.revision,rulingType:type.value,summary:summary.value};
  if(subject.value)p.subjectCharacterId=subject.value.toLowerCase();
  if(type.value==='verdict'){
   if(!p.subjectCharacterId)throw Error(t('rulings.subjectRequired'));
   p.findings=findings.filter(([charge,input])=>input.value!=='skip'&&charge.defendantCharacterId===p.subjectCharacterId)
    .map(([charge,input])=>({chargeId:charge.chargeId,finding:input.value}));
   if(!p.findings.length)throw Error(t('rulings.findingsRequired'));
  }
  if(type.value==='order'){if(!outcome.value)throw Error(t('rulings.outcomeRequired'));p.outcome=outcome.value;}
  if(!await confirmAction(t('rulings.confirm')))return;
  await api('rulings.record',p,true);await fresh();await rulings();
 });};
}
const sentenceTypes=['custodial','community_service','fine','restitution','probation','license_suspension','forfeiture'];
function sentenceTerms(s){
 const x=s.terms||{};
 switch(s.sentenceType){
  case 'custodial':return t('sentences.termsCustodial',{term:span(x.termSeconds),facility:x.facilityKey||'—'});
  case 'probation':return t('sentences.termsProbation',{term:span(x.termSeconds)});
  case 'community_service':return t('sentences.termsService',{units:x.units,task:x.taskKey});
  case 'fine':return t('sentences.termsFine',{amount:money(x.amount,s.currency)});
  case 'restitution':return t('sentences.termsRestitution',{amount:money(x.amount,s.currency),creditor:x.creditorCharacterId});
  case 'license_suspension':return t('sentences.termsLicense',{license:x.licenseKey,term:x.termSeconds?span(x.termSeconds):t('sentences.indefinite')});
  case 'forfeiture':return t('sentences.termsForfeiture',{type:label('targetType',x.targetType),reference:x.targetReference});
 }
 return '';
}
async function sentences(){
 const c=state.case;const data=await api('sentences.list',{caseId:c.caseId});const root=caseRoot(t('case.tab.sentences'));
 button(t('sentences.new'),()=>sentenceForm('custodial'),root);el('p',t('sentences.note'),root);
 if(!data.items.length)el('p',t('sentences.empty'),root);
 for(const s of data.items){
  const card=el('article',undefined,root);
  el('h3',`${label('sentenceType',s.sentenceType)} · ${label('recordStatus',s.status)}`,card);
  el('p',sentenceTerms(s),card);el('small',t('sentences.defendant',{id:s.defendantCharacterId}),card);
  if(s.endsAt)el('p',t('sentences.ends',{at:when(s.endsAt)}),card);
  if(s.outcome)el('p',t('sentences.outcome',{outcome:label('outcome',s.outcome)}),card);
  const change=async(operation,extra,question)=>{
   if(!await confirmAction(question))return;
   await api(`sentences.${operation}`,{caseId:c.caseId,sentenceId:s.sentenceId,expectedRevision:s.revision,...extra},true);await fresh();await sentences();
  };
  if(s.status==='pending')button(t('sentences.activate'),()=>change('activate',{},t('sentences.activateConfirm')),card);
  if(s.status==='suspended')button(t('sentences.resume'),()=>change('activate',{},t('sentences.resumeConfirm')),card);
  if(s.status==='active')button(t('sentences.suspend'),()=>change('suspend',{},t('sentences.suspendConfirm')),card);
  if(['pending','active','suspended'].includes(s.status)){
   button(t('sentences.vacate'),()=>change('complete',{outcome:'vacated'},t('sentences.vacateConfirm')),card);
   button(t('sentences.commute'),()=>change('complete',{outcome:'commuted'},t('sentences.commuteConfirm')),card);
  }
  if(s.status==='active'&&['license_suspension','forfeiture'].includes(s.sentenceType))form(card,t('sentences.served'),
   [[t('sentences.effectReference'),'effectReference',{max:128,pattern:tokenPattern}]],
   async p=>change('complete',{outcome:'served',effectReference:p.effectReference},t('sentences.servedConfirm')),t('sentences.servedSubmit'));
 }
 if(data.truncated)el('p',t('ui.truncated'),root);
}
function sentenceForm(kind){
 const c=state.case;const root=caseRoot(t('sentences.new'));
 const select=el('select',undefined,root);select.title=t('sentences.type');
 for(const type of sentenceTypes){const option=el('option',label('sentenceType',type),select);option.value=type;}
 select.value=kind;select.onchange=()=>sentenceForm(select.value);
 const verdicts=related('ruling').filter(r=>r.rulingType==='verdict');
 const ruling=verdicts.length?[t('sentences.ruling'),'rulingId',{choices:verdicts.map(r=>[r.rulingId,`${when(r.issuedAt)} · ${r.subjectCharacterId||''}`])}]
  :[t('sentences.ruling'),'rulingId',{uuid:true}];
 const facilities=(state.session.jailFacilities||[]).map(key=>[key,key]);
 const tasks=(state.session.serviceTasks||[]).map(task=>[task.key,task.label]);
 const amountField=[t('field.amount'),'amount',{number:true,min:0.01,max:10000,step:'0.01',scale:100}];
 const dueField=[t('field.dueDays'),'dueInSeconds',{number:true,min:1,max:30,value:7,scale:86400}];
 const fields={
  custodial:[[t('sentences.termMinutes'),'termSeconds',{number:true,min:1,max:525600,value:10,scale:60}],
   ...(facilities.length?[[t('sentences.facility'),'facilityKey',{choices:facilities}]]:[])],
  probation:[[t('sentences.termDays'),'termSeconds',{number:true,min:1,max:365,value:7,scale:86400}],[t('sentences.conditions'),'conditionsSummary',{multiline:true,max:2000}]],
  community_service:[[t('sentences.units'),'units',{number:true,min:1,max:1000,value:5}],
   tasks.length?[t('sentences.task'),'taskKey',{choices:tasks}]:[t('sentences.task'),'taskKey',{max:64,pattern:tokenPattern}]],
  fine:[amountField,dueField],
  restitution:[amountField,dueField,[t('sentences.creditor'),'creditorCharacterId',{uuid:true}]],
  license_suspension:[[t('sentences.license'),'licenseKey',{max:64,pattern:tokenPattern}],[t('sentences.termDaysOptional'),'termSeconds',{number:true,min:1,max:365,scale:86400,optional:true}]],
  forfeiture:[[t('sentences.targetType'),'targetType',{choices:['property','asset','item'].map(v=>[v,label('targetType',v)])}],
   [t('sentences.targetReference'),'targetReference',{max:64,pattern:tokenPattern}]]
 };
 if(['license_suspension','forfeiture'].includes(kind))el('p',t('sentences.effectNote'),root);
 form(root,t('sentences.terms'),[ruling,...fields[kind]],async p=>{
  if(!await confirmAction(t('sentences.createConfirm')))return;
  const {rulingId,...terms}=p;
  await api('sentences.create',{caseId:c.caseId,expectedCaseRevision:c.revision,rulingId,sentenceType:kind,terms},true);await fresh();await sentences();
 });
}
async function privacy(){
 const c=state.case;const root=caseRoot(t('case.tab.privacy'));el('p',t('privacy.note'),root);
 const act=operation=>button(t(`privacy.${operation}`),async()=>{
  if(!await confirmAction(t(`privacy.${operation}Confirm`)))return;
  await api(`cases.${operation}`,{caseId:c.caseId,expectedRevision:c.revision},true);
  if(operation==='unseal')await showCase(c.caseId);else await cases();
 },root);
 if(['closed','dismissed'].includes(c.status))act('seal');
 if(c.status==='sealed'){act('unseal');act('expunge');}
 button(t('privacy.history'),async()=>{
  const data=await api('cases.history',{caseId:c.caseId});const list=el('div',undefined,root);
  if(!data.items.length)el('p',t('privacy.noHistory'),list);
  for(const item of data.items){
   const row=el('article',undefined,list);el('p',`${when(item.createdAt)} · ${item.fact} · r${item.revision}`,row);
   el('small',t('privacy.historyLine',{reason:item.reasonCode||'—',actor:item.actorCharacterId||item.sourceResource||'—'}),row);
  }
 },root);
}

// Own legal status and fines -------------------------------------------------------
async function ownStatus(){
 const data=await api('execution.self');const root=heading(t('nav.status'));
 el('p',data.confined?t('mine.confined',{time:span(Math.ceil(data.remainingMs/1000))}):t('mine.free'),root);
 if(data.task)el('p',data.task.state==='working'?t('mine.working',{task:data.task.label,time:span(Math.ceil(data.task.remainingMs/1000))}):t('mine.taskPending'),root);
 for(const s of data.communityService||[]){
  const card=el('article',undefined,root);el('h3',s.label,card);el('p',t('mine.units',{done:s.completedUnits,total:s.units}),card);
  if(s.completing)el('p',t('mine.completing'),card);
  else if(s.available){
   el('p',t('mine.location',{x:s.x.toFixed(1),y:s.y.toFixed(1),z:s.z.toFixed(1)}),card);
   button(t('mine.startUnit'),async()=>{await api('service.start',{sentenceId:s.sentenceId});notice(t('mine.stayOnSite'));},card);
  }
 }
}
if(typeof window.setInterval==='function')window.setInterval(()=>{if(!$('mdt').hidden&&state.mode==='inmate'&&!state.busy)run(ownStatus);},2000);
async function debts(cursor){
 const data=await api('debts.list',{role:'debtor',limit:25,...(cursor?{cursor}:{})});const root=heading(t('nav.fines'));
 button(t('ui.reload'),()=>debts(),root);
 const items=data.items.filter(item=>['justice_citation','justice_sentence'].includes(item.referenceType));
 if(!items.length)el('p',t('fines.empty'),root);
 for(const item of items){
  const card=el('article',undefined,root);el('h3',money(item.amount,item.currency),card);
  el('p',t('fines.status',{status:label('obligation',item.status)}),card);el('small',t('fines.obligation',{id:item.obligationId}),card);
  if(item.settlementState==='pending')el('p',t('fines.pending'),card);
  if(!['settled','cancelled','draft','disputed'].includes(item.status)&&item.settlementState!=='pending')button(t('fines.pay'),async()=>{
   if(!await confirmAction(t('fines.payConfirm',{amount:money(item.amount,item.currency)})))return;
   await api('debts.settle',{obligationId:item.obligationId},true);await debts();
  },card);
 }
 pageButton(root,data.nextCursor,debts);
}

// Armory ---------------------------------------------------------------------------
async function armoryStations(){
 const data=await api('armory.stations');const root=heading(t('nav.armory'));
 if(!data.items.length)el('p',t('armory.none'),root);
 for(const s of data.items)button(s.label,()=>armory(s.key),root);
}
async function armory(stationKey){
 const data=await api('armory.catalog',{stationKey});const root=heading(t('armory.title'));
 el('p',t('armory.note'),root);button(t('armory.claims'),()=>armoryClaims(stationKey),root);
 for(const item of data.items){
  const card=el('article',undefined,root);el('h3',item.label,card);el('p',t('armory.quantity',{n:item.quantity}),card);
  if(item.available)button(t('armory.claim'),async()=>{
   if(!await confirmAction(t('armory.claimConfirm',{item:item.label})))return;
   await api('armory.claim',{stationKey,itemKey:item.key},true);notice(t('armory.confirmed'));
  },card);
  else el('p',t('armory.unavailable'),card);
 }
}
async function armoryClaims(stationKey,cursor){
 const data=await api('armory.claims',{stationKey,...(cursor?{cursor}:{})});const root=heading(t('armory.claims'));
 button(t('ui.back'),()=>armory(stationKey),root);
 for(const entry of data.items){
  const card=el('article',undefined,root);el('p',`${entry.itemKey} · ${entry.period} · ${entry.pending?t('armory.pending'):t('armory.done')}`,card);
  if(entry.pending)button(t('armory.recover'),async()=>{
   if(state.pending&&state.pending.payload.requestId!==entry.requestId)throw Error(t('retry.first'));
   state.pending={operation:'armory.claim',payload:{department:state.department,stationKey,itemKey:entry.itemKey,requestId:entry.requestId}};
   await retry();
  },card);
 }
 pageButton(root,data.nextCursor,next=>armoryClaims(stationKey,next));
}

// Lifecycle --------------------------------------------------------------------------
function applyStrings(data){
 if(data.strings&&typeof data.strings==='object')state.strings=data.strings;
 state.locale=typeof data.locale==='string'?data.locale:'en';
 if(document.documentElement)document.documentElement.lang=state.locale;
 $('close').textContent=t('ui.close');$('footer').textContent=t('ui.footer');$('department').title=t('ui.department');
}
window.addEventListener('message',event=>{
 const data=event.data||{};
 if(data.type==='locale'){applyStrings(data);if(!$('mdt').hidden)nav();return;}
 if(data.type==='close'){
  state.generation++;state.pending=null;state.case=null;state.busy=false;$('mdt').hidden=true;
  document.querySelectorAll('dialog').forEach(d=>d.dispatchEvent(new Event('cancel',{cancelable:true})));
  $('content').replaceChildren();notice();return;
 }
 if(data.type!=='open')return;
 state.generation++;state.epoch=data.epoch;state.mode=data.mode||'officer';state.case=null;state.pending=null;state.busy=false;
 state.session=data.session||{};applyStrings(data);
 const departments=state.session.departments||[];
 const select=$('department');select.replaceChildren();
 for(const d of departments){const option=el('option',d.label,select);option.value=d.key;}
 state.department=departments.find(d=>d.key===data.department)?.key||departments[0]?.key||null;
 select.value=state.department||'';select.hidden=state.mode!=='officer';
 $('mdt').hidden=false;nav();
 run(()=>state.mode==='debtor'?debts():state.mode==='inmate'?ownStatus():cases());
});
$('department').onchange=()=>{
 if(state.busy||state.pending){$('department').value=state.department;notice(t('ui.finishFirst'));return;}
 state.department=$('department').value;state.case=null;run(()=>cases());
};
$('close').onclick=()=>post('close',{});
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!document.querySelector('dialog'))post('close',{});});
