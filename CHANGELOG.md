# decimal changelog

# 3.0.2
* Added `isPositive()` and `isNegative()` tests.

# 3.0.1
* Fixed bug in `fromText()` - "-" now parses to `#InvalidFormat` rather than `0`.
* Consistent use of pow10() for exponents.
* Added `toDebugText()` to return the contents of a Decimal object as a string.
* Added `toJson()` to return a JSON representation of a Decimal object.
* Added `toJsonBigDecimal()` to return a JSON representation of a Decimal object with the keys aligning with JAVA's BigDecimal convention.
* Optimised `normalize` for performance.
* Documentation tweaks.

## 3.0.0

* Disambiguated behaviour of fromText() and rounding mode when `?decimals` is null.
* Aligned fromInt and fromNat with expected behaviour preserving the identity `Int v == Decimal.toInt(Decimal.fromInt(v, d), #halfUp)` for all values of d.
* Added fromIntUnscaled() and fromNatUnscaled() to preserve the previous behaviour of fromInt() and fromNat().
* Improved documentation

## 2.0.0

* Added:
* Optional `roundMode` parameter for `Decimal.fromText`, inferring decimal precision from the input when omitted.
* `Decimal.equal` helper to compare values after normalising scales and `Decimal.equalExact` for structural equality.
* `Decimal.fromUnscaledInt` and `Decimal.fromUnscaledNat` constructors for working with raw fixed-point magnitudes.
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
