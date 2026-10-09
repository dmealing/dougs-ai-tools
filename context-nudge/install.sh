#!/bin/sh
# Install or remove context-nudge for Claude Code without the plugin system.
#
# Copies the four scripts in scripts/ from this folder to
#   ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/context-nudge/bin/
# and prints the two settings entries that turn them on. It changes the
# settings file only when asked to with --write-settings.
#
# The copying is done by ../lib/install-skill.sh, which every tool in this
# repository shares, so run this from a full clone of the repository.
#
# POSIX sh; runs on macOS and Linux.

# $config_dir comes from the sourced file, which also reads $force and
# $uninstall; the jq programs are literal text.
# shellcheck disable=SC2154,SC2034,SC2016

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
lib="$here/../lib/install-skill.sh"
if [ ! -f "$lib" ]; then
	printf 'install.sh: cannot find %s; run install.sh from a full clone of the repository\n' "$lib" >&2
	exit 1
fi

{
	skill_name=context-nudge
	skill_src="$here/scripts"
	skill_files='context-nudge-lib.sh context-nudge-cache.sh context-nudge-statusline.sh context-nudge-hook.sh'
	skill_hint='The scripts do nothing until the settings file names them.'
}

# shellcheck source=/dev/null
. "$lib"

usage() {
	cat <<EOF
Usage: install.sh [--write-settings] [--force] [--uninstall] [--help]

Installs the context-nudge scripts into
\${CLAUDE_CONFIG_DIR:-\$HOME/.claude}/context-nudge/bin/ and prints the settings
entries that turn them on.

  --write-settings  Also add those entries to settings.json, using jq, after
                    writing a timestamped backup beside it. Refuses when a
                    different status line is already set.
  --force           Replace (or, with --uninstall, remove) an installed copy
                    that differs from the one shipped here.
  --uninstall       Remove the installed scripts, and the settings entries a
                    --write-settings run added.
  --help            Show this text.
EOF
}

force=0
uninstall=0
write_settings=0
for arg in "$@"; do
	case "$arg" in
	--force) force=1 ;;
	--uninstall) uninstall=1 ;;
	--write-settings) write_settings=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		usage >&2
		install_skill_die "unknown option: $arg"
		;;
	esac
done
if [ "$uninstall" -eq 1 ] && [ "$write_settings" -eq 1 ]; then
	install_skill_die "--write-settings cannot be combined with --uninstall"
fi

install_config_dir
tool_dir="$config_dir/context-nudge"
dest_dir="$tool_dir/bin"
settings="$config_dir/settings.json"
# Which entries a --write-settings run added, one word a line: hook, statusline.
marker="$tool_dir/settings-written"
jq_bin=${CONTEXT_NUDGE_JQ:-jq}

# The commands go into JSON inside single quotes, so the path must not hold a
# quote or a backslash.
case "$dest_dir" in
*\'* | *\"* | *\\*)
	install_skill_die "the configuration path holds a quote or a backslash, which the settings entries cannot carry: $dest_dir"
	;;
esac
hook_cmd="sh '$dest_dir/context-nudge-hook.sh'"
status_cmd="sh '$dest_dir/context-nudge-statusline.sh'"
cache_cmd="sh '$dest_dir/context-nudge-cache.sh'"

print_wrapper() {
	cat <<EOF
To keep a status line you already have, put the cache writer in front of its
command in "statusLine":

    "command": "$cache_cmd | <your current command>"
EOF
}

print_snippets() {
	cat <<EOF

To turn it on, add these two entries to $settings
(or re-run with --write-settings to have that done for you):

    "hooks": {
      "UserPromptSubmit": [
        { "hooks": [ { "type": "command", "command": "$hook_cmd" } ] }
      ]
    },
    "statusLine": { "type": "command", "command": "$status_cmd" }

EOF
	print_wrapper
}

# backup_settings: copies the settings file beside itself and reports where.
backup_settings() {
	backup="$settings.context-nudge-backup-$(date +%Y%m%d-%H%M%S)"
	cp -p "$settings" "$backup"
	printf 'Backup: %s\n' "$backup"
}

# replace_settings <new content>: writes through the existing file, so a
# settings file that is a symbolic link stays one.
replace_settings() {
	[ -n "$1" ] || install_skill_die "jq produced no settings; $settings is unchanged"
	printf '%s\n' "$1" >"$settings"
}

need_jq() {
	command -v "$jq_bin" >/dev/null 2>&1 ||
		install_skill_die "$1 needs jq, which was not found. $settings is unchanged."
}

