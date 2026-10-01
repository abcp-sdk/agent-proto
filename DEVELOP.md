# DEVELOP

Developer notes for `agent-proto`. See `README.md` for the user-facing overview
(what the repo is, how to generate + distribute the SDKs).

## What lives here

This repo is **source only** — it contains no generated code:

- `proto/agent/v1/agent.proto` — the single source of truth for `agent.v1`.
- `buf.yaml` / `buf.gen.{sync,preview}.yaml` — module + plugin config.
- `scripts/sync-agent-sdks.sh` — `buf generate` → staging → distribute / `--check`.
- `templates/kotlin/` — the **hand-maintained** Kotlin build files (see below).

## The Kotlin template (`templates/kotlin/`)

`buf` emits only `src/main/java/com/agent/v1/**` for Kotlin. Everything else in
`agent-sdk-kotlin` (the Gradle build) is hand-maintained — but it must be
*reproducible for a fresh repo*, so its source of truth lives here and the sync
script distributes + checks it:

| Template file | Ships to | Notes |
|---|---|---|
| `build.gradle.kts` | `agent-sdk-kotlin/build.gradle.kts` | plugins, deps, JVM 17 pinning |
| `settings.gradle.kts` | `agent-sdk-kotlin/settings.gradle.kts` | `rootProject.name` |
| `.gitignore` | `agent-sdk-kotlin/.gitignore` | `.gradle/`, `build/` |

`./scripts/sync-agent-sdks.sh --only kotlin --check` now fails if the SDK's build
files drift from the template, so the two cannot silently diverge.

### Non-obvious build decisions (learned the hard way)

These are encoded in `templates/kotlin/build.gradle.kts`; keep them there.

- **Kotlin plugin must be recent** (`kotlin("jvm") 2.4.20`). `2.1.0`'s compiler
  crashes on a newer JDK while parsing the JVM version
  (`IllegalArgumentException: 25.0.4.1`).
- **No `jvmToolchain(17)`.** Pin JVM 17 at the *bytecode* level instead
  (`java.source/targetCompatibility` + `kotlin.compilerOptions.jvmTarget` +
  `JavaCompile.options.release`). The toolchain form makes Gradle try to
  *download* a JDK 17 whenever the installed JDK is newer (e.g. JDK 25), which
  fails offline. Bytecode pinning gives the same Android/JVM-17 compatibility
  with no provisioning step.
- **Three runtime deps, all `api`** (the generated code exposes them in its
  signatures):
  - `com.connectrpc:connect-kotlin` + `-okhttp` — client runtime/transport.
  - `com.connectrpc:connect-kotlin-google-javalite-ext` — the protobuf-**lite**
    `SerializationStrategy` (`GoogleJavaLiteProtobufStrategy`); connect-kotlin
    ships no default, so this is required to construct a `ProtocolClientConfig`
    against LITE messages.
  - `com.google.protobuf:protobuf-javalite` **and** `protobuf-kotlin-lite` — the
    `*.java` messages and the `*Kt.kt` DSL builders respectively. Omitting
    `protobuf-kotlin-lite` makes every `*Kt.kt` file fail to compile.

## Verifying

```sh
bash -n scripts/sync-agent-sdks.sh        # syntax
./scripts/sync-agent-sdks.sh --check      # staging vs every SDK repo, no writes
```

The generated tree is checked by `--check`; the Kotlin build files are checked
too (see above). To prove the template actually builds, copy it over a checkout
of `agent-sdk-kotlin` in a Kotlin sandbox and run `gradle build` (Gradle 9.x /
JDK 25 → JVM 17 bytecode).

### Offline / sandbox notes

- `buf generate` uses **remote** BSR plugins and needs egress to `buf.build`;
  the in-cluster artifact mirror does not proxy it.
- Gradle in a sandbox reaches Maven through the pull-through mirror
  (`http://artifact.worker.svc.cluster.local/artifacts/maven/`). Gradle rejects
  plain-HTTP repositories unless you opt in, so use an `~/.gradle/init.gradle`
  with `allowInsecureProtocol = true` (see `abc-protocol/deploy` `DEVELOP.md`).

## Conventions

- Generated files are never edited by hand in the SDK repos; a change to them
  starts here (`.proto` for code, `templates/kotlin/` for the Kotlin build).
- The script is portable (GNU/BSD/macOS), deterministic and idempotent; keep it
  that way (no `cp -a`, no `rsync`, no bash-4-only syntax).
