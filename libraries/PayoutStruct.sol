pragma solidity =0.6.6;

library PayoutStruct {
    /* Internal storage structure */

    struct Round {
        mapping(address => TokenPayout) tokens;
        mapping(address => bytes32) agentHashes;
        mapping(address => bool) agentClaims;
        address[] tokenList;
        uint256 state;
        address creator;
        uint256 createTime;
        uint256 finishTime;
        address verifier;
        uint256 verifyTime;
        address approver;
        uint256 approveTime;
    }

    struct TokenPayout {
        uint256 totalPayout;
        uint256 claimedPayout;
        bool isAdded;
    }

    /* Used in caller input, because data cannot be mapping, change them to arrays */

    struct AgentPayoutInput {
        address agentAddr;
        uint256[] amounts;
    }

    /* For returning use */

    struct RoundSummary {
        TokenPayoutSummany[] tokenList;
        uint256 state;
        address creator;
        uint256 createTime;
        uint256 finishTime;
        address verifier;
        uint256 verifyTime;
        address approver;
        uint256 approveTime;
    }

    struct TokenPayoutSummany {
        address tokenAddr;
        uint256 totalPayout;
        uint256 claimedPayout;
    }
}
