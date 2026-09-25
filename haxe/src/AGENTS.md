# Gallery Haxe source conventions

Use the Haxe coding skill at `C:/Users/pshand/.agents/skills/haxe-coding/SKILL.md` for Haxe changes. Follow the Eva patterns in `I:/_projects/2026_Q4/webgl-viewer/haxe`.

- Keep each DOM component in its own folder with a `View.hx`, `ViewMediator.hx`, and matching `View.css` file. Map child mediators before creating child views.
- Views create DOM and render state. Put listeners, user input, and model subscriptions in mediators. Put asynchronous service calls and nonvisual workflows in logic classes.
- Models hold typed `Notifier` state and request `Signal`s. Keep application behavior and service calls out of models.
- Define every Haxe import used by files under `haxe/src` in the root `haxe/src/import.hx`. Keep its imports grouped by library and application layer. Do not add import statements to individual Haxe classes; add new dependencies to `import.hx` instead.
- Keep browser test selectors and native command contracts stable while refactoring. Run `npm run build` and the relevant UI test after a component change.
