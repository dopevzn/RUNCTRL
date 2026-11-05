export function credentialNext(status:string,owner:boolean):string[]{
 const next:Record<string,string[]>={draft:['approval_required'],approval_required:owner?['authorized','draft']:['draft'],authorized:owner?['sent','draft']:['draft'],sent:['pending','granted','denied','draft'],pending:['granted','denied','draft'],granted:['draft'],denied:['draft']};
 return [status,...(next[status]??[])];
}
export function httpsEvidence(value:string):boolean{
 try {const u=new URL(value);return u.protocol==='https:'&&!!u.hostname&&!u.username&&!u.password;}catch{return false;}
}
export const canUpload=(status:string)=>['submitted','revision'].includes(status);
