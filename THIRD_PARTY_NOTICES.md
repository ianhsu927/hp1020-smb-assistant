# Third-party notices

This repository's installer is adapted from the approach in [ardabeh/hp-legacy-mac](https://github.com/ardabeh/hp-legacy-mac), licensed GPL-2.0. It creates an SMB queue instead of detecting a USB printer and installs a dedicated HP 1020 filter under `/Library/Printers`.

The GUI downloads the upstream v1.0.0 ARM64 bundle at installation time. Third-party binaries are not committed to this repository or bundled inside the application.

- **foo2zjs** — Copyright Rick Richardson and contributors; GNU GPL v2 or later. Source: https://github.com/koenkooi/foo2zjs.
- **Ghostscript** — Artifex Software and contributors; GNU AGPL / commercial licensing. Source and licensing: https://ghostscript.com/releases/ and https://www.ghostscript.com/licensing/.
- The bundle also contains supporting libraries. Their licenses and corresponding source requirements remain applicable; consult https://github.com/ardabeh/hp-legacy-mac/tree/main/build.

This application is not affiliated with HP, Apple, Microsoft, Artifex, or the upstream driver authors. Local conversion testing is not a device compatibility test or a security audit.
