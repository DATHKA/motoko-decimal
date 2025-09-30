import Nat "mo:core/Nat";
import Int "mo:core/Int";
import Text "mo:core/Text";
import Iter "mo:core/Iter";
import Array "mo:core/Array";
import Float "mo:core/Float";
import Order "mo:core/Order";
import Result "mo:core/Result";

// ------------------------------------------------------------
// Decimal.mo — Fixed-point decimal arithmetic for Motoko
// ------------------------------------------------------------
// Highlights
// * Explicit Decimal type: { value : Int; decimals : Nat }
// * Clear rounding modes: DecimalRoundMode = { #down; #up; #halfUp }
//   - #down  => toward zero
//   - #up    => away from zero (if any fraction)
//   - #halfUp => to nearest, ties away from zero
// * Result-based errors for operations that can fail
// * Safer parsing/formatting (negatives supported, optional rounding)
// * Utility functions: abs, neg, signum, isZero, compare, min, max, clamp,
//   quantize, normalize, floorTo / ceilTo / truncTo, power (integer),
//   toInt, toNat, toFloat, fromFloat, format with separators
// ------------------------------------------------------------

module Decimal {
  /// Fixed-point decimal number represented by an integer magnitude `value` and a `decimal` scale.
  /// E.g. {value = 1000; decimals = 2} == 10.00
  /// ```motoko
  /// let amount : Decimal.Decimal = { value = 12345; decimals = 3 };
  /// // amount encodes the value 12.345
  /// ```
  public type Decimal = {
    /// Underlying integer magnitude. The actual value is `value * 10^{-decimals}`.
    value : Int;
    /// Number of decimal places encoded in `value`.
    decimals : Nat;
  };

