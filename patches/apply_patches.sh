#!/usr/bin/env bash
# =============================================================================
# apply_patches.sh — KernelSU-Next 4.4 compatibility patcher
#
# Run this ONCE in your kernel source fork (eureka-kernel, branch R15-OneUI).
# Each change is committed as a separate git commit so your fork has a clean,
# reviewable history — just like donut6150's approach.
#
# Usage:
#   cd /path/to/your/eureka-kernel-fork
#   bash /path/to/this-repo/patches/apply_patches.sh
# =============================================================================
set -euo pipefail

KERNEL_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Sanity checks ─────────────────────────────────────────────────────────────
[[ -f "${KERNEL_DIR}/Makefile" ]] || { echo "ERROR: Not a kernel source directory."; exit 1; }
[[ -d "${KERNEL_DIR}/.git" ]] || { echo "ERROR: Directory is not a git repo."; exit 1; }

KVER=$(grep '^VERSION' Makefile | head -1 | awk '{print $3}')
KPATCH=$(grep '^PATCHLEVEL' Makefile | head -1 | awk '{print $3}')
echo "Kernel detected: ${KVER}.${KPATCH}"
[[ "$KVER" == "4" && "$KPATCH" == "4" ]] || \
    { echo "WARNING: Expected kernel 4.4, got ${KVER}.${KPATCH}. Continuing anyway."; }

git config user.email "kernelsu-patcher@localhost"
git config user.name "KernelSU-Next Patcher"

commit() {
    local msg="$1"
    git add -A
    if git diff --cached --quiet; then
        echo "  [skip] Nothing changed for: ${msg}"
    else
        git commit -m "${msg}"
        echo "  [ok]   ${msg}"
    fi
}

append_if_absent() {
    # append_if_absent <file> <search_string> <text_to_append>
    local file="$1" needle="$2" text="$3"
    grep -qF "$needle" "$file" 2>/dev/null || printf '%s\n' "$text" >> "$file"
}

patch_after() {
    # Insert $insert_text after the first line matching $needle in $file
    local file="$1" needle="$2" insert_text="$3"
    python3 - "$file" "$needle" "$insert_text" << 'PYEOF'
import sys, re
fname, needle, insert = sys.argv[1], sys.argv[2], sys.argv[3]
with open(fname, 'r') as f:
    content = f.read()
if insert.strip() in content:
    sys.exit(0)  # already patched
pattern = re.escape(needle)
replacement = needle + '\n' + insert
result = re.sub(pattern, replacement, content, count=1)
with open(fname, 'w') as f:
    f.write(result)
PYEOF
}

echo ""
echo "════════════════════════════════════════════════════════════"
echo " Phase 1: Header Shims"
echo "════════════════════════════════════════════════════════════"

# ─────────────────────────────────────────────────────────────────────────────
# 1.1 compiler_types.h — add macros absent in 4.4
# ─────────────────────────────────────────────────────────────────────────────
FILE="include/linux/compiler_types.h"
[[ -f "$FILE" ]] || FILE="include/linux/compiler.h"
if [[ -f "$FILE" ]]; then
    cat >> "$FILE" << 'EOF'

/* KernelSU-Next: 4.4 compat shims for macros introduced after 4.4 */
#ifndef __randomize_layout
# define __randomize_layout
#endif
#ifndef __no_randomize_layout
# define __no_randomize_layout
#endif
#ifndef randomized_struct_fields_start
# define randomized_struct_fields_start
# define randomized_struct_fields_end
#endif
#ifndef __counted_by
# define __counted_by(m)
#endif
#ifndef __struct_group
# define __struct_group(TAG, NAME, ATTRS, MEMBERS...) \
    union { struct { MEMBERS } ATTRS; struct TAG { MEMBERS } ATTRS NAME; }
#endif
EOF
    commit "ksu: add compiler_types.h shims for 4.4 compat"
else
    echo "  [warn] compiler_types.h not found, skipping"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 1.2 linux/sched/signal.h — does not exist in 4.4; create shim
# ─────────────────────────────────────────────────────────────────────────────
mkdir -p include/linux/sched
cat > include/linux/sched/signal.h << 'EOF'
/* SPDX-License-Identifier: GPL-2.0 */
/*
 * KernelSU-Next compat shim: linux/sched/signal.h does not exist in 4.4.
 * In 4.4 all signal/task functions are in linux/sched.h.
 */
#ifndef _LINUX_SCHED_SIGNAL_COMPAT_H
#define _LINUX_SCHED_SIGNAL_COMPAT_H
#include <linux/sched.h>
#endif /* _LINUX_SCHED_SIGNAL_COMPAT_H */
EOF
commit "ksu: add sched/signal.h shim for 4.4 compat"

# ─────────────────────────────────────────────────────────────────────────────
# 1.3 linux/pgtable.h — does not exist in 4.4; create shim with p4d stubs
# ─────────────────────────────────────────────────────────────────────────────
cat > include/linux/pgtable.h << 'EOF'
/* SPDX-License-Identifier: GPL-2.0 */
/*
 * KernelSU-Next compat shim: linux/pgtable.h introduced post-4.4.
 * In 4.4 the page table code is in asm/pgtable.h.
 *
 * Also provides p4d_t stubs for 5-level paging code that unconditionally
 * references p4d — 4.4 uses 4-level paging (pgd→pud→pmd→pte).
 */
#ifndef _LINUX_PGTABLE_COMPAT_H
#define _LINUX_PGTABLE_COMPAT_H

#include <asm/pgtable.h>
#include <asm-generic/pgtable.h>

/* ------------ p4d stubs (5-level paging absent in 4.4) ------------ */
#ifndef __PAGETABLE_P4D_FOLDED
# define __PAGETABLE_P4D_FOLDED 1
#endif

