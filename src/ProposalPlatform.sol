pragma solidity ^0.5.10;

import './Auditable.sol';
import './ITRC20.sol';
import './PGPGame.sol';
import './SafeMath.sol';

contract ProposalPlatform is Auditable {
    using SafeMath for uint256;

    ITRC20 public pgp;

    /** @dev a single voter can only cast 100 PGP at a proposal. */
    uint constant public MAX_VOTES_PER_PROPOSAL = 100 * 10 ** 18; // 100 PGP

    // AUTONOMOUS MODE
    /** @dev if the threshold is met, a proposal can be enacted without admin approval. */
    uint constant public AUTONOMOUS_THRESHOLD = 2000 * 10 ** 18; // 2000 PGP

    /** @dev if threshold is met, 3 days must pass before proposal can be enacted without an admin. This is to protect against malicious activity by large bag holders. */
    uint constant public AUTONOMOUS_WAITING_PERIOD = 3 days;

    constructor(address votingToken) internal {
        pgp = ITRC20(votingToken);
    }

    event VoteRecorded(uint pid, bool inFavor, address indexed gameAddress);
    event AutonomousThresholdReached(uint pId, address indexed gameAddress);
    event AuditAccepted(uint pId, address indexed gameAddress, address indexed auditedBy);
    event AuditRejected(uint pId, address indexed gameAddress, address indexed auditedBy);
    event ProposalAccepted(uint pId, address indexed gameAddress);
    event ProposalRejected(uint pId, address indexed gameAddress);

    struct Proposal {
        uint pId;
        uint proposedOn;
        uint thresholdMetOn;
        PGPGame game;
        address gameAddress;
        uint daysToRun;
        bool isVotingClosed;
        bool isAccepted;
        bool isAudited;
        mapping(address => uint) acceptedVotes;
        mapping(address => uint) rejectedVotes;
        uint numAccepted;
        uint numRejected;
    }

    mapping(uint => Proposal) public proposals; // lazy array since we never delete
    uint numProposals;

    ///// INFORMATION /////
    function isProposalActive(uint pId) proposed(pId) public view returns (bool) {
        Proposal storage proposal = proposals[pId];
        return !proposal.isVotingClosed;
    }

    ///// VOTERS /////
    function proposeGame(address gameAddress, uint daysToRun) public {
        // TODO: Costs ... 1000 PGP to propose a game? goes to seed for players?
        PGPGame game = PGPGame(gameAddress);

        uint pId = numProposals++;
        Proposal storage proposal = proposals[pId];
        proposal.game = game;
        proposal.gameAddress = gameAddress;
        proposal.daysToRun = daysToRun;
        proposal.proposedOn = block.timestamp;
    }

    function voteForProposal(uint pId, uint votingStake) activeProposals(pId) voters(votingStake) public {
        Proposal storage proposal = proposals[pId];
        uint totalStake = proposal.acceptedVotes[_msgSender()].add(votingStake);
        require(totalStake <= MAX_VOTES_PER_PROPOSAL, "ProposalPlatform: Your voting stake cannot exceed the maximum per person.");

        proposal.numAccepted = proposal.numAccepted.add(votingStake);
        pgp.transferFrom(_msgSender(), address(this), votingStake);

        if (proposal.numAccepted >= AUTONOMOUS_THRESHOLD && proposal.thresholdMetOn == 0) {
            proposal.thresholdMetOn = block.timestamp;
            emit AutonomousThresholdReached(pId, proposal.gameAddress);
        }

        emit VoteRecorded(pId, true, proposal.gameAddress);
    }

    function voteAgainstProposal(uint pId, uint votingStake) activeProposals(pId) voters(votingStake) public {
        Proposal storage proposal = proposals[pId];
        uint totalStake = proposal.rejectedVotes[_msgSender()].add(votingStake);
        require(totalStake <= MAX_VOTES_PER_PROPOSAL, "ProposalPlatform: Your voting stake cannot exceed the maximum per person.");

        proposal.numRejected = proposal.numRejected.add(votingStake);
        pgp.transferFrom(_msgSender(), address(this), votingStake);

        if (proposal.numRejected >= AUTONOMOUS_THRESHOLD && proposal.thresholdMetOn == 0) {
            proposal.thresholdMetOn = block.timestamp;
            emit AutonomousThresholdReached(pId, proposal.gameAddress);
        }

        emit VoteRecorded(pId, false, proposal.gameAddress);
    }

    function finalizeProposal(uint pId) activeProposals(pId) public {
        Proposal storage proposal = proposals[pId];
        require(canFinalizeProposal(proposal), "ProposalPlatform: You cannot finalize this proposal yet.");

        _finalizeProposal(proposal, proposal.numAccepted > proposal.numRejected);
    }

    ///// AUDITORS /////
    function auditAcceptProposal(uint pId) activeProposals(pId) onlyAuditors public {
        Proposal storage proposal = proposals[pId];
        proposal.isAudited = true;
        emit AuditAccepted(pId, proposal.gameAddress, _msgSender());
    }

    function auditRejectProposal(uint pId) activeProposals(pId) onlyAuditors public {
        Proposal storage proposal = proposals[pId];
        proposal.isAudited = true; // TODO: Is this enough for display purposes?
        emit AuditRejected(pId, proposal.gameAddress, _msgSender());
        
        _finalizeProposal(proposal, false);
    }

    ///// ADMIN /////
    function adminAcceptProposal(uint pId) activeProposals(pId) onlyAdmins public {
        Proposal storage proposal = proposals[pId];
        _finalizeProposal(proposal, true);
    }

    ///// MISC HELPERS /////
    function canFinalizeProposal(Proposal memory proposal) internal view returns (bool) {
        if (isAdmin()) {
            return true;
        }

        if (proposal.thresholdMetOn == 0) {
            return false;
        }

        return block.timestamp >= proposal.thresholdMetOn.add(AUTONOMOUS_WAITING_PERIOD);
    }

    function _finalizeProposal(Proposal memory proposal, bool isAccepted) internal {
        proposal.isVotingClosed = true;
        proposal.isAccepted = isAccepted;

        if (isAccepted) {
            // TODO: refund all Nay voters
            emit ProposalAccepted(proposal.pId, proposal.gameAddress);
        } else {
            // TODO: refund all voters
            emit ProposalRejected(proposal.pId, proposal.gameAddress);
        }
    }

    ///// MODIFIERS /////
    modifier activeProposals(uint pId) {
        Proposal memory proposal = proposals[pId];
        require(isProposalActive(pId), "ProposalPlatform: This proposal is no longer accepting votes.");
        _;
    }

    modifier proposed(uint pId) {
        require(proposals[pId].pId != 0, "ProposalPlatform: The proposal does not exist yet.");
        _;
    }

    modifier voters(uint votingStake) {
        require(pgp.balanceOf(_msgSender()) >= votingStake, "ProposalPlatform: You do not have sufficient voting power.");
        require(pgp.allowance(_msgSender(), address(this)) >= votingStake, "ProposalPlatform: You must approve the platform for voting.");
        require(votingStake <= MAX_VOTES_PER_PROPOSAL, "ProposalPlatform: Your voting stake cannot exceed the maximum per person.");
        _;
    }
}
