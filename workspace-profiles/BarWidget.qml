import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property var m: pluginApi ? pluginApi.mainInstance : null
  readonly property string screenName: screen ? screen.name : ""
  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"

  readonly property bool showLabel: m ? m.setting("showLabelInBar", true) : true
  // This screen's active workspace, mapped to its profile's clean name.
  readonly property string activeLabel: {
    if (!m) return "";
    for (var i = 0; i < m.wsList.length; i++) {
      var w = m.wsList[i];
      if (w.output === root.screenName && w.is_active && w.name)
        return m.profileNameForWsName(w.name);
    }
    return "";
  }

  implicitWidth: isVertical ? Style.capsuleHeight : Math.round(layout.implicitWidth + Style.marginM * 2)
  implicitHeight: isVertical ? Math.round(layout.implicitHeight + Style.marginM * 2) : Style.capsuleHeight
  Layout.alignment: Qt.AlignVCenter

  Rectangle {
    id: capsule
    anchors.centerIn: parent
    width: root.implicitWidth
    height: root.implicitHeight
    radius: Style.radiusM
    color: Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    RowLayout {
      id: layout
      anchors.centerIn: parent
      spacing: Style.marginS

      NIcon {
        icon: "workspaces"
        color: Color.mOnSurface
      }
      NText {
        visible: root.showLabel && root.activeLabel.length > 0
        text: root.activeLabel
        color: Color.mOnSurface
        pointSize: Style.fontSizeS
      }
    }
  }

  NPopupContextMenu {
    id: menu
    model: [{ "label": "Settings", "action": "settings", "icon": "settings" }]
    onTriggered: function (action) {
      menu.close();
      PanelService.closeContextMenu(root.screen);
      if (action === "settings")
        BarService.openPluginSettings(root.screen, root.pluginApi.manifest);
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function (mouse) {
      if (mouse.button === Qt.RightButton)
        PanelService.showContextMenu(menu, root, root.screen);
      else if (pluginApi)
        pluginApi.openPanel(root.screen, root);
    }
  }
}
