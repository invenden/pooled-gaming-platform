// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.7.0;

interface TRC20 {
    function totalSupply() external view returns (uint);
    function balanceOf(address tokenOwner) external view returns (uint256 balance);
    function allowance(address owner, address spender) external  view returns (uint256 remaining);
    function transfer(address recipient, uint256 amount) external returns (bool success);
    function approve(address spender, uint256 amount) external  returns (bool success);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool success);
}

interface GameContract {
    function tokenAddress() external view returns (address);
    function deposit(uint256 amount) external returns (bool success);
    function withdraw() external returns (uint256 amount);
    function claim() external returns (uint256 amount);
}

contract Divpool {
    using SafeMath for uint256;

    struct Player {
        uint shares;
        address referredBy;
    }

    struct Game {
        address gameAddress;
        address trc20Address;
        uint gameEndsOn;
        mapping(address=>Player) players;
    }

    address internal dev;
    mapping(address=>bool) admin;
    mapping(address=>Game) games;
    uint constant WAITING_PERIOD = SECONDS_PER_DAY * 2;
    uint constant SECONDS_PER_DAY = 86400;

    constructor() {
        dev = msg.sender;
        admin[dev] = true;
    }

    //// PLAYER FUNCTIONS ////
    function deposit(address tokenAddress, uint amount, address referredBy) onlyDuringGame(tokenAddress) payable public returns (uint) { // TODO: msg.value and trc tokens...
        require(msg.value > 0, "Cannot purchase 0 tokens.");
        Game storage game = games[tokenAddress];
        Player storage player = game.players[msg.sender];
        if (player.referredBy == address(0)) { // new player
            player.referredBy = referredBy != address(0) ? referredBy : dev;
        }

        uint netAmount = extractFees(msg.value, true);
        player.shares = player.shares.add(netAmount);
        return player.shares;
    }

    function withdraw() onlyActivePlayers() onlyDuringGame() public returns (uint) {
        Player storage player = players[msg.sender];
        uint shares = player.shares;
        uint toWithdraw = extractFees(shares, false);
        msg.sender.transfer(toWithdraw); // TODO: Send correct token type.
        player.shares = 0;
        return toWithdraw;
    }

    function claim() onlyActivePlayers() onlyBetweenGames() public returns (uint) {
        return _claim(msg.sender);
    }

    function _claim(address payable receiver) internal returns (uint) {
        Player storage player = players[receiver];
        uint shares = player.shares;
        receiver.transfer(shares); // TODO: Send correct token type.
        player.shares = 0;
        return shares;
    }

    function claimableShares() public view returns (uint) {
        return players[msg.sender].shares;
    }

    function sellableShares() public view returns (uint) {
        return players[msg.sender].shares.percentage(90); // total 10% fee will be applied if player sells.
    }

    function addToGame(address gameAddress, uint amount) onlyDuringGame(gameAddress) public {
        require(amount > 0, "Cannot add 0 tokens to the game.");

        poolContract.transfer(amount); // TODO: actually call the right method for staking.
    }

    //// ADMIN FUNCTIONS ////
    function startGame(address gameAddress, uint daysToRun) onlyAdmins() onlyBetweenGames(gameAddress) public {
        Game storage game = games[gameAddress];
        require(block.timestamp >= game.gameEndsOn + WAITING_PERIOD, "A new game cannot begin until players have had enough time to collect their earnings from the last game.");
        require(daysToRun > 0, "Cannot run a game for 0 days.");
        game.gameEndsOn = block.timestamp.add(daysToRun.mul(SECONDS_PER_DAY));

        // add seed balance to contract balance, stake entire balance to stakingContract.
        // set all players' balances (if any remain) to 0
    }
    function endGame() onlyAdmins() onlyDuringGame() public {
        gameStarted = false;
        gameCanStartOn = block.timestamp + waitingPeriod;

        // Dev is always a player, but never a winner.
        _claim(dev);

        // unstake from stakingContract
        // calculate distributions
        // add to the players
    }
    function registerAdmin(address addr, bool isAdmin) onlyAdmins() public {
        require(addr != dev, "The dev will always be an Administrator.");
        admin[addr] = isAdmin;
    }

    function registerGame(address gameAddress) onlyAdmins() public {
        Game storage game = games[gameAddress];
        require(game.gameAddress == address(0), "The game cannot be altered once it has been registered.");
        GameContract gameContract = GameContract(gameAddress);
        
    }

    //// INTERNAL ////
    function extractFees(uint amount, bool shouldPayReferrer) internal returns (uint) {
        uint toPool = amount.percentage(4);
        uint toDivs = amount.percentage(4);
        uint toReferral = amount.percentage(2);

        if (shouldPayReferrer) {
            payReferral(players[msg.sender].referredBy, toReferral);
        } else {
            toPool = toPool.add(toReferral);
            toReferral = 0;
        }

        payDividends(msg.sender, toDivs);
        payPool(toPool);


        uint netAmount = amount.sub(toPool).sub(toDivs).sub(toReferral);

        return netAmount;
    }

    function payDividends(address exclude, uint dividends) internal {
        // TODO
    }

    function payPool(uint amount) internal {
        // TODO
        // hold amount in ledger. if ledger > threshold for poolContract, send. (50 for opals staking)
    }

    function payReferral(address referrer, uint amount) internal {
        if (players[referrer].shares > 0) {
            payPlayer(referrer, amount);
        } else {
            payPlayer(dev, amount);
        }
    }

    function payPlayer(address player, uint amount) internal {
        players[player].shares = players[player].shares.add(amount);
    }

    //// MODIFIERS ////
    modifier onlyActivePlayers() {
        require(players[msg.sender].shares > 0, "You are not eligible.");
        _;
    }

    modifier onlyAdmins() {
        require(admin[msg.sender], "Only an Administrator can perform this action.");
        _;
    }

    modifier onlyDuringGame(address gameAddress) {
        require(games[gameAddress].gameEndsOn > block.timestamp, "A game is not running.");
        _;
    }

    modifier onlyBetweenGames(address gameAddress) {
        require(games[gameAddress].gameEndsOn <= block.timestamp, "A game is currently running.");
        _;
    }
}

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a / b;
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }

    function percentage(uint256 a, uint256 percent) internal pure returns (uint256) {
        return div(mul(a, percent), 100);
    }
}
