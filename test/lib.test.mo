import { test } "mo:test";
import Result "mo:core/Result";
import Decimal "../src/";

// Convenience helpers ------------------------------------------------------

func expectDecimal(
  actual : Result.Result<Decimal.Decimal, Decimal.DecimalError>,
  expected : Decimal.Decimal
) {
  switch (actual) {
    case (#ok value) { assertDecimalEqual(value, expected) };
    case (#err _) { assert false };
  };
};

func expectError(
  actual : Result.Result<Decimal.Decimal, Decimal.DecimalError>,
  expected : Decimal.DecimalError
) {
  switch (actual) {
    case (#ok _) { assert false };
    case (#err err) { assert err == expected };
  };
};

// Helper to compare Decimal records
func assertDecimalEqual(actual : Decimal.Decimal, expected : Decimal.Decimal) {
  assert actual.value == expected.value;
  assert actual.decimals == expected.decimals;
};

test("Decimal constructors", func () {
  assertDecimalEqual(Decimal.zero(3), { value = 0; decimals = 3 });
  assertDecimalEqual(Decimal.fromInt(-123, 1), { value = -1230; decimals = 1 });
  assertDecimalEqual(Decimal.fromNat(789, 4), { value = 7890000; decimals = 4 });
  assertDecimalEqual(Decimal.fromNat(1, 2), { value = 100; decimals = 2 });

  assertDecimalEqual(Decimal.fromUnscaledInt(-123, 1), { value = -123; decimals = 1 });
  assertDecimalEqual(Decimal.fromUnscaledNat(789, 4), { value = 789; decimals = 4 });
});

test("Decimal toText and format", func () {
  let sample : Decimal.Decimal = { value = 123456789; decimals = 4 }; // 12_345.6789
  assert Decimal.toText(sample) == "12345.6789";

  let negative : Decimal.Decimal = { value = -5; decimals = 3 };
  assert Decimal.toText(negative) == "-0.005";

  let formatted = Decimal.format(sample, { thousandsSep = ?"_"; decimalSep = ?"," });
  assert formatted == "12_345,6789";

  let formattedDefault = Decimal.format(sample, { thousandsSep = null; decimalSep = null });
  assert formattedDefault == "12,345.6789";
});

test("Decimal fromText success cases", func () {
  expectDecimal(Decimal.fromText("4469.41", ?18, null), { value = 4469410000000000000000; decimals = 18 });
  expectDecimal(Decimal.fromText("123", ?6, null), { value = 123000000; decimals = 6 });
  expectDecimal(Decimal.fromText("123.456", null, null), { value = 123456; decimals = 3 });
  expectDecimal(Decimal.fromText("1234500000", ?10, null), { value = 12345000000000000000; decimals = 10 });
  expectDecimal(Decimal.fromText("123456.789", ?8, ?#halfUp), { value = 12345678900000; decimals = 8 });
  expectDecimal(Decimal.fromText("123.45", ?2, ?#down), { value = 12345; decimals = 2 });
  expectDecimal(Decimal.fromText("12.34567", ?2, null), { value = 1234; decimals = 2 });
  expectDecimal(Decimal.fromText("1.239", ?2, ?#down), { value = 123; decimals = 2 });
  expectDecimal(Decimal.fromText("1.231", ?2, ?#up), { value = 124; decimals = 2 });
  expectDecimal(Decimal.fromText("-2.301", ?2, ?#up), { value = -231; decimals = 2 });
  expectDecimal(Decimal.fromText("-2.345", ?2, ?#halfUp), { value = -235; decimals = 2 });
  expectDecimal(Decimal.fromText("1.2345", ?3, ?#halfUp), { value = 1235; decimals = 3 });
  expectDecimal(Decimal.fromText("19.875", ?2, ?#halfUp), { value = 1988; decimals = 2 });
});

test("Decimal fromText inference", func () {
  expectDecimal(Decimal.fromText("42", null, null), { value = 42; decimals = 0 });
  expectDecimal(Decimal.fromText("19.8750", null, null), { value = 198750; decimals = 4 });
  expectDecimal(Decimal.fromText("0", null, null), { value = 0; decimals = 0 });
});

test("Decimal fromText failures", func () {
  expectError(Decimal.fromText("nan", null, null), #InvalidFormat);
  expectError(Decimal.fromText("1.00.22", ?2, null), #InvalidFormat);
  expectError(Decimal.fromText("", null, null), #InvalidFormat);
  expectError(Decimal.fromText("--12", null, null), #InvalidFormat);
});

test("Decimal quantize and rounding helpers", func () {
  let x : Decimal.Decimal = { value = 12345; decimals = 3 }; // 12.345

  assertDecimalEqual(Decimal.quantize(x, 5, #down), { value = 1234500; decimals = 5 });
  assertDecimalEqual(Decimal.quantize(x, 2, #down), { value = 1234; decimals = 2 });
  assertDecimalEqual(Decimal.quantize(x, 2, #up), { value = 1235; decimals = 2 });
  assertDecimalEqual(Decimal.quantize({ value = -12345; decimals = 3 }, 2, #halfUp), { value = -1235; decimals = 2 });

  let y : Decimal.Decimal = { value = -10987; decimals = 3 }; // -10.987
  assertDecimalEqual(Decimal.truncTo(y, 2), { value = -1098; decimals = 2 });
  assertDecimalEqual(Decimal.floorTo(y, 2), { value = -1099; decimals = 2 });
  assertDecimalEqual(Decimal.ceilTo(y, 2), { value = -1098; decimals = 2 });
});

test("Decimal conversions toInt, toNat, toFloat/fromFloat", func () {
  let d : Decimal.Decimal = { value = 12345; decimals = 3 }; // 12.345
  assert Decimal.toInt(d, #down) == 12;
  assert Decimal.toInt(d, #up) == 13;

  switch (Decimal.toNat({ value = 500; decimals = 2 }, #halfUp)) {
    case (#ok value) { assert value == 5 };
    case (#err _) { assert false };
  };

  switch (Decimal.toNat({ value = -1; decimals = 0 }, #down)) {
    case (#ok _) { assert false };
    case (#err e) { assert e == #NegativeValue };
  };

  assert Decimal.toFloat(d) == 12.345;

  let ints : [Int] = [-999, -1, 0, 1234, 999999];
  let scales : [Nat] = [0, 1, 3, 6];
  for (n in ints.vals()) {
    for (dec in scales.vals()) {
      assert Decimal.toInt(Decimal.fromInt(n, dec), #halfUp) == n;
    };
  };

  let nats : [Nat] = [0, 1, 42, 999];
  for (n in nats.vals()) {
    for (dec in scales.vals()) {
      switch (Decimal.toNat(Decimal.fromNat(n, dec), #halfUp)) {
        case (#ok value) { assert value == n };
        case (#err _) { assert false };
      };
    };
  };

  switch (Decimal.fromFloat(12.345, 3, #halfUp)) {
    case (#ok value) { assertDecimalEqual(value, d) };
    case (#err _) { assert false };
  };

  switch (Decimal.fromFloat(-1.234, 2, #up)) {
    case (#ok value) { assertDecimalEqual(value, { value = -124; decimals = 2 }) };
    case (#err _) { assert false };
  };

  switch (Decimal.fromFloat(99.99, 2, #halfUp)) {
    case (#ok value) { assertDecimalEqual(value, { value = 9999; decimals = 2 }) };
    case (#err _) { assert false };
  };

  let nan = 0.0 / 0.0;
  switch (Decimal.fromFloat(nan, 2, #down)) {
    case (#ok _) { assert false };
    case (#err e) { assert e == #InvalidFloat };
  };

  let inf = 1.0 / 0.0;
  switch (Decimal.fromFloat(inf, 2, #down)) {
    case (#ok _) { assert false };
    case (#err e) { assert e == #InvalidFloat };
  };
});

test("Decimal equal helper", func () {
  let a : Decimal.Decimal = { value = 1234; decimals = 2 };  // 12.34
  let b : Decimal.Decimal = { value = 12340; decimals = 3 }; // 12.340
  let c : Decimal.Decimal = { value = 1235; decimals = 2 };  // 12.35

  assert Decimal.equal(a, b);
  assert Decimal.equal(Decimal.neg(a), { value = -12340; decimals = 3 });
  assert Decimal.equal(Decimal.zero(4), { value = 0; decimals = 0 });
  assert Decimal.equal(a, c) == false;
});

test("Decimal arithmetic operations", func () {
  let a : Decimal.Decimal = { value = 1234; decimals = 2 }; // 12.34
  let b : Decimal.Decimal = { value = 567; decimals = 1 };  // 56.7

  assertDecimalEqual(
    Decimal.add(a, b, null),
    { value = 6904; decimals = 2 }
  );

  assertDecimalEqual(
    Decimal.add(a, b, ?1),
    { value = 690; decimals = 1 }
  );

  assertDecimalEqual(
    Decimal.subtract(b, a, ?2),
    { value = 4436; decimals = 2 }
  );

  assertDecimalEqual(
    Decimal.multiply(a, b, ?3, #halfUp),
    { value = 699678; decimals = 3 }
  );
  assertDecimalEqual(
    Decimal.multiply(a, b, ?8, #halfUp),
    { value = 69967800000; decimals = 8}
  );

  expectDecimal(Decimal.divide(b, a, ?2, #halfUp), { value = 459; decimals = 2 });

  let c : Decimal.Decimal = { value = 11524600000000; decimals = 8 };
  let d : Decimal.Decimal = { value = 100; decimals = 2 };
  expectDecimal(Decimal.divide(d, c, ?c.decimals, #halfUp), { value = 868; decimals = 8 });

  expectError(Decimal.divide(a, { value = 0; decimals = 0 }, ?2, #down), #DivideByZero);
  expectDecimal(Decimal.divide(a, b, ?4, #halfUp), { value = 2176; decimals = 4 });
});

test("Decimal power", func () {
  let base : Decimal.Decimal = { value = 2; decimals = 0 };

  switch (Decimal.power(base, 3, ?0, #down)) {
    case (#ok value) { assertDecimalEqual(value, { value = 8; decimals = 0 }) };
    case (#err _) { assert false };
  };

  switch (Decimal.power(base, 0, ?2, #down)) {
    case (#ok value) { assertDecimalEqual(value, { value = 100; decimals = 2 }) };
    case (#err _) { assert false };
  };

  switch (Decimal.power({ value = 3; decimals = 0 }, -2, ?3, #halfUp)) {
    case (#ok value) { assertDecimalEqual(value, { value = 111; decimals = 3 }) };
    case (#err _) { assert false };
  };

  switch (Decimal.power({ value = 0; decimals = 0 }, -1, ?2, #down)) {
    case (#ok _) { assert false };
    case (#err e) { assert e == #ZeroToNegativePower };
  };
});

test("Decimal inverse identities", func () {
  let a : Decimal.Decimal = { value = 1234; decimals = 2 }; // 12.34
  let b : Decimal.Decimal = { value = 567; decimals = 1 };  // 56.7

  let sumDefault = Decimal.add(a, b, null);
  let recoverDefault = Decimal.subtract(sumDefault, b, null);
  assert Decimal.equal(recoverDefault, a);

  let sumScaled = Decimal.add(a, b, ?3);
  let recoverScaled = Decimal.subtract(sumScaled, Decimal.quantize(b, 3, #halfUp), ?3);
  assert Decimal.equal(recoverScaled, Decimal.quantize(a, 3, #halfUp));

  let c : Decimal.Decimal = { value = 1500; decimals = 2 }; // 15.00
  let d : Decimal.Decimal = { value = 200; decimals = 2 };  // 2.00

  let prod = Decimal.multiply(c, d, null, #halfUp);
  switch (Decimal.divide(prod, d, ?2, #halfUp)) {
    case (#ok recovered) { assert Decimal.equal(recovered, c) };
    case (#err _) { assert false };
  };

  let prodScaled = Decimal.multiply(c, d, ?5, #halfUp);
  let dScaled = Decimal.quantize(d, 5, #halfUp);
  switch (Decimal.divide(prodScaled, dScaled, ?2, #halfUp)) {
    case (#ok recoveredScaled) { assert Decimal.equal(recoveredScaled, c) };
    case (#err _) { assert false };
  };

});

test("Decimal utilities", func () {
  let neg : Decimal.Decimal = { value = -4500; decimals = 2 };
  let pos : Decimal.Decimal = { value = 750; decimals = 1 };

  assertDecimalEqual(Decimal.abs(neg), { value = 4500; decimals = 2 });
  assertDecimalEqual(Decimal.neg(pos), { value = -750; decimals = 1 });
  assert Decimal.isZero({ value = 0; decimals = 5 });
  assert Decimal.isZero({ value = 10; decimals = 1 }) == false;
  assert Decimal.signum(neg) == -1;
  assert Decimal.signum(pos) == 1;
  assert Decimal.signum({ value = 0; decimals = 0 }) == 0;

  assert Decimal.compare({ value = 100; decimals = 2 }, { value = 1; decimals = 0 }) == #equal;
  assert Decimal.compare({ value = -101; decimals = 1 }, { value = -10; decimals = 0 }) == #less;
  assert Decimal.compare({ value = 505; decimals = 2 }, { value = 50; decimals = 1 }) == #greater;

  assertDecimalEqual(Decimal.min(neg, pos), neg);
  assertDecimalEqual(Decimal.max(neg, pos), pos);

  assertDecimalEqual(
    Decimal.clamp({ value = 500; decimals = 2 }, { value = 400; decimals = 2 }, { value = 600; decimals = 2 }),
    { value = 500; decimals = 2 }
  );

  assertDecimalEqual(
    Decimal.clamp({ value = 300; decimals = 2 }, { value = 400; decimals = 2 }, { value = 600; decimals = 2 }),
    { value = 400; decimals = 2 }
  );

  assertDecimalEqual(
    Decimal.clamp({ value = 900; decimals = 2 }, { value = 400; decimals = 2 }, { value = 600; decimals = 2 }),
    { value = 600; decimals = 2 }
  );

  assertDecimalEqual(
    Decimal.normalize({ value = 1234000; decimals = 4 }),
    { value = 1234; decimals = 1 }
  );

  assertDecimalEqual(
    Decimal.normalize({ value = -450000; decimals = 5 }),
    { value = -45; decimals = 1 }
  );

  assertDecimalEqual(
    Decimal.normalize({ value = 0; decimals = 3 }),
    { value = 0; decimals = 3 }
  );
});
