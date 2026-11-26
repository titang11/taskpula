(function(){
'use strict';
const $=id=>document.getElementById(id);
const trigger=$('menuTrigger'),menu=$('commandMenu'),scrim=$('menuScrim'),close=$('menuClose');
if(!trigger||!menu||!scrim)return;
const topViews=['hero','authPanel','businessHub','appPanel','adminPanel'];
function setBusinessMode(mode){
 const hub=$('businessHub');if(!hub)return;
 const chosen=mode==='circle'?'circle':'overview';
 hub.querySelectorAll('[data-business-panel]').forEach(panel=>{panel.hidden=panel.dataset.businessPanel!==chosen;});
 hub.querySelectorAll('[data-business-tab]').forEach(tab=>{
   const active=tab.dataset.businessTab===chosen;
   tab.classList.toggle('active',active);tab.setAttribute('aria-selected',String(active));
 });
}
function show(view){
 const dashboardAvailable=!$('appPanel')?.hidden;
 const hero=document.querySelector('.hero'),auth=$('authPanel'),business=$('businessHub'),app=$('appPanel'),admin=$('adminPanel');
 topViews.forEach(id=>{const el=id==='hero'?hero:$(id);if(el)el.hidden=true;});
 if(view==='home'){hero.hidden=false;}
 if(view==='join'){auth.hidden=false;}
 if(view==='business'){business.hidden=false;setBusinessMode('all');}
 if(view==='circle'){business.hidden=false;setBusinessMode('circle');}
 if(view==='dashboard'){
   if(dashboardAvailable){app.hidden=false;}else{auth.hidden=false;document.getElementById('authMessage').textContent='Sign in to open your personal dashboard.';}
 }
 if(view==='admin'){
   const entry=$('adminEntry');
   if(entry&&!entry.hidden&&admin){admin.hidden=false;}else{auth.hidden=false;document.getElementById('authMessage').textContent='Admin access requires an authorized staff account.';}
 }
 document.querySelectorAll('.command-item').forEach(b=>b.classList.toggle('selected',b.dataset.view===view));
 closeMenu();
 window.scrollTo({top:0,behavior:'smooth'});
}
function openMenu(){menu.classList.add('open');scrim.hidden=false;trigger.setAttribute('aria-expanded','true');menu.setAttribute('aria-hidden','false');document.body.classList.add('menu-open');close.focus();}
function closeMenu(){menu.classList.remove('open');scrim.hidden=true;trigger.setAttribute('aria-expanded','false');menu.setAttribute('aria-hidden','true');document.body.classList.remove('menu-open');}
trigger.addEventListener('click',openMenu);close.addEventListener('click',closeMenu);scrim.addEventListener('click',closeMenu);
menu.querySelectorAll('[data-view]').forEach(b=>b.addEventListener('click',()=>show(b.dataset.view)));
document.querySelectorAll('[data-business-tab]').forEach(tab=>tab.addEventListener('click',()=>{
 const hub=$('businessHub');if(!hub)return;
 const chosen=tab.dataset.businessTab;
 hub.querySelectorAll('[data-business-panel]').forEach(panel=>{panel.hidden=panel.dataset.businessPanel!==chosen;});
 hub.querySelectorAll('[data-business-tab]').forEach(item=>{
   const active=item===tab;item.classList.toggle('active',active);item.setAttribute('aria-selected',String(active));
 });
}));
document.addEventListener('keydown',e=>{if(e.key==='Escape')closeMenu();});
document.querySelectorAll('.bottom [data-nav]').forEach(b=>b.addEventListener('click',()=>{
 const view=b.dataset.nav;
 if(view==='home')show('home');
 else if(view==='tasks')show('dashboard');
 else if(view==='wallet'){show('dashboard');setTimeout(()=>$('walletBtn')?.click(),80);}
 else if(view==='profile')$('profileBtn')?.click();
}));
window.taskPulaNavigate=show;
})();
