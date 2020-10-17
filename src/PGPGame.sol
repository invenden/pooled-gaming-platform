pragma solidity ^0.5.10;

interface PGPGame {
    function tokenAddress() external view returns (address);
    function deposit(uint256 amount) external returns (bool success);
    function withdraw() external returns (uint256 amount);
    function claim() external returns (uint256 amount);
}
