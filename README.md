# temporal-cli-flox

A Flox package that builds [Temporal CLI](https://github.com/temporalio/cli)
**v1.8.0** by overriding the nixpkgs recipe, published to the `jbayer` FloxHub
org.

```console
flox install jbayer/temporal-cli
```

## Motivation

The Flox Catalog (which tracks [nixpkgs](https://github.com/NixOS/nixpkgs) with a
short lag) had `temporal-cli` pinned at **1.7.2**, while the upstream project had
already shipped **1.8.0**. Rather than wait for the catalog to catch up, we
overrode the existing build recipe to point at the newer release and published
the result so it installs in any environment.

### Source links

- **Upstream:** [temporalio/cli](https://github.com/temporalio/cli) — release
  [`v1.8.0`](https://github.com/temporalio/cli/releases/tag/v1.8.0) (tagged
  2026-07-10)
- **nixpkgs recipe (the one we overrode):**
  [`pkgs/by-name/te/temporal-cli/package.nix`](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/te/temporal-cli/package.nix)
  on `nixos-unstable` — a `buildGoModule` derivation, catalog latest `1.7.2`

## How this was built

The whole thing was done in a single [Claude Code](https://claude.com/claude-code)
session driven by the Flox skill.

### 1. Registering the Flox skill as a Claude plugin

The Flox knowledge came from the [`flox/flox-skills`](https://github.com/flox/flox-skills)
plugin, registered before the session with the `/plugin` command:

```
/plugin marketplace add flox/flox-skills      # register the marketplace
/plugin install flox@flox-skills              # install the flox plugin (v1.0.0)
```

This exposes a `flox` skill that Claude loads on demand, covering environments,
manifest builds, Nix-expression overrides, and publishing to FloxHub.

### 2. The prompt

> The flox package temporal-cli is at version 1.7.2 but the upstream temporal-cli
> repository is at version 1.8.0. Let's build a 1.8.0 version of the temporal-cli
> package and publish it to the jbayer FloxHub org.

## Incremental discovery

We didn't know every Flox step up front. Each `flox build` surfaced the next
thing to fix:

1. **Scaffold the override.** `flox init`, then create
   `.flox/pkgs/temporal-cli/default.nix` that calls `temporal-cli.overrideAttrs`
   to bump `version` → `1.8.0` and repoint `src` at the `v1.8.0` tag. The recipe
   uses the `finalAttrs` fixpoint, so the tag and the `Version` ldflag follow
   `version` automatically. Hashes left empty (`hash = ""`) to be discovered.

2. **Discover the source hash.** The first `flox build` failed with a
   fixed-output hash mismatch and printed the real `src` hash. Pasted it in.

3. **Hit a Go toolchain wall.** The next build got past `src` but failed in the
   Go modules phase:

   ```
   go: go.mod requires go >= 1.26.4 (running go 1.26.3; GOTOOLCHAIN=local)
   ```

   temporal-cli 1.8.0 requires **Go 1.26.4**, but the default nixpkgs page built
   it with 1.26.3, and `GOTOOLCHAIN=local` blocks auto-download.

4. **Figure out how Flox resolves the build's nixpkgs.** A first attempt
   overrode `buildGoModule`'s `go` via an explicit `go` argument — no effect. The
   `go-modules` derivation hash was byte-identical, revealing that a
   `.flox/pkgs` build resolves *all* its inputs (including transitive ones like
   the Go compiler) against **a single locked nixpkgs page** — the environment's
   `toplevel` install group.

5. **Pin the newer page.** `flox install go` pulls in `go@1.26.4` and, crucially,
   pins the toplevel group to a nixpkgs page where the default Go is 1.26.4. The
   next build used 1.26.4 and downloaded all modules.

6. **Discover the vendor hash.** With Go fixed, the build failed once more on the
   `vendorHash` fixed-output derivation and printed the real value. Pasted it in.

7. **Green build.** `flox build temporal-cli` succeeded. The upstream
   `versionCheckPhase` confirmed the binary, and it ships bash/fish/zsh
   completions:

   ```
   temporal version 1.8.0 (Server 1.31.2, UI 2.50.1)
   ```

8. **Publish.** `flox publish` requires a git repo with a pushed remote (it
   clones to a temp dir for a clean, reproducible build). Committed, created this
   public repo, pushed, then:

   ```console
   flox publish -o jbayer temporal-cli
   ```

## The recipe

`.flox/pkgs/temporal-cli/default.nix`:

```nix
{ temporal-cli, fetchFromGitHub, buildGoModule, go }:

(temporal-cli.override {
  buildGoModule = buildGoModule.override { inherit go; };
}).overrideAttrs (finalAttrs: _oldAttrs: {
  version = "1.8.0";

  src = fetchFromGitHub {
    owner = "temporalio";
    repo = "cli";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Z5Ba4oVQR6g/HyaBd/0iLIWq6Ht2SJAdylTVaErRFL0=";
  };

  vendorHash = "sha256-9lO9uhy1n85QYyoh27cKhdlcuL4GT98aCNWwe8tOwoQ=";
})
```

`go@1.26.4` is installed in the environment (`.flox/env/manifest.toml`) to pin
the nixpkgs page that supplies Go 1.26.4 to the build.

## Result

`jbayer/temporal-cli@1.8.0` is live in the `jbayer` FloxHub catalog:

```console
$ flox show jbayer/temporal-cli
jbayer/temporal-cli - Command-line interface for running Temporal Server ...
Catalog: jbayer
Latest:  jbayer/temporal-cli@1.8.0
```

### Known limitation

`flox publish` builds for the host architecture, so the published artifact is
**aarch64-darwin only**. To cover Linux or Intel Mac, re-run
`flox publish -o jbayer temporal-cli` from a machine (or CI runner) of each
target arch — the recipe itself is platform-agnostic and needs no changes.
