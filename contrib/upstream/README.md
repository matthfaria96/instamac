# PR: split a method whose only flow is one giant switch

**Summary.** A method whose entire control flow is a single `switch` over
self-contained cases cannot be split by the forward-only chain: the part that
inherits the switch's successors gets one entry stub per target. On Instagram
455 that is 7,737 targets, 6,211 entry stubs and an 83,346-byte part, so the
method is stubbed and the app dies at `Application.onCreate`.

This adds `SwitchTableEmitter`, which **distributes the dispatcher** instead:
the case values are partitioned into ranges, the original method becomes a
driver that picks a part by range, and each part is a synthetic static method
holding its own (smaller) switch and the bodies of its cases.

## Measured on the real app

Method: `X/0000.A00(I)Ljava/lang/String;` in Instagram 455.0.0.51.72
(`com.instagram.android`), macOS 27.2, Apple Silicon.

| | |
|---|---|
| instructions | 15,477 |
| try blocks | 0 |
| bytecode | 77,269 bytes |
| composition | 1 `switch` (30,962 B) + 7,738 `const-string` + 7,738 `return-object` |

Before:

```
[dex-split] A00: 2 parts of 77269 bytes; [0 0e/0p] [15c3 6211e/0p]
[dex-split] target 40000 -> 83346 bytes, retrying
[dex-split] refused A00: no valid cut within 25161 bytes of index 0
[macapk-dex] STUBBED oversize method X/0000.A00(I)Ljava/lang/String; (code_length 77269)
```

After:

```
[switch-table] X/0000.A00(I)Ljava/lang/String;: 7737 cases, 4 parts
```

`X/0000.class` now carries `A00` plus `A00$sw0..3`, and the app boots to the
Instagram login screen instead of a white window.

## How it works

```
static String A00(int key) {                    // driver, original method
    if (key >= 0 && key <= 1999) return A00$sw0(key);
    if (key >= 2000 && key <= 3999) return A00$sw1(key);
    ...
    return "<default case string>";
}
static String A00$sw0(int key) {                // synthetic part
    switch (key) { case 0: return "s0"; ... }   // its own lookupSwitch
}
```

No value crosses a part boundary: every case ends in `return`, so there is no
frame, no portal and no parameter beyond the key. Each part gets explicit
`StackMapTable` frames (`[INTEGER]` locals, empty stack) for its case labels and
for the driver's range labels.

## Scope

Deliberately narrow. It accepts a method only when **all** of these hold:

- descriptor is `(I)L<something>;` (one int key, reference return);
- no try blocks;
- exactly one `switch`, and every other instruction is `nop`, `const-string`
  (`/jumbo`) or `return-object`;
- each case target is `const-string vX` immediately followed by
  `return-object vX`;
- the switch key register is the method's own int parameter;
- the default target is also a `const-string` + `return-object` pair;
- at least 4,000 cases (below that a forward-only plan or the outliner is the
  better tool and this transform stays out of the way).

Anything else returns `false` and the existing ladder runs untouched.
`DEX2JVM_SWITCH_TABLE=0` disables the transform for A/B.

The hook sits in `DexConverter` where the overflow has already been **measured**,
so a method that fits is still never re-translated and its bytes cannot change.

## Test

`contrib/upstream/fixture/StringTable.dex` is a self-contained fixture in the
same shape: 8,000 cases, 79,899 bytes of bytecode.

```bash
# against an installed Mac.apk runtime (uses its jars), or
DEX_CLASSPATH=/path/to/patched/classes ./contrib/upstream/test/run.sh
```

```
before:  [macapk-dex] STUBBED oversize method ...StringTable.table(I)Ljava/lang/String; (code_length 79899)
after:   [switch-table] ...StringTable.table(I)Ljava/lang/String;: 8000 cases, 4 parts
         OK: 9 values checked, -Xverify:all passed
```

The check covers the range boundaries (`0`, `1999`, `2000`, `5999`, `6000`,
`7999`), both default edges (`-1`, `8000`) and `-Xverify:all`, so a wrong frame
or a missing case fails loudly.

## Notes

- Adds one file and eleven lines in `DexConverter`.
- `contrib/upstream/files/SwitchTableEmitter.java` is the exact file the patch
  adds, for review convenience.
- Same AGPL-3.0 terms as the project; happy to rework naming, placement or
  comments to the project's style, and to add the case to the semantic suite if
  you point me at the harness (it is not in this checkout).

