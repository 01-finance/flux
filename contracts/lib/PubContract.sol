// SPDX-License-Identifier: MIT
// Created by Flux Team
pragma solidity 0.6.8;

library PubContract {
    function getERC1820RegistryAddress() internal view returns (address) {
        return isConflux() ? 0x88887eD889e776bCBe2f0f9932EcFaBcDfCd1820 : 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24;
    }

    function isConflux() internal view returns (bool) {
        uint32 size;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            // The Conflux create2factory contract
            size := extcodesize(0x8A3A92281Df6497105513B18543fd3B60c778E40)
        }
        return (size > 0);
    }
}
