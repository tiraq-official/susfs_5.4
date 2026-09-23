#!/bin/sh
# SUSFS-for-5.4 setup: applies this repo's kernel-side SUSFS backport on top of
# a ReSukiSU-integrated 5.4 kernel and updates the defconfig.
#
# Usage (from the kernel root):
#   ./susfs_5.4/setup.sh                     # use a cloned repo next to you
#   curl -LSs "<raw url>/setup.sh" | bash     # auto-clones the repo
#   ./susfs_5.4/setup.sh --no-defconfig      # patch only, leave defconfig alone
#   ./susfs_5.4/setup.sh path/to/defconfig   # non-default defconfig
#
# Run the ReSukiSU setup.sh BEFORE building (this script does not need it,
# the build does).

set -eu

SUSFS_REPO_URL="https://github.com/tiraq-official/susfs_5.4.git"
DEFCONFIG_PATH="arch/arm64/configs/vendor/holi-qgki_defconfig"
DO_DEFCONFIG=1

msg()  { echo "[+] $*"; }
warn() { echo "[-] $*"; }
die()  { echo "[!] ERROR: $*" >&2; exit 1; }

KERNEL_ROOT=$(pwd)

# ---- parse arguments ------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        -h|--help|help)
            sed -n '2,12p' "$0" 2>/dev/null || echo "see repo README"
            exit 0
            ;;
        --no-defconfig) DO_DEFCONFIG=0 ;;
        *) DEFCONFIG_PATH="$arg" ;;
    esac
done

# ---- locate the repo (cloned dir, or clone ourselves) --------------------
SCRIPT_DIR=""
if [ -f "$(dirname "$0")/kernel_patches/50_add_susfs_in_kernel-5.4.patch" ]; then
    SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
elif [ -d "$KERNEL_ROOT/susfs_5.4/kernel_patches" ]; then
    SCRIPT_DIR="$KERNEL_ROOT/susfs_5.4"
    msg "Using existing susfs_5.4/ directory."
else
    msg "Cloning $SUSFS_REPO_URL ..."
    git clone --depth=1 "$SUSFS_REPO_URL" "$KERNEL_ROOT/susfs_5.4"
    SCRIPT_DIR="$KERNEL_ROOT/susfs_5.4"
fi
PATCH="$SCRIPT_DIR/kernel_patches/50_add_susfs_in_kernel-5.4.patch"
[ -f "$PATCH" ] || die "kernel patch not found in $SCRIPT_DIR"

# ---- sanity checks --------------------------------------------------------
[ -f "$KERNEL_ROOT/Makefile" ] && [ -d "$KERNEL_ROOT/drivers" ] \
    || die "please run this from the kernel root."
KVER=$(head -n 3 "$KERNEL_ROOT/Makefile" | grep -E '^(VERSION|PATCHLEVEL)' \
        | awk '{print $3}' | paste -sd '.')
[ "$KVER" = "5.4" ] || warn "kernel is $KVER, this backport is written for 5.4 - continuing anyway."

if ! { [ -e "$KERNEL_ROOT/drivers/kernelsu" ] || [ -d "$KERNEL_ROOT/KernelSU" ]; }; then
    warn "ReSukiSU (KernelSU sources) not found in this tree."
    warn "Run the ReSukiSU setup.sh BEFORE building, or the build will fail."
fi

# ---- already applied? -----------------------------------------------------
if grep -q "CONFIG_KSU_SUSFS" "$KERNEL_ROOT/fs/namespace.c" 2>/dev/null; then
    msg "SUSFS is already applied, skipping the kernel patch."
    APPLY=0
else
    if grep -rq "CONFIG_KSU_MANUAL_HOOK" "$KERNEL_ROOT/fs" "$KERNEL_ROOT/kernel" \
                 "$KERNEL_ROOT/drivers" 2>/dev/null; then
        msg "ReSukiSU manual hooks detected - they will be replaced by SUSFS inline hooks."
    fi
    APPLY=1
fi

