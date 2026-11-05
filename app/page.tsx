'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import {createClient,type SupabaseClient,type User} from '@supabase/supabase-js';

import {credentialNext,httpsEvidence,canUpload} from '../lib/workflow';

type Workspace={id:string;name:string;slug:string};
type Member={workspace_id:string;user_id:string;role:'owner'|'editor'|'contributor'|'viewer'};
type Assignment={id:string;workspace_id:string;title:string;sport:string;venue:string;event_at:string|null;deadline_at:string|null;brief:string;assigned_to:string|null;created_by:string;status:string;credential_status:string;created_at:string};
type Credential={id:string;assignment_id:string;workspace_id:string;contact_name:string;contact_email:string;request_notes:string;status:string;approval_at:string|null;proof_url:string};
type Submission={id:string;assignment_id:string;workspace_id:string;uploaded_by:string;title:string;notes:string;rights_attested:boolean;status:string;created_at:string};
type Asset={id:string;submission_id:string;workspace_id:string;storage_path:string;original_name:string;mime_type:string;bytes:number;caption:string;review_status:string;rights_status:string;rights_note:string};
type AccessRequest={id:string;workspace_id:string;user_id:string;email:string;requested_role:string;status:string;created_at:string};
type Section='overview'|'assignments'|'credentials'|'submissions'|'people';
const assignmentStatuses=['requested','approved','assigned','in_progress','review','completed','declined'];
const icon:Record<Section,string>={overview:'◫',assignments:'▦',credentials:'◈',submissions:'▧',people:'♙'};
const pretty=(s:string)=>s.replace(/_/g,' ').replace(/\b\w/g,c=>c.toUpperCase());
const date=(s?:string|null)=>s?new Date(s).toLocaleString('en-US',{month:'short',day:'numeric',year:'numeric',hour:'numeric',minute:'2-digit'}):'Not scheduled';
const initialDraft={title:'',sport:'',venue:'',event_at:'',deadline_at:'',brief:'',assigned_to:''};
function errorText(e:unknown){return e&&typeof e==='object'&&'message' in e?String(e.message):String(e)}
export default function Home(){
 const [client,setClient]=useState<SupabaseClient|null>(null);
 const [user,setUser]=useState<User|null>(null);
 const [loading,setLoading]=useState(true);
 const [busy,setBusy]=useState(false);
 const [notice,setNotice]=useState('');
 const [workspaces,setWorkspaces]=useState<Workspace[]>([]);
 const [members,setMembers]=useState<Member[]>([]);
 const [workspace,setWorkspace]=useState('');
 const [section,setSection]=useState<Section>('overview');
 const [assignments,setAssignments]=useState<Assignment[]>([]);
 const [credentials,setCredentials]=useState<Credential[]>([]);
 const [submissions,setSubmissions]=useState<Submission[]>([]);
 const [assets,setAssets]=useState<Asset[]>([]);
 const [requests,setRequests]=useState<AccessRequest[]>([]);
 const [ownRequests,setOwnRequests]=useState<AccessRequest[]>([]);
 const [dataLoading,setDataLoading]=useState(false);
 const fetchSequence=useRef(0);
 const [newAssignment,setNewAssignment]=useState(false);
 const [draft,setDraft]=useState(initialDraft);
 const [credentialFor,setCredentialFor]=useState('');
 const [credentialDraft,setCredentialDraft]=useState({contact_name:'',contact_email:'',request_notes:''});
 const [submissionFor,setSubmissionFor]=useState('');
 const [submissionDraft,setSubmissionDraft]=useState({title:'',notes:'',rights_attested:false});
 const [fileFor,setFileFor]=useState('');
 const [uploadFiles,setUploadFiles]=useState<File[]>([]);
 const [rightsNotes,setRightsNotes]=useState<Record<string,string>>({});
 useEffect(()=>{
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if(!url||!key){setNotice('Setup required: RUNCTRL database environment is not configured.');setLoading(false);return;}
  const sb=createClient(url,key);
  setClient(sb);
  sb.auth.getUser().then(({data,error})=>{if(error&&error.name!=='AuthSessionMissingError')setNotice(error.message);setUser(data.user??null);setLoading(false)}).catch(e=>{setNotice(errorText(e));setLoading(false)});
  const {data:{subscription}}=sb.auth.onAuthStateChange((_event,session)=>setUser(session?.user??null));
  return()=>subscription.unsubscribe();
 },[]);
 const load=useCallback(async()=>{
  if(!client||!user)return;
  const [w,m,r]=await Promise.all([
   client.from('rc_workspaces').select('id,name,slug').order('name'),
   client.from('rc_members').select('workspace_id,user_id,role'),
   client.from('rc_access_requests').select('*').eq('user_id',user.id)
  ]);
  if(w.error)throw w.error;
  if(m.error)throw m.error;
  if(r.error)throw r.error;
  setOwnRequests((r.data??[]) as AccessRequest[]);
  setWorkspaces((w.data??[]) as Workspace[]);
  const ms=(m.data??[]) as Member[];
  setMembers(ms);
  setWorkspace(prev=>ms.some(m=>m.workspace_id===prev&&m.user_id===user.id)?prev:(ms.find(m=>m.user_id===user.id)?.workspace_id??''));
 },[client,user]);
 useEffect(()=>{setWorkspaces([]);setMembers([]);setWorkspace('');setOwnRequests([]);setRequests([]);setAssignments([]);setAssets([]);setSubmissions([]);setCredentials([])},[user?.id]);
 useEffect(()=>{load().catch(e=>setNotice(errorText(e)))},[load]);
 const myRole=members.find(m=>m.workspace_id===workspace&&m.user_id===user?.id)?.role;
 const isEditor=myRole==='owner'||myRole==='editor';
 const isOwner=myRole==='owner';
 const activeWorkspace=workspaces.find(w=>w.id===workspace);
 const fetchWorkspace=useCallback(async()=>{
  if(!client||!workspace||!myRole)return;
  const sequence=++fetchSequence.current;
  setDataLoading(true);
  const [a,c,s,x,r]=await Promise.all([
   client.from('rc_assignments').select('*').eq('workspace_id',workspace).order('created_at',{ascending:false}),
   client.from('rc_credentials').select('*').eq('workspace_id',workspace),
   client.from('rc_submissions').select('*').eq('workspace_id',workspace).order('created_at',{ascending:false}),
   client.from('rc_assets').select('*').eq('workspace_id',workspace),
   client.from('rc_access_requests').select('*').eq('workspace_id',workspace).order('created_at',{ascending:false})
  ]);
  if(sequence!==fetchSequence.current)return;
  setDataLoading(false);
  for(const item of [a,c,s,x,r])if(item.error)throw item.error;
  setAssignments((a.data??[]) as Assignment[]);
  setCredentials((c.data??[]) as Credential[]);
  setSubmissions((s.data??[]) as Submission[]);
  setAssets((x.data??[]) as Asset[]);
  setRequests((r.data??[]) as AccessRequest[]);
 },[client,workspace,myRole]);
 useEffect(()=>{setAssignments([]);setCredentials([]);setSubmissions([]);setAssets([]);setRequests([]);setDraft(initialDraft);setNewAssignment(false);setCredentialFor('');setSubmissionFor('');setUploadFiles([]);setFileFor('');setRightsNotes({});if(myRole)fetchWorkspace().catch(e=>{setDataLoading(false);setNotice(errorText(e))});return()=>{fetchSequence.current++}},[fetchWorkspace,myRole]);
 async function act(fn:()=>Promise<void>,message:string){setBusy(true);setNotice('');try{await fn();setNotice(message);await load();await fetchWorkspace()}catch(e){setNotice(errorText(e))}finally{setBusy(false)}}
 async function signIn(){
  if(!client)return;
  setBusy(true);setNotice('');
  try{
   const response=await fetch(process.env.NEXT_PUBLIC_SUPABASE_URL+'/auth/v1/settings',{headers:{apikey:process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!}});
   if(!response.ok)throw new Error('Sign-in is temporarily unavailable. Please try again later.');
   const settings=await response.json();
   if(!settings.external?.google)throw new Error('Google sign-in is not available yet. Contact your workspace owner.');
   const {error}=await client.auth.signInWithOAuth({provider:'google',options:{redirectTo:window.location.origin+'/'}});if(error)throw error;
  }catch(e){setNotice(errorText(e))}finally{setBusy(false)}
 }
 async function requestAccess(w:Workspace){
  if(!client||!user?.email||!user.id)return;
  await act(async()=>{const {error}=await client.from('rc_access_requests').insert({workspace_id:w.id,user_id:user.id,email:user.email,requested_role:'contributor',status:'pending'});if(error)throw error},'Request recorded for administrator review.');
 }
 async function createAssignment(){
  if(!client||!user||!workspace)return;
  const title=draft.title.trim();
  if(title.length<3){setNotice('Assignment title must have at least three characters.');return}
  await act(async()=>{
   const payload={workspace_id:workspace,title,sport:draft.sport.trim(),venue:draft.venue.trim(),brief:draft.brief.trim(),event_at:draft.event_at?new Date(draft.event_at).toISOString():null,deadline_at:draft.deadline_at?new Date(draft.deadline_at).toISOString():null,assigned_to:isEditor?(draft.assigned_to||null):user.id,status:isEditor?'approved':'requested',credential_status:'not_requested',created_by:user.id};
   const {error}=await client.from('rc_assignments').insert(payload);if(error)throw error;
   setDraft(initialDraft);setNewAssignment(false);
  },isEditor?'Assignment created.':'Assignment request submitted for review.');
 }
 async function assignmentStatus(a:Assignment,status:string){
  if(!client||!isEditor)return;
  await act(async()=>{const {error}=await client.from('rc_assignments').update({status}).eq('id',a.id).eq('workspace_id',workspace).select('id').single();if(error)throw error},'Assignment status updated.');
 }
 async function credentialCreate(a:Assignment){
  if(!client||!isEditor)return;
  await act(async()=>{
   const existing=credentials.find(c=>c.assignment_id===a.id);
   const result=existing?await client.from('rc_credentials').update(credentialDraft).eq('id',existing.id).eq('workspace_id',workspace).select('id').single():await client.from('rc_credentials').insert({assignment_id:a.id,workspace_id:workspace,...credentialDraft,status:'draft'});if(result.error)throw result.error;
   setCredentialFor('');setCredentialDraft({contact_name:'',contact_email:'',request_notes:''});
  },'Credential draft saved. Nothing was sent.');
 }
 async function credentialStatus(c:Credential,status:string){
  if(!client||!isEditor)return;
  if(!credentialNext(c.status,isOwner).includes(status))return;
  let proof_url=c.proof_url;
  if(['sent','granted','denied'].includes(status)){
   const answer=window.prompt(status==='sent'?'Paste the HTTPS link proving this authorized request was already sent. RUNCTRL sends no email.':'Paste the HTTPS link to the written credential decision:',c.proof_url||'');
   if(!answer)return;
   proof_url=answer.trim();
   if(!httpsEvidence(proof_url)){setNotice('Use a valid HTTPS evidence link.');return;}
  }
  await act(async()=>{const {error}=await client.from('rc_credentials').update({status,proof_url}).eq('id',c.id).eq('workspace_id',workspace).select('id').single();if(error)throw error},'Credential record updated. No email was sent.');
 }
 async function submitPackage(a:Assignment){
  if(!client||!user||!submissionDraft.rights_attested)return;
  await act(async()=>{
   const {error}=await client.from('rc_submissions').insert({assignment_id:a.id,workspace_id:workspace,uploaded_by:user.id,title:submissionDraft.title.trim()||a.title,notes:submissionDraft.notes,rights_attested:true,status:'submitted'});if(error)throw error;
   setSubmissionFor('');setSubmissionDraft({title:'',notes:'',rights_attested:false});
  },'Submission package created. Upload your files before editor review.');
 }
 async function upload(s:Submission){
  if(!client||!user||!uploadFiles.length)return;
  await act(async()=>{
   for(const f of uploadFiles){
    if(f.size===0)throw new Error('Empty file: '+f.name);
    if(f.size>50000000)throw new Error(f.name+' exceeds the 50 MB per-file limit. Use a dedicated large-file delivery workflow.');
    if(!(/^(image\/(jpeg|png|webp|tiff)|video\/(mp4|quicktime))$/.test(f.type)))throw new Error('Unsupported media type: '+f.name);
    const sanitized=f.name.replace(/[^a-zA-Z0-9._-]/g,'_');
    const path=[workspace,user.id,s.id,crypto.randomUUID()+'_'+sanitized].join('/');
    const uploaded=await client.storage.from('runctrl-media').upload(path,f,{contentType:f.type,upsert:false});
    if(uploaded.error)throw uploaded.error;
    const {error}=await client.from('rc_assets').insert({submission_id:s.id,workspace_id:workspace,uploader_id:user.id,storage_path:path,original_name:f.name,mime_type:f.type,bytes:f.size});
    if(error){const cleanup=await client.storage.from('runctrl-media').remove([path]);throw new Error('File registration failed for '+f.name+'. '+(cleanup.error?'An unregistered upload remains for administrator recovery. ': 'The unregistered upload was removed. ')+error.message);}
   }
   setUploadFiles([]);setFileFor('');
  },'Media uploaded to private storage. Editor review required.');
 }
 async function assetReview(a:Asset,status:'approved'|'rejected'){
  if(!client||!isEditor)return;
  const note=(rightsNotes[a.id]??a.rights_note).trim();
  if(status==='approved'&&note.length<8){setNotice('Provide supporting rights clearance notes (at least eight characters).');return;}
  await act(async()=>{
   const {error}=await client.from('rc_assets').update({review_status:status,rights_status:status==='approved'?'cleared':'restricted',rights_note:note}).eq('id',a.id).eq('workspace_id',workspace).select('id').single();if(error)throw error;
  },status==='approved'?'Asset approved with recorded rights clearance.':'Asset rejected and restricted.');
 }
 async function reviewSubmission(s:Submission,status:'revision'|'approved'){
  if(!client||!isEditor)return;
  await act(async()=>{const {error}=await client.from('rc_submissions').update({status}).eq('id',s.id).eq('workspace_id',workspace).select('id').single();if(error)throw error},'Submission review updated.');
 }
 async function download(a:Asset){
  if(!client)return;
  const {data,error}=await client.storage.from('runctrl-media').createSignedUrl(a.storage_path,60);
  if(error){setNotice(error.message);return}
  if(data?.signedUrl)window.open(data.signedUrl,'_blank','noopener,noreferrer');
 }
 async function resolveAccess(r:AccessRequest,decision:'approved'|'denied'){
  if(!client||!isOwner)return;
  await act(async()=>{const {error}=await client.rpc('rc_resolve_access',{request_id:r.id,decision});if(error)throw error},decision==='approved'?'Contributor access approved.':'Access request denied.');
 }
 const pending=assignments.filter(a=>a.status==='requested').length;
 const inProgress=assignments.filter(a=>['approved','assigned','in_progress','review'].includes(a.status)).length;
 const review=assets.filter(a=>a.review_status==='pending').length;
 const approved=assets.filter(a=>a.review_status==='approved'&&a.rights_status==='cleared').length;
 const available=workspaces.filter(w=>members.some(m=>m.workspace_id===w.id&&m.user_id===user?.id));
 const sectionNav:Section[]=['overview','assignments','credentials','submissions','people'];
 return <main className="rc-shell">
  <aside className="rc-sidebar"><div className="brand">RUN<span>CTRL</span><small>MEDIA OPERATIONS OS</small></div>
   <div className="navhead">WORKSPACE</div>
   {available.map(w=><button key={w.id} disabled={busy} className={'workspace '+(workspace===w.id?'active':'')} onClick={()=>{setWorkspace(w.id);setSection('overview');setNotice('')}}>{w.name}</button>)}
   {available.length>0&&<><div className="navhead nav-spacer">WORKSPACE TOOLS</div>{sectionNav.map(x=><button key={x} className={'workspace nav-item '+(section===x?'active':'')} onClick={()=>setSection(x)}><span className="nav-icon">{icon[x]}</span>{pretty(x)}</button>)}</>}
   <div className="sidefoot">Every assignment. Every asset. Accountable.</div>
  </aside>
  <section className="content rc-content">
   <header className="rc-header"><div><div className="eyebrow">COMMAND CENTER / {activeWorkspace?.slug?.toUpperCase()||'ACCESS'}</div><h1>{activeWorkspace?.name||'RUNCTRL'}</h1><p>Coverage, credentials, submissions, and editorial control in one place.</p></div>
   <div className="auth">{user?.email&&<small>{user.email}</small>}{user?<button onClick={()=>client?.auth.signOut()}>Sign out</button>:null}</div></header>
   {notice&&<div className="notice" role="status">{notice}<button onClick={()=>setNotice('')} aria-label="Dismiss notice">×</button></div>}
   {loading?<div className="empty">Loading your workspace…</div>:!user?
    <div className="empty welcome"><div className="eyebrow">THE OPERATING SYSTEM FOR MEDIA TEAMS</div><h2>Run the work. Own the outcome.</h2><p>Use the Google account approved by your workspace owner.</p><button className="primary" onClick={signIn} disabled={!client||busy}>Continue with Google</button></div>
   :!available.length?<div className="panel"><h2>Request workspace access</h2><p>Your account is signed in, but no active workspace membership has been granted. Choose a team to request access. An owner must approve you.</p><div className="stack">{workspaces.map(w=><div className="assignment" key={w.id}><div><strong>{w.name}</strong><p>Contributor access requires approval.</p></div><button className="primary" disabled={busy||ownRequests.some(r=>r.workspace_id===w.id&&r.user_id===user.id)} onClick={()=>requestAccess(w)}>{ownRequests.find(r=>r.workspace_id===w.id)?pretty(ownRequests.find(r=>r.workspace_id===w.id)!.status):'Request access'}</button></div>)}</div></div>
   :<>
    <div className="rc-strip"><span className="rc-chip">{pretty(myRole||'member')} access</span><span className="rc-chip">Private workspace</span><button onClick={()=>fetchWorkspace().catch(e=>setNotice(errorText(e)))} className="soft-button">↻ Refresh</button></div>
    {dataLoading&&<p role="status">Loading workspace records…</p>}
    {section==='overview'&&<><div className="stats four"><div className="stat"><small>Assignments</small><strong>{assignments.length}</strong><span>Total records</span></div><div className="stat"><small>In progress</small><strong>{inProgress}</strong><span>Live coverage</span></div><div className="stat"><small>Needs review</small><strong>{review+pending}</strong><span>Assets + requests</span></div><div className="stat"><small>Cleared assets</small><strong>{approved}</strong><span>Editorial approved</span></div></div><div className="panel"><h2>Operations pulse</h2><p>Every credential request requires owner authorization before external contact. Images never become licensable solely because they were uploaded.</p><div className="quicklinks"><button onClick={()=>setSection('assignments')}>Manage assignments →</button><button onClick={()=>setSection('credentials')}>Credential desk →</button><button onClick={()=>setSection('submissions')}>Review media →</button></div></div><div className="sectionhead rc-spaced"><div><h2>Recent assignments</h2><p>Operational records, not publication claims.</p></div></div><div className="assignments">{assignments.slice(0,5).map(a=><div className="assignment" key={a.id}><div><div className="eyebrow">{a.sport||'COVERAGE'} / {date(a.event_at)}</div><h3>{a.title}</h3><p>{a.venue||'Venue pending'}</p></div><span className="status-pill">{pretty(a.status)}</span></div>)}{assignments.length===0&&<div className="empty">No assignments yet.</div>}</div></>}
    {section==='assignments'&&<><div className="sectionhead rc-spaced"><div><h2>Assignments</h2><p>Create coverage requests, assign contributors and track delivery.</p></div>{myRole!=='viewer'&&<button className="primary" onClick={()=>setNewAssignment(v=>!v)}>+ {isEditor?'New assignment':'Request assignment'}</button>}</div>
     {newAssignment&&<div className="panel form rc-form"><label>Assignment title<input value={draft.title} onChange={e=>setDraft({...draft,title:e.target.value})} placeholder="Loyola vs Northwestern"/></label><label>Sport<input value={draft.sport} onChange={e=>setDraft({...draft,sport:e.target.value})} placeholder="Basketball"/></label><label>Venue<input value={draft.venue} onChange={e=>setDraft({...draft,venue:e.target.value})} placeholder="Venue name"/></label><label>Event date and time<input type="datetime-local" value={draft.event_at} onChange={e=>setDraft({...draft,event_at:e.target.value})}/></label><label>Deadline<input type="datetime-local" value={draft.deadline_at} onChange={e=>setDraft({...draft,deadline_at:e.target.value})}/></label>{isEditor&&<label>Assign contributor<select value={draft.assigned_to} onChange={e=>setDraft({...draft,assigned_to:e.target.value})}><option value="">Unassigned</option>{members.filter(m=>m.workspace_id===workspace&&m.role!=='viewer').map(m=><option key={m.user_id} value={m.user_id}>{m.user_id===user.id?user.email:(requests.find(r=>r.user_id===m.user_id)?.email??m.user_id)} ({m.role})</option>)}</select></label>}<label className="wide">Coverage brief<textarea value={draft.brief} onChange={e=>setDraft({...draft,brief:e.target.value})} placeholder="Deliverables, arrival instructions, editorial restrictions"/></label><div className="wide"><button className="primary" disabled={busy} onClick={createAssignment}>Save assignment</button></div></div>}
     <div className="assignments">{assignments.map(a=><div className="assignment" key={a.id}><div><div className="eyebrow">{a.sport||'SPORTS'} · {date(a.event_at)}</div><h3>{a.title}</h3><p>{a.venue||'Location not specified'} · {a.brief||'No brief added'}</p><div className="muted-line">Credential: {pretty(a.credential_status)} · Due: {date(a.deadline_at)}</div></div><div className="card-actions">{isEditor?<select value={a.status} disabled={busy} onChange={e=>assignmentStatus(a,e.target.value)} aria-label="Assignment status">{assignmentStatuses.map(x=><option key={x} value={x}>{pretty(x)}</option>)}</select>:<span className="status-pill">{pretty(a.status)}</span>}{(a.assigned_to===user.id||isEditor)&&['approved','assigned','in_progress','review','completed'].includes(a.status)&&<button className="soft-button" onClick={()=>{setSubmissionFor(a.id);setSection('submissions')}}>Submit media</button>}</div></div>)}{!assignments.length&&<div className="empty">No assignments in this workspace.</div>}</div></>}
    {section==='credentials'&&<><div className="sectionhead rc-spaced"><div><h2>Credential desk</h2><p>Track approvals, contacts and written evidence. No email sends occur in RUNCTRL.</p></div></div><div className="assignments">{assignments.map(a=>{const c=credentials.find(x=>x.assignment_id===a.id);return <div className="assignment" key={a.id}><div><div className="eyebrow">{date(a.event_at)}</div><h3>{a.title}</h3><p>{c?c.contact_name+' · '+c.contact_email:'No credential draft'}</p>{c?.proof_url&&httpsEvidence(c.proof_url)&&<a target="_blank" rel="noreferrer" href={c.proof_url}>View approval proof ↗</a>}</div><div className="card-actions">{c?<><span className="status-pill">{pretty(c.status)}</span>{isEditor&&<select value={c.status} disabled={busy} onChange={e=>credentialStatus(c,e.target.value)} aria-label="Credential status">{credentialNext(c.status,isOwner).map(x=><option key={x}>{x}</option>)}</select>}{isEditor&&['draft','approval_required'].includes(c.status)&&<button disabled={busy} onClick={()=>{setCredentialFor(a.id);setCredentialDraft({contact_name:c.contact_name,contact_email:c.contact_email,request_notes:c.request_notes})}}>Edit draft</button>}</>:isEditor?<button className="soft-button" onClick={()=>setCredentialFor(a.id)}>Create credential draft</button>:<span className="status-pill">Not requested</span>}</div>{credentialFor===a.id&&<div className="inline-form"><label>Host contact<input value={credentialDraft.contact_name} onChange={e=>setCredentialDraft({...credentialDraft,contact_name:e.target.value})}/></label><label>Verified email<input value={credentialDraft.contact_email} onChange={e=>setCredentialDraft({...credentialDraft,contact_email:e.target.value})}/></label><label>Internal request notes<textarea value={credentialDraft.request_notes} onChange={e=>setCredentialDraft({...credentialDraft,request_notes:e.target.value})}/></label><button className="primary" disabled={busy} onClick={()=>credentialCreate(a)}>Save draft</button></div>}</div>})}{!assignments.length&&<div className="empty">Create an assignment before adding a credential record.</div>}</div></>}
    {section==='submissions'&&<><div className="sectionhead rc-spaced"><div><h2>Media submissions</h2><p>Private ingest, controlled review and documented rights clearance.</p></div></div>
     {(submissionFor||(!isEditor&&assignments.length>0))&&<div className="panel"><h3>New submission</h3><div className="form rc-form"><label>Assignment<select value={submissionFor} onChange={e=>setSubmissionFor(e.target.value)}><option value="">Select eligible assignment</option>{assignments.filter(a=>['approved','assigned','in_progress','review','completed'].includes(a.status)&&(isEditor||a.assigned_to===user.id)).map(a=><option key={a.id} value={a.id}>{a.title}</option>)}</select></label><label>Package title<input value={submissionDraft.title} onChange={e=>setSubmissionDraft({...submissionDraft,title:e.target.value})}/></label><label className="wide">Delivery notes<textarea value={submissionDraft.notes} onChange={e=>setSubmissionDraft({...submissionDraft,notes:e.target.value})}/></label><label className="wide checkrow"><input type="checkbox" checked={submissionDraft.rights_attested} onChange={e=>setSubmissionDraft({...submissionDraft,rights_attested:e.target.checked})}/>I attest I am authorized to submit these files to this assignment. Final licensing rights require editorial verification.</label><button className="primary" disabled={busy||!submissionFor||!submissionDraft.rights_attested} onClick={()=>{const a=assignments.find(x=>x.id===submissionFor);if(a)submitPackage(a)}}>Create submission package</button></div></div>}
     <div className="assignments">{submissions.map(s=>{const sa=assets.filter(x=>x.submission_id===s.id);const a=assignments.find(x=>x.id===s.assignment_id);return <div className="assignment submission-card" key={s.id}><div className="submission-head"><div><div className="eyebrow">{a?.title||'ASSIGNMENT'} · {date(s.created_at)}</div><h3>{s.title}</h3><p>{s.notes||'No notes'}</p><div className="muted-line">{sa.length} file(s) · {pretty(s.status)}</div></div>{isEditor&&<div className="card-actions"><button className="soft-button" disabled={busy} onClick={()=>reviewSubmission(s,'revision')}>Request revision</button><button className="primary" disabled={busy} onClick={()=>reviewSubmission(s,'approved')}>Approve package</button></div>}</div>
      {(s.uploaded_by===user.id)&&canUpload(s.status)&&<div className="uploadrow"><input type="file" multiple accept="image/jpeg,image/png,image/webp,image/tiff,video/mp4,video/quicktime" onChange={e=>{setFileFor(s.id);setUploadFiles(Array.from(e.target.files??[]))}}/><button className="soft-button" disabled={busy||fileFor!==s.id||!uploadFiles.length} onClick={()=>upload(s)}>Upload selected files</button><small>50 MB maximum per file. RAW and large video need dedicated ingest.</small></div>}
      {sa.map(item=><div className="asset-row" key={item.id}><div><strong>{item.original_name}</strong><p>{Math.round(item.bytes/1024)} KB · {pretty(item.review_status)} · Rights: {pretty(item.rights_status)}</p></div><div className="card-actions"><button className="soft-button" onClick={()=>download(item)}>Open protected file</button>{isEditor&&canUpload(s.status)&&<><input className="rights-input" placeholder="Document rights evidence / restrictions" value={rightsNotes[item.id]??item.rights_note} onChange={e=>setRightsNotes({...rightsNotes,[item.id]:e.target.value})}/><button className="primary" disabled={busy} onClick={()=>assetReview(item,'approved')}>Clear</button><button className="soft-button" disabled={busy} onClick={()=>assetReview(item,'rejected')}>Reject</button></>}</div></div>)}
     </div>})}{!submissions.length&&<div className="empty">No media packages submitted yet.</div>}</div></>}
    {section==='people'&&<><div className="sectionhead rc-spaced"><div><h2>People & access</h2><p>Access requests require owner approval. Workspace records remain isolated.</p></div></div><div className="panel"><h3>Current access</h3>{members.filter(m=>m.workspace_id===workspace).map(m=><p key={m.user_id}>{m.user_id===user.id?user.email:(requests.find(r=>r.user_id===m.user_id)?.email??m.user_id)} · {pretty(m.role)}</p>)}<p>Contributors cannot grant themselves access.</p></div><div className="panel"><h3>Other workspaces</h3>{workspaces.filter(w=>!available.some(a=>a.id===w.id)).map(w=><p key={w.id}>{w.name} <button disabled={busy||ownRequests.some(r=>r.workspace_id===w.id)} onClick={()=>requestAccess(w)}>{ownRequests.find(r=>r.workspace_id===w.id)?pretty(ownRequests.find(r=>r.workspace_id===w.id)!.status):'Request access'}</button></p>)}</div>{isOwner&&<div className="panel rc-spaced"><h3>Access requests</h3><div className="assignments">{requests.filter(r=>r.status==='pending').map(r=><div className="assignment" key={r.id}><div><strong>{r.email}</strong><p>Requested role: {pretty(r.requested_role)} · {date(r.created_at)}</p></div><button className="primary" disabled={busy} onClick={()=>resolveAccess(r,'approved')}>Approve access</button><button disabled={busy} onClick={()=>resolveAccess(r,'denied')}>Deny</button></div>)}{!requests.filter(r=>r.status==='pending').length&&<p>No pending access requests.</p>}</div></div>}</>}
   </>}
  </section>
 </main>;
}
