(function(){
'use strict';
const db=window.taskPulaSupabase;
const $=id=>document.getElementById(id);
const box=$('adCarousel'),link=$('adSlideLink'),img=$('adSlideImage'),title=$('adSlideTitle'),advertiser=$('adSlideAdvertiser'),dots=$('adDots');
if(!db||!box||!link)return;
let items=[],index=0,timer=null,viewTimer=null,isViewable=false;
const counted=new Set();
function clearViewTimer(){if(viewTimer){clearTimeout(viewTimer);viewTimer=null;}}
function recordViewableImpression(ad){
 if(!ad||counted.has(ad.id)||document.visibilityState!=='visible'||!isViewable)return;
 clearViewTimer();
 viewTimer=setTimeout(()=>{
  viewTimer=null;
  if(document.visibilityState!=='visible'||!isViewable||items[index]?.id!==ad.id||counted.has(ad.id))return;
  counted.add(ad.id);
  db.functions.invoke('taskpula-banner-track',{body:{ad_id:ad.id,event:'impression',viewable_ms:1000}})
   .then(({error})=>{if(error)counted.delete(ad.id);})
   .catch(()=>counted.delete(ad.id));
 },1000);
}
const observer='IntersectionObserver' in window?new IntersectionObserver(entries=>{
 const entry=entries[0];
 isViewable=!!entry&&entry.isIntersecting&&entry.intersectionRatio>=0.5;
 if(!isViewable)clearViewTimer();
 else recordViewableImpression(items[index]);
},{threshold:[0,0.5,1]}):null;
if(observer)observer.observe(box);
function draw(){
 if(!items.length){box.hidden=true;clearViewTimer();return;}
 const ad=items[index];
 const file=db.storage.from('taskpula-ads').getPublicUrl(ad.image_path);
 let destination='';
 try{const u=new URL(ad.destination_url);if(u.protocol!=='https:')throw new Error();destination=u.href;}
 catch(_){box.hidden=true;clearViewTimer();return;}
 img.src=file.data.publicUrl;img.alt=ad.title+' advertisement';
 title.textContent=ad.title;advertiser.textContent=ad.advertiser_name;
 link.href=destination;
 link.onclick=()=>{db.functions.invoke('taskpula-banner-track',{body:{ad_id:ad.id,event:'click',viewable_ms:0}}).catch(()=>{});};
 dots.innerHTML=items.map((_,i)=>'<span class="'+(i===index?'active':'')+'" aria-hidden="true"></span>').join('');
 box.hidden=false;
 if(isViewable)recordViewableImpression(ad);
}
async function init(){
 try{
  const now=new Date().toISOString();
  const r=await db.from('advertisements').select('id,advertiser_name,title,image_path,destination_url,starts_at,ends_at,display_order')
   .eq('status','active').in('payment_status',['paid','waived'])
   .or('starts_at.is.null,starts_at.lte.'+now).or('ends_at.is.null,ends_at.gt.'+now)
   .order('display_order').order('created_at',{ascending:false});
  if(r.error)throw r.error;
  items=(r.data||[]).filter(a=>a.image_path&&/^https:\/\//i.test(a.destination_url||''));
  if(!items.length){box.hidden=true;return;}
  index=0;draw();
  if(timer)clearInterval(timer);
  if(items.length>3)timer=setInterval(()=>{index=(index+1)%items.length;draw();},3000);
 }catch(e){console.warn('TaskPula ads could not load:',e.message);box.hidden=true;}
}
document.addEventListener('visibilitychange',()=>{
 if(document.hidden){clearViewTimer();if(timer){clearInterval(timer);timer=null;}}
 else{
  if(isViewable)recordViewableImpression(items[index]);
  if(items.length>3&&!timer)timer=setInterval(()=>{index=(index+1)%items.length;draw();},3000);
 }
});
init();
})();