# PR 2: serve Linux's `/dev/zero` mmap on macOS

`patches/0002-linux-memory-syscalls.patch` — `bionic_shim.cpp`.

Linux maps character devices: `mmap(NULL, len, PROT_READ|PROT_WRITE, MAP_SHARED, fd,
0)` on `/dev/zero` hands back zero-filled memory, and Android code uses it to measure
or reserve address space (`com.facebook.analytics.memory.AddressSpace` does). macOS
refuses every mapping of `/dev/zero` (`ENODEV`; measured: `flags=0` → `EINVAL`,
`MAP_SHARED`/`MAP_PRIVATE` → `ENODEV`), so the guest's call fails where a device
succeeds.

The patch maps an anonymous private region instead — the same memory, because every
page of `/dev/zero` and `/dev/null` is zero — and drops fd/offset with it. Measured on
Instagram 455: the per-pass `mmap FAILED` series goes to zero, and the `libstartup.so`
null-recovery storm that ended at the shim's 100M cap no longer reproduces.

The same patch also routes `SYS_munmap` (arm64 215) in the raw-syscall router: the libc
export existed, but a caller issuing the raw syscall got `-ENOSYS`, so Meta's
memory-analytics path leaked 4 MB per probe (`open("/dev/zero")` + `mmap` + `syscall(215)`
every ~500 ms) and fed the `libstartup.so` null-recovery storm.

# PR 3: one screen per launch (multi-display)

`patches/0003-single-launch-screen.patch` — `cocoa_bridge.mm`.

`[NSScreen mainScreen]` answers for the KEY window and flips as windows move. On a Mac
with two displays (2560x1440 + 1080x1920) the launch budget came from one screen while the
window opened on the other, so the app ran with a Configuration describing one display and
a surface of the other (suspected at the time of feeding the `CacheKeyGenerator` hang; the
measured cause of that hang is PR 6). The patch pins the screen once per launch (mouse screen, else mainScreen, else first) and uses it for
both the policy budget and the window frame.

# PR 5: install the guest TLS block on the faulting thread

`patches/0005-x18-guest-tls-self-heal.patch` — `bionic_shim.cpp`, `arm64_native.cpp`.

The Bionic TLS block (x18) was installed only on the loader thread. Guest code running on
a JVM-created thread read `[x18+k]` from a null base; the null-recovery masked every such
load to 0. When the fault is a load through x18 and x18 holds no block, the handler now
installs the block for that thread and re-executes the instruction. Once per thread.

# PR 6: canary backstop must compare against the prologue's guard slot

`patches/0006-canary-backstop-guard-slot.patch` — `arm64_native.cpp` (+ a diagnostic in
`bionic_shim.cpp`).

The stack-canary pass's backstop arm rewrites `ldr Xt,[Xn,#0x28]` to `mov Xt,#0` when the
load is followed by `ldr Xu,[sp,#M] ; cmp Xt,Xu ; b.cond`. A `std::map` emptiness test with
a spilled `end()` has the same shape. In Instagram 455's `libstartup.so` (CDN cache-key
init) it zeroed `begin()` of an inner map at `+0x445258` — read back from the live code at
the fault: `d2800014` (`mov x20,#0`) where the file has `f9401554`
(`ldr x20,[x10,#0x28]`). The walk dereferenced NULL, the null-recovery masked the cascade,
and `CacheKeyGenerator.initializeKeyGenerator` spun forever: a black window on **every**
launch with a logged-in session.

The pass now remembers, per function, the frame slot where the prologue saved the guard,
and the backstop declines a candidate whose compare reloads a different offset off the
same base. Declining is safe: a genuine guard read left unpatched still faults on the
TPIDR magic and is answered at fault time. `MACAPK_CANARY_GUARD_SLOT=0` restores the old
behavior (it is part of the plan-cache key).

| measured (Instagram 455, macOS 27.2) | before | after |
|---|---|---|
| saved logged-in data trees that open | 0/6 | 6/6 (feed, 8–10 s) |
| backstop sites declined, all 42 images | — | 1 (`libstartup+0x445258`) |
| remaining backstop sites that reach `__stack_chk_fail` or a straight-line epilogue (offline audit) | — | 5,764 / 5,764 |

The patch also adds `MACAPK_FAULT_DUMP=N` (default off): registers, live code before `pc`,
the frame above `sp` and the memory behind each register for the first N near-null faults
the recovery is about to mask. Without a debugger (SIP, no `get-task-allow`) it is the only
way to see the state at the first divergence from a device.

