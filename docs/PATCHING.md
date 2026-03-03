# Patching Reference — KernelSU-Next on Samsung Exynos 7885 / Kernel 4.4

This document explains every compatibility change made by `apply_patches.sh`,
why it is needed, and what real kernel behaviour it enables or preserves.

---

## Why are patches needed?

KernelSU-Next's `legacy` branch targets kernel 4.9–4.19.  
The Samsung Exynos 7885 ships kernel **4.4**, which predates several Linux kernel
API changes.  Every patch below bridges that gap — none of them disable core
KernelSU functionality; they translate newer API calls into their 4.4 equivalents.

---

## Phase 1 — Header Shims

### `include/linux/compiler_types.h`
**Why**: `__randomize_layout`, `__counted_by`, `__struct_group` were added post-4.4.
KernelSU source uses them (or headers it pulls in do).  
**Fix**: Add `#ifndef` guards that define them as empty macros — harmless no-ops on
a kernel that doesn't have struct randomisation anyway.

### `include/linux/sched/signal.h` (new file)
**Why**: In 4.11+ the scheduler headers were split; `linux/sched/signal.h` holds
`send_sig()`, `signal_pending()` etc.  In 4.4 these all live in `linux/sched.h`.  
**Fix**: Create a one-liner shim that `#include <linux/sched.h>`, so any KSU
file that does `#include <linux/sched/signal.h>` gets the right symbols.

### `include/linux/pgtable.h` (new file) + p4d stubs
**Why**: `linux/pgtable.h` doesn't exist in 4.4 (it's `asm/pgtable.h`).  
Also, KernelSU's memory-walking code (`util.c`) uses the 5-level paging
`p4d_t` type introduced in 4.11.  Exynos 7885 uses 4-level paging.  
**Fix**: Create the header as a shim to `asm/pgtable.h` and provide inline
`p4d_t` / `p4d_offset()` / `p4d_none()` etc. that fold p4d into pgd —
identical to how the kernel handles `__PAGETABLE_P4D_FOLDED` on 32-bit arches.

### `include/uapi/linux/mount.h`
**Why**: `MOVE_MOUNT_*` flags were added in 5.2.  
**Fix**: `#ifndef` guards add the constants — they are only values, no kernel
logic changes.

---

## Phase 2 — KernelSU-Next Integration

### `drivers/kernelsu/` (from KernelSU-Next `legacy` branch)
The `legacy` branch is specifically maintained for 4.4/4.14 non-GKI devices.
Unlike the `main` branch it does **not** require `KPROBES`.

### `drivers/Makefile` + `drivers/Kconfig`
Standard wiring so `CONFIG_KSU=y` in defconfig enables the driver.

---

## Phase 3 — KernelSU Source Patches

### `ksu_compat_44.h` — master shim header
Rather than scatter `#if LINUX_VERSION_CODE` blocks across dozens of files,
a single header is force-included at compile time via `ccflags-y += -include`.
This header provides:

| Shim | 4.4 equivalent |
|---|---|
| `mmap_read_lock(mm)` | `down_read(&mm->mmap_sem)` |
| `mmap_read_unlock(mm)` | `up_read(&mm->mmap_sem)` |
| `strncpy_from_user_nofault(d,s,n)` | `strncpy_from_user(d,s,n)` |
| `copy_from_user_nofault(d,s,n)` | `access_ok + __copy_from_user_inatomic` |
| `TWA_RESUME` | `true` (bool form of task_work_add notify arg) |
| `ksys_close(fd)` | `sys_close(fd)` via fget/fput |
| `ksys_unshare(flags)` | `sys_unshare(flags)` |
| `kernel_write(f,b,n,pp)` | `set_fs(KERNEL_DS) + vfs_write + set_fs(old)` |
| `kernel_read(f,b,n,pp)` | `set_fs(KERNEL_DS) + vfs_read + set_fs(old)` |
| `ksu_full_name_hash(s,n,l)` | `full_name_hash(n,l)` (2-arg in 4.4) |
| `untagged_addr(a)` | `(a)` (identity — no MTE on 7885) |
| `KSU_GROUP_GID(gi,i)` | `gi->gid[i].val` or `gi->gid[i]` |
| `ksu_selinux_enforcing()` | `selinux_enforcing` (global int in 4.4) |
| `ksu_set_selinux_enforcing(v)` | `selinux_enforcing = v` |

### `allowlist.c`
`kernel_write()` in 4.4 takes `loff_t pos` (by value), not `loff_t *pos`.
The compat shim transparently redirects to `vfs_write` with `KERNEL_DS`.

