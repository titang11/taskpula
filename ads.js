(function(){
'use strict';
const db=window.taskPulaSupabase;
const $=id=>document.getElementById(id);
const box=$('adCarousel'),link=$('adSlideLink'),img=$('adSlideImage'),title=$('adSlideTitle'),advertiser=$('adSlideAdvertiser'),dots=$('adDots');
if(!db||!box||!link)return;
let items=[],index=0,timer=null;
function draw(){
 if(!items.length){box.hidden=true;return;}
 const ad=items[index];db.rpc('track_banner_ad_event',{p_ad_id:ad.id,p_event:'impression'}).then(()=>{}).catch(()=>{});const file=db.storage.from('taskpula-ads').getPublicUrl(ad.image_path);
 let destination='';try{const u=new URL(ad.destination_url);if(u.protocol!=='https:')throw new Error();destination=u.href;}catch(_){box.hidden=true;return;}
 img.src=file.data.publicUrl;img.alt=ad.title+' advertisement';title.textContent=ad.title;advertiser.textContent=ad.advertiser_name;link.href=destination;link.onclick=()=>{db.rpc('track_banner_ad_event',{p_ad_id:ad.id,p_event:'click'}).then(()=>{}).catch(()=>{});};
 dots.innerHTML=items.map((_,i)=>'<span class="'+(i===index?'active':'')+'" aria-hidden="true"></span>').join('');
 box.hidden=false;
}
async function init(){
 try{
 const now=new Date().toISOString();
 const r=await db.from('advertisements').select('id,advertiser_name,title,image_path,destination_url,starts_at,ends_at,display_order').eq('status','active').in('payment_status',['paid','waived']).or('starts_at.is.null,starts_at.lte.'+now).or('ends_at.is.null,ends_at.gt.'+now).order('display_order').order('created_at',{ascending:false});
 if(r.error)throw r.error;
 items=(r.data||[]).filter(a=>a.image_path&&/^https:\/\//i.test(a.destination_url||''));
 if(!items.length){box.hidden=true;return;}
 index=0;draw();
 if(timer)clearInterval(timer);
 if(items.length>3)timer=setInterval(()=>{index=(index+1)%items.length;draw();},3000);
 }catch(e){console.warn('TaskPula ads could not load:',e.message);box.hidden=true;}
}
document.addEventListener('visibilitychange',()=>{if(document.hidden&&timer){clearInterval(timer);timer=null;}else if(!document.hidden&&items.length>3&&!timer){timer=setInterval(()=>{index=(index+1)%items.length;draw();},3000);}});
init();
})();