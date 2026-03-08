// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IIdentityRegistry.sol";
import "../interfaces/IClaimTopicsRegistry.sol";
import "../interfaces/ITrustedIssuersRegistry.sol";

/**
 * @title IdentityRegistry
 * @dev Manages the mapping between investor wallet addresses and their verified
 *      on-chain identities. Verifies that investors hold the required claims from
 *      trusted issuers in order to be eligible for token transfers.
 *
 *      In a full ERC-3643 / ONCHAINID deployment, the `_identity` addresses
 *      would be ERC-734/735 identity contracts. For this demo the registry
 *      accepts any non-zero address as a valid identity and trusts the
 *      deployer to register only genuinely KYC-verified investors.
 */
contract IdentityRegistry is IIdentityRegistry, Ownable {
    // investor wallet -> identity contract
    mapping(address => address) private _identities;
    // investor wallet -> ISO 3166-1 alpha-2 country code (numeric)
    mapping(address => uint16) private _investorCountries;

    address private _claimTopicsRegistry;
    address private _trustedIssuersRegistry;

    // roles
    mapping(address => bool) private _agents;

    modifier onlyAgent() {
        require(_agents[msg.sender] || msg.sender == owner(), "IdentityRegistry: caller is not an agent");
        _;
    }

    constructor(
        address claimTopicsRegistry_,
        address trustedIssuersRegistry_
    ) Ownable(msg.sender) {
        require(claimTopicsRegistry_ != address(0), "IdentityRegistry: zero address for CTR");
        require(trustedIssuersRegistry_ != address(0), "IdentityRegistry: zero address for TIR");
        _claimTopicsRegistry = claimTopicsRegistry_;
        _trustedIssuersRegistry = trustedIssuersRegistry_;
    }

    // -------------------------------------------------------------------------
    // Agent management
    // -------------------------------------------------------------------------

    function addAgent(address _agent) external onlyOwner {
        _agents[_agent] = true;
    }

    function removeAgent(address _agent) external onlyOwner {
        _agents[_agent] = false;
    }

    // -------------------------------------------------------------------------
    // IIdentityRegistry
    // -------------------------------------------------------------------------

    function registerIdentity(
        address _userAddress,
        address _identity,
        uint16 _country
    ) external override onlyAgent {
        require(_userAddress != address(0), "IdentityRegistry: zero user address");
        require(_identity != address(0), "IdentityRegistry: zero identity address");
        require(_identities[_userAddress] == address(0), "IdentityRegistry: identity already registered");

        _identities[_userAddress] = _identity;
        _investorCountries[_userAddress] = _country;
        emit IdentityRegistered(_userAddress, _identity);
    }

    function deleteIdentity(address _userAddress) external override onlyAgent {
        require(_identities[_userAddress] != address(0), "IdentityRegistry: identity not found");
        address old = _identities[_userAddress];
        delete _identities[_userAddress];
        delete _investorCountries[_userAddress];
        emit IdentityRemoved(_userAddress, old);
    }

    function updateIdentity(address _userAddress, address _identity) external override onlyAgent {
        require(_identities[_userAddress] != address(0), "IdentityRegistry: identity not found");
        require(_identity != address(0), "IdentityRegistry: zero identity address");
        address old = _identities[_userAddress];
        _identities[_userAddress] = _identity;
        emit IdentityUpdated(old, _identity);
    }

    function updateCountry(address _userAddress, uint16 _country) external override onlyAgent {
        require(_identities[_userAddress] != address(0), "IdentityRegistry: identity not found");
        _investorCountries[_userAddress] = _country;
        emit CountryUpdated(_userAddress, _country);
    }

    /**
     * @dev Returns true when the investor is registered.
     *      A full implementation would also verify that the identity contract
     *      holds valid claims for every required topic from trusted issuers.
     *      For this demo, presence in the registry is treated as verified.
     */
    function isVerified(address _userAddress) external view override returns (bool) {
        if (_identities[_userAddress] == address(0)) {
            return false;
        }

        // Check required claim topics — in this demo any registered identity
        // is considered to satisfy all topics (full ONCHAINID integration
        // would call into the identity contract to verify each claim).
        uint256[] memory topics = IClaimTopicsRegistry(_claimTopicsRegistry).getClaimTopics();
        if (topics.length == 0) {
            return true;
        }

        address[] memory issuers = ITrustedIssuersRegistry(_trustedIssuersRegistry).getTrustedIssuers();
        if (issuers.length == 0) {
            return false;
        }

        // Verify that at least one trusted issuer covers every required topic
        for (uint256 t = 0; t < topics.length; t++) {
            bool topicCovered = false;
            for (uint256 i = 0; i < issuers.length; i++) {
                if (ITrustedIssuersRegistry(_trustedIssuersRegistry).hasClaimTopic(issuers[i], topics[t])) {
                    topicCovered = true;
                    break;
                }
            }
            if (!topicCovered) {
                return false;
            }
        }

        return true;
    }

    function identity(address _userAddress) external view override returns (address) {
        return _identities[_userAddress];
    }

    function investorCountry(address _userAddress) external view override returns (uint16) {
        return _investorCountries[_userAddress];
    }

    function claimTopicsRegistry() external view override returns (address) {
        return _claimTopicsRegistry;
    }

    function trustedIssuersRegistry() external view override returns (address) {
        return _trustedIssuersRegistry;
    }

    function contains(address _userAddress) external view override returns (bool) {
        return _identities[_userAddress] != address(0);
    }
}
