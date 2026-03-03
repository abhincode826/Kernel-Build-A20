# Samsung Galaxy A20 (SM-A205F) Custom Kernel with KernelSU-Next

> Exynos 7885 · Kernel 4.4 · OneUI · KernelSU-Next (legacy/non-GKI)

---

## Device Information

| Field | Value |
|---|---|
| Device | Samsung Galaxy A20 (SM-A205F) |
| SoC | Samsung Exynos 7885 |
| Kernel base | 4.4 (non-GKI, legacy) |
| Android target | OneUI (Samsung) |
| Root solution | KernelSU-Next — `legacy` branch |
| Toolchain | Clang 15 + LLD (see [Toolchain note](#toolchain-recommendation)) |

---

## Repo Structure

```
kernel-build-a20/           ← this repo (workflow + tooling)
│
├── .github/workflows/
│   └── main.yml            ← GitHub Actions build workflow
│
├── patches/
│   ├── apply_patches.sh    ← ONE-TIME setup script: run in your kernel fork
│   ├── headers/            ← Linux 4.4 header shims
│   ├── ksu/                ← KernelSU-Next compat patches (per-file)
│   └── core/               ← Core kernel export/hook patches
│
├── AnyKernel3/             ← AnyKernel3 flasher config
│   └── anykernel.sh
│
└── docs/
    └── PATCHING.md         ← Detailed explanation of every patch
```

The **kernel source** lives in a separate fork:
```
github.com/YOUR_USERNAME/eureka-kernel   (fork of CodeAbhi826/eureka-kernel, branch: R15-OneUI)
```
All compatibility patches are committed directly into that fork as real git commits — not applied at build time.

---

## Quick Setup

### Step 1 — Fork the kernel source

1. Go to [CodeAbhi826/eureka-kernel](https://github.com/CodeAbhi826/eureka-kernel)
2. Fork it to your account
3. Clone locally:

```bash
git clone https://github.com/YOUR_USERNAME/eureka-kernel.git -b R15-OneUI
cd eureka-kernel
```

### Step 2 — Apply compatibility patches (one-time)

```bash
bash /path/to/this-repo/patches/apply_patches.sh
```

This script:
- Adds KernelSU-Next `legacy` branch as `drivers/kernelsu/`
- Applies every compatibility shim as a separate, descriptive `git commit`
- Adds VFS manual hooks to `fs/exec.c`, `fs/open.c`, `fs/read_write.c`, `fs/stat.c`
- Exports required symbols from `kernel/seccomp.c`, `fs/namespace.c`, `kernel/nsproxy.c`

Push your patched fork:
```bash
git push origin R15-OneUI
```

### Step 3 — Configure this workflow repo

Edit `.github/workflows/main.yml` and set:
```yaml
env:
  KERNEL_SOURCE: https://github.com/YOUR_USERNAME/eureka-kernel
  KERNEL_BRANCH: R15-OneUI
  KERNEL_DEFCONFIG: exynos7885-a20_defconfig   # adjust if needed
```

Add repository secrets:
| Secret | Value |
|---|---|
| `TG_BOT_TOKEN` | Your Telegram bot token |
| `TG_CHAT_ID` | Your chat/channel ID |

### Step 4 — Build

Push to `main` or trigger manually via **Actions → Run workflow**.

---

## Toolchain Recommendation

**Clang 15 is recommended** over Clang 18 for this kernel. Here's why:

- Kernel 4.4 predates Clang's modern C23 defaults and stricter `-Wimplicit-function-declaration` as an error
- Clang 17+ made several old GCC-isms into hard errors that appear throughout Samsung's 4.4 BSP code
- Clang 15 still applies modern LTO-friendly IR and gives better performance than GCC 4.9, without the breakage of Clang 17+
- If you need Clang 18: add `KCFLAGS="-Wno-error -Wno-unused-function -Wno-return-type"` — it will build but you'll suppress real warnings

---

## KernelSU-Next (Legacy Non-GKI)

This kernel uses **KernelSU-Next legacy branch** — the fork maintained for pre-GKI (kernel 4.4/4.14) devices.

- Repo: [rifsxd/KernelSU-Next](https://github.com/rifsxd/KernelSU-Next) — branch `legacy`
- Manager APK: [KernelSU-Next releases](https://github.com/rifsxd/KernelSU-Next/releases)
- Uses **manual VFS hooks** (no KPROBES — Exynos 7885 doesn't have it enabled)

---

## Patch Summary

| Category | Files Patched | Key Change |
|---|---|---|
| Header shims | `include/linux/compiler_types.h` etc. | Missing macros for 4.4 |
| Header shims | `include/linux/sched/signal.h` | Shim → include `linux/sched.h` |
| Header shims | `include/linux/pgtable.h` | Shim → `asm/pgtable.h` + p4d stubs |
| Header shims | `include/uapi/linux/mount.h` | Add missing `MOVE_MOUNT_*` flags |
| KSU compat | `allowlist.c` | `kernel_write` 4.4 API + `TWA_RESUME` |
| KSU compat | `app_profile.c` | `group_info->gid[i].val`, `filter_count` |
| KSU compat | `syscall_hook_manager.c` | `untagged_addr` shim |
| KSU compat | `sucompat.c` | `strncpy_from_user_nofault` → `strncpy_from_user` |
| KSU compat | `throne_tracker.c` | `full_name_hash` 2-arg (4.4) |
| KSU compat | `supercalls.c` | `ksys_close` → `sys_close` |
| KSU compat | `su_mount_ns.c` | `ksys_close`, `ksys_unshare` |
| KSU compat | `ksud.c` | `_nofault` variants, `copy_to_iter` cast |
| KSU compat | `apk_sign.c` | `kernel_read` 4.4 API |
| KSU compat | `util.c` | No p4d level + `mmap_sem` |
| KSU compat | `selinux/selinux.c` | `selinux_enforcing` global (not struct) |
| KSU compat | `selinux/sepolicy.c` | Samsung 4.4 sepolicy stubs |
| Core kernel | `kernel/seccomp.c` | `EXPORT_SYMBOL(seccomp_filter_release)` |
| Core kernel | `fs/namespace.c` | `EXPORT_SYMBOL(path_umount/path_mount)` |
| Core kernel | `kernel/nsproxy.c` | `EXPORT_SYMBOL(ksys_setns / sys_setns)` |
| VFS hooks | `fs/exec.c` | `ksu_handle_execveat` |
| VFS hooks | `fs/open.c` | `ksu_handle_faccessat` |
| VFS hooks | `fs/read_write.c` | `ksu_handle_vfs_read` |
| VFS hooks | `fs/stat.c` | `ksu_handle_stat` |

---

## Output

A successful build produces:
```
A20_<kernel-version>-KSUN-<ksu-version>_b<build-num>.zip
```

Uploaded to:
- GitHub Releases (tagged automatically)
- Telegram (via bot)

Flash in **TWRP** or any recovery supporting AnyKernel3 zips.
