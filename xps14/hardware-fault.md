# Intermittent embedded controller fault

Since August 2026 this machine has had sudden power-offs, Dell diagnostic blink
codes, a false "not a Dell battery" warning and blocked charging. All of these
are handled by the embedded controller (EC), the always-on chip on the system
board that manages power, charging, the battery handshake, USB-C power
negotiation and the power-button LED. A Dell warranty case was opened on
2026-10-14 (filed as "battery problem"; an onsite technician is being scheduled).

The EC sits below the OS, so most of this is invisible to Linux. The blink
codes have to be read off the power button by eye.

## Symptoms

| Symptom | Seen |
|---|---|
| Sudden power-off: no shutdown, nothing in pstore, no BERT record, journals corrupt on next boot | Aug 1, Sep 11, Oct 9, Oct 14 (41, 28, then 5 days apart) |
| Blink code **1,6**: "generic catch-all for ungraceful EC code flow errors" | Sep 12 |
| Blink code **1,1**: "TPM detection failure", mostly **with the OS running normally** | Oct 14, at least four times |
| BIOS warns the original factory battery is "not a Dell battery" | Oct 14, during a 1,1 blink |
| Battery won't charge (about 1 mA) while 1,1 is active, even on the Dell 100 W charger plugged in directly | Oct 14 |
| The Dell 100 W charger negotiates only 15 V / 5 A (75 W), not 20 V | Oct 14 |
| F12 diagnostics fail: "battery cannot supply the system with sufficient power" | Oct 14 (they passed on Sep 12) |

