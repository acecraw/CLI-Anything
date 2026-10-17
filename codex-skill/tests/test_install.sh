#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SKILL_DIR}/.." && pwd)"
PLUGIN_DIR="${REPO_ROOT}/cli-anything-plugin"
TMP_DIR="$(mktemp -d)"
CODEX_HOME="${TMP_DIR}/codex-home"
INSTALLED_DIR="${CODEX_HOME}/skills/cli-anything"
STALE_STAGING_DIR="${CODEX_HOME}/skills/.cli-anything.tmp.stale"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_same() {
  cmp -s "$1" "$2" || fail "files differ: $1 $2"
}

assert_tree_same() {
  diff -qr "$1" "$2" >/dev/null || fail "directories differ: $1 $2"
}

mkdir -p "${STALE_STAGING_DIR}/codex-skill"
echo "left over from an interrupted install" > "${STALE_STAGING_DIR}/codex-skill/stale.txt"

env -u CODEX_USER_SKILLS_DIR CODEX_HOME="${CODEX_HOME}" bash "${SKILL_DIR}/scripts/install.sh"

assert_file "${INSTALLED_DIR}/SKILL.md"
[[ -d "${STALE_STAGING_DIR}" ]] ||
  fail "installer reused or removed the stale staging directory"
[[ ! -d "${INSTALLED_DIR}/codex-skill" ]] ||
  fail "installer created a nested codex-skill directory"
assert_file "${INSTALLED_DIR}/references/HARNESS.md"
assert_file "${INSTALLED_DIR}/references/commands/cli-anything.md"
assert_file "${INSTALLED_DIR}/references/commands/refine.md"
assert_file "${INSTALLED_DIR}/references/commands/test.md"
assert_file "${INSTALLED_DIR}/references/commands/validate.md"
assert_file "${INSTALLED_DIR}/references/commands/list.md"
assert_file "${INSTALLED_DIR}/references/guides/auto-save-dry-run.md"
assert_file "${INSTALLED_DIR}/references/guides/session-locking.md"
assert_file "${INSTALLED_DIR}/references/guides/preview-methodology.md"
assert_file "${INSTALLED_DIR}/scripts/repl_skin.py"
assert_file "${INSTALLED_DIR}/scripts/preview_bundle.py"
assert_file "${INSTALLED_DIR}/scripts/skill_generator.py"
assert_file "${INSTALLED_DIR}/scripts/templates/SKILL.md.template"
assert_file "${INSTALLED_DIR}/references/docs/PREVIEW_PROTOCOL.md"

assert_same "${PLUGIN_DIR}/HARNESS.md" "${INSTALLED_DIR}/references/HARNESS.md"
assert_same "${PLUGIN_DIR}/repl_skin.py" "${INSTALLED_DIR}/scripts/repl_skin.py"
assert_same "${PLUGIN_DIR}/preview_bundle.py" "${INSTALLED_DIR}/scripts/preview_bundle.py"
assert_same "${PLUGIN_DIR}/skill_generator.py" "${INSTALLED_DIR}/scripts/skill_generator.py"
assert_same "${REPO_ROOT}/docs/PREVIEW_PROTOCOL.md" "${INSTALLED_DIR}/references/docs/PREVIEW_PROTOCOL.md"
assert_tree_same "${PLUGIN_DIR}/commands" "${INSTALLED_DIR}/references/commands"
assert_tree_same "${PLUGIN_DIR}/guides" "${INSTALLED_DIR}/references/guides"
assert_tree_same "${PLUGIN_DIR}/templates" "${INSTALLED_DIR}/scripts/templates"

python3 -m py_compile \
  "${INSTALLED_DIR}/scripts/repl_skin.py" \
  "${INSTALLED_DIR}/scripts/preview_bundle.py" \
  "${INSTALLED_DIR}/scripts/skill_generator.py"

if env -u CODEX_USER_SKILLS_DIR CODEX_HOME="${CODEX_HOME}" bash "${SKILL_DIR}/scripts/install.sh" >/dev/null 2>&1; then
  fail "installer overwrote an existing skill"
fi

grep -q 'references/HARNESS.md' "${INSTALLED_DIR}/SKILL.md" ||
  fail "installed SKILL.md does not point to vendored HARNESS.md"

CUSTOM_SKILLS_DIR="${TMP_DIR}/user skills root"
CUSTOM_INSTALLED_DIR="${CUSTOM_SKILLS_DIR}/cli-anything"
CUSTOM_CODEX_HOME="${TMP_DIR}/secondary-codex-home"
CODEX_USER_SKILLS_DIR="${CUSTOM_SKILLS_DIR}" CODEX_HOME="${CUSTOM_CODEX_HOME}" \
  bash "${SKILL_DIR}/scripts/install.sh"
assert_file "${CUSTOM_INSTALLED_DIR}/SKILL.md"
[[ ! -e "${CUSTOM_CODEX_HOME}/skills/cli-anything" ]] ||
  fail "explicit CODEX_USER_SKILLS_DIR did not take precedence over CODEX_HOME"

INVALID_SKILLS_ROOT="${TMP_DIR}/not-a-directory"
INVALID_FALLBACK_HOME="${TMP_DIR}/invalid-fallback-home"
touch "${INVALID_SKILLS_ROOT}"
if CODEX_USER_SKILLS_DIR="${INVALID_SKILLS_ROOT}" CODEX_HOME="${INVALID_FALLBACK_HOME}" \
  bash "${SKILL_DIR}/scripts/install.sh" >/dev/null 2>&1; then
  fail "installer accepted an invalid explicit CODEX_USER_SKILLS_DIR"
fi
[[ ! -e "${INVALID_FALLBACK_HOME}/skills/cli-anything" ]] ||
  fail "installer fell back to CODEX_HOME after invalid explicit CODEX_USER_SKILLS_DIR"

DEFAULT_HOME="${TMP_DIR}/default home"
DEFAULT_INSTALLED_DIR="${DEFAULT_HOME}/.codex/skills/cli-anything"
env -u CODEX_USER_SKILLS_DIR -u CODEX_HOME HOME="${DEFAULT_HOME}" \
  bash "${SKILL_DIR}/scripts/install.sh"
assert_file "${DEFAULT_INSTALLED_DIR}/SKILL.md"

DETACHED_ROOT="${TMP_DIR}/detached"
DETACHED_LOG="${TMP_DIR}/detached-install.log"
mkdir -p "${DETACHED_ROOT}"
cp -R "${SKILL_DIR}" "${DETACHED_ROOT}/codex-skill"
if env -u CODEX_USER_SKILLS_DIR CODEX_HOME="${TMP_DIR}/detached-home" bash "${DETACHED_ROOT}/codex-skill/scripts/install.sh" >"${DETACHED_LOG}" 2>&1; then
  fail "installer accepted a detached skill without canonical resources"
fi
grep -q 'Cannot find canonical CLI-Anything resources' "${DETACHED_LOG}" ||
  fail "detached install did not explain the missing canonical resources"

echo "PASS: Codex skill installer vendors the complete CLI-Anything resource set."
