// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(uint256 initialSupply) public ERC20("TT", "TT") {
        _setupDecimals(9);
        _mint(msg.sender, initialSupply);
    }
}
