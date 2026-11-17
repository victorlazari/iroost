#!/bin/sh
# Behaviour of .github/scripts/next-version.sh: previous version + commit subject -> next version.
S=$(cd "$(dirname "$0")/.." && pwd)/.github/scripts/next-version.sh
fail=0
check() { # want previous subject
  got=$(sh "$S" "$2" "$3")
  [ "$got" = "$1" ] || { echo "FAIL: ($2, '$3') want $1 got $got"; fail=1; }
}
check 0.2.0 0.1.0 'feat(panel): a thing (#1)'
check 0.1.1 0.1.0 'fix(panel): a thing (#2)'
check 0.1.1 0.1.0 'chore: bump'
check 0.1.1 0.1.0 'docs(readme): words'
check 1.0.0 0.9.4 'feat(panel)!: break it (#3)'
check 1.0.0 0.9.4 'refactor!: break it'
check 2.0.0 1.4.2 'fix(api)!: break it'
check 1.5.0 1.4.2 'feat: something'
check 0.1.1 0.1.0 'feature flags tidy'
check 0.1.1 0.1.0 'Merge pull request #4 from x/y'
[ $fail = 0 ] && echo "ok"
exit $fail
