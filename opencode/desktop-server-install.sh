#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd)
LABEL=com.danilomartinelli.opencode-desktop-server
SERVER_URL=http://127.0.0.1:4097
TEMPLATE=$SCRIPT_DIR/$LABEL.plist.template
LAUNCH_AGENTS_DIR=${OPENCODE_DESKTOP_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}
PLIST=$LAUNCH_AGENTS_DIR/$LABEL.plist
LOG_DIRECTORY=${OPENCODE_DESKTOP_LOG_DIRECTORY:-$HOME/Library/Logs/OpenCode}
SETTINGS=${OPENCODE_DESKTOP_SETTINGS:-$HOME/Library/Application Support/ai.opencode.desktop/opencode.settings}

usage() {
	printf '%s\n' "usage: $0 install|connect|status|uninstall"
}

escape_sed_replacement() {
	printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

desktop_is_running() {
	pgrep -x OpenCode >/dev/null 2>&1
}

install_server() {
	mkdir -p "$LAUNCH_AGENTS_DIR" "$LOG_DIRECTORY"

	server_script=$(escape_sed_replacement "$SCRIPT_DIR/desktop-server.sh")
	log_directory=$(escape_sed_replacement "$LOG_DIRECTORY")
	temporary_plist=$PLIST.tmp.$$
	trap 'rm -f "$temporary_plist"' EXIT HUP INT TERM

	sed \
		-e "s|__DESKTOP_SERVER_SCRIPT__|$server_script|g" \
		-e "s|__LOG_DIRECTORY__|$log_directory|g" \
		"$TEMPLATE" >"$temporary_plist"
	plutil -lint "$temporary_plist" >/dev/null
	mv "$temporary_plist" "$PLIST"
	trap - EXIT HUP INT TERM

	launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
	launchctl bootstrap "gui/$(id -u)" "$PLIST"
	launchctl kickstart -k "gui/$(id -u)/$LABEL"

	printf '%s\n' "OpenCode managed Desktop backend installed at $SERVER_URL"
}

connect_desktop() {
	if desktop_is_running; then
		printf '%s\n' "OpenCode Desktop is running. Quit it completely, rerun '$0 connect', then reopen it." >&2
		exit 2
	fi

	if [ ! -f "$SETTINGS" ]; then
		printf '%s\n' "OpenCode Desktop settings not found: $SETTINGS" >&2
		exit 1
	fi

	if ! plutil -replace defaultServerUrl -string "$SERVER_URL" "$SETTINGS" 2>/dev/null; then
		plutil -insert defaultServerUrl -string "$SERVER_URL" "$SETTINGS"
	fi

	printf '%s\n' "OpenCode Desktop will use the managed backend at $SERVER_URL on next launch"
}

show_status() {
	if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
		printf '%s\n' "managed backend: loaded ($SERVER_URL)"
	else
		printf '%s\n' "managed backend: not loaded"
	fi

	if [ -f "$SETTINGS" ]; then
		configured_url=$(plutil -extract defaultServerUrl raw "$SETTINGS" 2>/dev/null || true)
		printf '%s\n' "Desktop default server: ${configured_url:-embedded sidecar}"
	else
		printf '%s\n' "Desktop settings: not found"
	fi
}

uninstall_server() {
	launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
	rm -f "$PLIST"
	printf '%s\n' "OpenCode managed Desktop backend removed"
}

case ${1:-} in
	install) install_server ;;
	connect) connect_desktop ;;
	status) show_status ;;
	uninstall) uninstall_server ;;
	*) usage >&2; exit 64 ;;
esac
