#!/usr/bin/env bash
# Run every purr test one at a time, printing a live [PASS]/[FAIL] per test.
#
# Nix is lazy, so a single `nix eval` cannot stream results — this script
# enumerates all test cases and evaluates each one individually, so you can
# watch tests pass/fail one by one.
#
# Usage:  tests/run-tests.sh          (fast iteration, still hermetic)
#         nix flake check             (the CI gate)
set -uo pipefail
cd "$(dirname "$0")"

RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RESET=$'\033[0m'

LIB_EXPR='lib = (builtins.getFlake "github:nix-community/nixpkgs.lib").lib;'

lines=$(nix eval --raw --impure --expr "
  let
    $LIB_EXPR
  in
  builtins.concatStringsSep \"\n\" (
    builtins.map (t: \"\${t.file}\t\${t.group}\t\${t.test}\") (import ./list-tests.nix { inherit lib; })
  )
") || {
  echo "failed to enumerate tests" >&2
  exit 1
}

total=0
passed=0
failed=0
declare -a failedNames=()

while IFS=$'\t' read -r file group test; do
  if [ -z "${file:-}" ]; then
    continue
  fi
  total=$((total + 1))
  # Test names are plain strings (no double quotes/backslashes), so inlining
  # them into the expression is safe and avoids --argstr quirks.
  expr="let lib = (builtins.getFlake \"github:nix-community/nixpkgs.lib\").lib; in import ./run-one.nix { inherit lib; file = \"${file}\"; group = \"${group}\"; test = \"${test}\"; }"
  out=$(nix eval --raw --impure --expr "$expr" 2>/dev/null)
  if [ "$out" = "[]" ]; then
    passed=$((passed + 1))
    printf '%s[PASS]%s %s :: %s :: %s\n' "$GREEN" "$RESET" "$file" "$group" "$test"
  else
    failed=$((failed + 1))
    failedNames+=("$file :: $group :: $test")
    printf '%s[FAIL]%s %s :: %s :: %s\n' "$RED" "$RESET" "$file" "$group" "$test"
  fi
done <<<"$lines"

printf '\n'
printf '  %-9s %d\n' 'total:' "$total"
printf '  %-9s %d\n' 'passed:' "$passed"
printf '  %-9s %d\n' 'failed:' "$failed"

if [ "$failed" -gt 0 ]; then
  printf '\n%sFailed tests:%s\n' "$YELLOW" "$RESET"
  for n in "${failedNames[@]}"; do
    printf '    %s\n' "$n"
  done
  exit 1
fi
exit 0
