# Development TODO

This document records the development state and the work that must remain
separate from PicoRuby core. Update it when a milestone or validation result
changes.

GitHub Issue and pull request titles, descriptions, and validation comments
are written in Japanese by default. Commit messages remain in English to match
the existing history.

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

## Current state (2026-09-11)

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
- Without rebooting the Pico, the AP was re-enabled and the client reconnected
  with the same DHCP settings. The second connection completed faster than
  the first, but the source of the difference is not yet known.
- On Pico 2 W with mruby/c, force init while the AP was active shut it down,
  reinitialized the driver, and allowed the AP and DHCP to be reused. The
  pre-force-init cleanup paths were audited in both mruby/c and mruby bindings.
- On the same firmware, an STA-only connection reached `LINK_UP` with assigned
  IPv4 settings while the AP remained inactive, then returned to `LINK_DOWN`
  after disconnecting. Only encrypted device-local connection settings were
  used, and no connection details were recorded.
- A minimal HTTP server example outside PicoRuby core returned its plain-text
  response to a browser on Pico 2 W with mruby/c and left the AP inactive after
  a clean Ctrl-C exit.
- Twenty sequential requests, responses, and client closes succeeded on the
  same AP and HTTP server. Rebinding the same port after shutdown still
  required rebooting the Pico, and interrupting a waiting `TCPServer#accept`
  produced its existing shutdown exception. Both are PicoRuby socket follow-up
  issues tracked in Issue #16.
- Issue #16 isolation showed that the same port can be rebound immediately
  after an AP restart when no client has connected. With the AP left active,
  accepting and closing only one client before closing the server makes the
  rebind fail. The current `picoruby-socket` sets `SOF_REUSEADDR` on the
  listener, but PicoRuby's `lwipopts.h` does not enable `SO_REUSE`, so lwIP's
  TIME_WAIT reuse paths are not compiled. A comparison firmware enabling only
  `SO_REUSE=1` in a temporary worktree successfully rebound immediately after
  the same one-client sequence. Ten consecutive cycles, each accepting and
  closing one client, closing the server, and rebinding the same port, all
  passed. This comparison confirms the cause on hardware. The same A/B result
  was reproduced on PicoRuby upstream `80efbea3` with Pico 2 W and mruby: the
  unmodified firmware failed the immediate rebind after one client, while the
  firmware enabling only `SO_REUSE=1` passed.
- With the same `SO_REUSE=1` comparison firmware, Ctrl-C while waiting in
  `TCPServer#accept` still produced `server is not initialized`. The `ensure`
  cleanup did disable the AP and `active?` was false, confirming that this
  shutdown exception is independent of the rebind issue. The mruby build also
  rebound immediately after one connection. Its Ctrl-C path reported
  `server is not initialized` while closing the already-closed server during
  cleanup, followed by `Already stopped`; AP cleanup still succeeded. Neither
  behavior is binding-specific. The first mruby client connection dropped its
  Wi-Fi connection once, but a retry completed the HTTP response and rebind,
  so the drop has not been reproduced.