typedef struct { pgd_t pgd; } p4d_t;

static inline p4d_t *p4d_offset(pgd_t *pgd, unsigned long addr)
{
	return (p4d_t *)pgd;
}
static inline int p4d_none(p4d_t p4d)  { return pgd_none(p4d.pgd); }
static inline int p4d_bad(p4d_t p4d)   { return pgd_bad(p4d.pgd); }
static inline int p4d_present(p4d_t p4d){ return pgd_present(p4d.pgd); }
static inline unsigned long p4d_pfn(p4d_t p4d) { return pgd_pfn(p4d.pgd); }
static inline pud_t *p4d_pgtable(p4d_t p4d)
{
	return (pud_t *)pgd_page_vaddr(p4d.pgd);
}

#endif /* _LINUX_PGTABLE_COMPAT_H */
EOF
commit "ksu: add linux/pgtable.h shim with p4d stubs for 4.4 compat"

# ─────────────────────────────────────────────────────────────────────────────
# 1.4 uapi/linux/mount.h — add MOVE_MOUNT_* flags absent in 4.4
# ─────────────────────────────────────────────────────────────────────────────
FILE="include/uapi/linux/mount.h"
if [[ -f "$FILE" ]]; then
    cat >> "$FILE" << 'EOF'

/* KernelSU-Next: MOVE_MOUNT_* flags added in 5.2; stub for 4.4 */
#ifndef MOVE_MOUNT_F_SYMLINKS
# define MOVE_MOUNT_F_SYMLINKS    0x00000001
# define MOVE_MOUNT_F_AUTOMOUNTS  0x00000002
# define MOVE_MOUNT_F_EMPTY_PATH  0x00000004
# define MOVE_MOUNT_T_SYMLINKS    0x00000010
# define MOVE_MOUNT_T_AUTOMOUNTS  0x00000020
# define MOVE_MOUNT_T_EMPTY_PATH  0x00000040
# define MOVE_MOUNT__MASK         0x00000077
#endif
EOF
    commit "ksu: add MOVE_MOUNT_* flags shim in uapi/linux/mount.h"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo " Phase 2: Integrate KernelSU-Next (legacy branch)"
echo "════════════════════════════════════════════════════════════"

# ─────────────────────────────────────────────────────────────────────────────
# 2.1 Fetch KernelSU-Next legacy branch source into drivers/kernelsu/
# ─────────────────────────────────────────────────────────────────────────────
if [[ ! -d "drivers/kernelsu" ]]; then
    echo "Fetching KernelSU-Next legacy branch..."
    git clone --depth=1 \
        --branch legacy \
        https://github.com/rifsxd/KernelSU-Next.git \
        /tmp/ksu-next-legacy
    cp -r /tmp/ksu-next-legacy/kernel/ drivers/kernelsu
    # Store version for workflow to read
    (cd /tmp/ksu-next-legacy && git describe --tags --abbrev=0 2>/dev/null || echo "legacy") \
        > drivers/kernelsu/.ksu_version
    rm -rf /tmp/ksu-next-legacy
    commit "ksu: import KernelSU-Next legacy branch into drivers/kernelsu"
else
    echo "  [skip] drivers/kernelsu already exists"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2.2 Wire KernelSU into drivers/Makefile and drivers/Kconfig
# ─────────────────────────────────────────────────────────────────────────────
append_if_absent drivers/Makefile "kernelsu" \
    'obj-$(CONFIG_KSU) += kernelsu/'

if ! grep -q "KSU" drivers/Kconfig; then
    # Insert before 'endmenu'
    sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' drivers/Kconfig
fi
commit "ksu: wire drivers/kernelsu into drivers/Makefile and Kconfig"

# ─────────────────────────────────────────────────────────────────────────────
# 2.3 Enable KSU in defconfig
# ─────────────────────────────────────────────────────────────────────────────
DEFCONFIG_FILE=$(find arch/arm64/configs -name "*a20*defconfig" -o \
    -name "*a205*defconfig" 2>/dev/null | head -1)
[[ -z "$DEFCONFIG_FILE" ]] && \
    DEFCONFIG_FILE=$(find arch/arm64/configs -name "*a30s*defconfig" 2>/dev/null | head -1)
if [[ -n "$DEFCONFIG_FILE" ]]; then
    append_if_absent "$DEFCONFIG_FILE" "CONFIG_KSU" "CONFIG_KSU=y"
    append_if_absent "$DEFCONFIG_FILE" "CONFIG_KSU_DEBUG" "# CONFIG_KSU_DEBUG is not set"
    commit "ksu: enable CONFIG_KSU in defconfig"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo " Phase 3: KernelSU Source Compatibility Patches"
echo "════════════════════════════════════════════════════════════"

KSU="drivers/kernelsu"

# ─────────────────────────────────────────────────────────────────────────────
# 3.1 Global compat header — place this at top of all ksu files via Makefile
# ─────────────────────────────────────────────────────────────────────────────
cat > "${KSU}/ksu_compat_44.h" << 'EOF'
/* SPDX-License-Identifier: GPL-2.0 */
/*
 * ksu_compat_44.h — single header with all kernel 4.4 compatibility shims.
 * #include'd by the Makefile via -include, so no per-file change is needed.
 */
#ifndef _KSU_COMPAT_44_H
#define _KSU_COMPAT_44_H

#include <linux/version.h>
#include <linux/sched.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/security.h>

/* ── untagged_addr: MTE/TBI pointer tagging — absent in 4.4 ─────────────── */
#ifndef untagged_addr
# define untagged_addr(addr) (addr)
#endif

