#!/bin/sh
#
# What an MCP server row must satisfy on its text alone.
#
# Sourced after _scripts/catalog.sh by _scripts/mcp-servers, which checks the
# whole catalog before it writes or applies anything, and by
# tests/catalog_rules_test.sh. Whether a server answers, or an agent is
# installed, is not a rule: the consumer reports it while applying.

# Usage: catalog_check <catalog> mcp_servers_check_row
mcp_servers_check_row() {
  case $1 in
    '') catalog_reject 'missing name' ;;
    *[!a-z0-9_-]*) catalog_reject "name '$1' may hold only a-z, 0-9, '-' and '_'" ;;
    *) catalog_reject_duplicate "$1" ;;
  esac

  case $2 in
    remote)
      case $3 in
        https://?*) ;;
        *) catalog_reject "remote target '$3' is not an https URL" ;;
      esac
      [ "$4" = - ] || catalog_reject 'a remote server takes no environment'
      ;;
    local)
      [ -n "$3" ] || catalog_reject 'missing command'
      mcp_servers_check_environment "$4"
      ;;
    *) catalog_reject "unknown transport '$2'" ;;
  esac

  mcp_servers_check_agents "$5"
  return 0
}

mcp_servers_check_environment() {
  case $1 in
    '') catalog_reject 'missing environment; write - for none' ;;
    -) return 0 ;;
  esac
  for mcp_servers_pair in $1; do
    case $mcp_servers_pair in
      [A-Z_]*=*) ;;
      *) catalog_reject "environment entry '$mcp_servers_pair' is not KEY=value" ;;
    esac
  done
  unset mcp_servers_pair
}

mcp_servers_check_agents() {
  [ -n "$1" ] || {
    catalog_reject 'missing agents'
    return 0
  }
  mcp_servers_seen=,
  mcp_servers_rest=$1,
  while [ -n "$mcp_servers_rest" ]; do
    mcp_servers_agent=${mcp_servers_rest%%,*}
    mcp_servers_rest=${mcp_servers_rest#*,}
    case $mcp_servers_agent in
      claude | codex | opencode | zed) ;;
      *) catalog_reject "unknown agent '$mcp_servers_agent'" ;;
    esac
    case $mcp_servers_seen in
      *",$mcp_servers_agent,"*) catalog_reject "agent '$mcp_servers_agent' is listed twice" ;;
    esac
    mcp_servers_seen=$mcp_servers_seen$mcp_servers_agent,
  done
  unset mcp_servers_seen mcp_servers_rest mcp_servers_agent
}
