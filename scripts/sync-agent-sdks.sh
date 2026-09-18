#!/usr/bin/env bash
# =============================================================================
# agent-proto: generate the agent.v1 Connect/Protobuf SDKs and distribute them
# to the five language SDK repos under abcp-sdk/.
#
#   agent-proto            = SOURCE ONLY (.proto + this script + buf config)
#   agent-sdk-go           = Go SDK    (generated pb.go + connect.go + aliases)
#   agent-sdk-typescript   = TS SDK    (generated agent_pb.ts)
#   agent-sdk-dart         = Dart SDK  (generated pb.dart + connect.client.dart)
#   agent-sdk-kotlin       = Kotlin SDK(generated com/agent/v1/**)
#   agent-sdk-swift        = Swift SDK (generated agent.pb.swift + agent.connect.swift)
#
# The agent server's schema package (agent/packages/schema) re-exports the TS
# generation from @abcp/agent-sdk, so it needs no separate copy.
#
# Portable (GNU/BSD/macOS), deterministic, idempotent. Network is required for
# the buf.build remote plugins (first run populates the buf module cache).
#
# Usage:
#   ./scripts/sync-agent-sdks.sh            # generate + distribute
#   ./scripts/sync-agent-sdks.sh --check    # generate to staging, diff, no writes
#   ./scripts/sync-agent-sdks.sh --only go,ts
#   ./scripts/sync-agent-sdks.sh --from <path>   # one-shot: import a proto revision
# =============================================================================
set -euo pipefail

# ---- paths -----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_PROTO="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$AGENT_PROTO/.." && pwd)"          # abcp-sdk/
PROTO_DIR="$AGENT_PROTO/proto"
PROTO_SRC="$PROTO_DIR/agent/v1/agent.proto"    # THIS repo is the source of truth

SDK_GO="$ROOT/agent-sdk-go"
SDK_TS="$ROOT/agent-sdk-typescript"
SDK_DART="$ROOT/agent-sdk-dart"
SDK_KOTLIN="$ROOT/agent-sdk-kotlin"
SDK_SWIFT="$ROOT/agent-sdk-swift"

# The agent-sdk-go Go module path the generated Go code must target.
GO_PKG_OLD="github.com/abcp-sdk/agent-proto/agent/v1;agentv1"
GO_PKG_NEW="github.com/abcp-sdk/agent-sdk-go/agent/v1;agentv1"

CHECK=0
ONLY=""
IMPORT_FROM=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    --only) ONLY="$2"; shift 2 ;;
    --from) IMPORT_FROM="$2"; shift 2 ;;
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

want() { [ -z "$ONLY" ] && return 0; case ",$ONLY," in *",$1,"*) return 0 ;; esac; return 1; }

# ---- portable in-place copy of a directory's contents ----------------------
copy_contents() { # copy_contents <src-dir> <dst-dir>
  local src="$1" dst="$2"
  mkdir -p "$dst"
  cp -R "$src"/. "$dst"/
}

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "== agent-proto sync =="
echo "proto source : $PROTO_SRC (authoritative)"

# ---- 1. optionally import a proto revision (one-shot; abcp-sdk is upstream) --
if [ -n "$IMPORT_FROM" ]; then
  if [ -f "$IMPORT_FROM" ]; then
    mkdir -p "$PROTO_DIR/agent/v1"
    sed "s#$GO_PKG_OLD#$GO_PKG_NEW#" "$IMPORT_FROM" > "$PROTO_SRC"
    echo "imported     : $IMPORT_FROM -> $PROTO_SRC"
  else
    echo "--from target not found: $IMPORT_FROM" >&2
    exit 2
  fi
fi
[ -f "$PROTO_SRC" ] || { echo "missing proto: $PROTO_SRC" >&2; exit 2; }