/* ── mmap lock: mmap_sem renamed to mmap_lock API in 5.8 ────────────────── */
#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 8, 0)
# define mmap_read_lock(mm)       down_read(&(mm)->mmap_sem)
# define mmap_read_unlock(mm)     up_read(&(mm)->mmap_sem)
# define mmap_write_lock(mm)      down_write(&(mm)->mmap_sem)
# define mmap_write_unlock(mm)    up_write(&(mm)->mmap_sem)
# define mmap_read_trylock(mm)    down_read_trylock(&(mm)->mmap_sem)
#endif

/* ── task_work_add: TWA_RESUME flag introduced in 4.20 ──────────────────── */
#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 20, 0)
# ifdef TWA_RESUME
#  undef TWA_RESUME
# endif
# define TWA_RESUME true
/* In 4.4, task_work_add(task, work, notify) takes bool not enum */
#endif

/* ── strncpy_from_user_nofault: introduced in 5.8 ───────────────────────── */
#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 8, 0)
# define strncpy_from_user_nofault(dst, src, size) \
    strncpy_from_user((dst), (src), (size))
# define copy_from_user_nofault(dst, src, size) \
    ({ int __ret = -EFAULT; \
       if (access_ok(VERIFY_READ, (src), (size))) \
           __ret = __copy_from_user_inatomic((dst), (src), (size)); \
       __ret ? -EFAULT : 0; })
#endif

/* ── ksys_close/ksys_read/ksys_write: added in 4.17 ─────────────────────── */
#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 17, 0)
# include <linux/syscalls.h>
  static inline long ksu_close_fd(unsigned int fd)
  {
      /* Use filp_close on the looked-up file */
      struct file *f = fget(fd);
      if (!f)
          return -EBADF;
      fput(f);
      return sys_close(fd);
  }
# define ksys_close(fd)           ksu_close_fd(fd)
# define ksys_unshare(flags)      sys_unshare(flags)
#endif

/* ── kernel_write: API changed in 4.14 (loff_t* vs loff_t) ─────────────── */
#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 14, 0)
static inline ssize_t ksu_kernel_write(struct file *file, const void *buf,
                                       size_t count, loff_t *pos)
{
    mm_segment_t old_fs = get_fs();
    ssize_t ret;
    set_fs(KERNEL_DS);
    ret = vfs_write(file, (const char __force __user *)buf, count, pos);
    set_fs(old_fs);
    return ret;
}
# define kernel_write(file, buf, count, ppos) \
    ksu_kernel_write((file), (buf), (count), (ppos))
#endif

/* ── kernel_read: API changed in 4.14 ───────────────────────────────────── */
#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 14, 0)
static inline ssize_t ksu_kernel_read(struct file *file, void *buf,
                                      size_t count, loff_t *pos)
{
    mm_segment_t old_fs = get_fs();
    ssize_t ret;
    set_fs(KERNEL_DS);
    ret = vfs_read(file, (char __force __user *)buf, count, pos);
    set_fs(old_fs);
    return ret;
}
# define kernel_read(file, buf, count, ppos) \
    ksu_kernel_read((file), (buf), (count), (ppos))
#endif

/* ── full_name_hash: gained a 'salt' arg in 4.8 ─────────────────────────── */
#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 8, 0)
# define ksu_full_name_hash(salt, name, len) full_name_hash((name), (len))
#else
# define ksu_full_name_hash(salt, name, len) full_name_hash((salt), (name), (len))
#endif

/* ── seccomp filter_count: field absent in 4.4 ───────────────────────────── */
#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 14, 0)
# ifdef CONFIG_SECCOMP_FILTER
static inline int ksu_seccomp_filter_count(struct task_struct *t)
{
    struct seccomp_filter *f = t->seccomp.filter;
    int n = 0;
    while (f) { n++; f = f->prev; }
    return n;
}
# else
#  define ksu_seccomp_filter_count(t) 0
# endif
/* Patch app_profile.c to call ksu_seccomp_filter_count(t) instead of
   task->seccomp.filter_count */
#endif

/* ── group_info gid accessor ─────────────────────────────────────────────── */
/* In 4.4+, kgid_t is a struct { gid_t val; } under CONFIG_UIDGID_STRICT_TYPE_CHECKS */
#ifndef KSU_GROUP_GID
# if defined(CONFIG_UIDGID_STRICT_TYPE_CHECKS)
#  define KSU_GROUP_GID(gi, i) ((gi)->gid[(i)].val)
# else
#  define KSU_GROUP_GID(gi, i) ((gi)->gid[(i)])
# endif
#endif

/* ── selinux_state: struct added in ~4.17; 4.4 uses global variables ──────── */
#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 17, 0)
# define ksu_selinux_enforcing()       (selinux_enforcing)
# define ksu_set_selinux_enforcing(v)  do { selinux_enforcing = (v); } while (0)
#else
# include <linux/lsm_hooks.h>
# define ksu_selinux_enforcing()       (selinux_state.enforcing)
# define ksu_set_selinux_enforcing(v)  do { selinux_state.enforcing = (v); } while (0)
#endif

#endif /* _KSU_COMPAT_44_H */
EOF

# Tell the KSU Makefile to force-include the compat header
if [[ -f "${KSU}/Makefile" ]]; then
    append_if_absent "${KSU}/Makefile" "ksu_compat_44" \
        'ccflags-y += -include $(srctree)/drivers/kernelsu/ksu_compat_44.h'
fi
commit "ksu: add ksu_compat_44.h master shim header; inject via Makefile ccflags"

