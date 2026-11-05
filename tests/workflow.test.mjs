import test from 'node:test';
import assert from 'node:assert/strict';
import {credentialNext,httpsEvidence,canUpload} from '../lib/workflow.ts';
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
