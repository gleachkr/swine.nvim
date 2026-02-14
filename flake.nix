{
  inputs = {
    nixpkgs.url = "nixpkgs";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = self.packages.${system}.swine-nvim;

        packages.swine-nvim = pkgs.vimUtils.buildVimPlugin {
          pname = "swine-nvim";
          version = "0.0.1";
          src = ./.;
        };

        checks.tests = pkgs.runCommand "swine-tests" {
          nativeBuildInputs = [
            pkgs.neovim
            pkgs.swi-prolog
          ];
        } ''
          cd ${self}

          export HOME="$TMPDIR"
          export XDG_DATA_HOME="$TMPDIR/.local/share"
          export XDG_STATE_HOME="$TMPDIR/.local/state"
          export XDG_CACHE_HOME="$TMPDIR/.cache"
          mkdir -p "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

          nvim --headless -u tests/minimal_init.lua -i NONE \
            -c "lua dofile('tests/run_unit.lua')"

          touch "$out"
        '';

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.swi-prolog
            pkgs.lua-language-server
            pkgs.stylua
            pkgs.luajitPackages.luacheck
          ];
        };
      }
    );
}