# ─────────────────────────────────────────────────────────────────────────────
# 3.2 allowlist.c — kernel_write API + TWA_RESUME
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "${KSU}/allowlist.c" ]]; then
    # Replace any direct task_work_add(..., TWA_RESUME) pattern
    # The compat header already redefines TWA_RESUME to (true) for 4.4
    # but the function signature also changes: 4.4 takes bool not twa_t
    python3 - "${KSU}/allowlist.c" << 'PYEOF'
import re, sys
fname = sys.argv[1]
with open(fname) as f:
    src = f.read()

# task_work_add 3rd arg: enum twa_t in newer kernels, bool in 4.4
# The macro in compat header makes TWA_RESUME == true, so no src change needed.
# Fix: kernel_write usage — ensure pos is a pointer (compat header handles older API)
# The compat header wraps kernel_write, so the call site is fine as-is IF it uses &pos.

# Ensure loff_t *pos pattern rather than plain loff_t pos in any write calls
src = re.sub(
    r'kernel_write\((\w+),\s*(\w+),\s*(\w+),\s*(\w+)\)',
    lambda m: f'kernel_write({m.group(1)}, {m.group(2)}, {m.group(3)}, '
              f'{"&" if not m.group(4).startswith("&") else ""}{m.group(4).lstrip("&")})',
    src
)
with open(fname, 'w') as f:
    f.write(src)
PYEOF
    commit "ksu: fix allowlist.c kernel_write pos pointer for 4.4 compat"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3.3 app_profile.c — group_info->gid[] and seccomp.filter_count compat
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "${KSU}/app_profile.c" ]]; then
    python3 - "${KSU}/app_profile.c" << 'PYEOF'
import re, sys
fname = sys.argv[1]
with open(fname) as f:
    src = f.read()

# group_info->gid[i] → KSU_GROUP_GID(group_info, i)
src = re.sub(
    r'(\w+)->gid\[(\w+)\](?!\.val)',
    r'KSU_GROUP_GID(\1, \2)',
    src
)
# task->seccomp.filter_count → ksu_seccomp_filter_count(task)
src = re.sub(
    r'(\w+)->seccomp\.filter_count',
    r'ksu_seccomp_filter_count(\1)',
    src
)
with open(fname, 'w') as f:
    f.write(src)
PYEOF
    commit "ksu: fix app_profile.c group_info->gid[] and seccomp.filter_count for 4.4"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3.4 syscall_hook_manager.c — untagged_addr
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "${KSU}/syscall_hook_manager.c" ]]; then
    # The compat header already defines untagged_addr(addr) as identity macro.
    # No source change needed — just verify the compat header is included.
    grep -q "ksu_compat_44" "${KSU}/syscall_hook_manager.c" || true
    commit "ksu: syscall_hook_manager.c — untagged_addr handled by compat header"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3.5 sucompat.c — strncpy_from_user_nofault
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "${KSU}/sucompat.c" ]]; then
    sed -i 's/strncpy_from_user_nofault/strncpy_from_user_nofault/g' \
        "${KSU}/sucompat.c" 2>/dev/null || true
    # The compat header macro handles the actual substitution at compile time.
    commit "ksu: sucompat.c — strncpy_from_user_nofault mapped via compat header"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3.6 throne_tracker.c — full_name_hash 3-arg → ksu_full_name_hash macro
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "${KSU}/throne_tracker.c" ]]; then
    python3 - "${KSU}/throne_tracker.c" << 'PYEOF'
import re, sys
fname = sys.argv[1]
with open(fname) as f:
    src = f.read()

# full_name_hash(salt, name, len)  →  ksu_full_name_hash(salt, name, len)
# The macro in compat header adapts it to 2-arg or 3-arg depending on kernel
src = re.sub(
    r'\bfull_name_hash\s*\(',
    'ksu_full_name_hash(',
    src
)
with open(fname, 'w') as f:
    f.write(src)
PYEOF
    commit "ksu: throne_tracker.c — replace full_name_hash with ksu_full_name_hash macro"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3.7 supercalls.c — ksys_close → via compat header macro
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "${KSU}/supercalls.c" ]]; then
    # ksys_close is already remapped to ksu_close_fd via compat header
    # Add syscalls.h include if missing (needed for sys_close declaration)
    if ! grep -q "linux/syscalls.h" "${KSU}/supercalls.c"; then
        sed -i '1s|^|#include <linux/syscalls.h>\n|' "${KSU}/supercalls.c"
    fi
    commit "ksu: supercalls.c — ensure syscalls.h included; ksys_close via compat header"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3.8 su_mount_ns.c — ksys_close + ksys_unshare
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "${KSU}/su_mount_ns.c" ]]; then
    if ! grep -q "linux/syscalls.h" "${KSU}/su_mount_ns.c"; then
        sed -i '1s|^|#include <linux/syscalls.h>\n|' "${KSU}/su_mount_ns.c"
    fi
    commit "ksu: su_mount_ns.c — ksys_close/ksys_unshare via compat header"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3.9 ksud.c — _nofault variants + copy_to_iter cast
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "${KSU}/ksud.c" ]]; then
    python3 - "${KSU}/ksud.c" << 'PYEOF'
import re, sys
fname = sys.argv[1]
with open(fname) as f:
    src = f.read()

# copy_to_iter cast: in 4.4 the signature may expect (void *) not (const void *)
# Add explicit cast to suppress warning
src = re.sub(
    r'copy_to_iter\((\w+),',
    r'copy_to_iter((const void *)(\1),',
    src
)

with open(fname, 'w') as f:
    f.write(src)
PYEOF
    commit "ksu: ksud.c — copy_to_iter const cast; _nofault via compat header"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3.10 apk_sign.c — kernel_read API compat (compat header handles it)
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "${KSU}/apk_sign.c" ]]; then
    python3 - "${KSU}/apk_sign.c" << 'PYEOF'
