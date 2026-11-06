import test from 'node:test';
import assert from 'node:assert/strict';
import {credentialNext,httpsEvidence,canUpload,driveFolder} from '../lib/workflow.ts';
test('credential workflow requires approval and limits owner actions',()=>{
 assert.deepEqual(credentialNext('draft',true),['draft','approval_required']);
 assert(!credentialNext('approval_required',false).includes('authorized'));
 assert(credentialNext('approval_required',true).includes('authorized'));
 assert(!credentialNext('authorized',false).includes('sent'));
 assert(!credentialNext('draft',true).includes('granted'));
});
test('evidence rejects script URLs and embedded credentials',()=>{
 for(const v of ['javascript:alert(1)','http://example.com','https://a:b@example.com','garbage'])assert.equal(httpsEvidence(v),false);
 assert.equal(httpsEvidence('https://example.com/evidence'),true);
});
test('approved packages do not accept new uploads',()=>{
 assert(canUpload('submitted'));assert(canUpload('revision'));assert(!canUpload('approved'));assert(!canUpload('published'));
});

test('Drive folder URLs reject credential, host, and path substitution',()=>{
 const id='aBcdEFGHijklMNOP1234567890';
 assert.equal(driveFolder('https://drive.google.com/drive/u/0/folders/'+id+'?usp=sharing'),'https://drive.google.com/drive/folders/'+id);
 for(const v of ['https://drive.google.com.evil.test/drive/folders/'+id,'https://a:b@drive.google.com/drive/folders/'+id,'http://drive.google.com/drive/folders/'+id,'https://drive.google.com/file/d/'+id,'javascript:alert(1)'])assert.equal(driveFolder(v),null);
});