# PR 7: an app that bundles SQLite binds to its own copy

`patches/0007-guest-sqlite-over-host.patch` — `arm64_native.cpp`.

The loader already refuses Apple's private crypto dylibs when a guest image defines the
symbol. `/usr/lib/libsqlite3.dylib` needs the same rule. Instagram 455's `libstartup.so`
defines the whole `sqlite3_*` API; `libscrollmerged.so` imported it and was bound to the
host's copy. `sqlite3_config` is variadic — Bionic passes variadic args in registers,
Apple's arm64 ABI reads them from the stack — so the host stored a stack word as the
`SQLITE_CONFIG_LOG` callback, and the first WAL recovery jumped to it (SIGILL, breakpad
abort). Two SQLite engines also ended up sharing the same `-wal`/`-shm` files.

| logged-in sessions held 150 s | host SQLite | guest SQLite |
|---|---|---|
| outcome | died 2/2 (11 s, 29 s after focus) | survived 3/3 |

`MACAPK_GUEST_SQLITE=0` restores the old binding.

# PR 8–11: resources, inflation, media, compact locals

Each patch file carries its own description and measurements.

| patch | what | measured on Instagram 455 |
|---|---|---|
| `0008-resources-density-contract.patch` | density qualifier on value rows is ranked; raster files (and compiled 9-patches) are scaled from their bucket to the display; a colour alias reaches its state-list file | bottom tab bar 0 px → 48 px; 72 dp icons → 24 dp; button backgrounds drawn |
| `0009-inflation-and-imageview-fidelity.patch` | `getNonResourceString`; numeric `@0x…` references; an app's `generateLayoutParams` override is final; `ImageView` scales app drawables through a matrix | 2 view constructors failing → 0; profile tab icons and chip glyphs drawn |
| `0010-media-input-clear-xhe-aac.patch` | dequeued input buffers are cleared; xHE-AAC (USAC) decodes | VP9 `out=0` → 150/5 s; xHE-AAC self-test PASS; Reels audible |
| `0011-translator-compact-locals.patch` | last-resort slot renumbering by use count for an oversize method | `X/09IF.A0p` 68,700 → 61,730 bytes; 1 class of 228,034 changes |
| `0015-window-orientation-rotate-relaunch.patch` | two window modes that open at a device's size (`MACAPK_WINDOW_SIZE_*`) and stay resizable inside their layout class; a rebuilt menu bar (Visualizar, Rolagem, Navegar, Janela); `MACAPK_ROTATE_RELAUNCH=1` relaunches the activity on a user rotation; an app-replayed stale `Configuration` no longer moves the shared `Resources` off the committed display | opens 412x915, Cmd+R -> 1280x800 -> 412x915 by one relaunch each: side rail in landscape, tab bar in portrait (before: phone layout stretched to 1280 px, and the way back was a no-op); boot 10/10 |
| `0016-trackpad-scroll-first-delta.patch` | the synthesized finger of a two-finger scroll starts past the touch slop; pointer events carry the host delivery time; queued moves merge into the newest; scroll speed, macOS-momentum inertia and auto-scroll behind the Rolagem menu | slow scroll of 5 / 12 / 30 pt moves the feed 6 / 13 / 31 px (before: a 5 pt scroll moved nothing); auto-scroll turns one Reel per step, 3/3 (released at rest: 0/3) |
| `0017-sigill-guard-same-frame.patch` | the SIGILL re-trap guard counts the same PC **and SP**: a recursive method being deoptimized traps at one return site once per nested activation | 20/20 launches, 0 deaths, no "chain looping" line in any log (before: 2 of 10 launches died 7-8 s after the first frame; 1-2 shutdown crashes per 10 in earlier runs) |
| `0018-framework-fidelity-tablet.patch` | covariant `LinearLayout.generateLayoutParams`; the inflater calls `addView(view, params)` with a params-less view, as AOSP; app quirk: the large-screen rail hides the phone tab bar and its separator; `VMRuntime.setTargetHeapUtilization` | `NoSuchMethodError` 378 -> 0 per launch; tablet inbox detail panel centred (was 300 px at the left of an 816 px pane); the stray line 48 px above the bottom of the tablet window is gone |

`0008`–`0010` together reconstruct the eleven vendor files they touch exactly (checked
against the pinned commit).

