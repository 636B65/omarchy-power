import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Wayland

// Sleeps the machine after a per-power-source idle timeout.
//
// logind's IdleAction= never fires on Omarchy: nothing in the session reports
// an idle hint to logind. This service does the idle tracking in the session
// instead, with the same Wayland idle notification the built-in omarchy.idle
// service uses, and runs `systemctl <action>` itself.
//
// Settings live inline on this plugin's entry in ~/.config/omarchy/shell.json:
//
//   "plugins": [
//     { "id": "omarchy-power.idle-sleep",
//       "acAction": "ignore", "acTimeout": 0,
//       "batteryAction": "suspend", "batteryTimeout": 1800 }
//   ]
//
// Timeouts are seconds since idle began; 0 or action "ignore" disables that
// source. "dryRun": true sends a notification instead of sleeping.
Item {
  id: root

  readonly property string pluginId: "omarchy-power.idle-sleep"
  readonly property string home: Quickshell.env("HOME")
  readonly property var allowedActions: ["ignore", "suspend", "hibernate", "hybrid-sleep", "suspend-then-hibernate", "poweroff"]
  readonly property string screensaverClass: "org.omarchy.screensaver"

  // The away period starts after this much input silence (or the configured
  // timeout, if shorter); the per-source timeouts are measured from there.
  readonly property int awayAfterSeconds: 10
  // Activity is judged this long after it is reported, so the screensaver or
  // lock surface has time to appear when it caused the report itself.
  readonly property int activityGraceMs: 3000

  property var settings: ({})
  property bool settingsLoaded: false

  readonly property string acAction: actionFrom(settings.acAction, "ignore")
  readonly property int acTimeout: secondsFrom(settings.acTimeout, 0)
  readonly property string batteryAction: actionFrom(settings.batteryAction, "suspend")
  readonly property int batteryTimeout: secondsFrom(settings.batteryTimeout, 1800)
  readonly property bool dryRun: settings.dryRun === true

  readonly property bool acEnabled: acAction !== "ignore" && acTimeout > 0
  readonly property bool batteryEnabled: batteryAction !== "ignore" && batteryTimeout > 0
  readonly property int firstTimeout: {
    if (acEnabled && batteryEnabled) return Math.min(acTimeout, batteryTimeout)
    if (acEnabled) return acTimeout
    if (batteryEnabled) return batteryTimeout
    return 0
  }
  readonly property int monitorTimeout: firstTimeout > 0 ? Math.min(awayAfterSeconds, firstTimeout) : 0

  readonly property bool onBattery: UPower.onBattery
  readonly property string source: onBattery ? "battery" : "ac"

  readonly property bool isIdle: idleLoader.item ? idleLoader.item.isIdle : false
  property bool monitorRebuilding: false

  property bool away: false
  property double awaySinceMs: 0
  property double lastActiveMs: 0
  property bool actedThisCycle: false
  property bool locked: false
  property var screensaverWindows: ({})
  readonly property int screensaverCount: Object.keys(screensaverWindows).length
  property string lastEvent: "starting"

  function actionFrom(value, fallback) {
    var action = String(value === undefined ? fallback : value)
    return allowedActions.indexOf(action) !== -1 ? action : fallback
  }

  function secondsFrom(value, fallback) {
    var n = Number(value)
    if (value === undefined || !isFinite(n) || n < 0) return fallback
    return Math.floor(n)
  }

  function logEvent(event) {
    root.lastEvent = new Date().toISOString() + " " + event
    console.log("omarchy-power idle-sleep " + root.lastEvent)
  }

  function loadSettings(text) {
    var next = ({})
    try {
      var config = JSON.parse(text)
      var entries = config && Array.isArray(config.plugins) ? config.plugins : []
      for (var i = 0; i < entries.length; i++) {
        if (entries[i] && entries[i].id === root.pluginId) {
          next = entries[i]
          break
        }
      }
    } catch (error) {
      logEvent("shell.json parse error, keeping previous settings: " + error)
      return
    }
    root.settings = next
    root.settingsLoaded = true
    logEvent("settings ac=" + root.acAction + "/" + root.acTimeout
      + " battery=" + root.batteryAction + "/" + root.batteryTimeout
      + (root.dryRun ? " dryRun" : ""))
  }

  function currentProfile() {
    return root.onBattery
      ? { action: root.batteryAction, timeout: root.batteryEnabled ? root.batteryTimeout : 0 }
      : { action: root.acAction, timeout: root.acEnabled ? root.acTimeout : 0 }
  }

  function awaySeconds() {
    return root.away ? (Date.now() - root.awaySinceMs) / 1000 : 0
  }

  function startAway() {
    // The monitor reports idle once monitorTimeout has already elapsed.
    root.away = true
    root.awaySinceMs = Date.now() - root.monitorTimeout * 1000
    root.actedThisCycle = false
    logEvent("away")
    checkTimer.start()
    evaluate()
  }

  function endAway(reason) {
    if (!root.away) return
    root.away = false
    root.awaySinceMs = 0
    root.actedThisCycle = false
    checkTimer.stop()
    activityTimer.stop()
    deadlineTimer.stop()
    logEvent("back: " + reason)
  }

  // Launching the screensaver and locking both make the compositor report
  // activity, and the built-in idle service relaunches the screensaver while
  // locked. Activity only ends the away period when, after a short grace,
  // the monitor still reports activity, the session is unlocked and no
  // screensaver is up.
  // Unlocking from the lock screen is caught by the periodic lock probe,
  // since the password is typed while still locked.
  function reconcile() {
    if (!root.away) return
    if (!root.isIdle && !root.locked && root.screensaverCount === 0
        && Date.now() - root.lastActiveMs >= root.activityGraceMs) {
      endAway("activity while unlocked")
      return
    }
    evaluate()
  }

  function evaluate() {
    if (!root.away || root.actedThisCycle || actionProcess.running) return
    var profile = currentProfile()
    if (profile.timeout <= 0) return
    var remainingMs = profile.timeout * 1000 - (Date.now() - root.awaySinceMs)
    if (remainingMs > 0) {
      deadlineTimer.interval = Math.max(1, Math.ceil(remainingMs))
      deadlineTimer.restart()
      return
    }
    act(profile.action)
  }

  function act(action) {
    root.actedThisCycle = true
    logEvent("away " + Math.round(awaySeconds()) + "s on " + root.source + ", running " + action + (root.dryRun ? " (dry run)" : ""))
    actionProcess.command = ["bash", "-c", actionScript, "idle-sleep", action, root.dryRun ? "1" : "0"]
    actionProcess.running = true
  }

  function probeLock() {
    if (!lockProbe.running) lockProbe.running = true
  }

  // Exit 3/4 mean "not now"; the cycle stays armed and is retried. Anything
  // else ends the attempts until the user is back, so a resume without input
  // cannot loop straight back into sleep.
  readonly property string actionScript: "
    [[ -f $HOME/.local/state/omarchy/indicators/stay-awake ]] && exit 3
    if busctl call --json=short org.freedesktop.login1 /org/freedesktop/login1 \\
        org.freedesktop.login1.Manager ListInhibitors 2>/dev/null \\
        | jq -e 'any(.data[0][]; .[3] == \"block\" and (.[0] | split(\":\") | index(\"idle\")))' >/dev/null; then
      exit 4
    fi
    if [[ $2 == 1 ]]; then
      notify-send -a omarchy-power 'Idle sleep (dry run)' \"Would run: systemctl $1\"
      exit 0
    fi
    exec systemctl \"$1\"
  "

  function statusJson() {
    return JSON.stringify({
      source: root.source,
      idle: root.isIdle,
      away: root.away,
      awaySeconds: Math.round(awaySeconds()),
      locked: root.locked,
      screensaver: root.screensaverCount > 0,
      actedThisCycle: root.actedThisCycle,
      ac: { action: root.acAction, timeout: root.acTimeout, enabled: root.acEnabled },
      battery: { action: root.batteryAction, timeout: root.batteryTimeout, enabled: root.batteryEnabled },
      dryRun: root.dryRun,
      monitor: {
        settingsLoaded: root.settingsLoaded,
        active: idleLoader.active,
        timeout: idleLoader.item ? idleLoader.item.timeout : null
      },
      lastEvent: root.lastEvent
    })
  }

  onOnBatteryChanged: {
    if (!root.settingsLoaded) return
    logEvent("power source " + root.source)
    evaluate()
  }

  onIsIdleChanged: {
    if (isIdle) {
      if (!root.away) startAway()
    } else {
      root.lastActiveMs = Date.now()
      if (root.away) {
        activityTimer.restart()
        probeLock()
      }
    }
  }

  // An IdleMonitor keeps the timeout it was created with, so a changed
  // monitorTimeout rebuilds it instead of rebinding the property. It also stays
  // unloaded until shell.json has been read, so it never starts on defaults.
  onMonitorTimeoutChanged: {
    if (!idleLoader.active) return
    root.monitorRebuilding = true
    Qt.callLater(function() { root.monitorRebuilding = false })
  }

  onFirstTimeoutChanged: if (firstTimeout <= 0) endAway("idle sleep disabled")

  Loader {
    id: idleLoader
    active: root.settingsLoaded && root.monitorTimeout > 0 && !root.monitorRebuilding
    sourceComponent: Component {
      IdleMonitor {
        timeout: root.monitorTimeout
        respectInhibitors: true
      }
    }
  }

  Timer {
    id: activityTimer
    interval: root.activityGraceMs
    repeat: false
    onTriggered: root.probeLock()
  }

  Timer {
    id: deadlineTimer
    repeat: false
    onTriggered: root.evaluate()
  }

  Timer {
    id: checkTimer
    // Poll faster while locked so an unlock is noticed promptly.
    interval: root.locked ? 5000 : 15000
    repeat: true
    onTriggered: root.probeLock()
  }

  Process {
    id: lockProbe
    command: ["omarchy-hyprland-session-locked"]
    onExited: function(exitCode, exitStatus) {
      // 0 locked, 1 unlocked, 2 undetermined (keep the last known state).
      var wasLocked = root.locked
      if (exitCode === 0) root.locked = true
      else if (exitCode === 1) root.locked = false
      // Unlocking takes the user's password, so it is a return on its own,
      // even if no input follows before the next check.
      if (wasLocked && !root.locked && root.away) {
        root.endAway("unlocked")
        return
      }
      root.reconcile()
    }
  }

  Process {
    id: actionProcess
    onExited: function(exitCode, exitStatus) {
      if (exitCode === 3 || exitCode === 4) {
        root.logEvent("skipped: " + (exitCode === 3 ? "stay awake is on" : "idle inhibitor active"))
        root.actedThisCycle = false
      } else {
        root.logEvent("action exited " + exitCode)
      }
    }
  }

  function setScreensaverWindow(address, open) {
    var next = ({})
    for (var key in root.screensaverWindows)
      if (key !== address) next[key] = true
    if (open) next[address] = true
    root.screensaverWindows = next
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event && event.name ? event.name : "")
      var parts = String(event && event.data ? event.data : "").split(",")
      if (name === "openwindow" && parts[2] === root.screensaverClass) {
        root.setScreensaverWindow(parts[0], true)
      } else if (name === "closewindow" && root.screensaverWindows[parts[0]]) {
        root.setScreensaverWindow(parts[0], false)
        // Dismissing the screensaver by hand is a return; closing it because
        // the lock took over is not. Let the lock probe decide.
        if (root.away) {
          root.lastActiveMs = Date.now()
          activityTimer.restart()
        }
      }
    }
  }

  FileView {
    id: shellConfig
    path: root.home + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onFileChanged: reload()
  }

  IpcHandler {
    target: "idle-sleep"

    function status(): string {
      return root.statusJson()
    }
  }
}