- Core follow-up status at the time (2026-09-16): [PR #506](https://github.com/picoruby/picoruby/pull/506)
  merged the rebind fix. All four CI checks passed on
  [PR #509](https://github.com/picoruby/picoruby/pull/509). Its commit `95bf98ac` stops
  accept after interruption, restores the INT handler, and makes mruby server
  close idempotent. Socket tests passed 57/57 on both VMs, and Steep passed.
  On Pico 2 W with both VMs, a test rescuing `Interrupt` confirmed cleanup,
  AP inactive, and shell return without server lifecycle errors. The earlier
  error observations above are historical, not the modified firmware results.
- Current Core follow-up status (2026-09-26): PR #509 was closed because it
  did not safely cover the actual R2P2 Ctrl-C path where `ensure` may not run,
  handler restoration across tasks, or interruption while an `accept_loop`
  block handles a client. Its replacement,
  [PR #513](https://github.com/picoruby/picoruby/pull/513), is merged. Future
  hardware validation uses current upstream containing #513 rather than
  building new firmware from #509 commit `95bf98ac`.
- [Core #505](https://github.com/picoruby/picoruby/issues/505) was resolved by
  PR #506 and is closed. The post-#513 revalidation does not require an update
  to that issue.
- Intermittent rerun instability of an AP/socket-free script was observed on
  baseline and modified mruby/c firmware. Its cause is unknown and is tracked
  separately in [Core #510](https://github.com/picoruby/picoruby/issues/510).
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
- [x] Enable the AP again after disabling it.
- [x] Verify cleanup during `CYW43.init(force: true)`.
- [x] Check that an existing STA-only program still behaves as before.

Do not flash hardware unless the board, BOOTSEL volume, serial device, and
serial-port owner have been identified unambiguously. Keep validation-only
PicoRuby build configuration changes in a temporary worktree.

## Deferred milestone

Start this only after the AP/DHCP milestone is stable:

- [x] Add a minimal HTTP-server example outside PicoRuby core.
- [x] Test repeated `accept`, `recv`, and `close` lifecycles.
- [x] Test refreshes, multiple tabs, reconnects, and client Wi-Fi recovery.
      - [x] Test sequential browser refreshes on Pico 2 W + mruby/c with Core
        `95bf98ac` from #509. After replacing blocking `gets` with bounded
        nonblocking header reads, 21 same-tab reloads completed with the
        expected response and no socket error. Ctrl-C cleanup disabled the AP
        and returned to the shell; a separate check reported inactive/nil.
      - [x] Test multiple tabs and concurrent browser connections.
        - On Pico 2 W with mruby/c and Core `95bf98ac`, an automated browser
          test issued 20 total requests with maximum concurrency of one, two,
          and three. Concurrency one passed 20/20, concurrency two passed
          60/60 over three runs, and concurrency three passed 40/40 over its
          first two runs.
        - On the third concurrency-three run, 7/20 completed before the next
          `client.write` failed to return after its request had been read. The
          remaining browser requests reached their 10-second timeout. Every
          earlier client completed both write and close. A similar stall was
          observed in another run but does not occur immediately every time.
          Treat this as a separate possible `picoruby-socket` issue rather
          than attributing it to the AP gem without further evidence.
        - Issue #24 compared a new Pico 2 W running official MicroPython
          v1.29.0. Maximum concurrency one passed 20/20; concurrency two and
          three each passed 60/60 over three runs in one AP/server session.
          Every read, `sendall`, and close completed without error; Ctrl-C
          stopped the AP and returned to the
          REPL. Board variation is not excluded, but a basic Pico 2 W
          performance limit is now less likely.
        - [x] In Issue #26, create a temporary worktree from current upstream
          containing PR #513 and rebuild Pico 2 W + mruby/c without modifying
          the normal Core checkout. The build used Core `729d9d55`, external
          gem `159232e`, and worktree `/private/tmp/picoruby-issue-26.cxTtmx`.
          The resulting UF2 is 3,895,296 bytes with SHA-256
          `0bb64e3d237e2359b47aa93dbba889a05cd806cfae5b00b55b6cbfdd84f8c593`.
          The host build used Homebrew Ruby 4.0.3 instead of the macOS system
          Ruby 2.6 and ran `mrbc:prod` before the R2P2 build.
        - [x] Revalidate #513 Ctrl-C lifecycle, AP cleanup, shell return, and
          same-port reuse on hardware. Ctrl-C while waiting in
          `TCPServer#accept` on port 10085 produced `cleanup active?: false`,
          `INTERRUPT RESCUED`, and returned to the shell. Starting the same
          probe again within the same boot reached `READY`, confirming the
          same-port rebind, and its second Ctrl-C cleanup also succeeded.
        - [x] Check the acceptance criteria of
          [Core #507](https://github.com/picoruby/picoruby/issues/507): no
          `server is not initialized` or double-close error after Ctrl-C, AP
          shutdown, shell return, and successful same-port reuse. Add the
          result in English and close #507 as resolved by #513 if all checks
          pass. All checks passed; the hardware result was added in English
          and #507 was closed as resolved by #513 on 2026-09-26.
        - [x] Run the minimal `Interrupt` probe from
          [Core #510](https://github.com/picoruby/picoruby/issues/510) multiple
          times within one boot. Record the Core revision, VM, run count, and
          complete serial output. With mruby/c on Core `729d9d55`, the first
          run printed `BEFORE`, `ENSURE`, the unhandled `Interrupt`, and
          returned to the shell. The second run stopped after
          `Exception(vm_id=26):`, before `BEFORE`, and did not return to the
          prompt after five seconds. This confirms reproduction after #513.
        - [x] Add the #510 reproduction result to the Core issue in English and
          keep it open as a separate shell/VM task recovery problem. The
          alternative of considering it resolved after sufficient clean runs
          did not apply because the second run reproduced the failure.
        - [ ] From a clean boot, run at least three 20-request rounds at
          maximum concurrency three and check whether the `client.write`
          stall observed on the #509 firmware still occurs. The first round
          showed 2/20 in the browser. On serial, the first probe response was
          written and closed, then the following connection completed its
          request read and remained inside `client.write` for more than 12
          seconds. It did not recover after the browser's 10-second timeout,
          and Ctrl-C produced neither cleanup nor a shell prompt. The
          three-round success criterion therefore remains unmet.
        - [x] Use the result and MicroPython comparison to decide whether to
          open a separate PicoRuby Core issue. Report this as a separate Core
          socket issue because it reproduced from a clean boot after #513,
          while MicroPython completed 60/60 under the same maximum-concurrency
          setting. [Core #516](https://github.com/picoruby/picoruby/issues/516)
          now tracks the exact native stopping point inside `TCPSocket_send`.
        - [x] Re-evaluate the separate Core startup report in
          [#524](https://github.com/picoruby/picoruby/issues/524) using current
          upstream `master` and direct native markers.
          - [x] Build a comparison firmware from Core `729d9d55` for Pico 2 W,
            mruby/c, poll mode, and the standard 388KB heap without the external
            AP gem. Because the existing build cache still contained external-AP
            gem objects, move the build directory aside instead of deleting it,
            rebuild from scratch, and verify that the external gem is absent.
          - [x] Confirm that a normal boot gives PicoModem no ACK, while
            automatically sending `s` during the two-second startup window to
            skip `/etc/init.d/r2p2` reaches the shell on the same firmware and
            reads all 6,490 bytes of `/home/background_test.rb`.
          - [x] Confirm that neither `/home/app.rb` nor `/home/app.mrb` exists.
            Inspect `/etc/network/wifi.yml` without exposing credentials and
            record `auto_connect=false`, `retry_if_failed=false`, and
            `watchdog=false`. The current `wifi_connect` calls
            `Network::WiFi.init` before checking `auto_connect`.
          - [x] Build the minimal comparison that returns early for
            `auto_connect=false` before `Network::WiFi.init`. Remove only
            `/etc/ruby-description` so bundled system executables are regenerated,
            preserving user files and Wi-Fi configuration. Both the first normal
            boot without startup skip and a subsequent normal reboot returned a
            PicoModem ACK and completed the 6,490-byte read.
          - [x] Open English PicoRuby Core
            [#524](https://github.com/picoruby/picoruby/issues/524) with the environment,
            minimal reproduction, normal-boot versus boot-skip A/B result,
            configuration flags, execution order, minimal comparison change,
            and two successful normal boots. Treat this as a pre-shell startup
            issue, not as a fix for #510's same-boot repeated `Interrupt` failure
            or #516's AP-side `TCPSocket#write` stall.
          - [x] Prepare the minimal fix and a regression test on a dedicated
            branch from current Core, checking both mruby/c and mruby because the
            shell command is shared. Do not mix it into the #516 diagnostic branch.
            - [x] Create `issue-524/skip-disabled-auto-connect` from current
              upstream `master` at `6b7c5437` (4.0.6) and apply only the minimal
              execution-order change.
            - [x] Build the Pico 2 W production configuration for both mruby/c
              and mruby.
            - [x] Flash the mruby/c build to the Pico 2 W while preserving the
              existing filesystem and `auto_connect=false` configuration. Confirm
              that both the first normal boot without startup skip and a normal
              reboot return a PicoModem ACK and complete the 6,490-byte read.
            - [x] Verify a normal boot and normal reboot on hardware with the
              mruby build as well. Both returned a PicoModem ACK and completed
              the 6,490-byte read.
            - [x] Use proportionate regression validation without adding a public
              helper API solely for this ordering check. The existing test harness
              cannot directly execute this shell command with a persistent device
              configuration and CYW43 initialization, so record both production
              builds and two normal hardware boots on each VM as the regression
              evidence for this minimal change.
            - [x] Commit the one-file minimal Core change on the dedicated branch
              as `7686f0e9 Fix disabled Wi-Fi auto-connect startup`, push it to
              the fork, and open English PR
              [#525](https://github.com/picoruby/picoruby/pull/525).
          - [x] After separating the startup fix, repeat #510's minimal
            `Interrupt` probe on scratch-built Core-only firmware. On Pico 2 W
            with mruby/c, poll mode, the standard 388KB heap, Core `6b7c5437`
            plus unmerged #525 commit `7686f0e9`, and no external AP gem, two
            reboot-separated normal boots each returned to the shell for 20/20
            runs, for 40/40 total. The first run of each boot printed the normal
            `Interrupt` only. Every later run also printed
            `Exception(vm_id=27)`, then still printed `BEFORE`, `ENSURE`, the
            normal `Interrupt`, and returned to the prompt.
          - [x] Post the result to #510 in
            [English](https://github.com/picoruby/picoruby/issues/510#issuecomment-5932655771).
            The comment does not claim resolution from
            40/40 alone: record the extra `vm_id=27` output and state that the
            unmerged #525 change only reorders startup handling and is not being
            treated as a #510 fix. Separately note the pre-test startup anomaly:
            the first normal boot had no shell/PicoModem response; a recovery
            build that skipped the boot script responded; the persisted `r2p2`
            bytecode exactly matched the build, Wi-Fi had `auto_connect=false`,
            no startup app existed, and both the Wi-Fi check and full boot script
            succeeded when run manually from the recovery shell. The normal
            build booted successfully after it was restored.
          - [x] After the maintainer could not reproduce the failure on current
            `master`, acknowledge that PR #525 only bypassed initialization for
            one configuration and could also skip applying the country code.
            Close the PR and do not reuse that change as a root fix.
          - [x] Reply to #524 that the next comparison will use current master
            and serial markers immediately before and after
            `cyw43_arch_init_with_country`.
          - [x] Create a fresh diagnostic branch/worktree from current upstream
            `master`. Add observation-only markers around
            `cyw43_arch_init_with_country`; do not change initialization order
            or behavior.
          - [x] Build a scratch Pico 2 W mruby/c production UF2 without the
            external AP gem from Core `d392ce47`. The UF2 is
            `/private/tmp/picoruby-issue-524-markers.fLGEeD/build/r2p2/femtoruby/pico2_w/prod/R2P2-FEMTORUBY-4.0.6-PICO2_W-20261002-d392ce47.uf2`,
            3,908,608 bytes, with SHA-256
            `65ee71f0ebdc8395798866ff4b9a5522b946c67a92ac01e0498be20d0bd5a407`.
            Both #524 marker strings are present in the UF2 and the external AP
            gem is absent from the build. The first build used `printf`, which
            targets the Picoprobe UART rather than the USB shell; after one
            successful boot with no visible markers, change only the marker
            transport to `picorb_hal_write` and rebuild with the hash above.
          - [x] Before flashing, verify the uniquely identified RP2350 BOOTSEL
            device. Preserve the filesystem and the existing
            `auto_connect=false` control condition.
          - [x] Repeat normal boots on the same Pico 2 W and capture the serial
            log. The first boot exposed a stale generated `/bin/wifi_connect`
            compile failure before the CYW43 markers. Recover non-destructively
            by moving `/etc/ruby-description` to
            `/etc/ruby-description.pre-524-usb-marker`; the next boot rewrote
            the mismatched bundled commands. That boot and the following normal
            reboot both printed the markers before and after
            `cyw43_arch_init_with_country`, then reached the shell with
            `auto_connect=false`.
          - [x] Report the negative reproduction result and exact conditions to
            #524. Explain separately that the initial compile failure occurred
            before CYW43 initialization and disappeared after the bundled
            commands were regenerated. The English correction and apology were
            posted as issue comment `5953909705`; PR #525's early-return
            hypothesis was not revived.
        - [x] Close Core #510 after upstream PR #527 fixed the retained sandbox
          exception reference that caused the extra `Exception(vm_id=27)` output.
          The explanation matches the local observation, and no AP/socket result
          is being used as evidence for this issue.
        - [x] Close Core #516 for the Core-only case after the maintainer tested
          current Core `d392ce47` or later: three rounds of 20 requests at maximum
          concurrency three completed 60/60, peer disconnect raised instead of
          hanging, the server continued accepting, and Ctrl-C returned to the
          shell.
        - [x] After #524 is answered, rebuild from `d392ce47` or later with the
          external AP gem explicitly included and rerun its equivalent concurrent
          HTTP test. If Core-only passes but the AP test hangs, continue in this
          gem repository rather than reopening #516. Reopen or file a Core issue
          only if the failure also reproduces without the AP gem and the native
          stopping point is known.
          - [x] Create the dedicated external-gem branch
            `issue-22/current-core-revalidation` without discarding the existing
            Issue #22 diagnostic changes.
          - [x] Create disposable Core worktree
            `/private/tmp/picoruby-cyw43-ap-current.XwP9bu` at `d392ce47`, add
            only the external-gem symlink and temporary mruby/c Pico 2 W build
            configuration, and complete the production build. The build summary
            includes `picoruby-cyw43-ap 0.1.0`, and the ELF exports
            `picoruby_cyw43_ap_prepare_deinit`.
          - [x] Record the normal, uninstrumented UF2 as
            `/private/tmp/picoruby-cyw43-ap-current.XwP9bu/build/r2p2/femtoruby/pico2_w/prod/R2P2-FEMTORUBY-4.0.6-PICO2_W-20261002-d392ce47.uf2`,
            3,914,752 bytes, SHA-256
            `619a3c3d0212dd3d0c97224f9c62bed89502ed1dc95ad9e262dd1f28ed975310`.
            Confirm that it contains no #524 diagnostic markers.
          - [x] Before flashing, uniquely identify the Pico 2 W RP2350 BOOTSEL
            volume. On first boot, verify that bundled system executables match
            this firmware before treating the HTTP result as valid. The first
            boot stopped on a stale generated `/bin/wifi_connect` compile
            failure and was excluded. After boot skip, move only
            `/etc/ruby-description` to
            `/etc/ruby-description.pre-issue22-d392ce47`; the next boot rewrote
            the mismatched commands, and a following normal boot reached the
            shell without regeneration.
          - [x] Transfer and explicitly run the concurrent HTTP example. Run
            three rounds of 20 requests at maximum concurrency three, then check
            Ctrl-C, AP shutdown, socket cleanup, and shell return. PicoModem
            transferred all 6,490 bytes with CRC32 `a659813e` as
            `/home/issue22_current_core_d392ce47.rb`. All three rounds completed
            quickly for 60/60 total probe responses; every logged request
            completed response write and client close, and the server returned
            to accept. Ctrl-C printed `Stopping HTTP server`, reported
            `AP active?: false`, and returned to the shell without a cleanup
            error.
          - [x] Remove the temporary request-parse and response-build markers
            after the successful comparison. Keep the existing accept, request
            read, response write, and client close boundary logs in the public
            diagnostic example.
          - [x] Post the revalidation result to Issue #22 and close it as
            `completed`.
            https://github.com/vestige/picoruby-cyw43-ap/issues/22#issuecomment-5954908956
        <!-- Historical #516 diagnostic notes retained below for reference. -->
        <!--
        - [ ] Continue Core #516 with the following diagnostic plan, revising
          it when evidence changes the working hypothesis.
          - Do not currently classify this as a regression introduced by
            #513: Core `95bf98ac` from #509 had already stalled at 7/20 on a
            later run. Keep open the possibility that later changes altered
            the reproduction frequency.
          - USB diagnostics have confirmed completion of `altcp_write`,
            `altcp_output`, and `lwip_end`, followed by a non-returning
            `cyw43_arch_poll()`. A comparison build that removed only the
            post-send poll produced 1/20 and then 0/20 and did not return on
            Ctrl-C. Do not adopt simple poll removal because it also prevents
            required network progress.
          - After restoring the post-send poll, trace the lwIP timeout, CYW43
            driver, and next-timeout-update worker boundaries. Every worker
            returned while the first three probes were handled, but a later
            0/20 run never re-entered the accept-side poll and remained asleep
            in `Task::Queue#pop`. This confirms a circular wait: polling is
            required to produce the connection event, while waiting for that
            event prevents execution from returning to the poll.
          - Test the smallest comparison that extends mruby's existing CYW43
            scheduler service to mruby/c. It passed the accept wait but stalled
            after 2/20 inside `client.write` for the fifth connection and did
            not respond to Ctrl-C. Treat the accept circular wait and TCP send
            stall as two layers; scheduler polling alone is not a complete fix.
          - Do not use the scheduler-poll comparison as the final candidate.
            Next, apply only the current-Core changes needed for Pico SDK's
            public `threadsafe_background` architecture and run an A/B test.
            Do not cherry-pick all of old commit `e83b87ae`, because it mixes
            unrelated and outdated socket changes; adapt only the build define,
            CMake link, and poll condition changes needed by current Core.
          - [x] Build a comparison firmware from current Core `729d9d55` in
            the temporary worktree using the public `threadsafe_background`
            architecture. Remove the scheduler-poll experiment and adapt only
            the build define, CMake link, and poll-dependent socket notification
            conditions. The UF2 is 3,896,320 bytes with SHA-256
            `0b6d6e20546349b821ffa0319971a5f91013c244fbe8b7b6b32d41b82da9e298`.
            The normal Core checkout remains unchanged.
          - [x] Isolate startup state from the comparison. A `/bin/wifi_connect`
            generated by another firmware remained in flash and failed to
            compile under the background build, stopping boot before the AP
            test. Boot a known rescue firmware, move generated startup state
            aside, flash the background build again, and confirm that its own
            `wifi_connect` is regenerated and the shell starts. Move
            `/home/app.rb` to `/home/app.rb.pre-background-20260928`; do not
            auto-start the AP, but transfer the test explicitly with PicoModem
            as `/home/background_test.rb`. Boot synchronizes `/bin` to bundled
            commands, so the moved old `wifi_connect` artifact did not remain,
            but it is reproducible from the rescue UF2.
          - [x] Add Ruby markers to the first concurrent-request result on the
            background build. The first unmarked run reported 0/20 and stopped
            after Connection 3 `request read complete`, before
            `response write start`. A marked run separating request-line, path,
            probe-query, response-build, and write boundaries reported 1/20.
            The test page and first probe completed every marker, write, and
            close, then execution remained at `Waiting for connection` without
            accepting the next connection. Ctrl-C produced no response for more
            than five seconds. Treat this run as an accept-side background
            callback or callback-to-`accept_nonblock` state visibility problem,
            not as an observed write stall.
          - [ ] Without printing or calling Ruby APIs from the background
            callback, record numeric counters for accept-callback entry, missing
            pending socket, and accepted-socket publication. Print those counters
            only from the safe Ruby-side `accept_nonblock` context. This separates
            a connection that never reaches lwIP from callback state that the
            Ruby side fails to observe. Do not notify `Task::Queue` directly from
            the background callback until VM access from that execution context
            is shown to be safe.
          - [ ] After adding the markers, repeat the same explicit-run background
            test across at least two reboots. Record the browser result, final
            serial marker, Ctrl-C response, AP shutdown, socket release, and
            shell return for each run. If stopping points differ, track them
            separately rather than reducing them to one reproduction rate.
          - [ ] Post the next English update to
            [Core #516](https://github.com/picoruby/picoruby/issues/516) after
            the marker run and at least two reboot-separated background runs
            are complete. Whether the result passes or fails, include the poll
            comparison, exact final marker, Ctrl-C and cleanup outcome, and the
            fact that this is diagnostic code rather than a proposed final fix.
            Do not post the current 0/20 and 1/20 alone because their stopping
            points differ from the previously reported write boundary.
          - [x] Complete the independent validation needed for the next English
            update to [Core #510](https://github.com/picoruby/picoruby/issues/510).
            The AP- and socket-free minimal `Interrupt` probe returned to the
            shell for 40/40 runs across two normal boots under the Core-only
            conditions recorded above. This result does not use the #516 hang as
            evidence, and the issues remain separate. The distinct English
            update item above is also complete.
          - Even if the background build succeeds, do not immediately declare
            it the final fix. Explain the difference from poll mode and review
            callback context and both mruby and mruby/c effects. If it fails,
            apply equivalent stopping-point diagnostics to #509 commit
            `95bf98ac` and compare reproduction frequency.
          - Design the smallest fix only after identifying the cause and stay
            within public APIs. A timeout may be a safety mechanism, but it is
            not a root fix if it only hides corrupted network state or an
            infinite operation.
          - Run an A/B comparison on the same Pico 2 W under the same test
            conditions. The fixed build must complete at least three
            20-request rounds at maximum concurrency three, then pass AP
            reconnection, Ctrl-C, AP shutdown, socket cleanup, and shell
            return. Update this sequence and the candidate fix before
            proceeding whenever observations contradict the hypothesis.
        -->
      - [x] In [Issue #29](https://github.com/vestige/picoruby-cyw43-ap/issues/29),
        test reconnects and client Wi-Fi recovery.
        - [x] Create `issue-29/ap-reconnect-validation` from the latest `main`
          at `9ad0375`. The Core upstream `master` at validation start is
          `d392ce47`; use Pico 2 W with mruby/c.
        - [x] The initial AP connection completed quickly and DHCP assigned IP
          address `192.168.4.2`, subnet mask `255.255.255.0`, and router
          `192.168.4.1`.
        - [x] Disable the AP in the same boot and confirm that its SSID disappears.
        - [x] Re-enable the AP in the same boot. The same client reconnected
          quickly and obtained the same DHCP information: `192.168.4.2`,
          `255.255.255.0`, and `192.168.4.1`.
        - [x] After both AP shutdowns, the client automatically recovered its
          normal Wi-Fi connection and could access the Internet.
        - [x] Both runs completed Ctrl-C, HTTP server shutdown,
          `AP active?: false`, cleanup without errors, and shell return. A test
          page left open in the browser also completed an incidental 20-request
          run at 20/20 during the first connection. Record the result in the
          Issue and close it as `completed`.
          https://github.com/vestige/picoruby-cyw43-ap/issues/29#issuecomment-5966735758
- [ ] In [Issue #31](https://github.com/vestige/picoruby-cyw43-ap/issues/31),
      implement the AP-based Pico Timer feasibility application and revisit its
      browser-facing behavior.
      - [x] Create `issue-31/pico-timer-feasibility` from `main` at `11317f6`.
        The Core upstream `master` at the start of this work is `d392ce47`.
      - [x] Use the old `codex/pcw-timer-replacement` only as reference; do not
        port the branch wholesale to current Core. Select only reusable pure
        Timer logic and UI pieces.
      - [x] Do not carry credentials from the historical STA example into the
        new implementation, and confirm by search that the new files do not
        contain them. If they remain valid, the user should rotate them; decide
        how to handle the remote branch separately and explicitly.
      - [x] Using the current `CYW43::AP` API and the validated HTTP-server
        lifecycle, implement `example/pico_w_ap_timer.rb` with duration setting,
        start, stop, reset, remaining-time display, and state display. Avoid
        automatic polling, refresh state manually, and send response bodies in
        512-byte chunks.
      - [x] Confirm that current Core exposes `Machine.board_millis` to both
        mruby/c and mruby. Review HTML and response size, chunked writes, and
        host-test scope. The Timer state and every route pass
        `example/pico_w_ap_timer_host_smoke.rb` under both CRuby and the PicoRuby
        host runtime, and both files compile with PicoRuby `mrbc`.
      - [x] Build Pico 2 W + mruby/c in the disposable Core worktree without
        modifying the normal Core checkout. At Core `d392ce47`, the UF2 is
        3,914,752 bytes with SHA-256
        `ce64d21d2f80254a2223043ec18dfac3b8a6d2c4392e8f32aa004cb39f080fd9`.
      - [x] Separate the historical and current execution conditions before
        retrying the full Timer on hardware. The old AP Timer was a WIP at Core
        `b526e123`, and its README did not record a completed hardware run. The
        later firmware-embedded, dedicated-VM boot path was for the STA Timer,
        so it is not equivalent to running the current app through shell
        `Sandbox#load_file`. Staged probes passed for `.mrb` loading, requires,
        constants, local variables, and ordinary class instance variables.
        Assignment to an instance variable on the module itself stalled.
        Moving Timer state to an ordinary class instance allowed AP startup and
        browser rendering.
      - [x] On hardware, verify the page, Timer controls and expiry, state after
        reload, Ctrl-C, AP cleanup, shell return, and recovery of normal Wi-Fi.
        Page, Set/Start/Stop/Reset, expiry, Ctrl-C, `AP active?: false`, and
        shell return passed. Before the timeout change, the user observed about
        3 seconds after Start and 3–6 seconds after Stop; serial also showed
        `HTTP request timeout` and `send failed`. Valid Start/Stop requests
        finished in at most 8 ms, while an earlier connection with no request
        data held the server for about 5.6 seconds. With a 500 ms first-byte
        timeout, the empty connection closed in about 0.56 seconds. The version
        without diagnostic logging also responded quickly to one click. Ctrl-C
        again disabled AP and returned to the shell. The user confirmed the
        SSID disappeared and the client returned to its usual Wi-Fi with
        internet access.
      - [x] Record the result in the README files, both TODO files, and the Issue.
        https://github.com/vestige/picoruby-cyw43-ap/issues/31#issuecomment-5980469546
      - [ ] Review the code and documentation changes with the user, then
        proceed to commit and PR after approval.

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