`task_work_add()` in 4.4 takes `bool notify` not `enum twa_t notify`.
`TWA_RESUME` is redefined to `true` in the compat header.

### `app_profile.c`
Two issues:
1. `group_info->gid[i]` is `kgid_t` (struct) in Samsung 4.4 under
   `CONFIG_UIDGID_STRICT_TYPE_CHECKS`.  Must use `.val` to get raw `gid_t`.
   Handled by the `KSU_GROUP_GID()` macro.
2. `task->seccomp.filter_count` does not exist in 4.4.  
   Replaced with `ksu_seccomp_filter_count()` which walks the filter chain.

### `sucompat.c` + `syscall_hook_manager.c`
`strncpy_from_user_nofault()` was added in 5.8.  
The compat header maps it to `strncpy_from_user()`.  
On 4.4 this can fault if the user pointer is invalid, but in the context
KernelSU calls this (after UACCESS checks), it is safe in practice.

### `throne_tracker.c`
`full_name_hash()` gained a `salt` first argument in 4.8 to harden dentry
hash randomisation.  The `ksu_full_name_hash()` macro selects the right form.

### `supercalls.c` / `su_mount_ns.c`
`ksys_close()` and `ksys_unshare()` are the kernel-internal versions of
`sys_close/sys_unshare` introduced in 4.17 for in-kernel use.  
In 4.4 use `sys_close()` / `sys_unshare()` directly.

### `ksud.c`
`copy_to_iter()` signature requires an explicit `const void *` cast in 4.4.

### `apk_sign.c`
`kernel_read()` API change same as `kernel_write`.

### `util.c`
- **p4d removal**: walks that go `pgd→p4d→pud→pmd→pte` are collapsed to
  `pgd→pud→pmd→pte` directly.  p4d folds into pgd on all 4-level arches.
- **mmap_sem**: `mmap_read_lock()` / `mmap_read_unlock()` macro-replaced
  with `down_read` / `up_read` on `mm->mmap_sem`.

### `selinux/selinux.c`
The `selinux_state` struct was introduced in ~4.17.  In 4.4 Samsung:
- `selinux_enforcing` is a global `int` in `security/selinux/selinuxfs.c`
- `selinux_cred(cred)` doesn't exist; credentials security blob is at `cred->security`

`ksu_selinux_enforcing()` and `ksu_set_selinux_enforcing()` macros abstract
both forms.  `selinux_cred()` is replaced with a direct struct cast.

---

## Phase 4 — Core Kernel Exports

| Symbol | Why exported |
|---|---|
| `seccomp_filter_release` | KSU module references it for seccomp cleanup |
| `path_umount` | KSU uses it for mount namespace manipulation |
| `path_mount` | KSU uses it to bind-mount overlays |
| `switch_task_namespaces` | KSU uses it to implement `su --mount-master` |

These are `EXPORT_SYMBOL` additions to existing kernel functions — they do not
change any function logic, only make the symbols visible to loadable modules
(and to the built-in KSU driver object, which also needs them if compiled as
a separate translation unit).

---

## Phase 5 — Manual VFS Hooks

Because Exynos 7885 doesn't expose `CONFIG_KPROBES`, KernelSU can't use its
preferred inline hooking.  Instead, 4 call sites in core VFS code are patched
with direct `extern` function calls guarded by `#ifdef CONFIG_KSU`.

| File | Function hooked | KSU purpose |
|---|---|---|
| `fs/exec.c` | `do_execveat_common` | su binary detection; exec intercept |
| `fs/open.c` | `do_faccessat` / `SYSCALL_DEFINE3(faccessat)` | `/system/bin/su` access check |
| `fs/read_write.c` | `vfs_read` | Manager APK detection on read |
| `fs/stat.c` | `vfs_statx` / `newfstatat` | Hide su binary from stat calls |

Each hook is:
- Guarded by `#ifdef CONFIG_KSU` — zero overhead if KSU is disabled
- Checked against a `__read_mostly` boolean (fast non-atomic read)
- An `extern` declaration only — no code is duplicated

---

## Toolchain Note

**Clang 15 is recommended.**  
Clang 17+ made `-Wimplicit-function-declaration` a hard error by default,
which breaks dozens of Samsung BSP inline asm and media driver headers in 4.4.
Clang 15 gives you modern IR optimisations, LTO support, and LLD linking
without the BSP breakage.  The `KCFLAGS="-Wno-error"` in the workflow is a
safety net but should not be needed for the KernelSU-specific code.