# ---- 2. buf generate (deterministic native output -> staging) ---------------
# The plugin set never changes; buf's BSR rate limit can, so retry with backoff.
generate() {
  local attempt=1 delay=5
  while [ "$attempt" -le 6 ]; do
    if ( cd "$AGENT_PROTO" && buf generate --template buf.gen.sync.yaml \
        --path proto/agent/v1/agent.proto --output "$STAGE" 2>"$STAGE/.buf.err" ); then
      return 0
    fi
    if grep -q "resource_exhausted\|too many requests" "$STAGE/.buf.err" 2>/dev/null; then
      echo "   buf rate-limited, retrying in ${delay}s (attempt $attempt/6)"
      sleep "$delay"; delay=$((delay * 2)); attempt=$((attempt + 1)); continue
    fi
    cat "$STAGE/.buf.err" >&2
    return 1
  done
  echo "buf generate failed after retries:" >&2
  cat "$STAGE/.buf.err" >&2
  return 1
}
echo "generating   : buf ..."
generate
GEN="$STAGE/gen"

# ---- 3. ensure the Go module path targets agent-sdk-go ----------------------
# The committed proto already carries the agent-sdk-go go_package, so this is a
# no-op in the normal path; it stays as a safety net for a proto synced from a
# source that still declares `agent-proto`.
if want go; then
  if grep -rq "github.com/abcp-sdk/agent-proto/agent/v1" "$GEN/go" 2>/dev/null; then
    echo "rewriting    : go_package -> agent-sdk-go"
    grep -rl "github.com/abcp-sdk/agent-proto/agent/v1" "$GEN/go" | while read -r f; do
      sed 's#github.com/abcp-sdk/agent-proto/agent/v1#github.com/abcp-sdk/agent-sdk-go/agent/v1#g' \
        "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    done
  fi
fi

# ---- 4. distribute ----------------------------------------------------------
DIRTY=0
dist() { # dist <label> <src> <dst>
  local label="$1" src="$2" dst="$3"
  if [ "$CHECK" = 1 ]; then
    if [ -d "$dst" ] && diff -r "$src" "$dst" >/dev/null 2>&1; then
      echo "-- $label: OK (in sync)"
    else
      DIRTY=1
      echo "-- $label: DIFFERS"
      [ -d "$dst" ] && diff -rq "$src" "$dst" 2>&1 | head -20 || echo "   (missing $dst)"
    fi
  else
    mkdir -p "$dst"
    copy_contents "$src" "$dst"
    echo "-- $label -> $dst"
  fi
}

if want go; then
  dist "go" "$GEN/go/agent/v1" "$SDK_GO/agent/v1"
fi
if want ts; then
  dist "ts" "$GEN/es/agent/v1" "$SDK_TS/src/gen/agent/v1"
fi
if want dart; then
  dist "dart" "$GEN/dart/agent/v1" "$SDK_DART/lib/src/gen/agent/v1"
fi
if want kotlin; then
  # buf emits java_package com.agent.v1; the repo expects src/main/java/com/agent/v1
  dist "kotlin" "$GEN/kotlin/com/agent/v1" "$SDK_KOTLIN/src/main/java/com/agent/v1"
fi
if want swift; then
  dist "swift" "$GEN/swift/agent/v1" "$SDK_SWIFT/Sources/AgentSDK/agent/v1"
fi
# NOTE: agent/packages/schema does NOT keep its own gen copy — it re-exports
# @abcp/agent-sdk (see packages/schema/src/index.ts). Only the ts target above
# feeds it. `schema` remains accepted as a no-op alias for `ts`.
if want schema; then
  dist "ts (agent-schema via @abcp/agent-sdk)" "$GEN/es/agent/v1" "$SDK_TS/src/gen/agent/v1"
fi

echo
if [ "$CHECK" = 1 ]; then
  if [ "$DIRTY" = 0 ]; then
    echo "check complete: every SDK is in sync."
  else
    echo "check complete: at least one SDK differs from the generated output."
    exit 1
  fi
else
  echo "done. Review diffs, then commit each SDK repo."
fi
