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
