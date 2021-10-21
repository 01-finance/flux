// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;
import "./Test.sol";
import "../lib/Exponential.sol";

contract TestExponential is Test {
    using Exponential for Exp;
    using Exponential for uint256;

    function testAdd() public pure {
        Exp memory a = Exponential.get(2, 1);
        Exp memory b = Exponential.get(3, 1);
        Exp memory c = a.add(b);
        Exp memory want = Exponential.get(5, 1);
        want;
        require(c.equal(want), "expect 2+3=5");

        a = Exponential.get(2, 1);
        b = Exponential.get(3, 10); //0.3
        c = a.add(b);
        require(c.equal(Exponential.get(23, 10)), "expect 2+0.3=2.3");
    }

    function testSub() public pure {
        Exp memory zeroExp = Exponential.get(0, 1);
        Exp memory a = Exponential.get(1e18, 1); // 1e18*1e18
        Exp memory b = Exponential.get(1e19, 1); // 1e19*1e18
        require(a.sub(a).isZero(), "expect a-a=0");
        require(b.sub(b).isZero(), "expect b-b=0");
        require(a.add(b).truncate() == 1e18 + 1e19, "expect truncate(1e18+1e19)= 1e18+1e19");

        require(a.add(b).sub(a).equal(b), "expect a+b-a=b");
        require(a.add(b).sub(b).equal(a), "expect a+b-b=a");
        require(a.add(b).sub(b).sub(a).isZero(), "expect a+b-a-b=0");
        require(a.add(zeroExp).equal(a), "expect a+0=a");
        require(b.add(zeroExp).equal(b), "expect b+0=b");
    }

    function testMulScalar() public pure {
        Exp memory a = Exponential.get(1e18, 1e18);
        require(a.mulScalar(1).equal(a), "expect 1e18*1=1e18");
        require(a.mulScalar(0).isZero(), "expect 1e18*0=0");
        require(a.mulScalar(1e18).equal(Exponential.get(1e18, 1)), "expect 1 * 1e18 = 1e18");
    }

    function testMulScalarTruncate() public pure {
        Exp memory a = Exponential.get(1e18, 1e18);
        require(a.mulScalarTruncate(1) == 1, "expect 1e18*1/1e18=1");
        require(a.mulScalarTruncate(0) == 0, "expect 1e18*0/1e18=0");
    }

    function testMulScalarTruncateAddUInt() public pure {
        Exp memory a = Exponential.get(1e18, 1e18);
        require(a.mulScalarTruncateAddUInt(1, 1) == 2, "expect 1e18*1/1e18 + 1 =2");
        require(a.mulScalarTruncateAddUInt(0, 1e18) == 1e18, "expect 1e18*0/1e18 + 1e18=1e18");
    }

    function testDivScalar() public pure {
        Exp memory a = Exponential.get(1e18, 1e18);

        require(a.divScalar(1e18).equal(Exponential.get(1, 1e18)), "expect 1e18/1e18=1");
    }

    // function divScalarByExp() public pure {
    //     Exp memory a = Exponential.get(1e19, 1);

    //     require(
    //         //  1e20/1e19=10
    //         Exponential.divScalarByExp(1e20, a).equal(
    //             Exponential.get(10, 1e18)
    //         ),
    //         "expect 1e20/1e19=10"
    //     );
    //     require(
    //         Exponential.divScalarByExp(0, a).isZero(),
    //         "expect 0/1e18=0"
    //     );
    // }

    // function divScalarByExpTruncate() public pure {
    //     Exp memory a = Exponential.get(1, 1e18);

    //     require(
    //         Exponential.divScalarByExpTruncate(1e19, a) == 1,
    //         "expect (1e19/1)/1e18=1"
    //     );
    //     require(
    //         Exponential.divScalarByExpTruncate(2.12 * 1e18, a) == 1,
    //         "expect (2.12e18/1)/1e18=2"
    //     );
    // }

    function testMul() public pure {
        Exp memory zeroExp = Exponential.get(0, 1);
        Exp memory one = Exponential.get(1, 1);
        Exp memory a = Exponential.get(2, 1);
        Exp memory b = Exponential.get(3, 1);
        Exp memory c = Exponential.get(4, 1);
        require(a.mul(b).equal(Exponential.get(6, 1)), "exepct  2*3=6");
        require(a.mul(zeroExp).isZero(), "exepct  a*0=0");
        require(b.mul(zeroExp).isZero(), "exepct  b*0=0");
        require(a.mul(one).equal(a), "exepct  a*1=a");
        require(a.mul3(b, c).equal(Exponential.get(2 * 3 * 4, 1)), "exepct 2*3*4=24");
        require(a.mul3(b, one).equal(a.mul(b)), "exepct a*b*1=a*b");
        require(a.mul3(c, one).equal(c.mul(a)), "exepct a*c*1=c*a");
    }

    function testDiv() public pure {
        Exp memory one = Exponential.get(1, 1);
        Exp memory a = Exponential.get(100, 1);
        Exp memory b = Exponential.get(10, 1);
        // Exp memory c = Exponential.get(4, 1);

        require(a.div(b).equal(Exponential.get(10, 1)), "exepct  100/10=10");
        require(a.div(one).equal(a), "exepct  a*1=a");
        require(a.div(b).mul(b).equal(a), "exepct  a*b/b=a");
        require(a.div(a).mul(a).equal(a), "exepct  a*a/a=a");
    }

    function testTruncate() public pure {
        require(Exponential.get(0, 1).truncate() == 0, "exepct truncate(0)=0");
        require(Exponential.get(100, 1).truncate() == 100, "exepct truncate(100)=100");
        require(Exponential.get(1, 10).truncate() == 0, "exepct truncate(0.1)=0");
        require(Exponential.get(12, 10).truncate() == 1, "exepct truncate(1.2)=1");
    }

    function testLessThanExp() public pure {
        Exp memory a = Exponential.get(100, 1);
        Exp memory b = Exponential.get(10, 1);
        require(a.lessThan(b) == false, "expect 100<10 == false");
        require(b.lessThan(a) == true, "expect 10<100 == true");
        require(b.lessThan(b) == false, "expect 10<10 == false");
    }

    function testLessThanOrEqualExp() public pure {
        Exp memory a = Exponential.get(100, 1);
        Exp memory b = Exponential.get(10, 1);
        require(a.lessThanOrEqual(b) == false, "expect 100<=10 == false");
        require(b.lessThanOrEqual(a) == true, "expect 10<=100 == true");
        require(b.lessThanOrEqual(b) == true, "expect 10<=10 == true");
    }

    function testgreaterThan() public pure {
        Exp memory a = Exponential.get(100, 1);
        Exp memory b = Exponential.get(10, 1);
        require(a.greaterThan(b) == true, "expect 100>10 == true");
        require(b.greaterThan(a) == false, "expect 10>100 == false");
        require(b.greaterThan(b) == false, "expect 10>10 == false");
    }

    function testIsZero() public pure {
        Exp memory a = Exponential.get(1, 1e18);
        Exp memory b = Exponential.get(0, 1);
        require(a.isZero() == false, "expect 1 is not zero");
        require(b.isZero() == true, "expect 0 is zero");
    }

    function testEqual() public pure {
        Exp memory a = Exponential.get(1, 1e18);
        Exp memory b = Exponential.get(0, 1);
        require(a.equal(a) == true, "expect a=a");
        require(b.equal(b) == true, "expect b=b");
        require(a.equal(b) == false, "expect a!=b");
    }
}
