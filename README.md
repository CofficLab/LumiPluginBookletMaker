# LumiBookletMaker

Shared Booklet Maker domain logic for Lumi and GameFactory.

## Current scope

`BookletMakerCore` is intentionally independent from `LumiKernel`, `LumiProviders`, SwiftUI, and host-specific plugin code. It currently contains:

- paper and booklet settings models;
- simple-pair, booklet-fold, and signature-fold layout planning;
- physical-sheet grouping and page-cell geometry;
- PDF split-point parsing and segment planning.

The package is the first extraction layer. PDF inspection/rendering, shared SwiftUI views, and host adapters will be added only after the two applications agree on their public domain model.

## Integration direction

```text
LumiBookletMaker
├── BookletMakerCore       # pure shared domain logic
├── BookletMakerServices   # PDF inspection/rendering/splitting
├── BookletMakerUI          # shared SwiftUI views and view models
└── BookletMakerAgent      # optional Agent tools and Skill contribution
```

Lumi and GameFactory should keep their own thin plugin/assembly layers. Those layers are responsible for Kernel registration, Rail/Chat/Toolbar lifecycle, plugin policy, localization bundles, and application-specific features.

## Development

```sh
swift test
```
