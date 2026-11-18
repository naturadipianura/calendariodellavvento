---
---
(() => {
  'use strict';
  const settings=Object.freeze({{ site.data.advent | jsonify }});
  const dateParts=date=>Object.fromEntries(new Intl.DateTimeFormat('en',{timeZone:'Europe/Rome',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(date).map(part=>[part.type,part.value]));
  const todayKey=(date=new Date())=>{const p=dateParts(date);return `${p.year}-${p.month}-${p.day}`;};
  function opensOn(day,config=settings){const year=Number(config.year),month=Number(config.month??12);if(!Number.isInteger(day)||day<1||day>24||!Number.isInteger(year)||!Number.isInteger(month)||month<1||month>12)throw new Error('Data di apertura non valida.');return `${year}-${String(month).padStart(2,'0')}-${String(day).padStart(2,'0')}`;}
  function isOpen(day,config=settings,date=new Date()){return config.preview===true||todayKey(date)>=opensOn(day,config);}
  function formatDate(iso,year=true){if(!/^\d{4}-\d{2}-\d{2}$/.test(String(iso)))return String(iso||'');return new Intl.DateTimeFormat('it-IT',{timeZone:'Europe/Rome',day:'numeric',month:'long',...(year?{year:'numeric'}:{})}).format(new Date(iso+'T12:00:00Z'));}
  const dateLabel=(day,config=settings,year=false)=>formatDate(opensOn(day,config),year);
  window.GiappCalendar=Object.freeze({settings,todayKey,opensOn,isOpen,formatDate,dateLabel});
  const grid=document.querySelector('[data-leaf-grid]');
  function refreshGrid(){if(!grid)return;grid.querySelectorAll('.calendar-card').forEach((card,index)=>{const day=Number(card.dataset.calendarDay||index+1),open=isOpen(day),link=card.querySelector('a');card.classList.toggle('is-locked',!open);card.setAttribute('aria-label',dateLabel(day));link.setAttribute('aria-disabled',String(!open));link.setAttribute('aria-label',open?'Apri la giornata del '+dateLabel(day):'Si apre il '+dateLabel(day));link.title=open?'Apri la giornata':'Si apre il '+dateLabel(day);});}
  if(grid){const notice=document.createElement('p');notice.className='calendar-note';notice.setAttribute('role','status');grid.after(notice);grid.addEventListener('click',event=>{const card=event.target.closest('.calendar-card');if(!card)return;const day=Number(card.dataset.calendarDay||[...grid.children].indexOf(card)+1);if(!isOpen(day)){event.preventDefault();notice.textContent='La giornata si aprirà il '+dateLabel(day,settings,true)+'.';}else notice.textContent='';});refreshGrid();}
  let previous=todayKey();function tick(){const key=todayKey();if(key!==previous){previous=key;refreshGrid();window.dispatchEvent(new Event('giapp:calendar'));}}
  setInterval(tick,30000);window.addEventListener('focus',tick);document.addEventListener('visibilitychange',()=>{if(!document.hidden)tick();});
})();
