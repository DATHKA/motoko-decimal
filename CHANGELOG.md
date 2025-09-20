# decimal changelog

## 2.0.0

* Added:
* Optional `roundMode` parameter for `Decimal.fromText`, inferring decimal precision from the input when omitted.
* `Decimal.equal` helper to compare values after normalising scales and `Decimal.equalExact` for structural equality.
* Inline Motoko snippets augmenting every public function’s documentation.
* Additional unit tests covering `Decimal.equal`, inverse arithmetic identities, and scale inference behaviour.

* Changed:
* Arithmetic helpers (`add`, `subtract`, `multiply`, `divide`, `power`) now accept optional decimal precision (`?Nat`) consistently.
* Switched comparison helpers from integer return values to Motoko `Order.Order` variants (`#less`, `#equal`, `#greater`).
* Removed redundant `Decimal.ofFloat` alias in favour of `Decimal.fromFloat`.
* Renamed `Decimal.pow` to `Decimal.power` for naming consistency.
* Standardised rounding parameter names to `roundMode` throughout the API.

* Fixed:
* README and API docs now reflect optional precision semantics and optional rounding mode behaviour.
* Major documentation enhancements with code examples.