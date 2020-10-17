pragma solidity ^0.5.10;

import './PGPGame.sol';
import './TRC20.sol';
import './PooledGamePlatform.sol';

contract OPLStaking is PGPGame {
    address public constant TokenAddress = 0xCA35b7d915458EF540aDe6068dFe2F44E8fa733c; // TODO: figure out
    address public constant PlatformAddress = 0xCA35b7d915458EF540aDe6068dFe2F44E8fa733c;
    address public constant StakingAddress = 0xCA35b7d915458EF540aDe6068dFe2F44E8fa733c;
    uint public constant MinimumStake = 50; // TODO: check big numbers

    function deposit(uint256 amount) external returns (bool success) {
        TRC20 token = TRC20(TokenAddress);
        token.transferFrom(PlatformAddress, address(this), amount);
        uint balance = token.balanceOf(address(this));
        if (balance >= MinimumStake) {
            // TODO: use StakingAddress here
        }
        return true;
    }

    function withdraw() external returns (uint256 amount) {
        TRC20 token = TRC20(TokenAddress);
        // any existing balance means the last deposit(s) was too small to stake.
        uint waitingToStake = token.balanceOf(address(this));

        // TODO: use StakingAddress to pull dividends to this address
        
        uint dividends = token.balanceOf(address(this)) - waitingToStake;
        token.transfer(PlatformAddress, dividends);
        return dividends;
    }

    function claim() external returns (uint256 amount) {
        TRC20 token = TRC20(TokenAddress);
        
        // TODO: use StakingAddress to unstake.  Will need  to pay 100 TRX

        uint payout = token.balanceOf(address(this));
        token.transfer(PlatformAddress, payout);
        return payout;
    }
}
