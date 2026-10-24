adjrned.github.io/TWC

## Layout

```
src/            the site (Vite): pages, UI, data loaders, damage sim, styles
public/         static files served as-is at the same URLs
  data/           game data (items, heroes, skills, bosses, effects, patch notes, sim)
  builds/         community builds
  twicons/        item/skill icons (WebP) + manifest.json
icon-sources/   original JPG icons; `npm run icons` converts them into public/twicons
scripts/        data import / maintenance scripts, overlay bundling
companion/      TW Companion (AutoHotkey): save loader, macros, and the in-game
                overlay that runs this site offline (see companion/README.md)
```

## Commands

- `npm run dev` / `npm run build` — the site (build also writes `dist/overlay-manifest.txt`)
- `npm run overlay` — build and copy the site into `companion/web/TWC` for the overlay
- `npm run icons`, `npm run share-dict`, `npm run sim-check`, `npm run sim-coverage` — data upkeep