Code meanings are from the [DA14260 service manual's diagnostic-light table](https://www.dell.com/support/manuals/en-us/xps-da14260-laptop/xps-14-da14260-service-manual/system-diagnostic-lights?guid=guid-924845d7-957f-49d6-8494-0d7d6b10e34d&lang=en-us).
Dell's general [XPS laptop diagnostic guide](https://www.dell.com/support/kbdoc/en-us/000141206/a-reference-guide-to-the-xps-notebook-diagnostic-indicators)
covers 2014–2025 models only and has no 1,x rows. A code N,M is N amber
flashes, a short pause, M white flashes, then a long pause.

## Timeline

Newest first. Times are PDT.

| When | Event | Power |
|---|---|---|
| Oct 14, evening | F12 diagnostics fail (see above) | Dell 100 W direct |
| Oct 14, 17:34 | Charging blocked on the Dell 100 W charger plugged in directly; stuck at 75 % | Dell 100 W direct |
| Oct 14, 17:33 | Blink 1,1; charging stops at the same moment | monitor USB-C |
| Oct 14, 15:35 | Blink 1,1 with the OS running; "Not charging" at 78 % with the charge cap removed | 45 W USB-C |
| Oct 14, 15:30 | Clean reboot; BIOS "not a Dell battery" warning during a 1,1 blink | 45 W USB-C |
| Oct 14, 12:20 | First boot after power loss #4: the Intel Bluetooth controller is wedged (`btintel_pcie`: `Controller in error state`) and blocks every later suspend with `-16`. Reloading the module fixed it. | — |
| Oct 14, 11:39 | **Power loss #4.** Lid closed, began to sleep, never resumed | battery |
| Oct 14, 06:52 and 06:57 | Blink 1,1 twice with the OS running; cleared by itself | 45 W USB-C |
| Oct 9, 07:39 | **Power loss #3.** Lid closed, began to sleep, never resumed | battery |
| Sep 12 | Blink 1,6; a reboot cleared it and F12 diagnostics passed | — |
| Sep 11, 15:37 | **Power loss #2.** Awake and in use, battery at 70 % | battery |
| Aug 1, 21:35 | **Power loss #1.** Awake at a desk, lid open | AC |

Throughout, the kernel shows the EC and the USB-C controller stalling:

```
workqueue: acpi_ec_event_processor hogged CPU for >10000us 131 times
workqueue: ucsi_handle_connector_change [typec_ucsi] hogged CPU for >10000us 19 times
ucsi_acpi USBC000:00: UCSI_GET_PDOS failed (-5)
ucsi_acpi USBC000:00: unknown error 0
```

## The two sleep crashes weren't real sleep

UPower's battery history (`/var/lib/upower/history-charge-DELL_*.dat`) shows how
much each sleep cost. Normal s2idle on this machine uses **0.35–0.9 %/h**
(about 0.25–0.6 W; 8 sleeps of 1–16 h in the week before).

| Power loss | Battery at lid close → next boot | Window | Minimum drain |
|---|---|---|---|
| #3, Oct 9 | 74 % → 61 % | 2 h 35 min | ≥ 5 %/h, at least 12× normal |
| #4, Oct 14 | 78 % → 75 % | 41 min | ≥ 4.4 %/h, about 10× normal |

These are minimums, because draining stops when power is cut. Both times the
journal ends at `PM: suspend entry (s2idle)` with no failure message. So the
machine got partway into suspend and then burned power at about awake-idle
levels, closed in a bag, until it lost power.

This is **not** the [camera leak](suspend.md): that aborts loudly
(`psys_suspend ... returns -16`, `Some devices failed to suspend`) and the
machine stays awake, and neither crashed boot logs it.

### Checking whether a sleep was real

`/sys/devices/system/cpu/cpuidle/low_power_idle_system_residency_us` counts
time spent in the deepest platform state. It only moves during s2idle, so it
will look frozen while the machine is awake. Read it before closing the lid and
after opening it: the difference should be close to the time the lid was shut.

| Test (on battery) | Asleep | Deep residency | Result |
|---|---|---|---|
| Clean boot, no BT/USB devices, no Zoom | 392 s | 390.4 s (99.6 %) | real sleep; battery cooled 27.6 → 26.2 °C |
| Same, Zoom still running | — | 0 s | suspend aborted twice by `intel_ipu7_psys` (`-16`), machine stayed awake |

## Battery or board?

The evidence favors the board:

- The battery is the original part (`DELL 7X1VJ64Q`, made 2026-04, 15 cycles,
  full design capacity), so "not a Dell battery" is false.
- It ran the machine normally on Oct 14 and slept correctly on battery at 15:41.
- Power loss #1 was on AC with the machine awake.
- Every check that fails (battery authentication, charging, USB-C negotiation,
  the TPM check behind 1,1, the power cut itself) belongs to the EC.

But the OS reads battery health *through* the EC, so a fault in the battery's
own controller or connector can't be fully ruled out. A battery swap is a fair
first step if F12 diagnostics and charging on the Dell 100 W charger are
re-tested straight after it. If 1,1, the charging block or a power-off comes
back on the new battery, it's the system board.

## Not the cause

- **Kernel panic:** `efi_pstore` is a working backend and pstore was empty.
- **Firmware-caught hardware error:** APEI firmware-first is on and there was
  no BERT on the next boot.
- **Load, MCE:** nothing logged before any event.
- **Charger or dock:** losses happened on AC and on battery.
- **Stale firmware:** BIOS 1.8.2 is the newest on LVFS (checked 2026-10-14).
  The EC image ships inside the BIOS capsule, so there is no separate EC update.
- **TPM gone:** `/dev/tpm0` still enumerates as TPM 2.0 after a 1,1 blink.

## Gotchas when digging

- `kdump` is installed and `crashkernel=` is reserved, but it isn't armed, so a
  missing vmcore proves nothing.
- `journalctl -k --since <date>` can miss entries across rotated journals;
  iterate `-b N` instead.
- A boot ended cleanly if it contains `systemd-shutdown` or
  `Reached target (Shutdown|Power-Off|Reboot)`.
- Whether the machine was on AC at a past moment can be recovered from
  `anacron.service ... ConditionACPower=true` (skipped means on battery).
- `dmidecode --type 15` is a dead end: there is no System Event Log table.
- The power-button LED is not in `/sys/class/leds`. It is EC-driven and
  can't be read from software.
- The `WARNING ... __setup_irq` at boot and `unexpected IRQ trap at vector e6`
  on resume happen on every boot and are unrelated.