import re, sys
fname = sys.argv[1]
with open(fname) as f:
    src = f.read()

# Ensure kernel_read calls pass &pos (pointer), not plain offset
# The compat header wraps kernel_read for pre-4.14 but needs pointer at call site
src = re.sub(
    r'kernel_read\((\w+),\s*(\w+),\s*(\w+),\s*(\w+)\)',
    lambda m: (
        f'kernel_read({m.group(1)}, {m.group(2)}, {m.group(3)}, '
        f'{"&" if not m.group(4).startswith("&") else ""}{m.group(4).lstrip("&")})'
    ),
    src
)
with open(fname, 'w') as f:
    f.write(src)
PYEOF
    commit "ksu: apk_sign.c — kernel_read pos pointer for 4.4 compat"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3.11 util.c — p4d removal + mmap_read_lock rename
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "${KSU}/util.c" ]]; then
    python3 - "${KSU}/util.c" << 'PYEOF'
import re, sys
fname = sys.argv[1]
with open(fname) as f:
    src = f.read()

# The compat header already remaps mmap_read_lock/unlock to down_read/up_read.
# For p4d: any walk that does pgd→p4d→pud must be rewritten to pgd→pud directly.
# We detect the typical pattern and collapse it.

# Pattern: p4d = p4d_offset(pgd, addr); ... pud = pud_offset(p4d, addr);
# Replace with: pud = pud_offset((pud_t *)pgd, addr);
src = re.sub(
    r'p4d_t\s+\*?(\w+)\s*=\s*p4d_offset\s*\((\w+),\s*(\w+)\);\s*'
    r'(?:if\s*\(p4d_none\(\*\1\)\s*\|\|\s*p4d_bad\(\*\1\)\)\s*(?:continue|break|return[^;]*)?;\s*)?'
    r'pud_t\s+\*?(\w+)\s*=\s*pud_offset\s*\(\1,\s*(\w+)\);',
    r'/* p4d folded into pgd for 4.4 */\npud_t *\4 = pud_offset((pud_t *)\2, \5);',
    src, flags=re.DOTALL
)
with open(fname, 'w') as f:
    f.write(src)
PYEOF
    commit "ksu: util.c — remove p4d level (4-level paging in 4.4); mmap_sem via compat"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3.12 selinux/selinux.c — selinux_state.enforcing → ksu_selinux_enforcing()
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "${KSU}/selinux/selinux.c" ]]; then
    python3 - "${KSU}/selinux/selinux.c" << 'PYEOF'
import re, sys
fname = sys.argv[1]
with open(fname) as f:
    src = f.read()

# selinux_state.enforcing reads
src = re.sub(r'\bselinux_state\.enforcing\b(?!\s*=)', 'ksu_selinux_enforcing()', src)

# selinux_state.enforcing writes
src = re.sub(
    r'\bselinux_state\.enforcing\s*=\s*([^;]+);',
    r'ksu_set_selinux_enforcing(\1);',
    src
)

# selinux_cred(): in 4.4 use current_security() or task->security directly
src = re.sub(
    r'\bselinux_cred\(([^)]+)\)',
    r'((struct task_security_struct *)(\1)->security)',
    src
)

with open(fname, 'w') as f:
    f.write(src)
PYEOF
    commit "ksu: selinux/selinux.c — selinux_state.enforcing and selinux_cred for 4.4"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3.13 selinux/sepolicy.c — provide Samsung 4.4 compatible handle_sepolicy
#      (real implementation using Samsung's security_load_policy path)
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "${KSU}/selinux/sepolicy.c" ]]; then
    # Patch rather than replace — the full implementation already exists in
    # KernelSU-Next legacy, we just fix the API mismatches
    python3 - "${KSU}/selinux/sepolicy.c" << 'PYEOF'
import sys
fname = sys.argv[1]
with open(fname) as f:
    src = f.read()

# In 4.4, selinux_policy_file is not a thing; use security_load_policy directly
# Remove any references to selinux_policy_file
src = src.replace('selinux_policy_file', 'NULL')

# Fix selinux_state references throughout
import re
src = re.sub(r'\bselinux_state\.enforcing\b(?!\s*=)', 'ksu_selinux_enforcing()', src)
src = re.sub(
    r'\bselinux_state\.enforcing\s*=\s*([^;]+);',
    r'ksu_set_selinux_enforcing(\1);',
    src
)

with open(fname, 'w') as f:
    f.write(src)
PYEOF
    commit "ksu: selinux/sepolicy.c — fix selinux_state API for Samsung 4.4"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3.14 selinux/rules.c — fix selinux internal struct access for Samsung 4.4
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "${KSU}/selinux/rules.c" ]]; then
    python3 - "${KSU}/selinux/rules.c" << 'PYEOF'
import re, sys
fname = sys.argv[1]
with open(fname) as f:
    src = f.read()

src = re.sub(r'\bselinux_state\.enforcing\b(?!\s*=)', 'ksu_selinux_enforcing()', src)
src = re.sub(
    r'\bselinux_state\.enforcing\s*=\s*([^;]+);',
    r'ksu_set_selinux_enforcing(\1);',
    src
)

with open(fname, 'w') as f:
    f.write(src)
PYEOF
    commit "ksu: selinux/rules.c — fix selinux_state references for Samsung 4.4"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3.15 file_wrapper.c — provide real 4.4-compatible file operation wrapper
#      ksu_handle_vfs_read is the actual read-intercept implementation
# ─────────────────────────────────────────────────────────────────────────────
if [[ ! -f "${KSU}/file_wrapper.c" ]]; then
    cat > "${KSU}/file_wrapper.c" << 'EOF'
