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
    function minimumDeposit() external view returns (uint256 minimum);
    function tokenAddress() external view returns (address);
    function deposit(uint256 amount) external returns (bool success);
    function withdraw() external returns (uint256 amount);
    function claim() external returns (uint256 amount);
}

contract PooledGamePlatform {
    using SafeMath for uint256;

    struct Player {
        uint shares;
        address referredBy;
    }

    struct Game {
        address gameAddress;
        address tokenAddress;
        uint gameEndsOn;
        mapping(address=>Player) players;
        address[] _players;
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
    function deposit(address tokenAddress, uint amount, address referredBy) onlyDuringGame(tokenAddress) public returns (uint) { // TODO: msg.value and trc tokens...
        require(amount > 0, "Cannot purchase 0 tokens.");
        Game storage game = games[tokenAddress];
        Player storage player = game.players[msg.sender];
        if (player.referredBy == address(0)) { // new player
            player.referredBy = referredBy != address(0) ? referredBy : dev;
        }

        uint netAmount = extractFees(game, amount, true);
        player.shares = player.shares.add(netAmount);
        return player.shares;
    }

    function withdraw(address tokenAddress) onlyDuringGame(tokenAddress) onlyActivePlayers(tokenAddress) public returns (uint) {
        Game storage game = games[tokenAddress];
        Player storage player = game.players[msg.sender];
        uint shares = player.shares;
        uint toWithdraw = extractFees(game, shares, false);
        TRC20 trc20 = TRC20(tokenAddress);
        trc20.transfer(msg.sender, toWithdraw);
        player.shares = 0;
        return toWithdraw;
    }

    function claim(address tokenAddress) onlyBetweenGames(tokenAddress) onlyActivePlayers(tokenAddress) public returns (uint) {
        return _claim(tokenAddress, msg.sender);
    }

    function _claim(address tokenAddress, address receiver) internal returns (uint) {
        Player storage player = games[tokenAddress].players[receiver];
        uint shares = player.shares;
        TRC20 trc20 = TRC20(tokenAddress);
        trc20.transfer(receiver, shares);
        player.shares = 0;
        return shares;
    }

    function claimableShares(address tokenAddress) public view returns (uint) {
        return games[tokenAddress].players[msg.sender].shares;
    }

    function sellableShares(address tokenAddress) public view returns (uint) {
        return games[tokenAddress].players[msg.sender].shares.percentage(90); // total 10% fee will be applied if player sells.
    }

    function addToGame(address tokenAddress, uint amount) onlyDuringGame(tokenAddress) public {
        GameContract gameContract = GameContract(games[tokenAddress].gameAddress);
        require(amount > gameContract.minimumDeposit(), "Insufficient tokens to add.");
        gameContract.deposit(amount); // TODO: make sure this call works
    }

    //// ADMIN FUNCTIONS ////
    function startGame(address tokenAddress, uint daysToRun) onlyAdmins() onlyBetweenGames(tokenAddress) public {
        Game storage game = games[tokenAddress];
        require(block.timestamp >= game.gameEndsOn + WAITING_PERIOD, "A new game cannot begin until players have had enough time to collect their earnings from the last game.");
        require(daysToRun > 0, "Cannot run a game for 0 days.");
        game.gameEndsOn = block.timestamp.add(daysToRun.mul(SECONDS_PER_DAY));
        
        GameContract gameContract = GameContract(game.gameAddress);
        TRC20 trc20 = TRC20(game.tokenAddress);
        uint seed = trc20.balanceOf(address(this));

        if (seed >= gameContract.minimumDeposit()) {
            gameContract.deposit(seed);
        }

        for (uint i=0; i<game._players.length; i++) {
            game.players[game._players[i]].shares = 0;
        }
    }

    function endGame(address tokenAddress) onlyAdmins() onlyDuringGame(tokenAddress) public {
        Game storage game = games[tokenAddress];
        game.gameEndsOn = block.timestamp; // TODO: onlyDuringGame() will fail here... really truly absolutely must use gameStarted bool

        // Dev is always a player, but never a winner.
        _claim(tokenAddress, dev);

        GameContract gameContract = GameContract(game.gameAddress);
        uint claimedRewards = gameContract.claim();

        TRC20 trc20 = TRC20(game.tokenAddress);
        uint balance = trc20.balanceOf(address(this));
        for (uint i=0; i< game._players.length; i++) {
            Player storage player = game.players[game._players[i]];
            uint newShares = player.shares.div(balance).mul(claimedRewards);
            player.shares = player.shares.add(newShares);
        }
    }

    function registerAdmin(address addr, bool isAdmin) onlyAdmins() public {
        require(addr != dev, "The dev will always be an Administrator.");
        admin[addr] = isAdmin;
    }

    function registerGame(address gameAddress) onlyAdmins() public {
        GameContract gameContract = GameContract(gameAddress);
        address tokenAddress = gameContract.tokenAddress();
        Game storage game = games[tokenAddress];
        
        require(game.gameEndsOn < block.timestamp, "A game is currently running.");
        game.gameAddress = gameAddress;
        game.tokenAddress = tokenAddress;
        // leave players alone, so they can still claim any possible rewards if we're changing gameAddresses on a token.
    }

    //// INTERNAL ////
    function extractFees(Game storage game, uint amount, bool shouldPayReferrer) internal returns (uint) {
        uint toPool = amount.percentage(4);
        uint toDivs = amount.percentage(4);
        uint toReferral = amount.percentage(2);

        if (shouldPayReferrer) {
            payReferral(game, game.players[msg.sender].referredBy, toReferral);
        } else {
            toPool = toPool.add(toReferral);
            toReferral = 0;
        }

        payDividends(game, msg.sender, toDivs);
        payPool(game, toPool);


        uint netAmount = amount.sub(toPool).sub(toDivs).sub(toReferral);

        return netAmount;
    }

    function payDividends(Game storage game, address exclude, uint dividends) internal {
        // TODO
    }

    function payPool(Game storage game, uint amount) internal {
        // TODO
        // hold amount in ledger. if ledger > threshold for poolContract, send. (50 for opals staking)
        addToGame(game.tokenAddress, amount);
    }

    function payReferral(Game storage game, address referrer, uint amount) internal {
        if (game.players[referrer].shares > 0) {
            payPlayer(game, referrer, amount);
        } else {
            payPlayer(game, dev, amount);
        }
    }

    function payPlayer(Game storage game, address player, uint amount) internal {
        game.players[player].shares = game.players[player].shares.add(amount);
    }

    //// MODIFIERS ////
    modifier onlyActivePlayers(address tokenAddress) {
        require(games[tokenAddress].players[msg.sender].shares > 0, "You are not eligible.");
        _;
    }

    modifier onlyAdmins() {
        require(admin[msg.sender], "Only an Administrator can perform this action.");
        _;
    }

    modifier onlyDuringGame(address tokenAddress) {
        require(games[tokenAddress].gameEndsOn > block.timestamp, "A game is not running.");
        _;
    }

    modifier onlyBetweenGames(address tokenAddress) {
        require(games[tokenAddress].gameEndsOn <= block.timestamp, "A game is currently running.");
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
