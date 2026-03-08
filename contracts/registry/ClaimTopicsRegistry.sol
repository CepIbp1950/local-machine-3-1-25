// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IClaimTopicsRegistry.sol";

/**
 * @title ClaimTopicsRegistry
 * @dev Stores the required claim topics for investor verification.
 *      Tokens using ERC-3643 require investors to hold claims matching
 *      all topics registered here, issued by a trusted issuer.
 */
contract ClaimTopicsRegistry is IClaimTopicsRegistry, Ownable {
    uint256[] private _claimTopics;
    mapping(uint256 => bool) private _requiredTopics;

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Adds a required claim topic.
     * @param _claimTopic The topic identifier to add.
     */
    function addClaimTopic(uint256 _claimTopic) external override onlyOwner {
        require(!_requiredTopics[_claimTopic], "ClaimTopicsRegistry: topic already exists");
        _claimTopics.push(_claimTopic);
        _requiredTopics[_claimTopic] = true;
        emit ClaimTopicAdded(_claimTopic);
    }

    /**
     * @dev Removes a required claim topic.
     * @param _claimTopic The topic identifier to remove.
     */
    function removeClaimTopic(uint256 _claimTopic) external override onlyOwner {
        require(_requiredTopics[_claimTopic], "ClaimTopicsRegistry: topic does not exist");
        _requiredTopics[_claimTopic] = false;
        uint256 length = _claimTopics.length;
        for (uint256 i = 0; i < length; i++) {
            if (_claimTopics[i] == _claimTopic) {
                _claimTopics[i] = _claimTopics[length - 1];
                _claimTopics.pop();
                break;
            }
        }
        emit ClaimTopicRemoved(_claimTopic);
    }

    /**
     * @dev Returns all required claim topics.
     */
    function getClaimTopics() external view override returns (uint256[] memory) {
        return _claimTopics;
    }

    /**
     * @dev Checks whether a given claim topic is required.
     * @param _claimTopic The topic identifier to check.
     */
    function isClaimTopicRequired(uint256 _claimTopic) external view override returns (bool) {
        return _requiredTopics[_claimTopic];
    }
}
