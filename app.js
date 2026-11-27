(function () {
  'use strict';
  const SUPABASE_URL = 'https://vmzsjkoandjqlzjvckqj.supabase.co';
  const SUPABASE_KEY = 'sb_publishable_7JZSxUeUm6nO2VQA16Wnkw_Oo_gxvhZ';
  const EVIDENCE_BUCKET = 'task-evidence';
  const client = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
  // Share one Supabase client across the member app and admin dashboard.
  window.taskPulaSupabase = client;
  const $ = id => document.getElementById(id);
  const money = n => 'P ' + Number(n || 0).toFixed(2);
  const safe = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let mode = 'login', recoveryMode = false, currentUser = null, tasks = [], submissions = [], transactions = [], profile = null, filter = 'all';
  function toast(message) { $('toast').textContent = message; $('toast').classList.add('show'); window.setTimeout(() => $('toast').classList.remove('show'), 2600); }
  function authMessage(message, error) { $('authMessage').textContent = message; $('authMessage').classList.toggle('error', !!error); }
  function setMode(next) {
    recoveryMode = false; $('loginTab').hidden = false; $('signupTab').hidden = false; $('password').placeholder = ''; mode = next; $('loginTab').classList.toggle('active', mode === 'login'); $('signupTab').classList.toggle('active', mode === 'signup'); $('forgotPassword').hidden = mode !== 'login';
    $('nameField').hidden = mode !== 'signup'; $('displayName').required = mode === 'signup';
    $('authSubmit').textContent = mode === 'login' ? 'Sign in' : 'Create account';
    $('password').autocomplete = mode === 'login' ? 'current-password' : 'new-password';
    authMessage(mode === 'login' ? 'Sign in to access live tasks and your wallet.' : 'Create your free TaskPula account with an email address.');
  }
  $('loginTab').addEventListener('click', () => setMode('login'));
  $('signupTab').addEventListener('click', () => setMode('signup'));
  $('forgotPassword').addEventListener('click', async () => {
    const email = $('email').value.trim().toLowerCase();
    if (!email) { authMessage('Enter your email address first, then choose Forgot password.', true); $('email').focus(); return; }
    const button = $('forgotPassword'); button.disabled = true; button.textContent = 'Sending reset link…';
    try {
      const result = await client.auth.resetPasswordForEmail(email, { redirectTo: window.location.origin + window.location.pathname });
      if (result.error) throw result.error;
      authMessage('If an account exists for ' + email + ', a password reset link has been sent. Open it on this device, then enter your new password here.');
    } catch (error) { authMessage(error.message || 'Could not send the reset email. Please try again.', true); }
    finally { button.disabled = false; button.textContent = 'Forgot password?'; }
  });
  $('authForm').addEventListener('submit', async event => {
    event.preventDefault();
    const email = $('email').value.trim().toLowerCase(), password = $('password').value, name = $('displayName').value.trim(), button = $('authSubmit');
    button.disabled = true; button.textContent = mode === 'login' ? 'Signing in…' : 'Creating account…';
    try {
      if (recoveryMode) {
        const result = await client.auth.updateUser({password});
        if (result.error) throw result.error;
        recoveryMode = false; $('password').value = ''; $('password').placeholder = '';
        $('loginTab').hidden = false; $('signupTab').hidden = false; setMode('login');
        authMessage('Your password has been updated. You can now sign in with your new password.');
      } else if (mode === 'signup') {
        const redirect = window.location.origin + window.location.pathname;
        const result = await client.auth.signUp({email, password, options:{data:{display_name:name},emailRedirectTo:redirect}});
        if (result.error) throw result.error;
        if (result.data.session) { currentUser = result.data.user; await showApp(); }
        else { setMode('login'); $('email').value = email; authMessage('Account created. Check ' + email + ' for the confirmation link, then return here to sign in.'); }
      } else {
        const result = await client.auth.signInWithPassword({email,password});
        if (result.error) throw result.error;
        currentUser = result.data.user; await showApp();
      }
    } catch (error) { authMessage(error.message || 'Unable to complete authentication. Please try again.', true); }
    finally { button.disabled = false; button.textContent = mode === 'login' ? 'Sign in' : 'Create account'; }
  });
  async function loadData() {
    const uid = currentUser.id;
    const results = await Promise.all([
      client.from('profiles').select('display_name,phone').eq('id',uid).maybeSingle(),
      client.from('tasks').select('id,title,description,category,reward_amount,currency,instructions,proof_requirements,ends_at').eq('status','active').order('created_at',{ascending:false}),
      client.from('task_submissions').select('id,task_id,status,created_at,note,rejection_reason').eq('user_id',uid).order('created_at',{ascending:false}),
      client.from('wallet_transactions').select('id,amount,currency,transaction_type,description,created_at').eq('user_id',uid).order('created_at',{ascending:false})
    ]);
    results.forEach(r => { if (r.error) throw r.error; });
    profile = results[0].data; tasks = results[1].data || []; submissions = results[2].data || []; transactions = results[3].data || [];
  }
  async function showApp() {
    $('authPanel').hidden = true; $('appPanel').hidden = false; window.taskPulaHasSession = true;
    try { await loadData(); render(); window.taskPulaNavigate?.('dashboard'); } catch (error) { toast(error.message || 'Could not load your account data.'); }
  }
  function render() {
    $('balance').textContent = money(transactions.reduce((sum,item) => sum + Number(item.amount || 0),0));
    $('submitted').textContent = submissions.length;
    $('pending').textContent = submissions.filter(x => x.status === 'pending').length;
    $('approved').textContent = submissions.filter(x => x.status === 'approved').length;
    renderTasks(); renderMemberPages();
  }
  function renderMemberPages() {
    const walletRows=transactions.map(item=>'<div class="history-item"><span><b>'+safe(item.description||item.transaction_type)+'</b><br><small>'+new Date(item.created_at).toLocaleDateString()+'</small></span><b>'+(Number(item.amount)>0?'+':'')+money(item.amount)+'</b></div>').join('');
    $('walletActivity').innerHTML=walletRows||'<div class="empty">No wallet transactions yet.</div>';
    const progressRows=submissions.map(item=>{const task=tasks.find(t=>t.id===item.task_id);return '<div class="history-item"><span><b>'+safe(task?task.title:'Task submission')+'</b><br><small>'+new Date(item.created_at).toLocaleDateString()+(item.rejection_reason?' · '+safe(item.rejection_reason):'')+'</small></span><i class="status">'+safe(item.status)+'</i></div>';}).join('');
    $('submissionHistory').innerHTML=progressRows||'<div class="empty">You have not submitted any activities yet.</div>';
    $('profilePageBody').innerHTML='<div class="profile-summary"><div class="profile-avatar">♙</div><div><p class="eyebrow">TASKPULA ACCOUNT</p><h3>'+safe(profile&&profile.display_name||currentUser.email)+'</h3><p class="subtle">'+safe(currentUser.email)+'</p></div></div><div class="profile-details"><div><small>Display name</small><b>'+safe(profile&&profile.display_name||'Not set')+'</b></div><div><small>Phone</small><b>'+safe(profile&&profile.phone||'Not provided')+'</b></div></div><button class="primary profile-signout" id="signOutBtn" type="button">Sign out</button>';
    $('signOutBtn').addEventListener('click',async()=>{const result=await client.auth.signOut();if(result.error){toast(result.error.message);return;}currentUser=null;window.taskPulaHasSession=false;$('appPanel').hidden=true;$('circlePage').hidden=true;$('authPanel').hidden=false;window.taskPulaNavigate?.('join');authMessage('You have signed out.');});
  }
  function renderTasks() {
    const root = $('taskCards'), visible = tasks.filter(t => filter === 'all' || t.category === filter);
    root.innerHTML = '';
    if (!visible.length) { root.innerHTML = '<div class="empty">No live tasks are available in this category yet. Check again later.</div>'; return; }
    visible.forEach(task => {
      const card = document.createElement('article'); card.className = 'task-card';
      const icon = task.category === 'shopping' ? '🛒' : task.category === 'survey' ? '📝' : '🎁';
      card.innerHTML = '<div class="task-thumb">' + icon + '</div><div class="task-info"><span class="task-tag">' + safe(task.category) + ' · BWP</span><h3>' + safe(task.title) + '</h3><p>' + safe(task.description || '') + '</p><div class="task-bottom"><span class="reward">+' + money(task.reward_amount) + '</span><button class="smallbtn" type="button">View task</button></div></div>';
      card.querySelector('button').addEventListener('click', () => openTask(task.id)); root.appendChild(card);
    });
  }
  document.querySelectorAll('.filter').forEach(button => button.addEventListener('click', () => {
    document.querySelectorAll('.filter').forEach(item => item.classList.remove('active')); button.classList.add('active'); filter = button.dataset.filter; renderTasks();
  }));
  function openTask(id) {
    const task = tasks.find(item => item.id === id); if (!task) return;
    const exists = submissions.some(item => item.task_id === id && item.status !== 'rejected');
    $('taskModalBody').innerHTML = '<div class="modal-content"><p class="eyebrow">' + safe(task.category) + ' TASK</p><h2>' + safe(task.title) + '</h2><p>' + safe(task.description || '') + '</p><div class="notice"><b>Instructions</b><br>' + safe(task.instructions || 'Complete the task as described by the sponsor.') + '<br><br><b>Evidence required</b><br>' + safe(task.proof_requirements || 'Upload a clear photo of your evidence.') + '<br><br><b>Reward:</b> ' + money(task.reward_amount) + ' after approval.</div>' +
      (exists ? '<p class="notice">You already have a submission for this task. Check your profile for its review status.</p>' :
      '<form id="proofForm"><label class="formlabel" for="proofNote">Note (optional)</label><textarea class="textarea" id="proofNote" maxlength="1000"></textarea><label class="formlabel" for="proofFile">Evidence photo</label><input class="input" id="proofFile" type="file" accept="image/jpeg,image/png,image/webp" capture="environment" required><p class="subtle">Private upload · JPEG, PNG or WebP · maximum 3 MB. Avoid sensitive documents.</p><button class="primary" id="proofSubmit">Submit proof for review</button></form>') + '</div>';
    $('taskModal').showModal(); if (!exists) $('proofForm').addEventListener('submit', event => submitProof(event,task));
  }
  async function submitProof(event,task) {
    event.preventDefault(); const file = $('proofFile').files[0]; if (!file) return;
    if (!['image/jpeg','image/png','image/webp'].includes(file.type)) { toast('Use a JPEG, PNG or WebP image.'); return; }
    if (file.size > 3*1024*1024) { toast('Evidence must be 3 MB or smaller.'); return; }
    const button = $('proofSubmit'); button.disabled = true; button.textContent = 'Uploading securely…';
    const sid = crypto.randomUUID(), ext = file.type === 'image/jpeg' ? 'jpg' : file.type === 'image/png' ? 'png' : 'webp', path = currentUser.id + '/' + sid + '.' + ext;
    try {
      const upload = await client.storage.from(EVIDENCE_BUCKET).upload(path,file,{contentType:file.type,upsert:false}); if (upload.error) throw upload.error;
      const insert = await client.from('task_submissions').insert({id:sid,task_id:task.id,user_id:currentUser.id,evidence_path:path,note:$('proofNote').value.trim()});
      if (insert.error) throw insert.error;
      $('taskModal').close(); await loadData(); render(); toast('Evidence submitted. Awaiting review.');
    } catch (error) { button.disabled = false; button.textContent = 'Try submission again'; toast(error.message || 'Submission failed. Please try again.'); }
  }
  function openWallet(){window.taskPulaNavigate?.('wallet');}
  function openProfile(){window.taskPulaNavigate?.('profile');}
  $('walletBtn')?.addEventListener('click',openWallet);
  $('profileBtn').addEventListener('click',()=>{if(currentUser)openProfile();else window.taskPulaNavigate?.('join');});
  $('refreshTasks').addEventListener('click',async()=>{try{await loadData();render();toast('Tasks and account activity refreshed.');}catch(error){toast(error.message||'Refresh failed.');}});
  client.auth.onAuthStateChange((event,session)=>{window.setTimeout(async()=>{
    if (event === 'PASSWORD_RECOVERY') {
      recoveryMode = true; currentUser = session?.user || null;
      $('appPanel').hidden = true; $('authPanel').hidden = false;
      $('loginTab').hidden = true; $('signupTab').hidden = true; $('nameField').hidden = true;
      $('password').value = ''; $('password').placeholder = 'Enter your new password'; $('password').autocomplete = 'new-password';
      $('authSubmit').textContent = 'Save new password'; $('forgotPassword').hidden = true;
      authMessage('Choose a new password with at least 8 characters, then tap Save new password.');
      return;
    }
    currentUser=session?session.user:null;
    if(currentUser) await showApp();
    else {$('appPanel').hidden=true;$('authPanel').hidden=false;}
  },0);});
  client.auth.getSession().then(({data,error})=>{if(error){authMessage(error.message,true);return;}currentUser=data.session?data.session.user:null;window.taskPulaHasSession=!!currentUser;if(currentUser)showApp();else setMode('login');});
  if('serviceWorker' in navigator&&location.protocol==='https:')navigator.serviceWorker.register('./sw.js').catch(()=>{});
})();