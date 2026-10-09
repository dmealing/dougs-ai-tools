#!/bin/sh
# Tests for ../install.sh. The cases for copying and removing files are shared
# with the other tools and live in ../../lib/test-install-skill.sh; the cases
# for the settings file are here. Every one runs against a throwaway config
# directory, so nothing under the real Claude Code configuration is touched.
#
# Run: sh context-nudge/tests/test-install.sh

# $work and the helper functions come from the sourced test-install-skill.sh.
# shellcheck disable=SC2154

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
root=$(dirname -- "$here")
repo=$(dirname -- "$root")

# The variables are read by the sourced cases.
# shellcheck disable=SC2034
{
	installer="$root/install.sh"
	skill_name=context-nudge
	skill_src="$root/scripts"
	skill_files='context-nudge-lib.sh context-nudge-cache.sh context-nudge-statusline.sh context-nudge-hook.sh'
	dest_subdir=context-nudge/bin
	install_noun=scripts
	# The tool's own folder goes when it is empty; the config directory stays.
	keep_subdir=.
}

# shellcheck source=/dev/null
. "$repo/lib/test-helpers.sh"
# shellcheck source=/dev/null
. "$repo/lib/test-install-skill.sh"

# --- a plain install prints the entries and leaves the settings alone ---------
cfg="$work/plain"
mkdir -p "$cfg"
printf '{"model":"example"}\n' >"$cfg/settings.json"
cp "$cfg/settings.json" "$work/before"
run_installer "$cfg"
check "plain install prints the hook entry" output_has '"UserPromptSubmit"'
check "plain install prints the status-line entry" output_has '"statusLine"'
check "plain install names --write-settings" output_has "--write-settings"
check "plain install explains the cache writer" output_has "context-nudge-cache.sh' | <your current command>"
check "plain install leaves the settings file alone" cmp -s "$work/before" "$cfg/settings.json"
check "plain install writes no backup" [ "$(find "$cfg" -name 'settings.json.*' | wc -l)" -eq 0 ]

if ! command -v jq >/dev/null 2>&1; then
	printf 'skip - jq not found; the settings cases were not run\n'
	finish install
	exit 0
fi

backups() { find "$1" -name 'settings.json.context-nudge-backup-*' | wc -l | tr -d ' '; }
hook_cmd="sh '$cfg/context-nudge/bin/context-nudge-hook.sh'"
status_cmd="sh '$cfg/context-nudge/bin/context-nudge-statusline.sh'"

# --- --write-settings without jq changes nothing --------------------------------
CONTEXT_NUDGE_JQ="$work/no-such-jq" CLAUDE_CONFIG_DIR="$cfg" sh "$installer" --write-settings >"$work/out" 2>&1
status=$?
check "--write-settings without jq fails" [ "$status" -ne 0 ]
check "--write-settings without jq says so" output_has "needs jq"
check "--write-settings without jq leaves the settings file alone" cmp -s "$work/before" "$cfg/settings.json"

# --- --write-settings backs up, then merges -----------------------------------
printf '{"model":"example","hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"other-hook"}]}],"Stop":[]}}\n' >"$cfg/settings.json"
cp "$cfg/settings.json" "$work/before"
run_installer "$cfg" --write-settings
check "--write-settings exits 0" [ "$status" -eq 0 ]
check "--write-settings writes one backup" [ "$(backups "$cfg")" -eq 1 ]
backup=$(find "$cfg" -name 'settings.json.context-nudge-backup-*')
check "the backup is the file as it was" cmp -s "$work/before" "$backup"
stamped() { printf '%s\n' "$1" | grep -Eq 'backup-[0-9]{8}-[0-9]{6}$'; }
check "the backup name carries a timestamp" stamped "$backup"
check "merge adds the hook" \
	[ "$(jq -r '.hooks.UserPromptSubmit[1].hooks[0].command' "$cfg/settings.json")" = "$hook_cmd" ]
check "merge adds the status line" \
	[ "$(jq -r '.statusLine.type + " " + .statusLine.command' "$cfg/settings.json")" = "command $status_cmd" ]
check "merge keeps the other hook" \
	[ "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$cfg/settings.json")" = "other-hook" ]
check "merge keeps unrelated settings" \
	[ "$(jq -c '[.model, .hooks.Stop]' "$cfg/settings.json")" = '["example",[]]' ]

