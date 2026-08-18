{ pkgs, lib ? pkgs.lib, name }:

let
  # Extension IDs only. We never build or wrap an editor here.
  # The user's own codium/code picks these up from .vscode/extensions.json.
  langs = {
    nix = {
      recommendations = [ "jnoortheen.nix-ide" ];
      unwanted = [
        "bbenoist.nix"              # competing .nix grammar
        "arrterian.nix-env-selector" # obsolete under direnv
      ];
      settings = {
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nixd";           # bare name: resolved from devshell PATH
        "nix.formatterPath" = "nixpkgs-fmt";
        "nix.serverSettings" = {
          nixd.formatting.command = [ "nixpkgs-fmt" ];
        };
        "[nix]" = {
          "editor.defaultFormatter" = "jnoortheen.nix-ide";
          "editor.formatOnSave" = false;
        };
      };
    };

    haskell = {
      recommendations = [ "haskell.haskell" "justusadam.language-haskell" ];
      unwanted = [ "hoovercj.haskell-linter" ]; # dead; HLS runs hlint natively
      settings = {
        # Critical: without this the extension downloads its own HLS via GHCup
        # on first open and throws dialogs at you. haskell.nix already gives us
        # a matching HLS on PATH.
        "haskell.manageHLS" = "PATH";
        "haskell.formattingProvider" = "fourmolu";
        "haskell.plugin.hlint.globalOn" = true;
        "haskell.checkProject" = true;
        "[haskell]" = {
          "editor.defaultFormatter" = "haskell.haskell";
          "editor.formatOnSave" = false;
        };
        "[cabal]" = {
          "editor.formatOnSave" = false;
        };
      };
    };

    purescript = {
      recommendations = [
        "nwolverson.language-purescript"
        "nwolverson.ide-purescript"
      ];
      unwanted = [ ];
      settings = {
        "purescript.pursExe" = "purs";
        "purescript.spagoExe" = "spago";
        "purescript.formatter" = "purs-tidy";
        "purescript.addSpagoSources" = true;
        "purescript.addNpmPath" = false;      # tools come from Nix, not node_modules
        "purescript.autoStartPscIde" = true;
        "purescript.buildCommand" = "spago build --purs-args --json-errors";
        "[purescript]" = {
          "editor.defaultFormatter" = "nwolverson.ide-purescript";
          "editor.formatOnSave" = false;
        };
      };
    };
  };

  base = {
    recommendations = [ "mkhl.direnv" ];
    unwanted = [
      "cab404.vscode-direnv"   # conflicts with mkhl.direnv; source of reload popups
    ];
    settings = {
      "direnv.restart.automatic" = true;

      # Stop the editor nagging about things Nix owns.
      "extensions.autoUpdate" = false;
      "extensions.autoCheckUpdates" = false;
      "update.mode" = "none";
      "telemetry.telemetryLevel" = "off";
      "npm.autoDetect" = "off";
      "typescript.tsc.autoDetect" = "off";

      # Build artefacts. Watching these is why the editor stalls and prompts.
      "files.watcherExclude" = {
        "**/.direnv/**" = true;
        "**/.spago/**" = true;
        "**/dist-newstyle/**" = true;
        "**/node_modules/**" = true;
        "**/output/**" = true;
        "**/frontend/dist/**" = true;
        "**/script/concat_archive/**" = true;
        "**/result" = true;
        "**/result-*" = true;
      };
      "search.exclude" = {
        "**/.direnv" = true;
        "**/.spago" = true;
        "**/dist-newstyle" = true;
        "**/node_modules" = true;
        "**/output" = true;
        "**/frontend/dist" = true;
        "**/script/concat_archive" = true;
      };
    };
  };

  profile = {
    recommendations =
      base.recommendations
      ++ langs.nix.recommendations
      ++ langs.haskell.recommendations
      ++ langs.purescript.recommendations;

    unwantedRecommendations =
      base.unwanted
      ++ langs.nix.unwanted
      ++ langs.haskell.unwanted
      ++ langs.purescript.unwanted;

    settings =
      base.settings
      // langs.nix.settings
      // langs.haskell.settings
      // langs.purescript.settings;
  };

  extensionsJson = pkgs.writeText "extensions.json" (builtins.toJSON {
    inherit (profile) recommendations unwantedRecommendations;
  });

  settingsJson = pkgs.writeText "settings.json" (builtins.toJSON profile.settings);

in
{
  # LSP + formatter binaries the settings above refer to by bare name.
  # HLS / fourmolu / hlint / cabal come from the haskell.nix shell (inputsFrom).
  # purs / purs-tidy / purescript-language-server come from ps-tools in build.nix.
  tools = [ pkgs.nixd pkgs.nixpkgs-fmt ];

  sync = pkgs.writeShellApplication {
    name = "${name}-ide-sync";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      repo="''${${lib.toUpper name}_REPO:-$PWD}"
      while [ "$repo" != "/" ] && [ ! -f "$repo/flake.nix" ]; do
        repo="$(dirname "$repo")"
      done
      if [ ! -f "$repo/flake.nix" ]; then
        echo "[ide-sync] no flake.nix found above $PWD; skipping" >&2
        exit 0
      fi

      vs="$repo/.vscode"
      mkdir -p "$vs"

      sync_one() {
        src="$1"; dst="$2"
        if ! cmp -s "$src" "$dst" 2>/dev/null; then
          if [ -f "$dst" ]; then
            echo "[ide-sync] overwriting $dst (nix owns this; edit nix/ide.nix)"
          else
            echo "[ide-sync] writing $dst"
          fi
          install -m 0644 "$src" "$dst"
        fi
      }

      sync_one ${extensionsJson} "$vs/extensions.json"
      sync_one ${settingsJson}   "$vs/settings.json"

      # Legacy junk from the old devshell. argv.json is a user-level file
      # (~/.vscode-oss/argv.json); a workspace copy is ignored and only
      # churns the .vscode watcher.
      if [ -f "$vs/argv.json" ]; then
        echo "[ide-sync] removing stale $vs/argv.json"
        rm -f "$vs/argv.json"
      fi
    '';
  };
}