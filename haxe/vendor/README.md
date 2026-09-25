# Local Haxe runtime dependencies

This directory makes Gallery's Haxe build independent of the sibling reference project and the machine's Haxelib path.

- `eva`, `inject`, and `polyfill` were copied from `I:\_projects\2026_Q4\webgl-viewer\haxe\shared\libs` on 23 September 2026, at the user's request. Gallery uses Eva's context, DOM bundle, model and logic maps, and mediator map.
- `signals` was copied from `I:\_projects\2026_Q4\webgl-viewer\node_modules\haxe\.haxelib\signals\1,3,2\src\signals`. Its Haxelib manifest identifies version 1.3.2 and the MIT license.

The packages are compiled through `-cp haxe/vendor` in `haxe/build.hxml`. Other webgl-viewer libraries are not needed by this prototype.
