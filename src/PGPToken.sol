pragma solidity ^0.5.8;

import "./Context.sol";
import "./ITRC20.sol";
import "./BaseTRC20.sol";

contract PGPToken is ITRC20, TRC20Detailed {
    constructor(address gr) public TRC20Detailed("PGP TOKEN", "PGP", 18){
        require(gr != address(0), "invalid gr");
        _mint(gr, 180000 * 10 ** 18); // 180,000 supply
    }
}
