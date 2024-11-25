// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CometMainInterface} from "../interfaces/IComet.sol";

contract Knight {
    CometMainInterface private comet;

    constructor(address _comet) {
        comet = CometMainInterface(_comet);
    }

    function isLiquidatable(address account) external view returns (bool) {
        return comet.isLiquidatable(account);
    }

    function liquidate(address absorber, address[] calldata accounts) external {
        comet.absorb(absorber, accounts);
    }
}
