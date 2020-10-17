pragma solidity ^0.5.10;

interface TRC20 {
    function totalSupply() external view returns (uint);
    function balanceOf(address tokenOwner) external view returns (uint256 balance);
    function allowance(address owner, address spender) external  view returns (uint256 remaining);
    function transfer(address recipient, uint256 amount) external returns (bool success);
    function approve(address spender, uint256 amount) external  returns (bool success);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool success);
}
