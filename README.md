# agent-proto — agent.v1 protobuf source + SDK generator

**SOURCE ONLY.** This repo holds the `agent.v1` protobuf definition and the
tooling that generates + distributes the five language SDKs. It contains **no
generated code**.

```
agent-proto/
├── proto/agent/v1/agent.proto   # single source of truth (this repo is upstream)
├── buf.yaml                     # buf module + lint/breaking config
├── buf.gen.sync.yaml            # what the sync script runs (native output -> staging)
├── buf.gen.preview.yaml         # same plugins, for `buf generate` inspection
└── scripts/sync-agent-sdks.sh   # generate + distribute + --check
```

## Generate & distribute

```bash
./scripts/sync-agent-sdks.sh              # generate + write into the SDK repos
./scripts/sync-agent-sdks.sh --check      # diff staging vs repos, no writes
./scripts/sync-agent-sdks.sh --only go,ts # subset
./scripts/sync-agent-sdks.sh --src /path/to/agent.proto   # re-home a new proto revision
```

Distribution targets:

| Language | Repo | Path |
|---|---|---|
| Go     | `agent-sdk-go`         | `agent/v1/{agent.pb.go,agentv1connect/agent.connect.go}` |
| TS     | `agent-sdk-typescript` | `src/gen/agent/v1/agent_pb.ts` |
| Dart   | `agent-sdk-dart`       | `lib/src/gen/agent/v1/*` |
| Kotlin | `agent-sdk-kotlin`     | `src/main/java/com/agent/v1/*` |
| Swift  | `agent-sdk-swift`      | `Sources/AgentSDK/agent/v1/*` |
| TS (server) | `agent`            | `packages/schema/src/gen/agent/v1/agent_pb.ts` |

The Go output is generated with the canonical `agent-proto` go_package and then
rewritten to `github.com/abcp-sdk/agent-sdk-go/agent/v1` — a deterministic,
self-contained step, so upstream proto generation stays unchanged.

## Updating the proto

1. Edit `proto/agent/v1/agent.proto` (or import a revision with `--from <path>`).
2. Run `./scripts/sync-agent-sdks.sh`.
3. Commit `proto/` here, then commit the regenerated files in each SDK repo.
