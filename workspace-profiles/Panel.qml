import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

// Workspace Profiles — visual panel.
//
//   ┌─ Tabs (drag to reorder) ──────────────────────┐
//   │  [GDHQ●] [Personal] [Work]  [＋ New]          │
//   ├─ Hero ─────────────────────────────────────────┤
//   │   GDHQ                              [ ▶ Switch ]│
//   │   Linked across all screens                     │
//   ├─ Body (two columns) ───────────────────────────┤
//   │  LEFT (placement + settings)  │  RIGHT (apps)  │
//   │  ┌─monitor cards─┐            │  ┌app rows────┐│
//   │  └───────────────┘            │  └────────────┘│
//   │  NAME / MODE / MONITOR        │                │
//   ├─ Footer ───────────────────────────────────────┤
//   │ Delete profile (right)                         │
//   └────────────────────────────────────────────────┘
Item {
  id: root

  property var pluginApi: null
  readonly property var m: pluginApi ? pluginApi.mainInstance : null

  readonly property var geometryPlaceholder: container
  property real contentPreferredWidth: 980 * Style.uiScaleRatio
  property real contentPreferredHeight: 680 * Style.uiScaleRatio
  readonly property bool allowAttach: true

  anchors.fill: parent

  property int sel: 0
  readonly property var profiles: m ? m.profiles : []
  readonly property var current: (profiles && sel >= 0 && sel < profiles.length) ? profiles[sel] : null

  // ── live helpers ──
  function activeWsNameOn(output) {
    if (!m) return "";
    for (var i = 0; i < m.wsList.length; i++) {
      var w = m.wsList[i];
      if (w.output === output && w.is_active) return w.name || "";
    }
    return "";
  }
  function isProfileLiveOnAnyMonitor(p) {
    if (!m || !p) return false;
    for (var i = 0; i < m.outputs.length; i++) {
      var o = m.outputs[i];
      var nm = m.wsNameFor(p, o);
      if (nm && activeWsNameOn(o) === nm) return true;
    }
    return false;
  }
  function isProfileLiveOnOutput(p, o) {
    if (!m || !p || !o) return false;
    var nm = m.wsNameFor(p, o);
    return nm && activeWsNameOn(o) === nm;
  }

  function modeOf(p) {
    if (!p) return "single";
    if (p.onAllScreens && p.linked) return "linked";
    if (p.onAllScreens) return "all";
    return "single";
  }
  function setMode(mode) {
    if (!current) return;
    var p = JSON.parse(JSON.stringify(current));
    p.onAllScreens = (mode !== "single");
    p.linked = (mode === "linked");
    m.updateProfile(sel, p);
  }
  function statusFor(p) {
    if (!p) return "";
    if (p.onAllScreens) return p.linked ? "Linked across all screens" : "Independent on every screen";
    return "Single monitor · " + (p.output || "—");
  }

  // ── picker state ──
  property bool pickerOpen: false
  property string pickerQuery: ""
  property var allApps: []
  property var pickerApps: []
  function openPicker() {
    allApps = m ? m.installedApps() : [];
    pickerQuery = "";
    pickerApps = allApps;
    pickerOpen = true;
  }
  onPickerQueryChanged: {
    var q = pickerQuery.toLowerCase().trim();
    if (!q) { pickerApps = allApps; return; }
    pickerApps = allApps.filter(function (a) {
      return (a.name || "").toLowerCase().indexOf(q) >= 0 || (a.appId || "").toLowerCase().indexOf(q) >= 0;
    });
  }

  function appIconSrc(appId, iconName) {
    var s = "";
    try { s = ThemeIcons.iconForAppId(appId ? String(appId).toLowerCase() : ""); } catch (e) {}
    if ((!s || s === "") && iconName) { try { s = ThemeIcons.iconFromName(iconName); } catch (e2) {} }
    if (!s || s === "") { try { s = ThemeIcons.iconFromName("application-x-executable"); } catch (e3) {} }
    return s || "";
  }

  function edit(field, value) {
    if (!current) return;
    var p = JSON.parse(JSON.stringify(current));
    p[field] = value;
    m.updateProfile(sel, p);
  }
  function addAppObj(app) {
    if (!current || !app || !app.appId) { pickerOpen = false; return; }
    var p = JSON.parse(JSON.stringify(current));
    p.apps = p.apps || [];
    for (var i = 0; i < p.apps.length; i++) if (p.apps[i].appId === app.appId) { pickerOpen = false; return; }
    p.apps.push({ appId: app.appId, title: "", name: app.name || app.appId, icon: app.icon || app.appId });
    m.updateProfile(sel, p);
    pickerOpen = false;
  }
  function addAppId(appId) { if (appId) addAppObj({ appId: appId, name: appId, icon: appId }); }
  function removeApp(idx) {
    if (!current) return;
    var p = JSON.parse(JSON.stringify(current));
    p.apps.splice(idx, 1);
    m.updateProfile(sel, p);
  }
  function editAppTitle(idx, title) {
    if (!current) return;
    var p = JSON.parse(JSON.stringify(current));
    if (idx < 0 || idx >= (p.apps || []).length) return;
    p.apps[idx].title = title;
    m.updateProfile(sel, p);
  }

  // ── DnD: compute drop index based on dragged tab center vs other tabs' centers ──
  function dropIndexFor(draggedTab) {
    var centerX = draggedTab.x + draggedTab.width / 2;
    var newIdx = 0;
    for (var i = 0; i < tabsRow.children.length; i++) {
      var c = tabsRow.children[i];
      if (c === draggedTab) continue;
      if (typeof c.tabIndex !== "number") continue;  // skip non-tab items (Repeater proxy)
      if ((c.x + c.width / 2) < centerX) newIdx++;
    }
    return newIdx;
  }

  // ═════════════════════════════════════════════════════════════════
  Rectangle {
    id: container
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // ────── TABS STRIP (drag to reorder) ──────
      Item {
        Layout.fillWidth: true
        implicitHeight: 50 * Style.uiScaleRatio
        ScrollView {
          anchors.fill: parent
          clip: true
          ScrollBar.vertical.policy: ScrollBar.AlwaysOff
          contentHeight: availableHeight

          Row {
            id: tabsRow
            spacing: Style.marginS
            move: Transition { NumberAnimation { properties: "x,y"; duration: 160; easing.type: Easing.OutQuad } }

            Repeater {
              model: root.profiles
              delegate: Rectangle {
                id: tab
                required property int index
                required property var modelData
                // expose for the dropIndex helper to filter delegates
                property int tabIndex: tab.index
                property bool isSelected: tab.index === root.sel
                property bool hovered: false
                property bool isLive: root.isProfileLiveOnAnyMonitor(tab.modelData)
                property bool dragging: false

                width: tabRow.implicitWidth + Style.marginL * 2
                height: 42 * Style.uiScaleRatio
                radius: Style.radiusM
                color: tab.isSelected ? Color.mPrimary : (tab.hovered ? Color.mHover : Qt.alpha(Color.mSurfaceVariant, 0.55))
                border.color: tab.isSelected ? Color.mPrimary : Qt.alpha(Color.mOutline, 0.4)
                border.width: 1
                z: tab.dragging ? 100 : 1
                scale: tab.dragging ? 1.04 : 1.0
                opacity: tab.dragging ? 0.92 : 1.0
                Behavior on color { ColorAnimation { duration: 110 } }
                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }
                Behavior on opacity { NumberAnimation { duration: 110 } }

                RowLayout {
                  id: tabRow
                  anchors.centerIn: parent
                  spacing: Style.marginS
                  NText {
                    text: tab.modelData.onAllScreens ? (tab.modelData.linked ? "⊜" : "⧉") : "▭"
                    pointSize: Style.fontSizeM
                    color: tab.isSelected ? Color.mOnPrimary : Color.mPrimary
                  }
                  NText {
                    text: tab.modelData.name || "(unnamed)"
                    pointSize: Style.fontSizeM
                    color: tab.isSelected ? Color.mOnPrimary : Color.mOnSurface
                  }
                  Rectangle {
                    visible: tab.isLive
                    width: 7; height: 7; radius: 4
                    color: tab.isSelected ? Color.mOnPrimary : Color.mPrimary
                    opacity: 0.95
                  }
                  NText {
                    visible: (tab.modelData.apps || []).length > 0
                    text: (tab.modelData.apps || []).length
                    pointSize: Style.fontSizeXS
                    color: tab.isSelected ? Qt.alpha(Color.mOnPrimary, 0.7) : Color.mOnSurfaceVariant
                  }
                }

                MouseArea {
                  id: tabMa
                  anchors.fill: parent
                  hoverEnabled: true
                  drag.target: tab
                  drag.axis: Drag.XAxis
                  drag.threshold: 6
                  cursorShape: tab.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                  onEntered: tab.hovered = true
                  onExited: tab.hovered = false
                  onPressed: tab.dragging = false
                  onPositionChanged: if (drag.active) tab.dragging = true
                  onClicked: if (!tab.dragging) root.sel = tab.index
                  onReleased: {
                    if (tab.dragging) {
                      var newIdx = root.dropIndexFor(tab);
                      var oldIdx = tab.index;
                      if (newIdx !== oldIdx && root.m) {
                        if (root.sel === oldIdx) root.sel = newIdx;
                        root.m.moveProfile(oldIdx, newIdx - oldIdx);
                      }
                      tab.dragging = false;
                      tab.x = 0;            // hand back to Row positioner
                    }
                  }
                }
              }
            }

            // + new tab
            Rectangle {
              id: newTab
              property bool hovered: false
              width: newRow.implicitWidth + Style.marginL * 2
              height: 42 * Style.uiScaleRatio
              radius: Style.radiusM
              color: newTab.hovered ? Color.mHover : "transparent"
              border.color: Qt.alpha(Color.mOutline, 0.45)
              border.width: 1
              Behavior on color { ColorAnimation { duration: 110 } }
              RowLayout {
                id: newRow
                anchors.centerIn: parent
                spacing: Style.marginS
                NText { text: "＋"; pointSize: Style.fontSizeM; color: Color.mPrimary }
                NText { text: "New profile"; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: newTab.hovered = true
                onExited: newTab.hovered = false
                onClicked: { if (root.m) { root.m.addProfile(); root.sel = root.profiles.length - 1; } }
              }
            }
          }
        }
      }

      // ────── HERO ──────
      RowLayout {
        Layout.fillWidth: true
        visible: root.current !== null
        spacing: Style.marginM

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM
            NText {
              text: root.current ? (root.current.name || "(unnamed)") : ""
              pointSize: Style.fontSizeL * 1.8
              color: Color.mOnSurface
            }
            Rectangle {
              visible: root.current && root.isProfileLiveOnAnyMonitor(root.current)
              Layout.alignment: Qt.AlignVCenter
              radius: Style.radiusS
              color: Qt.alpha(Color.mPrimary, 0.18)
              implicitWidth: liveRow.implicitWidth + Style.marginM
              implicitHeight: liveRow.implicitHeight + Style.marginXS * 2
              RowLayout {
                id: liveRow
                anchors.centerIn: parent
                spacing: Style.marginXS
                Rectangle { width: 7; height: 7; radius: 4; color: Color.mPrimary }
                NText { text: "live"; pointSize: Style.fontSizeXS; color: Color.mPrimary }
              }
            }
            Item { Layout.fillWidth: true }
          }
          NText {
            text: root.statusFor(root.current)
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
          }
        }

        Rectangle {
          id: switchBtn
          property bool hovered: false
          implicitWidth: switchRow.implicitWidth + Style.marginL * 2
          implicitHeight: 42 * Style.uiScaleRatio
          radius: Style.radiusM
          color: switchBtn.hovered ? Qt.alpha(Color.mPrimary, 0.85) : Color.mPrimary
          Behavior on color { ColorAnimation { duration: 110 } }
          RowLayout {
            id: switchRow
            anchors.centerIn: parent
            spacing: Style.marginS
            NText { text: "▶"; pointSize: Style.fontSizeS; color: Color.mOnPrimary }
            NText { text: "Switch"; pointSize: Style.fontSizeM; color: Color.mOnPrimary }
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: switchBtn.hovered = true
            onExited: switchBtn.hovered = false
            onClicked: if (root.m && root.current) root.m.activateProfile(root.current)
          }
        }
      }

      // ────── BODY (two columns) ──────
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.current !== null

        RowLayout {
          anchors.fill: parent
          spacing: Style.marginL

          // ─── LEFT COLUMN: placement + settings ───
          ColumnLayout {
            Layout.preferredWidth: parent.width * 0.6
            Layout.fillHeight: true
            spacing: Style.marginL

            // WORKSPACE PLACEMENT
            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.marginS
              NText { text: "WORKSPACE PLACEMENT"; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
              GridLayout {
                Layout.fillWidth: true
                columns: Math.max(1, (root.m ? root.m.outputs.length : 1))
                rowSpacing: Style.marginM
                columnSpacing: Style.marginM
                Repeater {
                  model: root.m ? root.m.outputs : []
                  delegate: Rectangle {
                    id: monCard
                    required property var modelData
                    readonly property bool isPrimary: root.current ? (root.current.output === modelData) : false
                    readonly property bool hasWs: root.current && (root.current.onAllScreens || root.current.output === modelData)
                    readonly property string wsName: (root.m && root.current && monCard.hasWs) ? root.m.wsNameFor(root.current, modelData) : ""
                    readonly property bool isLive: root.current && root.isProfileLiveOnOutput(root.current, modelData)
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150 * Style.uiScaleRatio
                    radius: Style.radiusM
                    color: monCard.hasWs ? Qt.alpha(Color.mSurfaceVariant, 0.6) : Qt.alpha(Color.mSurfaceVariant, 0.25)
                    border.color: monCard.isLive ? Color.mPrimary : (monCard.hasWs ? Qt.alpha(Color.mOutline, 0.6) : Qt.alpha(Color.mOutline, 0.3))
                    border.width: monCard.isLive ? 2 : 1
                    Behavior on border.color { ColorAnimation { duration: 140 } }
                    Behavior on border.width { NumberAnimation { duration: 140 } }

                    ColumnLayout {
                      anchors.fill: parent
                      anchors.margins: Style.marginM
                      spacing: Style.marginXS

                      RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS
                        NText {
                          Layout.fillWidth: true
                          text: monCard.modelData
                          pointSize: Style.fontSizeS
                          color: monCard.hasWs ? Color.mOnSurfaceVariant : Qt.alpha(Color.mOnSurfaceVariant, 0.6)
                          elide: Text.ElideRight
                        }
                        NText {
                          visible: monCard.isPrimary
                          text: "★"
                          pointSize: Style.fontSizeS
                          color: Color.mPrimary
                        }
                        Rectangle {
                          visible: monCard.isLive
                          width: 8; height: 8; radius: 4
                          color: Color.mPrimary
                        }
                      }

                      NText {
                        Layout.fillWidth: true
                        Layout.topMargin: Style.marginXS
                        text: monCard.hasWs ? ("\"" + monCard.wsName + "\"") : "—"
                        pointSize: Style.fontSizeL * 1.3
                        color: monCard.hasWs ? Color.mOnSurface : Color.mOnSurfaceVariant
                        elide: Text.ElideRight
                      }
                      NText {
                        Layout.fillWidth: true
                        visible: !monCard.hasWs
                        text: "not on this monitor"
                        pointSize: Style.fontSizeXS
                        color: Color.mOnSurfaceVariant
                      }

                      Item { Layout.fillHeight: true }

                      RowLayout {
                        Layout.fillWidth: true
                        visible: monCard.hasWs && root.current && (root.current.apps || []).length > 0
                        spacing: Style.marginXS
                        Repeater {
                          model: root.current ? (root.current.apps || []).slice(0, 8) : []
                          delegate: Image {
                            required property var modelData
                            source: root.appIconSrc(modelData.appId, modelData.icon)
                            sourceSize.width: 22
                            sourceSize.height: 22
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                            fillMode: Image.PreserveAspectFit
                          }
                        }
                        NText {
                          visible: (root.current.apps || []).length > 8
                          text: "+" + ((root.current.apps || []).length - 8)
                          pointSize: Style.fontSizeXS
                          color: Color.mOnSurfaceVariant
                        }
                        Item { Layout.fillWidth: true }
                      }
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: monCard.hasWs && root.current && root.current.onAllScreens ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: { if (root.current && root.current.onAllScreens) root.edit("output", monCard.modelData) }
                    }
                  }
                }
              }
              NText {
                visible: root.current && root.current.onAllScreens
                text: "Click a monitor to make it primary (gets the clean name)."
                pointSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
              }
            }

            // NAME
            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.marginXS
              NText { text: "NAME"; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
              NTextInput {
                Layout.fillWidth: true
                text: root.current ? root.current.name : ""
                placeholderText: "Profile name"
                onEditingFinished: if (text.length) root.edit("name", text)
              }
            }

            // MODE (3-way segmented)
            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.marginS
              NText { text: "MODE"; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
              Rectangle {
                Layout.fillWidth: true
                radius: Style.radiusM
                color: Qt.alpha(Color.mSurfaceVariant, 0.5)
                border.color: Qt.alpha(Color.mOutline, 0.4)
                border.width: 1
                implicitHeight: modeRow.implicitHeight + 6
                RowLayout {
                  id: modeRow
                  anchors.fill: parent
                  anchors.margins: 3
                  spacing: 3
                  Repeater {
                    model: [
                      { key: "single", label: "Single monitor",  hint: "Lives on one screen" },
                      { key: "all",    label: "All screens",     hint: "Independent on every screen" },
                      { key: "linked", label: "Linked",          hint: "Switches every screen together" }
                    ]
                    delegate: Rectangle {
                      id: segOpt
                      required property var modelData
                      property bool isSelected: root.current && root.modeOf(root.current) === segOpt.modelData.key
                      property bool hovered: false
                      Layout.fillWidth: true
                      Layout.preferredHeight: 48 * Style.uiScaleRatio
                      radius: Style.radiusS
                      color: segOpt.isSelected ? Color.mPrimary : (segOpt.hovered ? Qt.alpha(Color.mHover, 0.7) : "transparent")
                      Behavior on color { ColorAnimation { duration: 110 } }
                      ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 1
                        NText {
                          Layout.alignment: Qt.AlignHCenter
                          text: segOpt.modelData.label
                          pointSize: Style.fontSizeS
                          color: segOpt.isSelected ? Color.mOnPrimary : Color.mOnSurface
                        }
                        NText {
                          Layout.alignment: Qt.AlignHCenter
                          text: segOpt.modelData.hint
                          pointSize: Style.fontSizeXS
                          color: segOpt.isSelected ? Qt.alpha(Color.mOnPrimary, 0.75) : Color.mOnSurfaceVariant
                        }
                      }
                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: segOpt.hovered = true
                        onExited: segOpt.hovered = false
                        onClicked: root.setMode(segOpt.modelData.key)
                      }
                    }
                  }
                }
              }
            }

            // MONITOR (single-screen)
            ColumnLayout {
              Layout.fillWidth: true
              visible: root.current && !root.current.onAllScreens
              spacing: Style.marginXS
              NText { text: "MONITOR"; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
              Flow {
                Layout.fillWidth: true
                spacing: Style.marginS
                Repeater {
                  model: root.m ? root.m.outputs : []
                  delegate: Rectangle {
                    id: monChip
                    required property var modelData
                    property bool isPrimary: root.current ? (root.current.output === modelData) : false
                    property bool hovered: false
                    implicitWidth: chipRow.implicitWidth + Style.marginM * 2
                    implicitHeight: 32 * Style.uiScaleRatio
                    radius: Style.radiusS
                    color: monChip.isPrimary ? Color.mPrimary : (monChip.hovered ? Color.mHover : Color.mSurfaceVariant)
                    border.color: monChip.isPrimary ? Color.mPrimary : Qt.alpha(Color.mOutline, 0.5)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 110 } }
                    RowLayout {
                      id: chipRow
                      anchors.centerIn: parent
                      spacing: Style.marginXS
                      NText { visible: monChip.isPrimary; text: "★"; pointSize: Style.fontSizeS; color: Color.mOnPrimary }
                      NText {
                        text: monChip.modelData
                        pointSize: Style.fontSizeS
                        color: monChip.isPrimary ? Color.mOnPrimary : Color.mOnSurface
                      }
                    }
                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: monChip.hovered = true
                      onExited: monChip.hovered = false
                      onClicked: root.edit("output", monChip.modelData)
                    }
                  }
                }
              }
            }

            Item { Layout.fillHeight: true } // bottom spacer
          }

          // ─── RIGHT COLUMN: pinned apps ───
          ColumnLayout {
            Layout.preferredWidth: parent.width * 0.4
            Layout.fillHeight: true
            spacing: Style.marginS

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS
              NText {
                Layout.fillWidth: true
                text: "PINNED APPS"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
              }
              NText {
                visible: root.current && (root.current.apps || []).length > 0
                text: (root.current ? (root.current.apps || []).length : 0)
                pointSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
              }
              Rectangle {
                id: addAppBtn
                property bool hovered: false
                implicitWidth: addRow.implicitWidth + Style.marginM * 2
                implicitHeight: 30 * Style.uiScaleRatio
                radius: Style.radiusS
                color: addAppBtn.hovered ? Qt.alpha(Color.mPrimary, 0.85) : Color.mPrimary
                Behavior on color { ColorAnimation { duration: 110 } }
                RowLayout {
                  id: addRow
                  anchors.centerIn: parent
                  spacing: Style.marginXS
                  NText { text: "＋"; pointSize: Style.fontSizeS; color: Color.mOnPrimary }
                  NText { text: "Add app"; pointSize: Style.fontSizeS; color: Color.mOnPrimary }
                }
                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: addAppBtn.hovered = true
                  onExited: addAppBtn.hovered = false
                  onClicked: root.openPicker()
                }
              }
            }

            // apps list (scrollable)
            ScrollView {
              id: appsScroll
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              contentWidth: availableWidth
              ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

              ColumnLayout {
                width: appsScroll.availableWidth
                spacing: Style.marginS

                Repeater {
                  model: root.current ? (root.current.apps || []) : []
                  delegate: Rectangle {
                    id: appRow
                    required property int index
                    required property var modelData
                    property bool hovered: false
                    Layout.fillWidth: true
                    implicitHeight: appCol.implicitHeight + Style.marginM * 2
                    radius: Style.radiusS
                    color: appRow.hovered ? Color.mHover : Qt.alpha(Color.mSurfaceVariant, 0.6)
                    border.color: Qt.alpha(Color.mOutline, 0.3)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 90 } }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      acceptedButtons: Qt.NoButton
                      onEntered: appRow.hovered = true
                      onExited: appRow.hovered = false
                    }

                    ColumnLayout {
                      id: appCol
                      anchors.fill: parent
                      anchors.margins: Style.marginM
                      spacing: Style.marginXS
                      RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginM

                        Image {
                          source: root.appIconSrc(appRow.modelData.appId, appRow.modelData.icon)
                          sourceSize.width: 32
                          sourceSize.height: 32
                          Layout.preferredWidth: 32
                          Layout.preferredHeight: 32
                          fillMode: Image.PreserveAspectFit
                        }
                        ColumnLayout {
                          Layout.fillWidth: true
                          spacing: 0
                          NText {
                            Layout.fillWidth: true
                            text: appRow.modelData.name || appRow.modelData.appId
                            pointSize: Style.fontSizeM
                            color: Color.mOnSurface
                            elide: Text.ElideRight
                          }
                          NText {
                            Layout.fillWidth: true
                            text: appRow.modelData.appId
                            pointSize: Style.fontSizeXS
                            color: Color.mOnSurfaceVariant
                            elide: Text.ElideRight
                          }
                        }
                        NIconButton {
                          icon: "close"
                          baseSize: Style.baseWidgetSize * 0.7
                          tooltipText: "Remove"
                          onClicked: root.removeApp(appRow.index)
                        }
                      }
                      NTextInput {
                        Layout.fillWidth: true
                        text: appRow.modelData.title || ""
                        placeholderText: "Also match title (regex, for browser windows)"
                        fontSize: Style.fontSizeXS
                        onEditingFinished: root.editAppTitle(appRow.index, text)
                      }
                    }
                  }
                }

                // empty
                Rectangle {
                  Layout.fillWidth: true
                  visible: root.current && (root.current.apps || []).length === 0
                  implicitHeight: emptyCol.implicitHeight + Style.marginL * 2
                  color: "transparent"
                  border.color: Qt.alpha(Color.mOutline, 0.35)
                  border.width: 1
                  radius: Style.radiusS
                  ColumnLayout {
                    id: emptyCol
                    anchors.centerIn: parent
                    spacing: Style.marginXS
                    NText { Layout.alignment: Qt.AlignHCenter; text: "No apps pinned"; pointSize: Style.fontSizeS; color: Color.mOnSurface }
                    NText { Layout.alignment: Qt.AlignHCenter; text: "Add one — it'll auto-route to this profile's workspace"; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
                  }
                }
              }
            }
          }
        }
      }

      // ────── FOOTER ──────
      Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.alpha(Color.mOutline, 0.3); visible: root.current !== null }
      RowLayout {
        Layout.fillWidth: true
        visible: root.current !== null
        spacing: Style.marginS
        NText {
          text: "Drag tabs to reorder"
          pointSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
        }
        Item { Layout.fillWidth: true }
        Rectangle {
          id: delBtn
          property bool hovered: false
          implicitWidth: delRow.implicitWidth + Style.marginL * 2
          implicitHeight: 32 * Style.uiScaleRatio
          radius: Style.radiusS
          color: delBtn.hovered ? Qt.alpha(Color.mError ? Color.mError : Color.mPrimary, 0.15) : "transparent"
          border.color: Qt.alpha(Color.mError ? Color.mError : Color.mPrimary, 0.5)
          border.width: 1
          Behavior on color { ColorAnimation { duration: 100 } }
          RowLayout {
            id: delRow
            anchors.centerIn: parent
            spacing: Style.marginS
            NText { text: "🗑"; pointSize: Style.fontSizeS; color: Color.mError ? Color.mError : Color.mPrimary }
            NText { text: "Delete profile"; pointSize: Style.fontSizeS; color: Color.mError ? Color.mError : Color.mPrimary }
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: delBtn.hovered = true
            onExited: delBtn.hovered = false
            onClicked: { var i = root.sel; root.sel = Math.max(0, i - 1); root.m.deleteProfile(i); }
          }
        }
      }

      // empty (no profile)
      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.alignment: Qt.AlignCenter
        visible: root.current === null
        spacing: Style.marginS
        NText { Layout.alignment: Qt.AlignHCenter; text: "⧉"; pointSize: Style.fontSizeL * 3; color: Color.mOnSurfaceVariant }
        NText { Layout.alignment: Qt.AlignHCenter; text: "No profile yet"; pointSize: Style.fontSizeL; color: Color.mOnSurface }
        NText { Layout.alignment: Qt.AlignHCenter; text: "Hit ＋ New profile to set one up"; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
      }
    }

    // ═════════════ APP PICKER OVERLAY ═════════════
    Rectangle {
      anchors.fill: parent
      visible: root.pickerOpen
      color: Color.mSurface
      radius: Style.radiusM
      border.color: Qt.alpha(Color.mOutline, 0.4)
      border.width: 1

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.marginL
        spacing: Style.marginM

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginM
          NText {
            Layout.fillWidth: true
            text: "Pin an app"
            pointSize: Style.fontSizeL * 1.3
            color: Color.mOnSurface
          }
          NText {
            visible: root.pickerApps.length > 0
            text: root.pickerApps.length + (root.pickerApps.length === 1 ? " match" : " matches")
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
          }
          NIconButton {
            icon: "close"
            tooltipText: "Cancel"
            onClicked: root.pickerOpen = false
          }
        }
        NTextInput {
          Layout.fillWidth: true
          placeholderText: "🔍   Filter by name or app-id…"
          text: root.pickerQuery
          onTextChanged: root.pickerQuery = text
        }

        ListView {
          id: appList
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: root.pickerApps
          spacing: 2
          delegate: Rectangle {
            id: appItem
            required property int index
            required property var modelData
            property bool hovered: false
            width: ListView.view.width
            height: 52 * Style.uiScaleRatio
            radius: Style.radiusS
            color: appItem.hovered ? Color.mHover : "transparent"
            Behavior on color { ColorAnimation { duration: 90 } }
            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.marginM
              anchors.rightMargin: Style.marginM
              spacing: Style.marginM

              Image {
                source: root.appIconSrc(appItem.modelData.appId, appItem.modelData.icon)
                sourceSize.width: 30
                sourceSize.height: 30
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                fillMode: Image.PreserveAspectFit
              }
              // text column — fillWidth + NText fillWidth so name/id left-align
              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                NText {
                  Layout.fillWidth: true
                  text: appItem.modelData.name || appItem.modelData.appId
                  pointSize: Style.fontSizeM
                  color: Color.mOnSurface
                  elide: Text.ElideRight
                }
                NText {
                  Layout.fillWidth: true
                  text: appItem.modelData.appId
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                  elide: Text.ElideRight
                }
              }
              Rectangle {
                visible: !!appItem.modelData.running
                radius: Style.radiusS
                color: Qt.alpha(Color.mPrimary, 0.18)
                implicitWidth: runRow.implicitWidth + Style.marginS * 2
                implicitHeight: 22 * Style.uiScaleRatio
                RowLayout {
                  id: runRow
                  anchors.centerIn: parent
                  spacing: Style.marginXS
                  Rectangle { width: 6; height: 6; radius: 3; color: Color.mPrimary }
                  NText { text: "running"; pointSize: Style.fontSizeXS; color: Color.mPrimary }
                }
              }
            }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: appItem.hovered = true
              onExited: appItem.hovered = false
              onClicked: root.addAppObj(appItem.modelData)
            }
          }
        }

        // manual fallback
        Rectangle {
          Layout.fillWidth: true
          implicitHeight: manualCol.implicitHeight + Style.marginM * 2
          color: Qt.alpha(Color.mSurfaceVariant, 0.5)
          radius: Style.radiusS
          border.color: Qt.alpha(Color.mOutline, 0.4)
          border.width: 1
          ColumnLayout {
            id: manualCol
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: Style.marginXS
            NText {
              Layout.fillWidth: true
              text: "Can't find it? Enter the exact app-id"
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS
              NTextInput {
                id: manualApp
                Layout.fillWidth: true
                placeholderText: "e.g. org.kde.dolphin"
                fontSize: Style.fontSizeS
              }
              NButton {
                text: "Add"
                fontSize: Style.fontSizeS
                onClicked: { root.addAppId(manualApp.text); manualApp.text = ""; }
              }
            }
          }
        }
      }
    }
  }
}