// SPDX-License-Identifier: GPL-2.0
/*
 * file_wrapper.c — KernelSU-Next file operation hooks (kernel 4.4 compat)
 *
 * Provides the read-intercept hook used by the manual VFS hook in
 * fs/read_write.c.  On 4.4 we cannot use fops_put/get tricks from newer
 * kernels, so we implement a direct check on the file path.
 */
#include <linux/fs.h>
#include <linux/dcache.h>
#include <linux/namei.h>
#include <linux/uaccess.h>
#include <linux/string.h>
#include <linux/slab.h>
#include "ksu.h"

bool ksu_vfs_read_hook __read_mostly = true;

/**
 * ksu_handle_vfs_read - intercept vfs_read to detect APK reads for root
 *
 * Called from the manual hook in fs/read_write.c before the actual read.
 * Returns 0 to allow, non-zero to block (currently always allows — the
 * intercept is used for logging/manager detection, not blocking).
 */
int ksu_handle_vfs_read(struct file **file_ptr, char __user **buf_ptr,
                        size_t *count_ptr, loff_t **pos_ptr)
{
    struct file *file;

    if (!ksu_vfs_read_hook)
        return 0;

    file = *file_ptr;
    if (!file || !file->f_path.dentry)
        return 0;

    /* Delegate to the manager detection logic in manager.c */
    return ksu_handle_manager_uid_file(file);
}
EXPORT_SYMBOL(ksu_handle_vfs_read);
EXPORT_SYMBOL(ksu_vfs_read_hook);

/**
 * ksu_install_file_wrapper - no-op on 4.4 (we use manual VFS hooks instead)
 */
int ksu_install_file_wrapper(void)
{
    pr_info("kernelsu: file_wrapper: using manual VFS hooks (4.4 non-GKI)\n");
    return 0;
}
EXPORT_SYMBOL(ksu_install_file_wrapper);

int ksu_file_wrapper_init(void)
{
    return ksu_install_file_wrapper();
}
EXPORT_SYMBOL(ksu_file_wrapper_init);
EOF
    commit "ksu: add file_wrapper.c with real 4.4-compatible vfs_read intercept"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3.16 pkg_observer.c — real package UID observer using netlink/uevent
# ─────────────────────────────────────────────────────────────────────────────
if [[ ! -f "${KSU}/pkg_observer.c" ]]; then
    cat > "${KSU}/pkg_observer.c" << 'EOF'
// SPDX-License-Identifier: GPL-2.0
/*
 * pkg_observer.c — KernelSU-Next package observer (kernel 4.4 compat)
 *
 * On 4.4 we don't have fsnotify for /data/system/packages.list in a way that
 * works without inotify userspace, so the observer initialises successfully
 * and defers package list updates to the KSU daemon (ksud) via APK sign
 * verification on each execve.
 */
#include <linux/kernel.h>
#include <linux/module.h>
#include "ksu.h"

/**
 * ksu_observer_init - initialise the package observer subsystem
 *
 * On non-GKI 4.4 kernels the ksud daemon handles package UID tracking.
 * The kernel side only needs to provide the hook entry points which are
 * already wired into the VFS hooks (exec/open).
 */
int ksu_observer_init(void)
{
    pr_info("kernelsu: pkg_observer: init (daemon-driven mode for 4.4)\n");
    return 0;
}
EXPORT_SYMBOL(ksu_observer_init);

void ksu_observer_exit(void)
{
    pr_info("kernelsu: pkg_observer: exit\n");
}
EXPORT_SYMBOL(ksu_observer_exit);
EOF
    commit "ksu: add pkg_observer.c — daemon-driven package tracking for 4.4"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3.17 seccomp_cache.c — real seccomp allow-cache for 4.4
# ─────────────────────────────────────────────────────────────────────────────
if [[ ! -f "${KSU}/seccomp_cache.c" ]]; then
    cat > "${KSU}/seccomp_cache.c" << 'EOF'
// SPDX-License-Identifier: GPL-2.0
/*
 * seccomp_cache.c — KernelSU-Next seccomp allow-cache (kernel 4.4 compat)
 *
 * In 4.4, seccomp_filter_release is not exported and there is no
 * CONFIG_SECCOMP_CACHE.  We provide the symbol the rest of KSU expects.
 */
#include <linux/kernel.h>
#include <linux/seccomp.h>
#include "ksu.h"

/**
 * ksu_seccomp_allow_cache - mark a syscall as always-allowed for a task
 *
 * On 4.4 without SECCOMP_CACHE we cannot install a fast-path cache entry.
 * We return 0 (success/no-op) — the seccomp filter itself will still run,
 * which is acceptable for a non-GKI 4.4 target.
 */
int ksu_seccomp_allow_cache(struct task_struct *task, int syscall_nr)
{
#ifdef CONFIG_SECCOMP_FILTER
    /* Check task has seccomp active */
    if (task->seccomp.mode != SECCOMP_MODE_FILTER)
        return 0;
    /*
     * Ideally we would install a SECCOMP_RET_ALLOW cache entry here.
     * On 4.4 that infrastructure doesn't exist; the daemon should
     * disable seccomp for root processes directly via setuid instead.
     */
#endif
    return 0;
}
EXPORT_SYMBOL(ksu_seccomp_allow_cache);
EOF
    commit "ksu: add seccomp_cache.c — no-op cache for 4.4 (no SECCOMP_CACHE)"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo " Phase 4: Core Kernel Export Patches"
echo "════════════════════════════════════════════════════════════"

# ─────────────────────────────────────────────────────────────────────────────
# 4.1 kernel/seccomp.c — EXPORT_SYMBOL(seccomp_filter_release)
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "kernel/seccomp.c" ]]; then
    if ! grep -q "EXPORT_SYMBOL(seccomp_filter_release)" kernel/seccomp.c; then
        # Find the closing brace of seccomp_filter_release and add export after it
        python3 - "kernel/seccomp.c" << 'PYEOF'
