# decimal

Motoko `Decimal` provides fixed-point decimal math built on top of big integer primitives so financial or currency calculations can avoid floating-point rounding errors. It focuses on predictable precision, conversion utilities, and ergonomic arithmetic helpers for canister development.

## Install
```
mops add decimal
```

## Usage
```motoko
import Debug "mo:base/Debug";
import Decimal "mo:decimal";

var orderTotal : Decimal.Decimal = Decimal.zero(2);

let unitPrice = Decimal.ofNat(1999, 2);        // 19.99
let discount = Decimal.ofInt(-150, 2);         // -1.50

let taxRate = switch (Decimal.ofText("0.0825", 4, #halfUp)) {
  case (#ok value) value;
  case (#err _) Debug.trap("invalid tax rate");
};

orderTotal := Decimal.add(orderTotal, unitPrice, null);
orderTotal := Decimal.add(orderTotal, discount, null);

let tax = Decimal.multiply(orderTotal, taxRate, 2, #halfUp);
orderTotal := Decimal.add(orderTotal, tax, null);

Debug.print("Total due: " # Decimal.toText(orderTotal)); // prints: Total due: 20.02
```

Passing `null` for the optional `decimals` parameter in arithmetic helpers such as `Decimal.add` keeps whatever scale each operand already uses (effectively aligning to the maximum decimals of the inputs). Supplying a concrete value forces that many fractional digits, quantizing the operands to the requested precision before performing the operation.
