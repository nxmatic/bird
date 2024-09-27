{
  description = "A Nix-flake-based for building BIRD";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    in
    flake-utils.lib.eachSystem systems (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            allowBroken = false;
          };
        };

        birdSrc = pkgs.fetchFromGitHub {
          owner = "nxmatic";
          repo = "bird";
          rev = "hotfix/v2.15.1-nix-darwin";
          sha256 = "14zc5926sk2hvpif6jnypdlbv2sybpfvlgdrmmy6f9xahzrsxbs0";
        };

        sysioMd5sum = pkgs.stdenv.mkDerivation {
          name = "sysio-md5sum";
          buildInputs = [ pkgs.coreutils ];
          buildCommand = ''
            md5sum ${birdSrc}/sysdep/bsd/sysio.h | cut -d' ' -f1 > $out
          '';
        };

        birdPackageWithMeta = pkgs.bird.overrideAttrs (oldAttrs: let
          defaultConfigureFlags = oldAttrs.configureFlags or [];
          darwinConfigureFlags = pkgs.lib.optionals pkgs.stdenv.isDarwin [ "--with-sysconfig=bsd" ];
          allConfigureFlags = defaultConfigureFlags ++ darwinConfigureFlags;
        in {
          meta = oldAttrs.meta // {
            platforms = oldAttrs.meta.platforms ++ pkgs.lib.platforms.darwin;
          };
          passthru = (oldAttrs.passthru or {}) // {
            sysioMd5sum = builtins.readFile (pkgs.runCommand "sysio-md5sum" {} ''
              md5sum ${birdSrc}/sysdep/bsd/sysio.h | cut -d' ' -f1 > $out
            '');
          };
          src = birdSrc;
          buildInputs = (oldAttrs.buildInputs or [])
            ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
              pkgs.darwin.apple_sdk.frameworks.CoreFoundation
              pkgs.darwin.apple_sdk.frameworks.Security
            ];

          nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [
            pkgs.autoconf
            pkgs.automake
            pkgs.libtool
          ];

          configureFlags = allConfigureFlags;

          preConfigure = ''
            echo "Running autoreconf..."
            autoreconf -vfi
            echo "Configure flags: ${toString allConfigureFlags}"
          '';

          configurePhase = ''
            runHook preConfigure
            ./configure --prefix=$out $configureFlags
            runHook postConfigure
          '';
        });

        devShell = pkgs.mkShell {
          packages = with pkgs; [
            autoconf
            automake
            libtool
            pkg-config
            flex
            bison
            readline
            ncurses
            libssh
            openssl
            gcc
            birdPackageWithMeta
          ];
          shellHook = ''
            echo 'Setting env variables'
            export CFLAGS="-I${pkgs.ncurses.dev}/include"
            export LDFLAGS="-L${pkgs.ncurses.out}/lib"
          '';
        };
      in
      {
        packages = {
          default = birdPackageWithMeta;
        };

        devShells = {
          default = devShell;
        };
      }
    );
}
