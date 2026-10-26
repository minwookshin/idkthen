import {releasePresentation} from './release-policy.js';
try {
  const response=await fetch('./release.json',{cache:'no-store'});
  if (response.ok) {
    const release=await response.json(), state=releasePresentation(release,window.location.origin), url=state.url;
    document.getElementById('release-status').textContent=state.label;
    if (url) {
      const link=document.getElementById('mac-download');link.href=url;link.rel='noopener noreferrer';link.hidden=false;
      document.getElementById('release-notice').textContent='Verified Mac preview available. Check the release notes and system requirements before installing.';
      const integrity=document.getElementById('download-integrity');integrity.textContent=`SHA-256: ${state.checksum}`;integrity.hidden=false;
    }
  }
} catch { /* Fail closed: do not invent a download when metadata is missing. */ }
