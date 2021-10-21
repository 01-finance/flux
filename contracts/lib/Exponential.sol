// SPDX-License-Identifier: MIT
// Created by Flux Team
// Copy from Compund and editor by Flux.

pragma solidity 0.6.8;

import "./SafeMath.sol";

struct Exp {
    uint256 mantissa;
}

library Exponential {
    using SafeMath for uint256;
    uint256 private constant expScale = 1e18; // solhint-disable-line  const-name-snakecase
    uint256 private constant halfExpScale = expScale / 2; // solhint-disable-line  const-name-snakecase

    /**
     * @dev Creates an exponential from numerator and denominator values.
     *      Note: Returns an error if (`num` * 10e18) > MAX_INT,
     *            or if `denom` is zero.
     */
    function get(uint256 num, uint256 denom) internal pure returns (Exp memory) {
        return Exp({ mantissa: num.mul(expScale).div(denom) });
    }

    /**
     * @dev Adds two exponentials, returning a get exponential.
     */
    function add(Exp memory a, Exp memory b) internal pure returns (Exp memory) {
        return Exp({ mantissa: a.mantissa.add(b.mantissa) });
    }

    /**
     * @dev Subtracts two exponentials, returning a get exponential.
     */
    function sub(Exp memory a, Exp memory b) internal pure returns (Exp memory) {
        return (Exp({ mantissa: a.mantissa.sub(b.mantissa) }));
    }

    /**
     * @dev Multiply an Exp by a scalar, returning a get Exp.
     */
    function mulScalar(Exp memory a, uint256 scalar) internal pure returns (Exp memory) {
        return (Exp({ mantissa: a.mantissa.mul(scalar) }));
    }

    /**
     * @dev Multiply an Exp by a scalar, then truncate to return an unsigned integer.
     */
    function mulScalarTruncate(Exp memory a, uint256 scalar) internal pure returns (uint256) {
        return (truncate(mulScalar(a, scalar)));
    }

    /**
     * @dev Multiply an Exp by a scalar, truncate, then add an to an unsigned integer, returning an unsigned integer.
     */
    function mulScalarTruncateAddUInt(
        Exp memory a,
        uint256 scalar,
        uint256 addend
    ) internal pure returns (uint256) {
        return mulScalarTruncate(a, scalar).add(addend);
    }

    /**
     * @dev Divide an Exp by a scalar, returning a get Exp.
     */
    function divScalar(Exp memory a, uint256 scalar) internal pure returns (Exp memory) {
        return (Exp({ mantissa: a.mantissa.div(scalar) }));
    }

    /**
     * @dev Divide a scalar by an Exp, returning a get Exp.
     */
    function divScalarByExp(uint256 scalar, Exp memory divisor) internal pure returns (Exp memory) {
        /*
          We are doing this as:
          get(mulUInt(expScale, scalar), divisor.mantissa)

          How it works:
          Exp = a / b;
          Scalar = s;
          `s / (a / b)` = `b * s / a` and since for an Exp `a = mantissa, b = expScale`
        */
        //  s/divisor = (s*1e18)/(divisor)

        return get(scalar.mul(expScale), divisor.mantissa);
    }

    /**
     * @dev Divide a scalar by an Exp, then truncate to return an unsigned integer.
     */
    function divScalarByExpTruncate(uint256 scalar, Exp memory divisor) internal pure returns (uint256) {
        return (truncate(divScalarByExp(scalar, divisor)));
    }

    /**
     * @dev Multiplies two exponentials, returning a get exponential.
     */
    function mul(Exp memory a, Exp memory b) internal pure returns (Exp memory) {
        uint256 doubleScaledProduct = a.mantissa.mul(b.mantissa);

        //  100*3 * 100*4  / 10 /100
        // We add half the scale before dividing so that we get rounding instead of truncation.
        //  See "Listing 6" and text above it at https://accu.org/index.php/journals/1717
        // Without this change, a result like 6.6...e-19 will be truncated to 0 instead of being rounded to 1e-18.
        uint256 doubleScaledProductWithHalfScale = doubleScaledProduct.add(halfExpScale);

        return (Exp({ mantissa: doubleScaledProductWithHalfScale.div(expScale) }));
    }

    /**
     * @dev Multiplies two exponentials given their mantissas, returning a get exponential.
     */
    function mul(uint256 a, uint256 b) internal pure returns (Exp memory) {
        return mul(Exp({ mantissa: a }), Exp({ mantissa: b }));
    }

    /**
     * @dev Multiplies three exponentials, returning a get exponential.
     */
    function mul3(
        Exp memory a,
        Exp memory b,
        Exp memory c
    ) internal pure returns (Exp memory) {
        return mul(mul(a, b), c);
    }

    /**
     * @dev Divides two exponentials, returning a get exponential.
     *     (a/scale) / (b/scale) = (a/scale) * (scale/b) = a/b,
     *  which we can scale as an Exp by calling get(a.mantissa, b.mantissa)
     */
    function div(Exp memory a, Exp memory b) internal pure returns (Exp memory) {
        return get(a.mantissa, b.mantissa);
    }

    /**
      @dev 两个数字相除，但允许除数 b 为 0
     */
    function divAllowZero(Exp memory a, Exp memory b) internal pure returns (Exp memory) {
        if (b.mantissa == 0) {
            return Exp({ mantissa: 0 });
        }
        return get(a.mantissa, b.mantissa);
    }

    /**
     * @dev Truncates the given exp to a whole number value.
     *      For example, truncate(Exp{mantissa: 15 * expScale}) = 15
     */
    function truncate(Exp memory exp) internal pure returns (uint256) {
        // Note: We are not using careful math here as we're performing a division that cannot fail
        return exp.mantissa / expScale;
    }

    /**
     * @dev Checks if first Exp is less than second Exp.
     */
    function lessThan(Exp memory left, Exp memory right) internal pure returns (bool) {
        return left.mantissa < right.mantissa;
    }

    /**
     * @dev Checks if left Exp <= right Exp.
     */
    function lessThanOrEqual(Exp memory left, Exp memory right) internal pure returns (bool) {
        return left.mantissa <= right.mantissa;
    }

    /**
     * @dev Checks if left Exp > right Exp.
     */
    function greaterThan(Exp memory left, Exp memory right) internal pure returns (bool) {
        return left.mantissa > right.mantissa;
    }

    /**
     * @dev Checks if left Exp = right Exp.
     */
    function equal(Exp memory left, Exp memory right) internal pure returns (bool) {
        return left.mantissa == right.mantissa;
    }

    /**
     * @dev returns true if Exp is exactly zero
     */
    function isZero(Exp memory value) internal pure returns (bool) {
        return value.mantissa == 0;
    }
}
