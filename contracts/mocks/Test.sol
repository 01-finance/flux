// SPDX-License-Identifier: MIT
// Created by Flux Team

pragma solidity 0.6.8;

import { Strings } from "../lib/Strings.sol";

contract Test {
    using Strings for uint256;
    using Strings for string;

    mapping(string => string) public errorInfos;

    /**
        @notice 检查 uint256 是否是预期值
        @param expect 期望值
        @param actual 实际值
        @param title  不等于期望值时的错误信息
     */
    function expectEqual(
        uint256 expect,
        uint256 actual,
        string memory title
    ) internal pure {
        if (expect != actual) {
            title = title.join("\n\t期望值：").join(expect.toString()).join("\n\t实际值：").join(actual.toString());
            revert(title);
        }
    }

    function expectEqual(
        address expect,
        address actual,
        string memory title
    ) internal pure {
        if (expect != actual) {
            // 不知为何，下面代码会让部署合约的Gas燃料消耗变成巨大。
            // 不含下面代码，usedGas =6426724，包含后 usedGas 30000000 还不够。
            string memory e = addressToAsciiString(expect);
            string memory a = addressToAsciiString(actual);
            title = title.join("\n\t期望值：").join(e).join("\n\t实际值：").join(a);
            revert(title);
        }
    }

    /* ethereum address to string */
    // https://ethereum.stackexchange.com/questions/8346/convert-address-to-string
    // https://ethereum.stackexchange.com/a/8447/1964
    function addressToAsciiString(address _address) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint256(_address) / (2**(8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return string(s);
    }

    function char(bytes1 b) private pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
}
