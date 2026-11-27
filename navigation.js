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
 const hero=document.querySelector('.hero'),auth=$('authPanel'),business=$('businessHub'),app=$('appPanel'),admin=$('adminPanel'),circle=$('circlePage');
 [hero,auth,business,app,admin,circle].forEach(el=>{if(el)el.hidden=true;});
 if(view==='home'){if(hero)hero.hidden=false;}
 else if(view==='join'){if(auth)auth.hidden=false;}
 else if(view==='about'){if(business){business.hidden=false;setBusinessMode('overview');}}
 else if(view==='circle'){if(!window.taskPulaHasSession){if(auth)auth.hidden=false;const m=$('authMessage');if(m)m.textContent='Sign in to manage your TaskPula Circle membership.';}else if(circle)circle.hidden=false;}
 else if(['tasks','progress','wallet','profile','dashboard','research','campaigns','growth','watch'].includes(view)){
   if(!window.taskPulaHasSession||!app){if(auth)auth.hidden=false;const m=$('authMessage');if(m)m.textContent='Sign in to access your personal TaskPula workspace.';}
   else{app.hidden=false;const target=view==='dashboard'?'dashboard':view;const map={dashboard:'memberHomePage',tasks:'tasksPage',progress:'progressPage',wallet:'walletPage',profile:'profilePage',research:'researchPage',campaigns:'campaignsPage',growth:'growthPage',watch:'watchPage'};app.querySelectorAll('.member-page').forEach(page=>{page.hidden=page.id!==map[target];});}
 }
 else if(view==='admin'){const entry=$('adminEntry');if(entry&&!entry.hidden&&admin)admin.hidden=false;else{if(auth)auth.hidden=false;const m=$('authMessage');if(m)m.textContent='Admin access requires an authorized staff account.';}}
 document.querySelectorAll('.command-item').forEach(b=>b.classList.toggle('selected',b.dataset.view===view));
 document.querySelectorAll('.bottom [data-nav]').forEach(b=>b.classList.toggle('active',b.dataset.nav===view));
 closeMenu();if(view==='watch')window.taskPulaLoadWatch?.();window.scrollTo({top:0,behavior:'smooth'});
}
function openMenu(){menu.classList.add('open');scrim.hidden=false;trigger.setAttribute('aria-expanded','true');menu.setAttribute('aria-hidden','false');document.body.classList.add('menu-open');close.focus();}
function closeMenu(){menu.classList.remove('open');scrim.hidden=true;trigger.setAttribute('aria-expanded','false');menu.setAttribute('aria-hidden','true');document.body.classList.remove('menu-open');}
trigger.addEventListener('click',openMenu);close.addEventListener('click',closeMenu);scrim.addEventListener('click',closeMenu);
menu.querySelectorAll('[data-view]').forEach(b=>b.addEventListener('click',()=>show(b.dataset.view)));
document.querySelectorAll('[data-open-view]').forEach(link=>link.addEventListener('click',e=>{e.preventDefault();show(link.dataset.openView);}));
document.querySelectorAll('[data-business-tab]').forEach(tab=>tab.addEventListener('click',()=>{
 const hub=$('businessHub');if(!hub)return;
 const chosen=tab.dataset.businessTab;
 hub.querySelectorAll('[data-business-panel]').forEach(panel=>{panel.hidden=panel.dataset.businessPanel!==chosen;});
 hub.querySelectorAll('[data-business-tab]').forEach(item=>{
   const active=item===tab;item.classList.toggle('active',active);item.setAttribute('aria-selected',String(active));
 });
}));
document.addEventListener('keydown',e=>{if(e.key==='Escape')closeMenu();});
document.querySelectorAll('.bottom [data-nav]').forEach(b=>b.addEventListener('click',()=>show(b.dataset.nav)));
document.querySelectorAll('[data-module-link]').forEach(b=>b.addEventListener('click',()=>show(b.dataset.moduleLink)));\nwindow.taskPulaNavigate=show;
})();
