# Brand assets

`windwardlogo.png` is the master (1536×1024). Nothing references it directly — it is kept so
the derived assets can be regenerated.

`web/public/windward-mark.png` is the only logo the site ships: a 128×128 centre crop, used for
the nav, the footer and the favicon. It is 28 KB, against 1.2 MB for the master. The site is a
static export with `images: { unoptimized: true }`, so whatever lands in `web/public` is served
verbatim at full size — the derived asset is not an optimisation, it is the difference between a
30 px icon costing 28 KB and costing 1.2 MB.

Regenerate it with:

```sh
sips -c 820 820 brand/windwardlogo.png --out /tmp/_mark.png
sips -Z 128 /tmp/_mark.png --out web/public/windward-mark.png
```
