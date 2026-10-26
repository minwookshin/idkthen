import test from 'node:test';
import assert from 'node:assert/strict';
import {releasePresentation} from '../dist/release-policy.js';

test('development version updates without exposing an unsigned download',()=>{
  assert.deepEqual(releasePresentation({version:'0.16.1',channel:'development-preview',available:false,
    downloadURL:'https://example.com/unsigned.zip',sha256:'a'.repeat(64)},'https://example.com'),
    {url:null,label:'Development preview · 0.16.1',checksum:null});
});
test('missing or contradictory metadata cannot claim a verified release',()=>{
  for(const value of [null,{}, {version:'<script>',available:false,channel:'development-preview'},
    {version:'0.16.1',available:true,notarized:false,channel:'verified-preview'},
    {version:'0.16.1',available:false,channel:'verified-preview'}]) {
    assert.deepEqual(releasePresentation(value,'https://example.com'),
      {url:null,label:'Mac preview · preparing',checksum:null});
  }
});
test('only a valid same-origin release supplies an integrity label and URL',()=>{
  const release={version:'0.16.1',channel:'verified-preview',available:true,notarized:true,
    sha256:'a'.repeat(64),downloadURL:'https://example.com/downloads/idkthen-0.16.1.zip'};
  assert.deepEqual(releasePresentation(release,'https://example.com'),
    {url:release.downloadURL,label:'Verified preview · 0.16.1',checksum:release.sha256});
  assert.equal(releasePresentation(release,'https://other.example').url,null);
});