# --- a second --write-settings changes nothing ----------------------------------
cp "$cfg/settings.json" "$work/merged"
run_installer "$cfg" --write-settings
check "second --write-settings exits 0" [ "$status" -eq 0 ]
check "second --write-settings reports nothing changed" output_has "nothing changed"
check "second --write-settings leaves the file alone" cmp -s "$work/merged" "$cfg/settings.json"
check "second --write-settings writes no second backup" [ "$(backups "$cfg")" -eq 1 ]

# --- --uninstall takes out only what was added -----------------------------------
rm -f "$backup"
run_installer "$cfg" --uninstall
check "--uninstall after --write-settings exits 0" [ "$status" -eq 0 ]
check "--uninstall backs the settings up first" [ "$(backups "$cfg")" -eq 1 ]
check "--uninstall restores the settings content" \
	[ "$(jq -S -c . "$cfg/settings.json")" = "$(jq -S -c . "$work/before")" ]
check "--uninstall removes the scripts" none_installed "$cfg/context-nudge/bin"
check "--uninstall removes the empty tool folder" [ ! -d "$cfg/context-nudge" ]

# --- --uninstall leaves entries it did not write ---------------------------------
cfg="$work/by-hand"
run_installer "$cfg"
jq -n --arg hook "sh '$cfg/context-nudge/bin/context-nudge-hook.sh'" \
	'{hooks: {UserPromptSubmit: [{hooks: [{type: "command", command: $hook}]}]}}' >"$cfg/settings.json"
cp "$cfg/settings.json" "$work/before"
run_installer "$cfg" --uninstall
check "--uninstall leaves entries added by hand" cmp -s "$work/before" "$cfg/settings.json"
check "--uninstall says to remove them" output_has "Remove the context-nudge entries"

# --- refuses when another status line is set ------------------------------------
cfg="$work/other-line"
mkdir -p "$cfg"
printf '{"statusLine":{"type":"command","command":"my-status-line --wide"}}\n' >"$cfg/settings.json"
cp "$cfg/settings.json" "$work/before"
run_installer "$cfg" --write-settings
check "another status line makes --write-settings fail" [ "$status" -ne 0 ]
check "the refusal shows the current command" output_has "my-status-line --wide"
check "the refusal prints the wrapper line" output_has "context-nudge-cache.sh' | <your current command>"
check "the refusal leaves the settings file alone" cmp -s "$work/before" "$cfg/settings.json"
check "the refusal writes no backup" [ "$(backups "$cfg")" -eq 0 ]
check "the refusal still installs the scripts" all_installed "$cfg/context-nudge/bin"

# --- once the status line is wrapped, only the hook is added ---------------------
wrapped="sh '$cfg/context-nudge/bin/context-nudge-cache.sh' | my-status-line --wide"
jq -n --arg line "$wrapped" '{statusLine: {type: "command", command: $line}}' >"$cfg/settings.json"
run_installer "$cfg" --write-settings
check "a wrapped status line is accepted" [ "$status" -eq 0 ]
check "the wrapped status line is kept" [ "$(jq -r '.statusLine.command' "$cfg/settings.json")" = "$wrapped" ]
check "the hook is added beside it" \
	[ "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$cfg/settings.json")" = "sh '$cfg/context-nudge/bin/context-nudge-hook.sh'" ]
run_installer "$cfg" --uninstall
check "--uninstall keeps the wrapped status line" [ "$(jq -r '.statusLine.command' "$cfg/settings.json")" = "$wrapped" ]
check "--uninstall removes the hook it added" [ "$(jq -r '.hooks // "none"' "$cfg/settings.json")" = "none" ]

# --- no settings file yet ----------------------------------------------------------
cfg="$work/no-settings"
run_installer "$cfg" --write-settings
check "--write-settings creates a missing settings file" \
	[ "$(jq -r '.statusLine.command' "$cfg/settings.json")" = "sh '$cfg/context-nudge/bin/context-nudge-statusline.sh'" ]
check "a new settings file needs no backup" [ "$(backups "$cfg")" -eq 0 ]

# --- a settings file that is not JSON is left alone -------------------------------
cfg="$work/broken"
mkdir -p "$cfg"
printf 'not json\n' >"$cfg/settings.json"
run_installer "$cfg" --write-settings
check "a broken settings file makes --write-settings fail" [ "$status" -ne 0 ]
check "a broken settings file is left alone" [ "$(cat "$cfg/settings.json")" = "not json" ]

# --- options that cannot be combined ------------------------------------------------
run_installer "$cfg" --uninstall --write-settings
check "--uninstall with --write-settings fails" [ "$status" -ne 0 ]

finish install
