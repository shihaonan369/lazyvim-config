#!/bin/sh
# claude_open splits its command on whitespace, not shell syntax. Carry the
# display name as one base64 token, then restore exactly one --name argument.
# No skill option on later ordinary spawns: forward argv unchanged (the plugin
# remembers this executable for M.new). No per-session name in cached env.
set -eu
case "${1-}" in
  --skill-name=*)
    name=$(printf '%s' "${1#--skill-name=}" | base64 -d)
    shift
    set -- --name "$name" "$@"
    ;;
esac
exec claude "$@"
