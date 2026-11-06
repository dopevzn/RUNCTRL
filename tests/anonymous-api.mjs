import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const env=Object.fromEntries(readFileSync('.env.local','utf8').trim().split('\n').map(l=>{const i=l.indexOf('=');return [l.slice(0,i),l.slice(i+1)]}));
const base=env.NEXT_PUBLIC_SUPABASE_URL;
const headers={apikey:env.NEXT_PUBLIC_SUPABASE_ANON_KEY};
const results=[];
for(const table of ['rc_members','rc_assignments','rc_credentials','rc_submissions','rc_assets','rc_audit','rc_access_requests','rc_storage_locations']){
 const r=await fetch(base+'/rest/v1/'+table+'?select=*',{headers});const body=await r.json();
 assert((r.ok&&Array.isArray(body)&&body.length===0)||[401,403].includes(r.status),'Anonymous data exposure: '+table);
 results.push({test:'Anonymous cannot read '+table,result:'PASS'});
}
const rpc=await fetch(base+'/rest/v1/rpc/rc_resolve_access',{method:'POST',headers:{...headers,'Content-Type':'application/json'},body:JSON.stringify({request_id:'00000000-0000-0000-0000-000000000000',decision:'approved'})});
assert([401,403,404].includes(rpc.status));results.push({test:'Anonymous cannot approve contributor access',result:'PASS'});
const settings=await fetch(base+'/auth/v1/settings',{headers});assert(settings.ok);const auth=await settings.json();
console.log(JSON.stringify({tests:results,googleEnabled:auth.external?.google,signupDisabled:auth.disable_signup},null,2));
