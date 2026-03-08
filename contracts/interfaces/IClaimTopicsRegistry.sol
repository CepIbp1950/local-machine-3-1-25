// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/**
 * @title IClaimTopicsRegistry
 * @dev Interface for the Claim Topics Registry which stores required claim topics
 *      that investors must hold in their identity to be eligible for token operations.
 */
interface IClaimTopicsRegistry {
    event ClaimTopicAdded(uint256 indexed claimTopic);
    event ClaimTopicRemoved(uint256 indexed claimTopic);

    function addClaimTopic(uint256 _claimTopic) external;
    function removeClaimTopic(uint256 _claimTopic) external;
    function getClaimTopics() external view returns (uint256[] memory);
    function isClaimTopicRequired(uint256 _claimTopic) external view returns (bool);
}