  /// Supported rounding strategies used throughout the module.
  /// * `#down`: round toward zero (truncate any excess fractional digits).
  /// * `#up`: round away from zero whenever dropped digits are non-zero.
  /// * `#halfUp`: round to the nearest value; ties (>= 0.5) are rounded away from zero.
  public type DecimalRoundMode = { #down; #up; #halfUp };

  /// Errors that can be produced by parsing and arithmetic.
  /// Variants:
  /// * `#DivideByZero`: attempted to divide by a zero-valued decimal.
  /// * `#InvalidFormat`: input text or configuration cannot be parsed into a decimal.
  /// * `#TooManyFractionDigits`: requested scale requires more fractional digits than supplied.
  /// * `#NegativeValue`: conversion to `Nat` would yield a negative number.
  /// * `#InvalidFloat`: floating-point source is NaN or Infinity (not representable).
  /// * `#ZeroToNegativePower`: attempted to raise zero to a negative exponent.
  public type DecimalError = {
    /// Division attempted with a zero denominator.
    #DivideByZero;
    /// Input text is malformed or cannot be represented with the requested scale.
    #InvalidFormat;
    /// Requested scale has more fractional digits than supported by the value.
    #TooManyFractionDigits;
    /// Conversion to `Nat` would yield a negative number.
    #NegativeValue;
    /// Floating-point input is NaN or Infinity.
    #InvalidFloat;
    /// Tried to compute `0` to a negative power.
    #ZeroToNegativePower;
  };

  /// Default number of fractional digits to keep when callers don't request a specific scale.
  let defaultExtraPrecision : Nat = 12;

  /// Constant unity = 1
  /// `public let unity : Decimal = { value = 1; decimals = 0 };`
  public let unity : Decimal = { value = 1; decimals = 0 };

  /// Creates a zero `Decimal` with the provided scale.
  /// ```motoko
  /// let nil = Decimal.zero(2);
  /// // nil == { value = 0; decimals = 2 }
  /// ```
  public func zero(decimals : Nat) : Decimal = { value = 0; decimals };

/// Creates a `Decimal` from a `Float`, rounding according to `roundMode`.
///
/// ```motoko
/// let parsed = Decimal.fromFloat(1.234, 3, #halfUp);
/// // parsed == #ok({ value = 1234; decimals = 3 })
/// ```
  public func fromFloat(f : Float, decimals : Nat, roundMode : DecimalRoundMode) : Result.Result<Decimal, DecimalError> {
    if (Float.isNaN(f) or isInfinity(f)) return #err(#InvalidFloat);
    let scaleI : Int = Int.fromNat(pow10(decimals));
    let scaled : Float = f * Float.fromInt(scaleI);

    let rounded : Int = switch (roundMode) {
      case (#down) { Float.toInt(scaled) }; // toward 0
      case (#up) {
        let t = Float.toInt(scaled);
        if (Float.fromInt(t) == scaled) t
        else t + (if (scaled >= 0) 1 else -1)
      };
      case (#halfUp) {
        let t = Float.toInt(scaled);
        let frac = Float.abs(scaled - Float.fromInt(t));
        if (frac >= 0.5) t + (if (scaled >= 0) 1 else -1) else t
      }
    };

    #ok({ value = rounded; decimals })
  };

  /// Parses textual input into a `Decimal` with the specified scale and optional rounding mode.
  /// Supports optional leading `-` and fractional part. When `decimals` is `null`, the scale is
  /// inferred from the input text (and `roundMode` is ignored). When a concrete `decimals` is
  /// provided, any excess fractional digits are rounded using `roundMode` (defaulting to `#down`
  /// when omitted).
  /// ```motoko
  /// let inferred = Decimal.fromText("12.345", null, null);
  /// // inferred == #ok({ value = 12345; decimals = 3 })
  /// let rounded = Decimal.fromText("12.345", ?2, ?#halfUp);
  /// // rounded == #ok({ value = 1235; decimals = 2 })
  /// let truncated = Decimal.fromText("12.345", ?2, null);
  /// // truncated == #ok({ value = 1234; decimals = 2 })
  /// ```
  public func fromText(txt : Text, decimals : ?Nat, roundMode : ?DecimalRoundMode)
    : Result.Result<Decimal, DecimalError> {
    if (txt.size() == 0) return #err(#InvalidFormat);

    let isNeg = Text.startsWith(txt, #text "-");
    let body = if (isNeg) slice(txt, 1, txt.size() - 1) else txt;
    if (body.size() == 0) return #err(#InvalidFormat);

    let parts = Iter.toArray(Text.split(body, #char '.'));
    if (parts.size() > 2) return #err(#InvalidFormat);

    let intPart = parts[0];
    let fracSrc = if (parts.size() == 2) parts[1] else "";

    let intDigits = if (intPart == "") "0" else intPart;
    let fracLen = fracSrc.size();

    switch (decimals) {
      case (null) {
        let magTxt = if (fracLen == 0) intDigits else intDigits # fracSrc;
        switch (Nat.fromText(magTxt)) {
          case (null) { #err(#InvalidFormat) };
          case (?m) {
            let signed = if (isNeg) Int.neg(Int.fromNat(m)) else Int.fromNat(m);
            #ok({ value = signed; decimals = fracLen })
          };
        }
      };
      case (?targetDecimals) {
        if (fracLen <= targetDecimals) {
          let pad = Text.fromArray(Array.repeat('0', Nat.sub(targetDecimals, fracLen)));
          let magTxt = intDigits # fracSrc # pad;
          switch (Nat.fromText(magTxt)) {
            case (null) { #err(#InvalidFormat) };
            case (?m) {
              let signed = if (isNeg) Int.neg(Int.fromNat(m)) else Int.fromNat(m);
              #ok({ value = signed; decimals = targetDecimals })
            };
          }
        } else {
          let rm = switch (roundMode) {
            case (null) { #down };
            case (?mode) { mode };
          };

          let keep = slice(fracSrc, 0, targetDecimals);
          let dropped = slice(fracSrc, targetDecimals, fracLen - targetDecimals);

          func anyNonZero(t : Text) : Bool {
            for (c in t.chars()) { if (c != '0') return true };
            false
          };

          let bump : Int = switch (rm) {
            case (#down) { 0 };
            case (#up) { if (anyNonZero(dropped)) 1 else 0 };
            case (#halfUp) {
              let first = dropped.chars().next();
              switch (first) {
                case (null) { 0 };
                case (?c) {
                  if ((c >= '5') and (c <= '9')) 1 else 0
                }
              }
            }
          };

          let magTxt = intDigits # keep;
          switch (Nat.fromText(magTxt)) {
            case (null) { #err(#InvalidFormat) };
            case (?m0) {
              let base = Int.fromNat(m0);
              let signedBase = if (isNeg) -base else base;
              let signedBump = if (bump == 0) 0 else if (isNeg) -bump else bump;
              #ok({ value = signedBase + signedBump; decimals = targetDecimals })
            }
          }
        }
      }
    }
  };

  /// Creates a `Decimal` from an `Int` value, with the required `decimals`.
  /// ```motoko
  /// let a = Decimal.fromInt(-1234, 2);
  /// // a == { value = -123400; decimals = 2 }
  /// ```
  public func fromInt(n : Int, decimals : Nat) : Decimal = { value = n * pow10(decimals); decimals };

  /// Creates a `Decimal` from a `Nat` value, with the required `decimals`.
  /// ```motoko
  /// let a = Decimal.fromNat(1299, 2);
  /// // a == { value = 129900; decimals = 2 }
  /// ```
  public func fromNat(n : Nat, decimals : Nat) : Decimal = { value = Int.fromNat(n) * pow10(decimals); decimals };

  /// Creates a `Decimal` from an unscaled `Int` magnitude (no automatic scaling).
  /// ```motoko
  /// let raw = Decimal.fromUnscaledInt(-1234, 2);
  /// // raw == { value = -1234; decimals = 2 }
  /// ```
  public func fromUnscaledInt(n : Int, decimals : Nat) : Decimal = { value = n; decimals };

  /// Creates a `Decimal` from an unscaled `Nat` magnitude (no automatic scaling).
  /// ```motoko
  /// let raw = Decimal.fromUnscaledNat(1299, 2);
  /// // raw == { value = 1299; decimals = 2 }
  /// ```
  public func fromUnscaledNat(n : Nat, decimals : Nat) : Decimal = { value = Int.fromNat(n); decimals };



  // ------------ Formatting & Parsing ------------
  /// Renders a `Decimal` using canonical formatting (dot separator, optional sign).
  /// ```motoko
  /// let display = Decimal.toText(Decimal.fromNat(12345, 2));
  /// // display == "123.45"
  /// ```
  public func toText(d : Decimal) : Text {
    let sign = if (d.value < 0) "-" else "";
    let mag : Nat = Int.abs(d.value);
    let s = Nat.toText(mag);

    if (d.decimals == 0) return sign # s;

    if (s.size() <= d.decimals) {
      let zerosNeeded = Nat.sub(d.decimals, s.size());
      let zeros = Text.fromArray(Array.repeat('0', zerosNeeded));
      return sign # "0." # zeros # s;
    } else {
      let splitIx = Nat.sub(s.size(), d.decimals);
      let (ip, fp) = splitAt(s, splitIx);
      return sign # ip # "." # fp;
    };
  };

  /// Pretty-formats a `Decimal` with optional custom thousands and decimal separators.
  /// ```motoko
  /// let formatted = Decimal.format(Decimal.fromNat(1234567, 2), { thousandsSep = ?"_"; decimalSep = ?"," });
  /// // formatted == "12_345,67"
  /// ```
  public func format(d : Decimal, opts : { thousandsSep : ?Text; decimalSep : ?Text }) : Text {
    let thousands = switch (opts.thousandsSep) { case (null) { "," }; case (?t) { t } };
    let decSep = switch (opts.decimalSep) { case (null) { "." }; case (?t) { t } };

    let canonical = toText(d); // includes sign
    let (sign, body) = if (Text.startsWith(canonical, #text "-")) {
      ("-", slice(canonical, 1, canonical.size() - 1))
    } else { ("", canonical) };

    let parts = Iter.toArray(Text.split(body, #char '.'));
    if (parts.size() == 1) {
      return sign # insertThousands(parts[0], thousands);
    } else {
      let ip = insertThousands(parts[0], thousands);
      let fp = parts[1];
      return sign # ip # decSep # fp;
    };
  };

  /// Produces a compact debug-friendly string representation.
  /// ```motoko
  /// let debug = Decimal.toDebugText(Decimal.fromInt(1234, 2));
  /// // debug == "{123400, 2}"
  /// ```
  public func toDebugText(d : Decimal) : Text {
    "{" # Int.toText(d.value) # ", " # Nat.toText(d.decimals) # "}";
  };

  /// Serialises the decimal as a JSON object using `value` / `decimals` fields.
  /// ```motoko
  /// let json = Decimal.toJson(Decimal.fromInt(-1234, 2));
  /// // json == "{\"value\": \"-123400\", \"decimals\": 2}"
  /// ```
  public func toJson(d : Decimal) : Text {
    "{\"value\": \"" # Int.toText(d.value) # "\", \"decimals\": " # Nat.toText(d.decimals) # "}";
  };

  /// Serialises using the BigDecimal-style field names `unscaledValue` and `scale`.
  /// ```motoko
  /// let json = Decimal.toJsonBigDecimal(Decimal.fromInt(1234, 2));
  /// // json == "{\"unscaledValue\": \"123400\", \"scale\": 2}"
  /// ```
  public func toJsonBigDecimal(d : Decimal) : Text {
    "{\"unscaledValue\": \"" # Int.toText(d.value) # "\", \"scale\": " # Nat.toText(d.decimals) # "}";
  };


  // ------------ Scaling & Rounding ------------
  /// Rescales a `Decimal` to `targetDecimals`, applying the supplied rounding mode.
  /// ```motoko
  /// let rounded = Decimal.quantize(Decimal.fromNat(12345, 3), 2, #halfUp);
  /// // rounded == { value = 1235; decimals = 2 }
  /// ```
  public func quantize(x : Decimal, targetDecimals : Nat, roundMode : DecimalRoundMode) : Decimal {
    if (x.decimals == targetDecimals) return x;

    if (x.decimals < targetDecimals) {
      let factorNat = pow10(targetDecimals - x.decimals);
      let factor = Int.fromNat(factorNat);
      { value = x.value * factor; decimals = targetDecimals }
    } else {
      let factorNat = pow10(x.decimals - targetDecimals);
      let factor = Int.fromNat(factorNat);
      let q = x.value / factor;
      let r = x.value % factor;
      if (r == 0) return { value = q; decimals = targetDecimals };

      let direction : Int = if (x.value >= 0) 1 else -1;
      let hasFraction = r != 0;
      let bump = switch (roundMode) {
        case (#down) { 0 };
        case (#up) { if (hasFraction) direction else 0 };
        case (#halfUp) {
          let remainderMagnitude = Int.fromNat(Int.abs(r));
          let factorMagnitude = Int.fromNat(Int.abs(factor));
          if (remainderMagnitude * 2 >= factorMagnitude) direction else 0
        }
      };
      { value = q + bump; decimals = targetDecimals }
    }
  };

  /// Truncates toward zero when increasing scale.
  /// ```motoko
  /// let truncated = Decimal.truncTo(Decimal.fromInt(-12345, 3), 2);
  /// // truncated == { value = -1234; decimals = 2 }
  /// ```
  public func truncTo(x : Decimal, targetDecimals : Nat) : Decimal = quantize(x, targetDecimals, #down);

  /// Floors toward negative infinity when reducing scale.
  /// ```motoko
  /// let floored = Decimal.floorTo(Decimal.fromInt(-12345, 3), 2);
  /// // floored == { value = -1235; decimals = 2 }
  /// ```
  public func floorTo(x : Decimal, targetDecimals : Nat) : Decimal {
    // floor differs from trunc for negatives
    if (x.decimals <= targetDecimals) return quantize(x, targetDecimals, #down);

    let factorNat = pow10(x.decimals - targetDecimals);
    let factor = Int.fromNat(factorNat);
    let q = x.value / factor;
    let r = x.value % factor;

    if (r == 0) return { value = q; decimals = targetDecimals };
    if (x.value >= 0) { { value = q; decimals = targetDecimals } }
    else { { value = q - 1; decimals = targetDecimals } }
  };

  /// Ceils toward positive infinity when reducing scale.
  /// ```motoko
  /// let ceiled = Decimal.ceilTo(Decimal.fromInt(12345, 3), 2);
  /// // ceiled == { value = 1235; decimals = 2 }
  /// ```
  public func ceilTo(x : Decimal, targetDecimals : Nat) : Decimal {
    if (x.decimals <= targetDecimals) return quantize(x, targetDecimals, #down);

    let factorNat = pow10(x.decimals - targetDecimals);
    let factor = Int.fromNat(factorNat);
    let q = x.value / factor;
    let r = x.value % factor;

    if (r == 0) return { value = q; decimals = targetDecimals };
    if (x.value >= 0) { { value = q + 1; decimals = targetDecimals } }
    else { { value = q; decimals = targetDecimals } }
  };

  // ------------ Conversions ------------
  /// Converts a `Decimal` to an `Int` by rescaling to zero decimals using `roundMode`.
  /// ```motoko
  /// let units = Decimal.toInt(Decimal.fromNat(12345, 2), #down);
  /// // units == 123
  /// ```
  public func toInt(d : Decimal, roundMode : DecimalRoundMode) : Int = quantize(d, 0, roundMode).value;

  /// Returns the unscaled integer magnitude ("base units") encoded by `Decimal`.
  /// ```motoko
  /// let raw = Decimal.toBaseUnits(Decimal.fromNat(12345, 2));
  /// // raw == 1234500
  /// ```
  public func toBaseUnits(d : Decimal) : Int = d.value;

  /// Attempts to convert a `Decimal` to `Nat`, failing when the rounded integer would be negative.
  /// ```motoko
  /// let whole = Decimal.toNat(Decimal.fromNat(4599, 2), #halfUp);
  /// // whole == #ok(46)
  /// ```
  public func toNat(d : Decimal, roundMode : DecimalRoundMode) : Result.Result<Nat, DecimalError> {
    let i = toInt(d, roundMode);
    if (i < 0) #err(#NegativeValue) else #ok(Int.abs(i))
  };

  /// Converts a `Decimal` to a `Float` by dividing the scaled integer magnitude.
  /// ```motoko
  /// let asFloat = Decimal.toFloat(Decimal.fromNat(12345, 3));
  /// // asFloat == 12.345
  /// ```
  public func toFloat(d : Decimal) : Float {
    let denomI : Int = Int.fromNat(pow10(d.decimals));
    Float.fromInt(d.value) / Float.fromInt(denomI)
  };

  

  // ------------ Arithmetic ------------
  /// Adds `a` to `b`, aligning scales optionally to `decimals`.
  /// ```motoko
  /// let total = Decimal.add(Decimal.fromNat(500, 2), Decimal.fromNat(125, 2), null);
  /// // total == { value = 625; decimals = 2 }
  /// ```
  public func add(a : Decimal, b : Decimal, decimals : ?Nat) : Decimal {
    let dec = switch (decimals) { case (null) { Nat.max(a.decimals, b.decimals) }; case (?v) { v } };
    let aa = quantize(a, dec, #halfUp);
    let bb = quantize(b, dec, #halfUp);
    { value = aa.value + bb.value; decimals = dec }
  };

  /// Subtracts `b` from `a`, aligning scales optionally to `decimals`.
  /// ```motoko
  /// let diff = Decimal.subtract(Decimal.fromNat(500, 2), Decimal.fromNat(125, 2), null);
  /// // diff == { value = 375; decimals = 2 }
  /// ```
  public func subtract(a : Decimal, b : Decimal, decimals : ?Nat) : Decimal {
    let dec = switch (decimals) { case (null) { Nat.max(a.decimals, b.decimals) }; case (?v) { v } };
    let aa = quantize(a, dec, #halfUp);
    let bb = quantize(b, dec, #halfUp);
    { value = aa.value - bb.value; decimals = dec }
  };

  /// Multiplies `a` and `b`. If `decimals` is `null`, the raw scale (`a.decimals + b.decimals`) is kept.
  /// Otherwise the product is quantized to the requested number of fractional digits using `roundMode`.
  /// ```motoko
  /// let product = Decimal.multiply(Decimal.fromNat(150, 2), Decimal.fromNat(200, 2), ?2, #halfUp);
  /// // product == { value = 300; decimals = 2 }
  /// ```
  public func multiply(a : Decimal, b : Decimal, decimals : ?Nat, roundMode : DecimalRoundMode) : Decimal {
    let raw = { value = a.value * b.value; decimals = a.decimals + b.decimals };
    switch (decimals) {
      case (null) { raw };
      case (?target) { quantize(raw, target, roundMode) };
    }
  };

  /// Divides `a` by `b`, producing a `Decimal` with the requested scale (or a default when `decimals` is `null`).
  /// ```motoko
  /// let ratio = switch (Decimal.divide(Decimal.fromNat(500, 2), Decimal.fromNat(200, 2), ?2, #halfUp)) {
  ///   case (#ok value) value;
  ///   case (#err _) Debug.trap("divide failed");
  /// };
  /// // ratio == { value = 250; decimals = 2 }
  /// ```
  public func divide(a : Decimal, b : Decimal, decimals : ?Nat, roundMode : DecimalRoundMode)
    : Result.Result<Decimal, DecimalError> {
    if (b.value == 0) return #err(#DivideByZero);

    let targetDecimals = switch (decimals) {
      case (null) { Nat.max(a.decimals, b.decimals) + defaultExtraPrecision };
      case (?value) { value };
    };

    let resultIsNegative = (a.value < 0 and b.value > 0) or (a.value > 0 and b.value < 0);
    let direction : Int = if (resultIsNegative) -1 else 1;

    let aAbs : Nat = Int.abs(a.value);
    let bAbs : Nat = Int.abs(b.value);

    let exponent = Int.fromNat(targetDecimals + b.decimals) - Int.fromNat(a.decimals);

    let (numeratorAbs : Nat, denominatorAbs : Nat) =
      if (exponent >= 0) {
        let m = pow10(Int.abs(exponent));
        (aAbs * m, bAbs)
      } else {
        let m = pow10(Int.abs(exponent));
        (aAbs, bAbs * m)
      };

    if (denominatorAbs == 0) return #err(#DivideByZero);

    let qAbs = numeratorAbs / denominatorAbs;
    let rAbs = numeratorAbs % denominatorAbs;
    let hasRemainder = rAbs != 0;

    let bumpMagnitude : Nat = switch (roundMode) {
      case (#down) { 0 };
      case (#up) { if (hasRemainder) 1 else 0 };
      case (#halfUp) {
        if (not hasRemainder) 0 else if (rAbs * 2 >= denominatorAbs) 1 else 0
      }
    };

    let baseValue = Int.fromNat(qAbs) * direction;
    let bumpValue = if (bumpMagnitude == 0) 0 else Int.fromNat(bumpMagnitude) * direction;

    #ok({ value = baseValue + bumpValue; decimals = targetDecimals })
  };

  /// Raises a `Decimal` to an integer power using fast exponentiation.
  /// When `decimals` is `null`, positive exponents return the natural scale and negative ones fall back to the
  /// division default; otherwise the result is quantized to `decimals` using `roundMode`.
  /// ```motoko
  /// let squared = switch (Decimal.power(Decimal.fromNat(150, 2), 2, ?2, #halfUp)) {
  ///   case (#ok value) value;
  ///   case (#err _) Debug.trap("power failed");
  /// };
  /// // squared == { value = 225; decimals = 2 }
  /// ```
  public func power(x : Decimal, n : Int, decimals : ?Nat, roundMode : DecimalRoundMode)
    : Result.Result<Decimal, DecimalError> {
    func finalize(d : Decimal) : Result.Result<Decimal, DecimalError> {
      switch (decimals) {
        case (null) { #ok(d) };
        case (?target) { #ok(quantize(d, target, roundMode)) };
      }
    };

    if (n == 0) return finalize(unity);

    if (n < 0) {
      if (x.value == 0) return #err(#ZeroToNegativePower);
      switch (power(x, -n, null, roundMode)) {
        case (#err e) { #err(e) };
        case (#ok p) { divide(unity, p, decimals, roundMode) }
      }
    } else {
      // fast exponentiation on integer magnitude while tracking scale
      var baseVal : Int = x.value;
      var baseDec : Nat = x.decimals;
      var resVal : Int = 1;
      var resDec : Nat = 0;
      var e : Nat = Int.abs(n);

      while (e > 0) {
        if (e % 2 == 1) {
          resVal := resVal * baseVal;
          resDec += baseDec;
        };
        e /= 2;
        if (e > 0) {
          baseVal := baseVal * baseVal;
          baseDec += baseDec;
        }
      };

      finalize({ value = resVal; decimals = resDec })
    }
  };

  // ------------ Utilities ------------
  /// Absolute value while keeping the scale unchanged.
  /// ```motoko
  /// let magnitude = Decimal.abs(Decimal.fromInt(-1234, 2));
  /// // magnitude == { value = 1234; decimals = 2 }
  /// ```
  public func abs(d : Decimal) : Decimal = { value = Int.abs(d.value); decimals = d.decimals };

  /// Returns the negation of a `Decimal` without altering the scale.
  /// ```motoko
  /// let negated = Decimal.neg(Decimal.fromNat(550, 2));
  /// // negated == { value = -550; decimals = 2 }
  /// ```
  public func neg(d : Decimal) : Decimal = { value = -d.value; decimals = d.decimals };

  /// Checks whether the stored magnitude is zero.
  /// ```motoko
  /// let isZeroBalance = Decimal.isZero(Decimal.zero(4));
  /// // isZeroBalance == true
  /// ```
  public func isZero(d : Decimal) : Bool = (d.value == 0);

  /// Checks whether the decimal is strictly greater than zero.
  /// ```motoko
  /// let hasSurplus = Decimal.isPositive(Decimal.fromInt(5, 1));
  /// // hasSurplus == true
  /// ```
  public func isPositive(d : Decimal) : Bool = (d.value > 0);

  /// Checks whether the decimal is strictly less than zero.
  /// ```motoko
  /// let inDeficit = Decimal.isNegative(Decimal.fromInt(-5, 1));
  /// // inDeficit == true
  /// ```
  public func isNegative(d : Decimal) : Bool = (d.value < 0);

  /// Returns the sign of the `Decimal` (`-1`, `0`, `1`).
  /// ```motoko
  /// let sign = Decimal.signum(Decimal.fromInt(-500, 2));
  /// // sign == -1
  /// ```
  public func signum(d : Decimal) : Int = if (d.value < 0) -1 else if (d.value > 0) 1 else 0;

  /// Compares two `Decimal`s after aligning them to a common scale.
  /// ```motoko
  /// let order = Decimal.compare(Decimal.fromNat(100, 2), Decimal.fromInt(1, 0));
  /// // order == #equal
  /// ```
  public func compare(a : Decimal, b : Decimal) : Order.Order {
    let dec = Nat.max(a.decimals, b.decimals);
    let aa = quantize(a, dec, #down); // increasing scale (no rounding)
    let bb = quantize(b, dec, #down);
    if (aa.value < bb.value) #less else if (aa.value > bb.value) #greater else #equal
  };

  /// Tests whether two `Decimal`s have equal value after aligning them to a common scale.
  /// ```motoko
  /// let same = Decimal.equal(Decimal.fromNat(1230, 3), Decimal.fromNat(123, 2));
  /// // same == true
  /// ```
  public func equal(a : Decimal, b : Decimal) : Bool {
    switch (compare(a, b)) {
      case (#equal) true;
      case (_) false;
    };
  };

  /// Tests whether two 'Decimal' values are exactly equal (both `value` and `decimals` equate)
  /// ```motoko
  /// let identical = Decimal.equalExact(Decimal.fromNat(123, 2), { value = 123; decimals = 2 });
  /// // identical == true
  /// ```
  public func equalExact(a : Decimal, b : Decimal) : Bool {
    a.value == b.value and a.decimals == b.decimals;
  };

  /// Returns the minimum of two `Decimal` values `a` and `b`.
  /// ```motoko
  /// let minValue = Decimal.min(Decimal.fromNat(250, 2), Decimal.fromNat(199, 2));
  /// // minValue == { value = 199; decimals = 2 }
  /// ```
  public func min(a : Decimal, b : Decimal) : Decimal = switch (compare(a, b)) {
    case (#less) a;
    case (#equal) a;
    case (#greater) b;
  };
  /// Returns the maximum of two `Decimal`s.
  /// ```motoko
  /// let maxValue = Decimal.max(Decimal.fromNat(250, 2), Decimal.fromNat(199, 2));
  /// // maxValue == { value = 250; decimals = 2 }
  /// ```
  public func max(a : Decimal, b : Decimal) : Decimal = switch (compare(a, b)) {
    case (#less) b;
    case (#equal) a;
    case (#greater) a;
  };
  /// Clamps `x` into the inclusive range `[lo, hi]`.
  /// ```motoko
  /// let clamped = Decimal.clamp(Decimal.fromNat(750, 2), Decimal.fromNat(500, 2), Decimal.fromNat(600, 2));
  /// // clamped == { value = 600; decimals = 2 }
  /// ```
  public func clamp(x : Decimal, lo : Decimal, hi : Decimal) : Decimal = max(lo, min(x, hi));

  /// Removes trailing zeros from the fractional part while preserving numeric value.
  /// ```motoko
  /// let normalised = Decimal.normalize({ value = 123400; decimals = 4 });
  /// // normalised == { value = 1234; decimals = 2 }
  /// ```
  public func normalize(d : Decimal) : Decimal {
    if (d.decimals == 0 or d.value == 0) return d;

    var mag : Nat = Int.abs(d.value);
    var dec : Nat = d.decimals;

    // strip groups of 3 decimal zeros first
    let thousand : Nat = 1_000;
    while (dec >= 3 and mag % thousand == 0) {
      mag /= thousand;
      dec := Nat.sub(dec, 3);   // safe, no underflow
    };

    // then groups of 2
    let hundred : Nat = 100;
    while (dec >= 2 and mag % hundred == 0) {
      mag /= hundred;
      dec := Nat.sub(dec, 2);
    };

    // finally single zeros
    let ten : Nat = 10;
    while (dec >= 1 and mag % ten == 0) {
      mag /= ten;
      dec := Nat.sub(dec, 1);
    };

    let signed = if (d.value < 0) -Int.fromNat(mag) else Int.fromNat(mag);
    { value = signed; decimals = dec }
  };


// ------------ Helpers ------------
  /// Computes `10^k` for non-negative `k`.
  func pow10(k : Nat) : Nat = 10 ** k;

  /// Determines whether a float is either positive or negative infinity.
  func isInfinity(x : Float) : Bool {
    let posInfinity : Float = 1.0 / 0.0;
    Float.abs(x) == posInfinity
  };

  /// Splits `text` into a prefix and suffix at `index`.
  func splitAt(text : Text, index : Nat) : (Text, Text) {
    (
      text.chars() |> Iter.take(_, index) |> Text.fromIter(_),
      text.chars() |> Iter.drop(_, index) |> Text.fromIter(_)
    );
  };

  /// Returns a substring of `text` starting at `startIndex` with length `length`.
  func slice(text : Text, startIndex : Nat, length : Nat) : Text {
    text.chars() |> Iter.drop(_, startIndex) |> Iter.take(_, length) |> Text.fromIter(_)
  };

  /// Inserts thousands separators into an unsigned integer string.
  func insertThousands(intPart : Text, sep : Text) : Text {
    let n = intPart.size();
    if (n <= 3) return intPart;

    var i : Nat = n;
    var out : Text = "";

    // Build from the right in chunks of 3
    while (i > 3) {
      let start = Nat.sub(i, 3);
      let chunk = slice(intPart, start, 3);
      out := sep # chunk # out;
      i -= 3;
    };
    slice(intPart, 0, i) # out
  };
}