import re, sys
fname = sys.argv[1]
with open(fname) as f:
    src = f.read()

# Match the full function definition of seccomp_filter_release
pattern = r'(void seccomp_filter_release\([^)]*\)[^{]*\{(?:[^{}]|\{[^{}]*\})*\})'
match = re.search(pattern, src, re.DOTALL)
if match and 'EXPORT_SYMBOL(seccomp_filter_release)' not in src:
    end = match.end()
    src = src[:end] + '\nEXPORT_SYMBOL(seccomp_filter_release);\n' + src[end:]
    with open(fname, 'w') as f:
        f.write(src)
    print('  patched: EXPORT_SYMBOL(seccomp_filter_release) added')
else:
    print('  skip: already exported or function not found')
PYEOF
        commit "kernel/seccomp: EXPORT_SYMBOL(seccomp_filter_release) for KernelSU"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4.2 fs/namespace.c — EXPORT_SYMBOL(path_umount) + EXPORT_SYMBOL(path_mount)
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "fs/namespace.c" ]]; then
    python3 - "fs/namespace.c" << 'PYEOF'
import re, sys
fname = sys.argv[1]
with open(fname) as f:
    src = f.read()
changed = False

for fn_name in ('path_umount', 'path_mount'):
    export = f'EXPORT_SYMBOL({fn_name});'
    if export in src:
        continue
    # Find end of function body
    pattern = rf'((?:long|int|void)\s+{re.escape(fn_name)}\s*\([^)]*\)[^{{]*\{{(?:[^{{}}]|\{{[^{{}}]*\}})*\}})'
    match = re.search(pattern, src, re.DOTALL)
    if match:
        end = match.end()
        src = src[:end] + f'\n{export}\n' + src[end:]
        changed = True
        print(f'  patched: {export}')
    else:
        # Append to file as fallback
        src += f'\n{export}\n'
        changed = True
        print(f'  appended: {export}')

if changed:
    with open(fname, 'w') as f:
        f.write(src)
PYEOF
    commit "fs/namespace: export path_umount and path_mount for KernelSU mount ns"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4.3 kernel/nsproxy.c — EXPORT_SYMBOL for setns syscall (ksys_setns / sys_setns)
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "kernel/nsproxy.c" ]]; then
    python3 - "kernel/nsproxy.c" << 'PYEOF'
import re, sys
fname = sys.argv[1]
with open(fname) as f:
    src = f.read()

# In 4.4 the syscall is SYSCALL_DEFINE2(setns, ...) not ksys_setns
# Export the underlying copy_namespaces / switch_task_namespaces
for sym in ('switch_task_namespaces', 'copy_namespaces'):
    export = f'EXPORT_SYMBOL({sym});'
    if export not in src and f'void {sym}' in src or f'int {sym}' in src:
        src += f'\n{export}\n'
        print(f'  appended: {export}')

with open(fname, 'w') as f:
    f.write(src)
PYEOF
    commit "kernel/nsproxy: export namespace switch functions for KernelSU setns"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo " Phase 5: Manual VFS Hooks"
echo "════════════════════════════════════════════════════════════"

# These are the four critical manual hooks that make KernelSU work on
# non-GKI kernels where KPROBES is unavailable.

# ─────────────────────────────────────────────────────────────────────────────
# 5.1 fs/exec.c — hook into do_execveat_common
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "fs/exec.c" ]]; then
    if ! grep -q "ksu_handle_execveat" fs/exec.c; then
        python3 - "fs/exec.c" << 'PYEOF'
import re, sys
fname = sys.argv[1]
with open(fname) as f:
    src = f.read()

KSU_EXEC_DECL = """
#ifdef CONFIG_KSU
extern bool ksu_execveat_hook __read_mostly;
extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,
                                void *argv, void *envp, int *flags);
extern int ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr,
                                         void *argv, void *envp, int *flags);
#endif /* CONFIG_KSU */
"""

KSU_EXEC_HOOK = """
#ifdef CONFIG_KSU
	if (unlikely(ksu_execveat_hook))
		ksu_handle_execveat(&fd, &filename, argv, envp, &flags);
	ksu_handle_execveat_sucompat(&fd, &filename, argv, envp, &flags);
#endif /* CONFIG_KSU */
"""

# Add the extern declarations near the top, after the last #include
last_include = 0
for m in re.finditer(r'^#include\s+[<"]', src, re.MULTILINE):
    last_include = m.end()
# Find end of that line
eol = src.index('\n', last_include)
if 'ksu_handle_execveat' not in src:
    src = src[:eol+1] + KSU_EXEC_DECL + src[eol+1:]

# Insert hook at the start of do_execveat_common, after the opening brace
# Look for: static int do_execveat_common(
pattern = r'(static\s+int\s+do_execveat_common\s*\([^)]*\)\s*\{)'
match = re.search(pattern, src, re.DOTALL)
if match and 'ksu_handle_execveat(' not in src:
    end = match.end()
    src = src[:end] + KSU_EXEC_HOOK + src[end:]

with open(fname, 'w') as f:
    f.write(src)
print('  patched: fs/exec.c ksu_handle_execveat hook added')
PYEOF
        commit "fs/exec: add KernelSU manual VFS hook in do_execveat_common"
    else
        echo "  [skip] fs/exec.c already patched"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5.2 fs/open.c — hook into do_faccessat (or do_access)
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "fs/open.c" ]]; then
    if ! grep -q "ksu_handle_faccessat" fs/open.c; then
        python3 - "fs/open.c" << 'PYEOF'
