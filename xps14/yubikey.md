# YubiKey touch for sudo (in place of the fingerprint reader)

## The fingerprint reader doesn't work

The reader is a Synaptics **06cb:0701 "SVP7500"** (in the power button). As of
2026-11, libfprint has no driver for it:

- the upstream `synaptics` driver only knows the older `06cb:01xx` IDs;
- `0701` isn't in libfprint's `autosuspend.hwdb`, not even as "known unsupported";
- there are no libfprint issues or MRs that mention it;
- Dell ships no Linux driver.

`fprintd` is installed (it comes with the OEM image) but `fprintd-list $USER` says
`No devices available`. Recheck after libfprint updates:

```sh
lsusb | grep 06cb
fprintd-list "$USER"
```

## What the YubiKey does instead

The YubiKey 5C Nano stays plugged in. With `pam_u2f`, **a touch replaces the password
for `sudo` only**:

| | Needs |
|---|---|
| `sudo`, `sudo -i` | touch (or the password, if the key is absent or you let it time out) |
| lock screen, GDM login | password |
| polkit (GUI admin prompts), `su` | password |

Why only sudo: you can only run `sudo` from an unlocked session, so you are
already there. A locked screen may mean you've walked away. Because the Nano never
leaves the laptop, accepting a touch at the lock screen would let anyone who picks up
the laptop unlock it.

## Setup

```sh
cd xps14
sudo ./yubikey-sudo.sh     # touch the key when it blinks
```

The script:

1. installs `libpam-u2f` and `pamu2fcfg`;
2. registers the key in `/etc/u2f_mappings`, which is root-owned so that a process
   running as you can't enrol its own key. It uses the fixed origin `pam://sudo`, so
   the registration survives a hostname change;
3. adds the following before `@include common-auth` in `/etc/pam.d/sudo` and
   `/etc/pam.d/sudo-i`, keeping the originals as `*.pre-u2f`:

   ```
   auth sufficient pam_u2f.so authfile=/etc/u2f_mappings origin=pam://sudo appid=pam://sudo cue
   ```

`sufficient` means a touch ends authentication right away. Anything else (no key,
timeout, module error) falls through to the normal password prompt, so a broken
`pam_u2f` can't lock you out of sudo. Even so, keep a `sudo -s` shell open while
you test.

### More keys

Any registered key works. All four of mine are enrolled. Because `pamu2fcfg` only
talks to the first key it finds, register one at a time with only that key inserted
(pull the Nano out too):

```sh
sudo ./yubikey-sudo.sh --add     # repeat for each key; refuses if >1 key is in
```

Each key's credential is appended to your single line in `/etc/u2f_mappings`
(`user:cred1:cred2:...`). Running the script with no arguments reports how many keys
are registered. To drop a lost key, delete its `:keyhandle,...` segment from that line.

Test it in a new terminal:

```sh
sudo -k; sudo true          # "Please touch the device." -> touch
```

Undo: `sudo ./yubikey-sudo.sh --remove`.

## Caveat

Any process running as you can start `sudo` and wait for a touch. Only touch the key
when *you* just ran a sudo command and the terminal is showing the touch prompt.
