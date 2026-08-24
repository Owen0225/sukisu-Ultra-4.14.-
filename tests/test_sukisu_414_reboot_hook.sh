#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

KERNEL_DIR="${TEST_TMP}/kernel-tree"
WORKSPACE="$TEST_TMP"
KSU_VARIANT=sukisu-ultra
KSU_DIR=KernelSU

mkdir -p \
	"${KERNEL_DIR}/KernelSU/kernel/policy" \
	"${KERNEL_DIR}/KernelSU/kernel/runtime" \
	"${KERNEL_DIR}/KernelSU/kernel/sulog" \
	"${KERNEL_DIR}/kernel"

printf 'VERSION = 4\nPATCHLEVEL = 14\n' >"${KERNEL_DIR}/Makefile"
printf '        fallthrough;\n' >"${KERNEL_DIR}/KernelSU/kernel/policy/allowlist.c"
printf '%s\n%s\n' \
	'ksu_selinux_hide_handle_post_fs_data();' \
	'ksu_selinux_hide_handle_second_stage();' \
	>"${KERNEL_DIR}/KernelSU/kernel/runtime/ksud.c"
printf '%s\n' '#define USER_ARG_NULL user_arg_null_ptr()' \
	>"${KERNEL_DIR}/KernelSU/kernel/sulog/event.c"
cat >"${KERNEL_DIR}/kernel/reboot.c" <<'EOF'
static DEFINE_MUTEX(reboot_mutex);

SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,
		void __user *, arg)
{
	struct pid_namespace *pid_ns = task_active_pid_ns(current);
	char buffer[256];
	int ret = 0;

	/* We only trust the superuser with rebooting the system. */
}
EOF

# shellcheck source=scripts/patches.sh
. "${REPO_ROOT}/scripts/patches.sh"
sukisu_414_compat_apply >/dev/null

grep -q 'extern int ksu_handle_sys_reboot' "${KERNEL_DIR}/kernel/reboot.c"
grep -q 'ksu_handle_sys_reboot(magic1, magic2, cmd, &arg);' \
	"${KERNEL_DIR}/kernel/reboot.c"

echo "PASS: SukiSU 4.14 compatibility adds the reboot FD hook"
