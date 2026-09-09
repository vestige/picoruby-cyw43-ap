# Development TODO

This document records the development state and the work that must remain
separate from PicoRuby core. Update it when a milestone or validation result
changes.

## Intended use cases

- Take a Raspberry Pi Pico outdoors, connect it as a station to an existing
  network such as a smartphone hotspot, and control the Pico from the phone.
- Where no existing network is available, make the Pico itself an access point
  and provide a standalone environment in which the phone communicates
  directly with the Pico.
  - For example, use the phone to operate a simple timer or as a remote control
    for an RC vehicle.

This gem primarily provides the AP and DHCP foundation for the second use case.
The user interface and HTTP communication belong to a later milestone. The
existing STA use case must continue to work without regression.

## Current state (2026-09-09)

- This repository is the third-party `picoruby-cyw43-ap` mrbgem.
- `main` tracks `origin/main` at `vestige/picoruby-cyw43-ap`.
- This repository is based on the initial MIT license commit on GitHub.
- The initial implementation includes the gem itself, English and Japanese
  documentation, type signature, and example.
- Compilation and linking have been verified for all three target
  configurations. AP and DHCP validation on hardware is in progress.
- On Pico 2 W with mruby/c, AP startup, client SSID discovery and connection,
  Ruby API state and IPv4 inspection, and AP shutdown have been verified on
  hardware.
- In the same hardware validation, the client received `192.168.4.2/24` by
  DHCP with router `192.168.4.1`. The client Wi-Fi settings screen continued
  to show a connecting indicator for about 10 seconds; the source of the delay
  is not yet known.
- A code audit of the AP shutdown path verified removal and clearing of the
  DHCP PCB reference and erasure of the lease array. Hardware validation
  confirmed the inactive API state and disappearance of the SSID.
- PicoRuby core must not be patched to install this gem.
- HTTP server and socket lifecycle work are outside the first AP/DHCP
  milestone.

## Before the first commit

- [x] Review every untracked file and confirm that no credentials, firmware,
      build output, serial logs, or temporary symlinks are included.
- [x] Resolve the LICENSE copyright line. The GitHub version currently names
      `Makoto Yonezawa`; the local draft previously used
      `picoruby-cyw43-ap contributors`.
- [x] Confirm `mrbgem.rake` declares its dependency on `picoruby-cyw43`.
- [x] Review the `CYW43::AP` API and the PR #489 compatibility method names.
- [x] Review the limited dependency on the private Ruby `_init` entry point
      used to clean up DHCP before `CYW43.init(force: true)`.
- [x] Confirm that TinyUSB-derived DHCP code retains its copyright and MIT
      notice.
- [x] Re-run all build checks after any source change.
- [x] Commit and push only after explicit approval.

## First AP/DHCP milestone

- [x] Build as an external mrbgem without changing tracked PicoRuby core files.
- [x] Compile and link Pico 2 W with mruby/c.
- [x] Compile and link Pico 2 W with mruby.
- [x] Compile and link Pico W with mruby/c using
      `R2P2_NO_SHARED_ALLOC=1`.
- [x] On Pico W or Pico 2 W, start the AP and detect its SSID from a client.
- [x] Obtain a client address by DHCP.
- [x] Verify `active?`, `ssid`, `ipv4_address`, and `ipv4_netmask` from Ruby.
- [x] Disable the AP and verify that the DHCP PCB and leases are released.
- [ ] Enable the AP again after disabling it.
- [ ] Verify cleanup during `CYW43.init(force: true)`.
- [ ] Check that an existing STA-only program still behaves as before.

Do not flash hardware unless the board, BOOTSEL volume, serial device, and
serial-port owner have been identified unambiguously. Keep validation-only
PicoRuby build configuration changes in a temporary worktree.

## Deferred milestone

Start this only after the AP/DHCP milestone is stable:

- [ ] Add a minimal HTTP-server example outside PicoRuby core.
- [ ] Test repeated `accept`, `recv`, and `close` lifecycles.
- [ ] Test refreshes, multiple tabs, reconnects, and client Wi-Fi recovery.
- [ ] Revisit the Pico Timer application and browser-facing behavior.

## PicoRuby core references

Core repository: `/Users/vestige/Spike/picoruby`

Keep these references until the external gem has a reviewed initial commit and
the provenance of the migrated code is documented:

- `codex/cyw43-ap-dhcp-review` / `c94d9808`: consolidated PR #489 AP/DHCP code.
- `codex/cyw43-ap-review` / `44d01d06`: staged PR #489 development history.
- `codex/sta-connect-retry-once-example` / `e83b87ae`: STA example plus socket
  background handling; this is not the external gem's development branch.
- `codex/pcw-timer-replacement` and the `codex/cyw43-ap-*` branches: earlier
  AP, HTTP, timer, and socket experiments.

### Later branch cleanup

- [ ] Fetch both `origin` and `upstream` and record their current tips.
- [ ] Check every candidate with `git branch -vv`, `git branch --merged`, and
      `git branch --no-merged` before deleting anything.
- [ ] Preserve PR #489 commits by tag, remote branch, or written commit IDs
      before removing local branches.
- [ ] Run `git worktree list` and confirm which worktrees still exist.
- [ ] Use `git worktree prune` only for entries explicitly reported as
      `prunable`; do not remove a live validation worktree by assumption.
- [ ] Treat `master`, `codex/master-reset`, serial-runner branches, and timer
      branches as separate cleanup decisions.
- [ ] Never force-push or delete remote branches as part of routine local
      cleanup.

## Useful validation commands

Run from a temporary PicoRuby worktree that references this gem:

```sh
PATH=/opt/homebrew/opt/ruby/bin:$PATH \
  rake r2p2:femtoruby:pico2_w:prod

PATH=/opt/homebrew/opt/ruby/bin:$PATH \
  rake r2p2:picoruby:pico2_w:prod

PATH=/opt/homebrew/opt/ruby/bin:$PATH \
  R2P2_NO_SHARED_ALLOC=1 rake r2p2:femtoruby:pico_w:prod
```

The previous validation worktree was
`/private/tmp/picoruby-cyw43-ap-validate.C09rUr`. It is disposable build
infrastructure, not the source of truth for this gem.
