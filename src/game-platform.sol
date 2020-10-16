// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.5.12;

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
        uint toPool;
        uint endsOn;
        bool running;
        mapping(address=>Player) players;
        uint numPlayers;
        address[] _players;
    }

    address internal dev;
    mapping(address=>bool) admin;
    mapping(address=>Game) games;
    uint constant WAITING_PERIOD = SECONDS_PER_DAY * 2;
    uint constant SECONDS_PER_DAY = 86400;

    constructor() public {
        dev = msg.sender;
        admin[dev] = true;
    }

    //// PLAYER FUNCTIONS ////
    function deposit(address tokenAddress, uint amount, address referredBy) onlyDuringGame(tokenAddress) public returns (uint) {
        require(amount > 0, "Cannot purchase 0 tokens.");
        Game storage game = games[tokenAddress];
        Player storage player = game.players[msg.sender];
        if (player.referredBy == address(0)) { // new player
            player.referredBy = referredBy != address(0) && referredBy != msg.sender ? referredBy : dev;
        }

        if (player.shares == 0) {
            // recycle array instead of actually deleting to conserve energy
            if (game._players.length == game.numPlayers) {
                game._players.length += 1;
            }
            game._players[game.numPlayers++] = msg.sender;
        }

        TRC20 trc20 = TRC20(game.tokenAddress);
        require(trc20.transferFrom(msg.sender, address(this), amount));
        uint netAmount = extractFees(game, amount, true);
        player.shares = player.shares.add(netAmount);
        return player.shares;
    }

    function withdraw(address tokenAddress) onlyDuringGame(tokenAddress) onlyActivePlayers(tokenAddress) public returns (uint) {
        Game storage game = games[tokenAddress];
        Player storage player = game.players[msg.sender];
        uint shares = extractFees(game, player.shares, false);
        TRC20 trc20 = TRC20(tokenAddress);
        uint toWithdraw = shares > trc20.balanceOf(address(this)) ? trc20.balanceOf(address(this)) : shares;
        trc20.transfer(msg.sender, toWithdraw);
        player.shares = 0;
        return toWithdraw;
    }

    function claim(address tokenAddress) onlyBetweenGames(tokenAddress) onlyActivePlayers(tokenAddress) public returns (uint) {
        return _claim(tokenAddress, msg.sender);
    }

    function _claim(address tokenAddress, address receiver) internal returns (uint) {
        Player storage player = games[tokenAddress].players[receiver];
        TRC20 trc20 = TRC20(tokenAddress);
        uint shares = player.shares > trc20.balanceOf(address(this)) ? trc20.balanceOf(address(this)) : player.shares;
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
        gameContract.deposit(amount);
    }

    function getRegisteredGame(address tokenAddress) public view returns (address gameAddress, uint endsOn, uint numPlayers) {
        Game storage game = games[tokenAddress];
        return (game.gameAddress, game.endsOn, game.numPlayers);
    }

    //// ADMIN FUNCTIONS ////
    function startGame(address tokenAddress, uint daysToRun) onlyAdmins() onlyBetweenGames(tokenAddress) public {
        Game storage game = games[tokenAddress];
        require(block.timestamp >= game.endsOn + WAITING_PERIOD, "A new game cannot begin until players have had enough time to collect their earnings from the last game.");
        require(daysToRun > 0, "Cannot run a game for 0 days.");
        game.endsOn = block.timestamp.add(daysToRun.mul(SECONDS_PER_DAY));
        game.running = true;
        game.toPool = 0;
        TRC20 trc20 = TRC20(game.tokenAddress);
        uint seed = trc20.balanceOf(address(this));

        payPool(game, seed);

        for (uint i=0; i<game.numPlayers; i++) {
            game.players[game._players[i]].shares = 0;
        }
        game.numPlayers = 1;
        game._players[0] = dev;
    }

    function endGame(address tokenAddress) onlyAdmins() onlyDuringGame(tokenAddress) public {
        Game storage game = games[tokenAddress];
        game.endsOn = block.timestamp;
        game.running = false;

        // Dev is always a player, but never a winner.
        _claim(tokenAddress, dev);

        GameContract gameContract = GameContract(game.gameAddress);
        uint claimedRewards = gameContract.claim();

        payDividends(game, dev, claimedRewards);
    }

    function registerAdmin(address addr, bool isAdmin) onlyAdmins() public {
        require(addr != dev, "The dev will always be an Administrator.");
        admin[addr] = isAdmin;
    }

    function registerGame(address gameAddress) onlyAdmins() public {
        GameContract gameContract = GameContract(gameAddress);
        address tokenAddress = gameContract.tokenAddress();
        Game storage game = games[tokenAddress];
        
        require(!game.running, "A game is currently running.");
        game.gameAddress = gameAddress;
        game.tokenAddress = tokenAddress;
    }

    function collectDivs(address tokenAddress) onlyDuringGame(tokenAddress) public {
        Game storage game = games[tokenAddress];
        GameContract gameContract = GameContract(game.gameAddress);
        uint divs = gameContract.withdraw();
        payDividends(game, address(0), divs);
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

        payPool(game, toPool);
        payDividends(game, msg.sender, toDivs);

        uint netAmount = amount.sub(toPool).sub(toDivs).sub(toReferral);

        return netAmount;
    }

    function payDividends(Game storage game, address exclude, uint dividends) internal {
        TRC20 trc20 = TRC20(game.tokenAddress);
        uint balance = trc20.balanceOf(address(this)).sub(dividends).sub(game.players[exclude].shares);

        for (uint i=0; i< game.numPlayers; i++) {
            if(game._players[i] == exclude) continue;

            Player storage player = game.players[game._players[i]];
            uint newShares = player.shares.div(balance).mul(dividends);
            player.shares = player.shares.add(newShares);
        }
    }

    function payPool(Game storage game, uint amount) internal {
        game.toPool = game.toPool.add(amount);
        GameContract gameContract = GameContract(game.gameAddress);
        if (game.toPool >= gameContract.minimumDeposit()) {
            gameContract.deposit(game.toPool);
            game.toPool = 0;
        }
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
        require(games[tokenAddress].gameAddress != address(0), "There are no games for this token.");
        require(games[tokenAddress].running, "A game is not running.");
        _;
    }

    modifier onlyBetweenGames(address tokenAddress) {
        require(games[tokenAddress].gameAddress != address(0), "There are no games for this token.");
        require(!games[tokenAddress].running, "A game is currently running.");
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
