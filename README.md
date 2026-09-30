# GlobalProtect Toggle

Native AppKit macOS utility built from `global-protect.sh`.

## Run

Open `build/GlobalProtect Toggle.app`. Each normal launch toggles GlobalProtect immediately:

- Either LaunchAgent loaded → request VPN disconnect, verify disconnected status, then unload pangps followed by pangpa.
- Both unloaded → load pangpa, then pangps.

The compact window displays the status and provides a button to toggle again. Opening the app again while it is running also toggles it. Closing the window quits the utility; the GlobalProtect state stays as selected.

The commands use the same `launchctl load -w` / `unload -w` calls and exact plist paths as the original script. They run as the logged-in user. No administrator helper is installed. State is checked in `gui/<uid>` before and after the operation. Failure to reach the requested loaded/unloaded state is shown in an error alert with command output. The persistent login preference is saved before these commands and restored afterward, including command failure paths.

Turning off uses macOS Accessibility to invoke the installed GlobalProtect client’s Disconnect control. Allow GlobalProtect Toggle under System Settings → Privacy & Security → Accessibility on the first off operation, then retry. The utility waits up to 35 seconds for the client to show Not Connected or Disconnected. If permission is missing, the control is unavailable, or a reason/passcode prompt is pending, it reports the problem and leaves the agents loaded. Complete any GlobalProtect prompt manually, then retry. Turning on still loads only the LaunchAgents; GlobalProtect handles connection. This utility controls only the two LaunchAgents in the script; it does not change GlobalProtect's LaunchDaemon or system extension.

## Run at login

The **Run GlobalProtect at login** checkbox controls both `pangpa` and `pangps` for the current Mac account. Checked enables startup at the next login; unchecked disables it. Changing the checkbox does not connect, disconnect, load, or unload the current session. If the two agents have different settings, the checkbox shows a mixed state; clicking enables both.

The preference uses macOS's persistent `launchctl enable` / `disable` override in `gui/<uid>`. No administrator password is needed, and the system-owned plist files are not edited. The installed plists can have `RunAtLoad=false` while their `KeepAlive` settings imply startup, so `RunAtLoad` alone is insufficient to prevent it. The disabled override prevents startup even with those KeepAlive settings.

This controls the two per-user LaunchAgents, not the separate GlobalProtect system LaunchDaemon or other accounts. A GlobalProtect reinstall or administrator policy can change these settings. Manual toggles preserve the selected startup preference.

## Test

1. Open the app: with GlobalProtect off, it loads both agents.
2. Use the button again: it disconnects the VPN and then unloads both agents.
3. Check the GlobalProtect menu bar icon and the app's status.

Read-only startup preview (the button still performs an actual toggle when clicked):

```sh
open -n 'build/GlobalProtect Toggle.app' --args --preview
```

The app was opened in preview mode and its compact layout, startup control, and current status verified. Actual GlobalProtect start/stop is left for your interactive test.

## Build

Requires macOS with Xcode Command Line Tools:

```sh
./build.sh
```

Produces an Apple Silicon app for macOS 12 or later and a ZIP in `build/`. It is locally ad-hoc signed, not notarized for public distribution.

The icon is derived from `/Applications/GlobalProtect.app/Contents/Resources/PanMSAgent.icns`, with a green toggle badge. The original icon belongs to Palo Alto Networks.

Controller tests use simulated launchctl responses and do not change GlobalProtect:

```sh
xcrun swiftc -swift-version 5 Sources/ServiceController.swift Sources/VPNDisconnector.swift Tests/main.swift -o build/controller-tests -framework AppKit
./build/controller-tests
```

Checks cover start/stop ordering, both partial states, silent command failures, unavailable login sessions, missing plists, disconnect-before-unload ordering, failure preserving loaded agents, and disconnected-status recognition. Automated disconnect needs an interactive test with a running GlobalProtect client and Accessibility permission; this has not yet been verified live.


Startup checks additionally cover rollback after a partial failure and preservation of enabled, disabled, and mixed settings across manual toggles. The following integration check uses two disposable sleep LaunchAgents and does not operate on GlobalProtect:

```sh
xcrun swiftc -swift-version 5 Sources/ServiceController.swift Tests/Integration/main.swift -o build/integration-tests
./build/integration-tests
```

Real launchd verification passed for manual start/stop preserving startup overrides and startup changes leaving current loaded state unchanged. Behavior after an actual logout/reboot has not been exercised.
