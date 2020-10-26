pragma solidity ^0.5.10;

import './Ownable.sol';

contract Administratable is Ownable {
    mapping(address=>bool) private admin;

    event AdminGranted(address indexed newAdmin);
    event AdminRevoked(address indexed oldAdmin);

    constructor() internal {
        admin[_msgSender()] = true;
        emit AdminGranted(_msgSender());
    }

    function grantAdmin(address newAdmin) onlyAdmins public {
        admin[newAdmin] = true;
        emit AdminGranted(newAdmin);
    }

    function revokeAdmin(address oldAdmin) onlyAdmins public {
        require(oldAdmin != owner, "Administratable: The owner will always be an Administrator.");
        admin[oldAdmin] = false;
        emit AdminRevoked(oldAdmin);
    }

    function isAdmin() public view returns (bool) {
        return admin[_msgSender()];
    }

    modifier onlyAdmins() {
        require(isAdmin(), "Administratable: Only an Administrator can perform this action.");
        _;
    }
}
