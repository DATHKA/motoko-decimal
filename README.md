# decimal

Motoko `Decimal` provides a fixed-point decimal type and maths operators built on big integer primitives so financial or currency calculations are deterministic, avoiding floating-point rounding errors.

It is designed for arithmetic across different fiat and crypto currency values with fixed decimals (e8s, sat, wei, USD).

## Install
```
mops add decimal
```

## Usage
```motoko
import Debug "mo:base/Debug";
import Decimal "mo:decimal";

var orderTotal : Decimal.Decimal = Decimal.zero(2);

let unitPrice = Decimal.fromNat(1999, 2);        // 19.99
let discount = Decimal.fromInt(-150, 2);         // -1.50

let taxRate = switch (Decimal.fromText("0.0825", ?4, ?#halfUp)) {
  case (#ok value) value;
  case (#err _) Debug.trap("invalid tax rate");
};

orderTotal := Decimal.add(orderTotal, unitPrice, null);
orderTotal := Decimal.add(orderTotal, discount, null);

let tax = Decimal.multiply(orderTotal, taxRate, ?2, #halfUp);
orderTotal := Decimal.add(orderTotal, tax, null);

Debug.print("Total due: " # Decimal.toText(orderTotal)); // prints: Total due: 20.02
```

Passing `null` for the optional `decimals` parameters lets the library pick a sensible scale automatically depending on the operation and operands.