merge_settings() {
	need_jq "--write-settings"
	if [ -e "$settings" ]; then
		"$jq_bin" -e 'type == "object"' "$settings" >/dev/null 2>&1 ||
			install_skill_die "$settings is not a JSON object; not changing it"
		current=$(cat "$settings")
	else
		current='{}'
	fi

	found=$(printf '%s' "$current" | "$jq_bin" -r '
		(.statusLine | if type == "object" then (.command // "" | tostring) else "" end) as $line
		| (if (.statusLine // null) == null then "absent"
		   elif ($line | test("context-nudge-(cache|statusline)\\.sh")) then "ours"
		   else "other" end),
		  (if ([.hooks.UserPromptSubmit[]?.hooks[]?.command? | strings
		        | select(test("context-nudge-hook\\.sh"))] | length) > 0
		   then "present" else "absent" end),
		  $line' 2>/dev/null) ||
		install_skill_die "cannot read the hooks in $settings; not changing it"
	{
		IFS= read -r status_state
		IFS= read -r hook_state
		# Empty when no command is set, and read then reports the end of input.
		IFS= read -r status_line || :
	} <<EOF
$found
EOF

	if [ "$status_state" = other ]; then
		cat >&2 <<EOF
install.sh: $settings already sets a different status line:
    ${status_line:-(not a command)}
Not changing the settings file.
EOF
		print_wrapper >&2
		printf 'Then run install.sh --write-settings again to add the hook.\n' >&2
		exit 1
	fi
	if [ "$status_state" = ours ] && [ "$hook_state" = present ]; then
		printf 'Settings already hold both entries; nothing changed: %s\n' "$settings"
		return 0
	fi

	add_hook=0
	add_status=0
	[ "$hook_state" = present ] || add_hook=1
	[ "$status_state" = ours ] || add_status=1
	merged=$(printf '%s' "$current" | "$jq_bin" \
		--arg hook "$hook_cmd" --arg status "$status_cmd" \
		--arg add_hook "$add_hook" --arg add_status "$add_status" '
		(if $add_hook == "1" then
			.hooks = ((.hooks // {}) | .UserPromptSubmit =
				((.UserPromptSubmit // []) + [{hooks: [{type: "command", command: $hook}]}]))
		 else . end)
		| (if $add_status == "1" then .statusLine = {type: "command", command: $status} else . end)') ||
		install_skill_die "cannot merge into $settings; not changing it"

	if [ -e "$settings" ]; then
		backup_settings
	else
		printf 'No settings file yet, so there is nothing to back up.\n'
	fi
	replace_settings "$merged"
	[ "$add_hook" -eq 0 ] || grep -qx hook "$marker" 2>/dev/null || printf 'hook\n' >>"$marker"
	[ "$add_status" -eq 0 ] || grep -qx statusline "$marker" 2>/dev/null || printf 'statusline\n' >>"$marker"
	[ "$add_hook" -eq 0 ] || printf 'Added the UserPromptSubmit hook to %s\n' "$settings"
	[ "$add_status" -eq 0 ] || printf 'Added the status line to %s\n' "$settings"
	printf 'Start a new Claude Code session to pick the change up.\n'
}

# unmerge_settings: takes out the entries a --write-settings run added, and
# only those: an entry is removed when the marker lists it and it still holds
# the exact command this script wrote.
unmerge_settings() {
	# Every refusal that leaves the settings file alone ends with the same
	# sentence, and the test greps for it, so it lives in one place.
	manual='Remove the context-nudge entries from it yourself.'
	if [ ! -f "$marker" ]; then
		if grep -q 'context-nudge-' "$settings" 2>/dev/null; then
			printf 'This script did not write %s, so it is unchanged. %s\n' "$settings" "$manual"
		fi
		return 0
	fi
	if [ ! -f "$settings" ]; then
		rm -f "$marker"
		return 0
	fi
	if ! command -v "$jq_bin" >/dev/null 2>&1; then
		printf 'jq was not found, so %s is unchanged. %s\n' "$settings" "$manual"
		return 0
	fi
	rm_hook=0
	rm_status=0
	! grep -qx hook "$marker" || rm_hook=1
	! grep -qx statusline "$marker" || rm_status=1
	before=$("$jq_bin" . "$settings" 2>/dev/null) || {
		printf '%s is not valid JSON, so it is unchanged. %s\n' "$settings" "$manual"
		return 0
	}
	after=$(printf '%s' "$before" | "$jq_bin" \
		--arg hook "$hook_cmd" --arg status "$status_cmd" \
		--arg rm_hook "$rm_hook" --arg rm_status "$rm_status" '
		(if $rm_hook == "1" and (.hooks.UserPromptSubmit? | type) == "array" then
			.hooks.UserPromptSubmit |= map(
				if (.hooks? | type) == "array" and (.hooks | map(.command?) | index($hook)) != null
				then (.hooks |= map(select(.command? != $hook))) | select(.hooks | length > 0)
				else . end)
			| (if (.hooks.UserPromptSubmit | length) == 0 then del(.hooks.UserPromptSubmit) else . end)
			| (if (.hooks | length) == 0 then del(.hooks) else . end)
		 else . end)
		| (if $rm_status == "1" and (.statusLine | type) == "object" and .statusLine.command == $status
		   then del(.statusLine) else . end)' 2>/dev/null) || {
		printf 'Cannot edit %s, so it is unchanged. %s\n' "$settings" "$manual"
		return 0
	}
	if [ "$before" = "$after" ]; then
		printf 'The entries this script added are no longer in %s; it is unchanged.\n' "$settings"
	else
		backup_settings
		replace_settings "$after"
		printf 'Removed the context-nudge entries from %s\n' "$settings"
	fi
	rm -f "$marker"
}

if [ "$uninstall" -eq 1 ]; then
	# A refusal here ends the run before the settings are looked at.
	install_files
	unmerge_settings
	# The folder stays while it still holds the hook's per-session files.
	rmdir "$tool_dir" 2>/dev/null || true
	exit 0
fi

install_files
if [ "$write_settings" -eq 1 ]; then
	merge_settings
else
	print_snippets
fi
