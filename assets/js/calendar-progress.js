---
---
(() => {
  'use strict';
  const root=document.querySelector('[data-map-calendar],[data-leaf-grid]');if(!root)return;
  const calendar=window.GiappCalendar;
  const read=(key,fallback=null)=>JSON.parse(localStorage.getItem(key)||'null')??fallback;
  let entries=new Map(),ready=false,request=0;
  const get=day=>calendar.isOpen(day)?entries.get(Number(day))||null:null;
  window.GiappCalendarProgress=Object.freeze({get,isReady:()=>ready});
  const legend=document.createElement('div');legend.className='calendar-status-legend';legend.setAttribute('aria-label','Stato delle giornate');
  for(const [kind,text]of [['available','Disponibile'],['played','Già giocata'],['locked','Ancora chiusa']]){const item=document.createElement('span'),key=document.createElement('i');key.className='calendar-status-key calendar-status-key--'+kind;key.setAttribute('aria-hidden','true');if(kind==='played')key.textContent='✓';item.append(key,text);legend.append(item);}
  const notice=document.createElement('p');notice.className='calendar-progress-note';notice.setAttribute('role','status');notice.dataset.calendarProgressNote='';
  const hint=root.querySelector('.map-calendar__hint');if(hint){hint.after(legend);legend.after(notice);}else{root.before(legend);legend.after(notice);}
  function paint(){
    const cards=[...root.querySelectorAll('[data-map-day],.calendar-card')];cards.forEach((card,index)=>{const day=Number(card.dataset.mapDay||card.dataset.calendarDay||index+1),progress=get(day),played=!!progress;card.classList.toggle('is-played',played);card.dataset.played=String(played);let badge=card.querySelector('.calendar-played-badge');if(!badge){badge=document.createElement('span');badge.className='calendar-played-badge';badge.textContent='✓';badge.setAttribute('aria-hidden','true');(card.matches('.calendar-card')?card.querySelector('a'):card).append(badge);}badge.hidden=!played;const label=card.matches('.calendar-card')?card.querySelector('a'):card;const original=(label.getAttribute('aria-label')||'').replace(/ · Già giocata.*$/,'');label.setAttribute('aria-label',original+(played?' · Già giocata'+(progress.closed?'':' · Secondo tentativo disponibile'):''));});
    window.dispatchEvent(new Event('giapp:progress'));
  }
  function apply(rows,note=''){entries=new Map(rows.filter(r=>Number.isInteger(r.day)&&r.day>=1&&r.day<=24&&Number.isInteger(r.attempts)&&r.attempts>0).map(r=>[r.day,{attempts:r.attempts,closed:r.closed===true,best_score:r.best_score}]));ready=true;notice.textContent=note;paint();}
  async function refresh(){const token=++request;try{
    const response=await fetch({{ '/assets/registration-config.json' | relative_url | jsonify }},{cache:'no-store'});if(!response.ok)throw new Error('Configurazione non disponibile.');const config=await response.json();
    if(config.mode==='demo'){
      const id=read('giapp-demo-current-v1'),profile=read('giapp-demo-profiles-v1',[]).find(p=>p.id===id);if(!profile){if(token===request)apply([],'Entra con il tuo codice per riconoscere le giornate già giocate.');return;}
      const result=await fetch({{ '/assets/data/advent.json' | relative_url | jsonify }},{cache:'no-store'});if(!result.ok)throw new Error('Giornate non disponibili.');const data=await result.json(),all=read('giapp-demo-games-v2',{}),rows=data.days.flatMap(day=>{const progress=all[`${id}:${data.settings.year}:${day.day}:${day.challenge.version||'prototype-v1'}`];return progress?[{day:day.day,...progress}]:[];});if(token===request)apply(rows);return;
    }
    if(config.mode!=='supabase'||!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(config.url)||!config.key||config.key.startsWith('sb_secret_'))throw new Error('Configurazione non disponibile.');
    const key=`giapp-auth:${config.url}`;let session=read(key);if(!session){if(token===request)apply([],'Entra con il tuo codice per riconoscere le giornate già giocate.');return;}
    if(session.expires_at*1000<Date.now()+60000){const result=await fetch(`${config.url}/auth/v1/token?grant_type=refresh_token`,{method:'POST',headers:{apikey:config.key,'Content-Type':'application/json'},body:JSON.stringify({refresh_token:session.refresh_token})});if(!result.ok)throw new Error('Accedi di nuovo dal tuo account.');session=await result.json();session.expires_at||=Math.floor(Date.now()/1000)+(session.expires_in||3600);localStorage.setItem(key,JSON.stringify(session));}
    const result=await fetch(`${config.url}/rest/v1/rpc/calendar_progress`,{method:'POST',headers:{apikey:config.key,Authorization:`Bearer ${session.access_token}`,'Content-Type':'application/json'},body:'{}'});if(!result.ok)throw new Error('Non riesco a leggere le giornate già giocate. Riprova ricaricando la pagina.');const data=await result.json();if(data.error)throw new Error(data.error);if(token===request)apply(data.days||[],data.login_required?'Entra con il tuo codice per riconoscere le giornate già giocate.':'');
  }catch(error){if(token===request)notice.textContent=error.message;}}
  window.addEventListener('giapp:calendar',()=>{paint();refresh();});window.addEventListener('focus',refresh);window.addEventListener('pageshow',event=>{if(event.persisted)refresh();});
  window.addEventListener('storage',event=>{if(event.key===null||['giapp-demo-current-v1','giapp-demo-profiles-v1','giapp-demo-games-v2'].includes(event.key)||event.key?.startsWith('giapp-auth:')){entries=new Map();ready=false;paint();refresh();}});
  notice.textContent='Carico le giornate già giocate…';refresh();
})();
