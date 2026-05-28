import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "utils/kdlgen.js" as Kdl
import "utils/niri.js" as NU

// Logic, niri integration, and the live engines. UI reads this via
// pluginApi.mainInstance.
//
// Profiles are named niri workspaces. Single-screen: bare name. On-all-screens:
// niri forbids duplicate names, so the *primary* monitor keeps the bare name and
// the others get a short numeric suffix ("GDHQ", "GDHQ 2", "GDHQ 3"). The naming
// scheme lives entirely here (wsNameFor / profileAndOutputForWsName).
Item {
  id: root
  property var pluginApi: null

  // ---- live state ----
  property var profiles: []      // [{name,onAllScreens,linked,output,apps:[{appId,title,name,icon}]}]
  property var outputs: []       // connected output names
  property var wsList: []        // current workspaces (id, idx, name, output, is_active, is_focused)
  property var winList: []       // current windows
  property bool includeMissing: false

  // ---- engine bookkeeping ----
  property var seenWindows: ({})
  property bool windowsInitialized: false
  property var activeByOutput: ({})   // output -> active workspace id (settled)
  property bool primed: false
  property bool syncing: false

  // ---------- settings ----------
  function setting(k, dflt) {
    var v = (pluginApi && pluginApi.pluginSettings) ? pluginApi.pluginSettings[k] : undefined;
    return (v === undefined || v === null) ? dflt : v;
  }
  function home() { return (Quickshell.env && Quickshell.env("HOME")) || "/home/miko"; }
  function expand(p) { return (p && p.length && p[0] === "~") ? home() + p.substring(1) : p; }
  function configPath() { return expand(setting("configPath", "~/.config/niri/config.kdl")); }
  function includePath() { return expand(setting("includeFile", "~/.config/niri/workspaces.kdl")); }

  // ---------- naming scheme ----------
  // Outputs for an all-screens profile, primary (clean-name) monitor first.
  function orderedOutputsFor(p) {
    var sorted = outputs.slice().sort();
    var prim = (p.output && outputs.indexOf(p.output) >= 0) ? p.output : (sorted.length ? sorted[0] : "");
    if (!prim) return [];
    var rest = sorted.filter(function (o) { return o !== prim; });
    return [prim].concat(rest);
  }
  // niri workspace name for a profile on a given output.
  function wsNameFor(p, output) {
    if (!p) return null;
    if (!p.onAllScreens) return p.name;
    var ord = orderedOutputsFor(p);
    var k = ord.indexOf(output);
    if (k < 0) return null;
    return k === 0 ? p.name : (p.name + " " + (k + 1));
  }
  // Reverse: which profile (and output) owns a given workspace name.
  function profileAndOutputForWsName(name) {
    if (!name) return null;
    for (var i = 0; i < profiles.length; i++) {
      var p = profiles[i];
      if (!p.onAllScreens) {
        if (p.name === name) return { profile: p, output: p.output };
        continue;
      }
      var ord = orderedOutputsFor(p);
      for (var k = 0; k < ord.length; k++)
        if (wsNameFor(p, ord[k]) === name) return { profile: p, output: ord[k] };
    }
    return null;
  }
  function profileNameForWsName(name) {
    var info = profileAndOutputForWsName(name);
    return info ? info.profile.name : (name || "");
  }

  // ---------- profiles model ----------
  function loadProfiles() {
    try {
      var a = JSON.parse(setting("profiles", "[]"));
      root.profiles = Array.isArray(a) ? a : [];
    } catch (e) { root.profiles = []; }
  }
  function persist() {
    if (!pluginApi) return;
    pluginApi.pluginSettings.profiles = JSON.stringify(root.profiles);
    pluginApi.saveSettings();
    regenerate();
    reconcileTimer.restart();   // niri won't move/rename existing workspaces on reload — we do it
  }
  function uniqueName(base) {
    var names = root.profiles.map(function (p) { return p.name; });
    if (names.indexOf(base) < 0) return base;
    var n = 2;
    while (names.indexOf(base + " " + n) >= 0) n++;
    return base + " " + n;
  }
  function addProfile() {
    var arr = root.profiles.slice();
    arr.push({ name: uniqueName("Workspace"), onAllScreens: false, linked: false,
               output: (root.outputs.length ? root.outputs.slice().sort()[0] : ""), apps: [] });
    root.profiles = arr;
    persist();
  }
  function updateProfile(i, obj) {
    if (i < 0 || i >= root.profiles.length) return;
    var arr = root.profiles.slice();
    arr[i] = obj;
    root.profiles = arr;
    persist();
  }
  function deleteProfile(i) {
    if (i < 0 || i >= root.profiles.length) return;
    var arr = root.profiles.slice();
    arr.splice(i, 1);
    root.profiles = arr;
    persist();
  }
  function moveProfile(i, dir) {
    var j = i + dir;
    if (i < 0 || j < 0 || i >= root.profiles.length || j >= root.profiles.length) return;
    var arr = root.profiles.slice();
    var t = arr[i]; arr[i] = arr[j]; arr[j] = t;
    root.profiles = arr;
    persist();
    applyLiveOrder();
  }

  // Installed + running apps for the picker (running first).
  function installedApps() {
    var out = [], seen = {};
    var i, a;
    for (i = 0; i < root.winList.length; i++) {
      a = root.winList[i].app_id;
      if (!a || seen[a]) continue;
      seen[a] = true;
      out.push({ appId: a, name: a, icon: a, running: true });
    }
    try {
      var vals = (typeof DesktopEntries !== "undefined" && DesktopEntries.applications)
                 ? (DesktopEntries.applications.values || []) : [];
      for (i = 0; i < vals.length; i++) {
        var e = vals[i];
        if (!e || e.noDisplay === true) continue;
        var id = String(e.id || e.name || "").replace(/\.desktop$/, "");
        if (!id || seen[id]) continue;
        seen[id] = true;
        out.push({ appId: id, name: e.name || id, icon: e.icon || id, running: false });
      }
    } catch (err) {}
    out.sort(function (x, y) {
      if (!!x.running !== !!y.running) return x.running ? -1 : 1;
      return (x.name || "").toLowerCase().localeCompare((y.name || "").toLowerCase());
    });
    return out;
  }

  // ---------- niri config generation ----------
  function buildDescriptors() {
    var wss = [], rules = [];
    for (var i = 0; i < profiles.length; i++) {
      var p = profiles[i];
      if (!p.name) continue;
      if (p.onAllScreens) {
        var ord = orderedOutputsFor(p);
        for (var k = 0; k < ord.length; k++)
          wss.push({ name: wsNameFor(p, ord[k]), output: ord[k] });
        // all-screens apps are routed live to the cursor monitor (no static rule)
      } else {
        wss.push({ name: p.name, output: p.output || (outputs.length ? outputs.slice().sort()[0] : "") });
        var apps = p.apps || [];
        for (var a = 0; a < apps.length; a++)
          if (apps[a].appId) rules.push({ appId: apps[a].appId, title: apps[a].title || "", wsName: p.name });
      }
    }
    return { workspaces: wss, rules: rules };
  }
  function writeFile(path, content, append) {
    var b64 = NU.b64utf8(content);
    var cmd = append
      ? "printf %s '" + b64 + "' | base64 -d >> '" + path + "'"
      : "printf %s '" + b64 + "' | base64 -d > '" + path + ".tmp' && mv '" + path + ".tmp' '" + path + "'";
    Quickshell.execDetached(["sh", "-c", cmd]);
  }
  function regenerate() {
    var d = buildDescriptors();
    writeFile(includePath(), Kdl.generate(d.workspaces, d.rules), false);
  }
  function addInclude() {
    writeFile(configPath(), "\ninclude \"./workspaces.kdl\"\n", true);
    includeMissing = false;
    recheckTimer.restart();
  }

  // ---------- niri actions ----------
  function action(args) { Quickshell.execDetached(["niri", "msg", "action"].concat(args)); }
  function actionBatch(cmds) {
    var parts = [];
    for (var i = 0; i < cmds.length; i++) {
      var a = cmds[i].map(function (x) { return "'" + String(x).replace(/'/g, "'\\''") + "'"; });
      parts.push("niri msg action " + a.join(" "));
    }
    Quickshell.execDetached(["sh", "-c", parts.join(" ; ")]);
  }

  // ---------- helpers ----------
  function wsById(id) {
    for (var i = 0; i < wsList.length; i++) if (wsList[i].id === id) return wsList[i];
    return null;
  }
  function activeWsOnOutput(o) {
    for (var i = 0; i < wsList.length; i++)
      if (wsList[i].output === o && wsList[i].is_active) return wsList[i];
    return null;
  }
  function focusedOutputName() {
    for (var i = 0; i < wsList.length; i++) if (wsList[i].is_focused) return wsList[i].output;
    return outputs.length ? outputs[0] : "";
  }

  // ---------- switching ----------
  function activateProfile(p) {
    if (!p) return;
    if (p.onAllScreens) {
      var origin = focusedOutputName();
      var cmds = [];
      for (var i = 0; i < outputs.length; i++) {
        if (outputs[i] === origin) continue;
        var nm = wsNameFor(p, outputs[i]);
        if (nm) cmds.push(["focus-workspace", nm]);   // focus-workspace, not focus-monitor (avoids cursor warp)
      }
      var ob = wsNameFor(p, origin);
      if (ob) cmds.push(["focus-workspace", ob]);      // end on the origin monitor's workspace
      if (cmds.length === 0) return;
      syncing = true;
      actionBatch(cmds);
      syncGuard.restart();
    } else {
      action(["focus-workspace", p.name]);
    }
  }

  // ---------- engines ----------
  function routeWindow(w) {
    if (!w || w.id === undefined) return;
    var known = seenWindows[w.id];
    seenWindows[w.id] = true;
    if (!windowsInitialized || known) return;
    var prof = NU.findProfileForApp(root.profiles, w.app_id || "", w.title || "");
    if (!prof) return;
    var ws = wsById(w.workspace_id);
    if (!ws) return;
    var target = wsNameFor(prof, ws.output);
    if (!target || ws.name === target) return;
    var follow = setting("openPinnedAppsSilently", false) ? "false" : "true";
    action(["move-window-to-workspace", "--window-id", String(w.id), "--focus", follow, target]);
  }

  // Linked switching keyed on a monitor's *active* workspace changing (debounced),
  // NOT on focus moving — so hovering another monitor (focus-follows-mouse) does
  // not re-trigger a sync.
  function currentActiveByOutput() {
    var m = {};
    for (var i = 0; i < wsList.length; i++) { var w = wsList[i]; if (w.is_active) m[w.output] = w.id; }
    return m;
  }
  function evaluateActive() {
    var cur = currentActiveByOutput();
    if (!primed) { activeByOutput = cur; primed = true; return; }
    if (syncing) { activeByOutput = cur; return; }   // absorb our own changes, don't re-trigger
    var trigger = null;
    for (var o in cur) {
      if (cur[o] !== activeByOutput[o]) {            // this monitor's active workspace actually changed
        var ws = wsById(cur[o]);
        if (ws) {
          var info = profileAndOutputForWsName(ws.name);
          if (info && info.profile.onAllScreens && info.profile.linked)
            trigger = { profile: info.profile, output: o };
        }
      }
    }
    activeByOutput = cur;
    if (trigger && setting("pairingEnabled", true)) syncOthers(trigger.profile, trigger.output);
  }
  function syncOthers(prof, origin) {
    var cmds = [];
    for (var i = 0; i < outputs.length; i++) {
      var o = outputs[i];
      if (o === origin) continue;
      var target = wsNameFor(prof, o);
      if (!target) continue;
      var cur = activeWsOnOutput(o);
      if (cur && cur.name === target) continue;
      cmds.push(["focus-workspace", target]);          // focus-workspace, not focus-monitor (avoids cursor warp)
    }
    if (cmds.length === 0) return;
    var back = wsNameFor(prof, origin);
    if (back) cmds.push(["focus-workspace", back]);     // return focus to the origin monitor's workspace
    syncing = true;
    actionBatch(cmds);
    syncGuard.restart();
  }

  // niri creates named workspaces from config but never moves/renames/reorders
  // existing ones when the config changes. So after edits we enforce the desired
  // layout: each profile workspace on the right monitor AND grouped contiguously
  // at the top in profile order (so they aren't scattered among dynamic
  // workspaces). Otherwise live state diverges and name-based actions misfire.
  function reconcile() {
    if (!primed) return;
    var cmds = [];
    for (var oi = 0; oi < outputs.length; oi++) {
      var o = outputs[oi];
      var idx = 1;
      for (var pi = 0; pi < profiles.length; pi++) {
        var p = profiles[pi];
        if (!p.name) continue;
        var nm = p.onAllScreens ? wsNameFor(p, o) : (p.output === o ? p.name : null);
        if (!nm) continue;
        var live = null;
        for (var j = 0; j < wsList.length; j++) if (wsList[j].name === nm) { live = wsList[j]; break; }
        if (!live) { idx++; continue; }     // not created yet (niri reload pending)
        var moved = live.output !== o;
        if (moved) cmds.push(["move-workspace-to-monitor", o, "--reference", nm]);
        if (moved || live.idx !== idx) cmds.push(["move-workspace-to-index", String(idx), "--reference", nm]);
        idx++;
      }
    }
    if (cmds.length) { syncing = true; actionBatch(cmds); syncGuard.restart(); }
  }
  // Reorder now just persists + reconciles (reconcile enforces order).
  function applyLiveOrder() { reconcileTimer.restart(); }

  // ---------- event stream ----------
  function onWorkspaceActivated(a) {
    if (!a || a.id === undefined) return;
    var ws = wsById(a.id);
    if (!ws) return;
    for (var i = 0; i < wsList.length; i++) {
      if (wsList[i].output === ws.output) wsList[i].is_active = (wsList[i].id === a.id);
      if (a.focused) wsList[i].is_focused = (wsList[i].id === a.id);
    }
    wsList = wsList.slice();      // notify bindings (bar label)
    evalTimer.restart();
  }
  function onEvent(line) {
    if (!line || !line.length) return;
    var ev;
    try { ev = JSON.parse(line); } catch (e) { return; }
    if (ev.WorkspacesChanged) {
      root.wsList = ev.WorkspacesChanged.workspaces || [];
      evalTimer.restart();
    } else if (ev.WorkspaceActivated) {
      onWorkspaceActivated(ev.WorkspaceActivated);
    } else if (ev.WindowsChanged) {
      root.winList = ev.WindowsChanged.windows || [];
      for (var i = 0; i < root.winList.length; i++) seenWindows[root.winList[i].id] = true;
      windowsInitialized = true;
    } else if (ev.WindowOpenedOrChanged) {
      routeWindow(ev.WindowOpenedOrChanged.window);
    }
  }

  Process {
    id: stream
    command: ["niri", "msg", "--json", "event-stream"]
    running: true
    stdout: SplitParser { splitMarker: "\n"; onRead: function (data) { root.onEvent(data); } }
    onExited: function () { streamRestart.restart(); }
  }
  Timer { id: streamRestart; interval: 1500; onTriggered: stream.running = true }
  Timer { id: evalTimer; interval: 130; onTriggered: root.evaluateActive() }
  Timer { id: syncGuard; interval: 450; onTriggered: root.syncing = false }
  Timer { id: recheckTimer; interval: 500; onTriggered: root.checkInclude() }
  // Runs after edits/reload, once niri has created any new named workspaces.
  Timer { id: reconcileTimer; interval: 600; onTriggered: root.reconcile() }

  // ---------- outputs + config check ----------
  Process {
    id: outputsProc
    command: ["niri", "msg", "--json", "outputs"]
    stdout: StdioCollector { onStreamFinished: function () { root.parseOutputs(this.text); } }
  }
  function parseOutputs(txt) {
    try {
      var o = JSON.parse(txt), names = [];
      if (Array.isArray(o)) { for (var i = 0; i < o.length; i++) names.push(o[i].name); }
      else { names = Object.keys(o); }
      root.outputs = names;
      regenerate();
      reconcileTimer.restart();
    } catch (e) {}
  }
  function checkInclude() {
    cfgCat.command = ["sh", "-c", "cat '" + configPath() + "' 2>/dev/null"];
    cfgCat.running = true;
  }
  Process {
    id: cfgCat
    stdout: StdioCollector {
      onStreamFinished: function () {
        root.includeMissing = (String(this.text).indexOf("workspaces.kdl") === -1);
      }
    }
  }

  Component.onCompleted: {
    loadProfiles();
    outputsProc.running = true;
    checkInclude();
    reconcileTimer.restart();   // fix any divergence left from a previous session
  }

  IpcHandler {
    target: "plugin:workspace-profiles"
    function toggle() {
      if (root.pluginApi)
        root.pluginApi.withCurrentScreen(function (s) { root.pluginApi.togglePanel(s); });
    }
  }
}
