// Newest first: compare "v0.69e" / "v0.64g3" numerically, then by suffix.
function versionKey(v) {
  const m = v.match(/^v?(\d+)\.(\d+)([a-z]*)(\d*)/i) || [];
  return [+m[1] || 0, +m[2] || 0, (m[3] || '').toLowerCase(), +m[4] || 0];
}
export function compareVersions(a, b) {
  const x = versionKey(a.version), y = versionKey(b.version);
  for (let i = 0; i < 4; i++) {
    if (x[i] === y[i]) continue;
    if (i === 2) return x[i].length !== y[i].length ? y[i].length - x[i].length : (y[i] > x[i] ? 1 : -1);
    return y[i] - x[i];
  }
  return 0;
}
