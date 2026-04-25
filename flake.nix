# flake.nix
#
# Purpose: Development shell with build dependencies for guix-shimboot
#
# This flake provides:
# - Dev shell with guix, cgpt, parted, and image assembly tools

{
  description = "Guix-Shimboot: GNU Guix System on ChromeOS hardware";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

    in
    {
      devShells.${system}.default = pkgs.mkShell {
        name = "guix-shimboot";

        packages = with pkgs; [
          # Image assembly
          guix
          parted
          e2fsprogs
          util-linux
          pv

          # ChromeOS partitioning
          vboot_reference

          # Driver harvest
          git

          # Development
          shellcheck
          bash
        ];

        shellHook = ''
          echo "guix-shimboot dev shell"
          echo "  guix:    $(guix --version 2>/dev/null | head -1 || echo 'not found')"
          echo "  cgpt:    $(command -v cgpt 2>/dev/null || echo 'not found')"
          echo "  parted:  $(parted --version 2>/dev/null | head -1 || echo 'not found')"
          echo ""
          echo "Build:  ./tools/build/assemble-guix-image.sh --board dedede"
          echo "Help:   ./tools/build/assemble-guix-image.sh --help"
        '';
      };
    };
}