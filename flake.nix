{
  description = "lethe development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          # nixpkgs' ruby ships an older default bundler than its rubygems,
          # so use the matching bundler package to avoid constant redefinition warnings.
          packages = [
            (pkgs.bundler.override { ruby = pkgs.ruby_3_4; })
            pkgs.ruby_3_4
            pkgs.git
          ];
          shellHook = ''
            export GEM_HOME="$PWD/.gem"
            export BUNDLE_PATH="$PWD/vendor/bundle"
            export PATH="$GEM_HOME/bin:$PATH"
          '';
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
