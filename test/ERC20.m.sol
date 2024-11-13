// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    mapping(address => bool) public blocked;
    bool public transferShouldRevert;
    bool public mintShouldRevert;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) public {
        require(!mintShouldRevert, "MINT_REVERTED");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function blockAddress(address user) external {
        blocked[user] = true;
    }

    function unblockAddress(address user) external {
        blocked[user] = false;
    }

    function setTransferShouldRevert(bool shouldRevert) external {
        transferShouldRevert = shouldRevert;
    }

    function setMintShouldRevert(bool shouldRevert) external {
        mintShouldRevert = shouldRevert;
    }
}
