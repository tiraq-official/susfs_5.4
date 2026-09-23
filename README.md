# susfs_5.4 — backport of current SUSFS for the 5.4 (holi) kernel + ReSukiSU

This repo is a backport of the **current** SUSFS to Linux 5.4 for use with
ReSukiSU on non-GKI kernels. It replaces the old frozen `kernel-5.4` branch
(v1.4.2, Feb 2025) this repo was originally mirrored from — that vintage is
incompatible with ReSukiSU v4.x and will not link or boot correctly.

## What it contains

```
kernel_patches/
  50_add_susfs_in_kernel-5.4.patch   The complete kernel-side backport.
                                     Applies ON TOP of the `resukisu` branch of
                                     tiraq-official/android_kernel_motorola_sm6375.
                                     Includes:
                                       - removal of the ReSukiSU manual hooks
                                         (replaced by susfs inline hooks)
                                       - ReSukiSU SUSFS inline hooks
                                         (execve, faccessat, newfstatat, read,
                                          input, selinux bprm, reboot, setresuid)
                                       - SUSFS kernel side v2.2.00 for 5.4
  fs/susfs.c                         Standalone copies of the sources (v2.2.00
  include/linux/susfs.h               lineage with two upstream fixes ported:
  include/linux/susfs_def.h            KSTAT_SPOOF_CTIME_TV_SEC (1 << 8) fix and
                                       the inverted vfs_statfs spoof check fix)
ksu_susfs/                            Current userspace tool sources (matches
                                      the kernel-side command set exactly)
ksu_module_susfs/                     Current susfs module skeleton with a
                                      prebuilt arm64 ksu_susfs tool
build_ksu_susfs_tool.sh               NDK build script for the tool
build_ksu_module.sh                   Module packing script
```

Files from the old mirror that are intentionally GONE (delete them from the
repo when committing this update):

- `kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch` — only for
  weishu's KernelSU; ReSukiSU already integrates the SUSFS kernel-side glue.
- `kernel_patches/fs/sus_su.c` and `kernel_patches/include/linux/sus_su.h` —
  SUS_SU needs the old kprobe-based hook variables (`execve_kp`,
  `newfstatat_kp`, ...) which do not exist with ReSukiSU inline hooks.
  Never enable `CONFIG_KSU_SUSFS_SUS_SU` with this backport.

## Usage (your workflow)

```sh
# 1. your ReSukiSU kernel
git clone -b resukisu https://github.com/tiraq-official/android_kernel_motorola_sm6375
cd android_kernel_motorola_sm6375

# 2. ReSukiSU sources
curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash

# 3a. plain ReSukiSU kernel: just build now.

# 3b. ReSukiSU + SUSFS: run this repo's setup.sh -
git clone https://github.com/tiraq-official/susfs_5.4
sh susfs_5.4/setup.sh
#    or, without cloning first:
#    curl -LSs "https://raw.githubusercontent.com/tiraq-official/susfs_5.4/main/setup.sh" | bash

# 4. build, flash, install the ksu_module_susfs module
```

What `setup.sh` does (all automatic):

- applies `kernel_patches/50_add_susfs_in_kernel-5.4.patch`
  (removes the manual hooks, adds the ReSukiSU SUSFS inline hooks, adds the
  SUSFS kernel side), and
- updates the defconfig (holi-qgki_defconfig by default): replaces the
  `CONFIG_KSU_MANUAL_HOOK` block with `CONFIG_KSU_SUSFS=y` + feature options.

It is idempotent - running it twice is safe. Options:
`--no-defconfig` (patch only, edit the defconfig yourself), or pass a
defconfig path if yours lives elsewhere.

Your `resukisu` branch stays untouched - it remains the plain-ReSukiSU
build whenever you want it; SUSFS is applied on top at build time.

## Provenance / verification

- Kernel side: the maintained v2.2.00-for-5.4 backport (from
  JackA1ltman/NonGKI_Kernel_Build_2nd, which CI-builds 5.4 kernels with
  ReSukiSU daily) plus two bugfixes ported from the current
  gki-android12-5.10 branch of simonpunk/susfs4ksu.
- The inline hooks are the ReSukiSU-compatible set (equivalent to
  `susfs_inline_hook_patches.sh` from the same repo, SUSFS v2.3.00+).
- Every `susfs_*` / `ksu_handle_*` symbol used by the patched kernel files
  was cross-checked against ReSukiSU main's kernel sources — all resolve.
- The userspace tool's command numbers were checked against the kernel-side
  definitions — all aligned.
- The patch applies with zero rejects on the `resukisu` branch
  (`git apply --check` verified on a pristine checkout).
- NOT compile-tested (no Android clang available to the backporter). Keep
  your known-good manual-hook kernel until the SUSFS build is verified.

## Keeping it up to date

Upstream SUSFS lives at https://gitlab.com/simonpunk/susfs4ksu (branch
`gki-android12-5.10` is the closest base for 5.4). When updating:

1. Diff the new `fs/susfs.c`, `include/linux/susfs.h`,
   `include/linux/susfs_def.h` against the copies here and port changes.
2. Watch for hunks in the new `50_add_susfs_in_gki-android12-5.10.patch`
   that touch 5.10-only APIs (bootconfig, `show_options2`, VMA walkers,
   `stat->mnt_id` placement) — those must NOT be ported as-is; the 5.4
   equivalents already exist in this patch.
3. Keep `fs/proc/cmdline.c` (not `fs/proc/bootconfig.c`) — 5.4 has no
   bootconfig.
