pragma solidity ^0.5.10;

import './Administratable.sol';

contract Auditable is Administratable {
    mapping(address=>bool) private auditor;

    event AuditorGranted(address indexed newAuditor);
    event AuditorRevoked(address indexed oldAuditor);

    constructor() internal {
        auditor[_msgSender()] = true;
        emit AuditorGranted(_msgSender());
    }

    function grantAuditor(address newAuditor) onlyAdmins public {
        auditor[newAuditor] = true;
        emit AuditorGranted(newAuditor);
    }

    function revokeAuditor(address oldAuditor) onlyAdmins public {
        require(oldAuditor != owner, "Audtiable: The owner will always be an Auditor.");
        auditor[oldAuditor] = false;
        emit AuditorRevoked(oldAuditor);
    }

    function isAuditor() public view returns (bool) {
        return auditor[_msgSender()];
    }

    modifier onlyAuditors() {
        require(isAuditor() || isAdmin(), "Auditable: Only an Auditor can perform this action.");
        _;
    }
}
