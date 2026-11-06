export function credentialNext(status:string,owner:boolean):string[]{
 const next:Record<string,string[]>={draft:['approval_required'],approval_required:owner?['authorized','draft']:['draft'],authorized:owner?['sent','draft']:['draft'],sent:['pending','granted','denied','draft'],pending:['granted','denied','draft'],granted:['draft'],denied:['draft']};
 return [status,...(next[status]??[])];
}
export function httpsEvidence(value:string):boolean{
 try {const u=new URL(value);return u.protocol==='https:'&&!!u.hostname&&!u.username&&!u.password;}catch{return false;}
}
export const canUpload=(status:string)=>['submitted','revision'].includes(status);

export function driveFolder(value:string):string|null{
 try{const u=new URL(value.trim());if(u.protocol!=='https:'||u.hostname!=='drive.google.com'||u.port||u.username||u.password)return null;const m=u.pathname.match(/^\/drive\/(?:u\/\d+\/)?folders\/([A-Za-z0-9_-]{10,200})\/?$/);return m?'https://drive.google.com/drive/folders/'+m[1]:null}catch{return null}
}
