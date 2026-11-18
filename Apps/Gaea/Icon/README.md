# Gaea.app's icon

`artwork.png` is a picture Gaea made of itself: `image.generate` on Gaea 1.9.1 with `z-image-turbo` (gaea-plugin-z-image
0.2.1, the int4 lane), 1024 x 1024, seed 11, about 12 s on an M5 Max. It follows the dotted globe of the site's hero
(`site/hero.js`) and its colours (`--sun`, `--leaf`, `--sea` on `--bg`). The operator picked it on 2026-11-18 from 38
candidates across Klein 4B, Z-Image Turbo and Z-Image.

The prompt:

> Minimal flat vector app icon artwork. A single sphere drawn only with round dots in a regular lattice, about
> fourteen dots across its widest row, the rows curving like lines of latitude and longitude so the dots shrink and
> crowd toward the sphere's edge and it reads as a ball. The dots are coloured in one smooth gradient that runs from
> warm peach orange at the upper left, through pale gold and soft leaf green, to sea teal blue at the lower right. The
> sphere is large: it fills about three quarters of the frame's width. A faint soft teal glow behind it. On a very
> dark blue-black background, almost black with a hint of deep teal. Crisp, clean, geometric, elegant. The artwork
> fills the whole square frame edge to edge with the dark background; the subject is centered with generous empty dark
> space around it. No text, no letters, no logo type, no frame, no border, no rounded rectangle, no watermark.

`../Gaea.icns` is made from it, with the artwork enlarged 10 % inside the macOS icon shape:

    swift tools/make-icon.swift icns Apps/Gaea/Icon/artwork.png Apps/Gaea/Gaea.icns --zoom 1.1

`scripts/build-app.sh` copies `Gaea.icns` into the bundle, and `Info.plist` names it (`CFBundleIconFile`). A classic
`.icns` on the standard icon grid is drawn as it is on macOS 27; no Icon Composer document is needed.