# ---- apply the kernel patch -----------------------------------------------
if [ "$APPLY" = "1" ]; then
    msg "Applying SUSFS kernel patch (this removes the manual hooks, adds the"
    msg "ReSukiSU-compatible SUSFS inline hooks and the SUSFS kernel side)..."
    if command -v git >/dev/null 2>&1 \
       && git -C "$KERNEL_ROOT" apply --check --whitespace=nowarn "$PATCH" 2>/dev/null; then
        git -C "$KERNEL_ROOT" apply --whitespace=nowarn "$PATCH"
        msg "Patch applied (git apply)."
    elif command -v patch >/dev/null 2>&1 \
         && (cd "$KERNEL_ROOT" && patch -p1 --dry-run --silent < "$PATCH") >/dev/null 2>&1; then
        (cd "$KERNEL_ROOT" && patch -p1 --silent < "$PATCH")
        msg "Patch applied (patch)."
    else
        die "the patch does not apply cleanly.
    Make sure you are on the 'resukisu' branch of your kernel with the
    manual-hook commit present and nothing else modifying these files:
        fs/exec.c fs/open.c fs/read_write.c fs/stat.c fs/namei.c
        fs/namespace.c fs/proc/* fs/proc_namespace.c fs/readdir.c
        fs/statfs.c fs/super.c fs/notify/fdinfo.c fs/Makefile
        kernel/sys.c kernel/reboot.c kernel/kallsyms.c mm/memory.c
        security/selinux/{avc.c,hooks.c} drivers/input/input.c
    See the rejected hunks (run with 'git apply' manually to see details) or
    report an issue in the susfs_5.4 repo."
    fi
fi

# ---- defconfig ------------------------------------------------------------
if [ "$DO_DEFCONFIG" = "0" ]; then
    warn "Skipping defconfig (--no-defconfig)."
    warn "Enable manually: CONFIG_KSU_SUSFS=y + feature options (see README),"
    warn "and remove CONFIG_KSU_MANUAL_HOOK=y and the AUTO_* lines."
    exit 0
fi

DEFCONFIG="$KERNEL_ROOT/$DEFCONFIG_PATH"
[ -f "$DEFCONFIG" ] || die "defconfig not found: $DEFCONFIG_PATH
(pass the path as an argument: ./susfs_5.4/setup.sh arch/arm64/configs/... )"

if grep -q "^CONFIG_KSU_SUSFS=y" "$DEFCONFIG"; then
    msg "Defconfig already has CONFIG_KSU_SUSFS=y, nothing to do."
    exit 0
fi

SUSFS_BLOCK="CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_THREAD_INFO_IN_TASK=y"

if grep -q "^CONFIG_KSU_MANUAL_HOOK=y" "$DEFCONFIG"; then
    # replace the whole old ReSukiSU manual-hook block with the SUSFS block
    if python3 - "$DEFCONFIG" "$SUSFS_BLOCK" <<'EOF'
import re, sys
path, block = sys.argv[1], sys.argv[2]
s = open(path).read()
pat = re.compile(
    r"# ReSukiSU(\+ SUSFS)?\n"
    r"CONFIG_KSU=y\n"
    r"CONFIG_KSU_MANUAL_HOOK=y\n"
    r"(CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK=y\n"
    r"CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK=y\n"
    r"(# CONFIG_KSU_MANUAL_HOOK_AUTO_INPUT_HOOK is not set\n)?)?"
    r"CONFIG_KALLSYMS_ALL=y\n?")
new = re.sub(pat, "# ReSukiSU + SUSFS\n" + block + "\n", s, count=1)
if new == s:
    sys.exit(1)
open(path, "w").write(new)
EOF
    then
        msg "Defconfig updated: manual-hook block replaced with CONFIG_KSU_SUSFS block."
    else
        die "could not rewrite the defconfig block - edit $DEFCONFIG_PATH by hand (see README)."
    fi
else
    printf '\n# ReSukiSU + SUSFS (appended by susfs_5.4 setup.sh)\n%s\n' \
        "$SUSFS_BLOCK" >> "$DEFCONFIG"
    warn "No manual-hook block found - SUSFS options appended to the defconfig."
    warn "Make sure CONFIG_KSU_MANUAL_HOOK=y is NOT set anywhere else in it."
fi

echo
msg "Done. Build the kernel now."
warn "Do NOT enable CONFIG_KSU_SUSFS_SUS_SU (unsupported with inline hooks)."
warn "After flashing, install the ksu_susfs module (see ksu_module_susfs/)."
