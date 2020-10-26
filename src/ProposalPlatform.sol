pragma solidity ^0.5.10;

import './Auditable.sol';

contract ProposalPlatform is Auditable {
    constructor() internal {}

    struct Proposal {
        uint proposalId; // just its index in the array
        address gameAddress;
        address tokenAddress;
        uint daysToRun;
        bool isVotingClosed;
        bool isAccepted;
        bool isAudited;
        mapping(address => uint) votes;
        uint numAccepted;
        uint numRejected;
    }

    Proposal[] public proposals;

    ///// VOTERS /////

    ///// AUDITORS /////

    ///// ADMIN /////
}
