export function verifiedDownload(release, siteOrigin) {
  if (!release || release.available!==true || release.notarized!==true || release.channel!=='verified-preview' || !/^\d+\.\d+\.\d+$/.test(release.version) || !/^[a-f0-9]{64}$/.test(release.sha256)) return null;
  try {
    const url=new URL(release.downloadURL);
    const site=new URL(siteOrigin);
    if (site.protocol!=='https:' || site.username || site.password || site.pathname!=='/' || site.search || site.hash) return null;
    if (url.origin!==site.origin || url.protocol!=='https:' || url.username || url.password || url.search || url.hash || url.pathname!==`/downloads/idkthen-${release.version}.zip`) return null;
    return url.href;
  } catch {return null;}
}

export function releasePresentation(release, siteOrigin) {
  const url = verifiedDownload(release, siteOrigin);
  if (url) return {url, label:`Verified preview · ${release.version}`, checksum:release.sha256};
  const development = release?.available === false && release?.channel === 'development-preview'
    && /^\d+\.\d+\.\d+$/.test(release?.version);
  return {url:null, label:development ? `Development preview · ${release.version}` : 'Mac preview · preparing', checksum:null};
}