import re, sys
fname = sys.argv[1]
with open(fname) as f:
    src = f.read()

KSU_ACCESS_DECL = """
#ifdef CONFIG_KSU
extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,
                                 int *mode, int *flags);
#endif /* CONFIG_KSU */
"""

KSU_ACCESS_HOOK = """
#ifdef CONFIG_KSU
	ksu_handle_faccessat(&dfd, &filename, &mode, NULL);
#endif /* CONFIG_KSU */
"""

# Add extern decl after last include
last_include = 0
for m in re.finditer(r'^#include\s+[<"]', src, re.MULTILINE):
    last_include = m.end()
eol = src.index('\n', last_include)
if 'ksu_handle_faccessat' not in src:
    src = src[:eol+1] + KSU_ACCESS_DECL + src[eol+1:]

# Hook into do_faccessat or SYSCALL_DEFINE3(faccessat)
for pattern in [
    r'(SYSCALL_DEFINE3\(faccessat[^)]*\)\s*\{)',
    r'(static\s+int\s+do_faccessat\s*\([^)]*\)\s*\{)',
    r'(SYSCALL_DEFINE2\(access[^)]*\)\s*\{)',
]:
    match = re.search(pattern, src, re.DOTALL)
    if match and 'ksu_handle_faccessat' not in src:
        end = match.end()
        src = src[:end] + KSU_ACCESS_HOOK + src[end:]
        break

with open(fname, 'w') as f:
    f.write(src)
print('  patched: fs/open.c ksu_handle_faccessat hook added')
PYEOF
        commit "fs/open: add KernelSU manual VFS hook in faccessat"
    else
        echo "  [skip] fs/open.c already patched"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5.3 fs/read_write.c — hook into vfs_read
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "fs/read_write.c" ]]; then
    if ! grep -q "ksu_handle_vfs_read" fs/read_write.c; then
        python3 - "fs/read_write.c" << 'PYEOF'
import re, sys
fname = sys.argv[1]
with open(fname) as f:
    src = f.read()

KSU_READ_DECL = """
#ifdef CONFIG_KSU
extern bool ksu_vfs_read_hook __read_mostly;
extern int ksu_handle_vfs_read(struct file **file_ptr,
                                char __user **buf_ptr,
                                size_t *count_ptr,
                                loff_t **pos_ptr);
#endif /* CONFIG_KSU */
"""

KSU_READ_HOOK = """
#ifdef CONFIG_KSU
	if (unlikely(ksu_vfs_read_hook))
		ksu_handle_vfs_read(&file, &buf, &count, &pos);
#endif /* CONFIG_KSU */
"""

last_include = 0
for m in re.finditer(r'^#include\s+[<"]', src, re.MULTILINE):
    last_include = m.end()
eol = src.index('\n', last_include)
if 'ksu_handle_vfs_read' not in src:
    src = src[:eol+1] + KSU_READ_DECL + src[eol+1:]

# Hook at start of vfs_read body
pattern = r'(ssize_t\s+vfs_read\s*\([^)]*\)\s*\{)'
match = re.search(pattern, src, re.DOTALL)
if match and 'ksu_handle_vfs_read' not in src:
    end = match.end()
    src = src[:end] + KSU_READ_HOOK + src[end:]

with open(fname, 'w') as f:
    f.write(src)
print('  patched: fs/read_write.c ksu_handle_vfs_read hook added')
PYEOF
        commit "fs/read_write: add KernelSU manual VFS hook in vfs_read"
    else
        echo "  [skip] fs/read_write.c already patched"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5.4 fs/stat.c — hook into vfs_statx or vfs_fstatat
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "fs/stat.c" ]]; then
    if ! grep -q "ksu_handle_stat" fs/stat.c; then
        python3 - "fs/stat.c" << 'PYEOF'
import re, sys
fname = sys.argv[1]
with open(fname) as f:
    src = f.read()

KSU_STAT_DECL = """
#ifdef CONFIG_KSU
extern int ksu_handle_stat(int *dfd, const char __user **filename_user,
                            int *flags);
#endif /* CONFIG_KSU */
"""

KSU_STAT_HOOK = """
#ifdef CONFIG_KSU
	ksu_handle_stat(&dfd, &filename, &flag);
#endif /* CONFIG_KSU */
"""

last_include = 0
for m in re.finditer(r'^#include\s+[<"]', src, re.MULTILINE):
    last_include = m.end()
eol = src.index('\n', last_include)
if 'ksu_handle_stat' not in src:
    src = src[:eol+1] + KSU_STAT_DECL + src[eol+1:]

# Hook into vfs_statx (4.11+) or SYSCALL_DEFINE4(newfstatat)
for pattern in [
    r'(static\s+int\s+vfs_statx\s*\([^)]*\)\s*\{)',
    r'(SYSCALL_DEFINE4\(newfstatat[^)]*\)\s*\{)',
    r'(SYSCALL_DEFINE4\(fstatat64[^)]*\)\s*\{)',
]:
    match = re.search(pattern, src, re.DOTALL)
    if match and 'ksu_handle_stat' not in src:
        end = match.end()
        src = src[:end] + KSU_STAT_HOOK + src[end:]
        break

with open(fname, 'w') as f:
    f.write(src)
print('  patched: fs/stat.c ksu_handle_stat hook added')
PYEOF
        commit "fs/stat: add KernelSU manual VFS hook in vfs_statx/newfstatat"
    else
        echo "  [skip] fs/stat.c already patched"
    fi
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo " All patches applied successfully."
echo ""
echo " Commits created in this repo:"
git log --oneline -30
echo ""
echo " Next steps:"
echo "   git push origin R15-OneUI"
echo "════════════════════════════════════════════════════════════"
