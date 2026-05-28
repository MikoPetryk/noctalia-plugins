.pragma library

// UTF-8 safe base64 (so we can pipe arbitrary content through `base64 -d` without
// shell-quoting hazards, and support non-Latin profile names).
function b64utf8(str) {
  var u = unescape(encodeURIComponent(String(str)));
  var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  var out = "", i = 0;
  while (i < u.length) {
    var a = u.charCodeAt(i++);
    var b = i < u.length ? u.charCodeAt(i++) : NaN;
    var d = i < u.length ? u.charCodeAt(i++) : NaN;
    var e1 = a >> 2;
    var e2 = ((a & 3) << 4) | (isNaN(b) ? 0 : (b >> 4));
    var e3 = isNaN(b) ? 64 : (((b & 15) << 2) | (isNaN(d) ? 0 : (d >> 6)));
    var e4 = isNaN(d) ? 64 : (d & 63);
    out += chars.charAt(e1) + chars.charAt(e2)
        + (e3 === 64 ? "=" : chars.charAt(e3))
        + (e4 === 64 ? "=" : chars.charAt(e4));
  }
  return out;
}

function appMatches(app, appId, title) {
  if (!app.appId || app.appId !== appId) return false;
  if (app.title && app.title.length) {
    try { if (!(new RegExp(app.title)).test(title || "")) return false; } catch (e) {}
  }
  return true;
}

// Find the all-screens profile a freshly opened window should be routed to.
// (Single-screen profiles are handled by static niri window-rules instead.)
function findProfileForApp(profiles, appId, title) {
  for (var i = 0; i < profiles.length; i++) {
    var p = profiles[i];
    if (!p.onAllScreens) continue;
    var apps = p.apps || [];
    for (var j = 0; j < apps.length; j++)
      if (appMatches(apps[j], appId, title)) return p;
  }
  return null;
}

// Given a workspace name like "Work·DP-1", find the linked profile it belongs to.
function findLinkedProfileByWsName(profiles, wsName) {
  if (!wsName) return null;
  var idx = wsName.lastIndexOf("·");
  if (idx < 0) return null;
  var base = wsName.substring(0, idx);
  for (var i = 0; i < profiles.length; i++) {
    var p = profiles[i];
    if (p.onAllScreens && p.linked && p.name === base) return p;
  }
  return null;
}
