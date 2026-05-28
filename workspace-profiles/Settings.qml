import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null
  readonly property var m: pluginApi ? pluginApi.mainInstance : null
  property var cfg: pluginApi ? pluginApi.pluginSettings : ({})
  property var defaults: pluginApi ? pluginApi.manifest.metadata.defaultSettings : ({})

  spacing: Style.marginL

  function save(k, v) {
    if (!pluginApi) return;
    pluginApi.pluginSettings[k] = v;
    pluginApi.saveSettings();
  }

  NToggle {
    label: "Linked switching"
    description: "Enable synchronized cross-monitor switching for linked profiles"
    checked: (cfg.pairingEnabled ?? defaults.pairingEnabled) === true
    onToggled: function (c) { root.save("pairingEnabled", c); }
  }
  NToggle {
    label: "Open pinned apps silently"
    description: "When on, launching a pinned app does not move focus to it"
    checked: (cfg.openPinnedAppsSilently ?? defaults.openPinnedAppsSilently) === true
    onToggled: function (c) { root.save("openPinnedAppsSilently", c); }
  }
  NToggle {
    label: "Show profile name in bar"
    checked: (cfg.showLabelInBar ?? defaults.showLabelInBar) === true
    onToggled: function (c) { root.save("showLabelInBar", c); }
  }
  property int debounceValue: cfg.pairingDebounceMs ?? defaults.pairingDebounceMs ?? 200
  NSpinBox {
    label: "Pairing debounce (ms)"
    from: 50
    to: 1000
    stepSize: 50
    value: root.debounceValue
    onValueChanged: {
      if (value === root.debounceValue) return;
      root.debounceValue = value;        // breaks the binding -> no loop
      root.save("pairingDebounceMs", value);
    }
  }
  NButton {
    text: "Regenerate workspaces.kdl now"
    onClicked: if (root.m) root.m.regenerate()
  }
}
