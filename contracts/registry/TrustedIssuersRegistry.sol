// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ITrustedIssuersRegistry.sol";

/**
 * @title TrustedIssuersRegistry
 * @dev Maintains the list of trusted claim issuers and the claim topics
 *      they are authorized to certify. Only claims from trusted issuers
 *      for the corresponding topics are accepted during investor verification.
 */
contract TrustedIssuersRegistry is ITrustedIssuersRegistry, Ownable {
    address[] private _trustedIssuers;
    mapping(address => bool) private _isTrusted;
    mapping(address => uint256[]) private _issuerClaimTopics;
    mapping(address => mapping(uint256 => bool)) private _issuerHasTopic;

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Adds a trusted issuer and the claim topics it can certify.
     */
    function addTrustedIssuer(
        address _trustedIssuer,
        uint256[] calldata _claimTopics
    ) external override onlyOwner {
        require(_trustedIssuer != address(0), "TrustedIssuersRegistry: zero address");
        require(!_isTrusted[_trustedIssuer], "TrustedIssuersRegistry: already trusted");
        require(_claimTopics.length > 0, "TrustedIssuersRegistry: empty claim topics");

        _trustedIssuers.push(_trustedIssuer);
        _isTrusted[_trustedIssuer] = true;
        _issuerClaimTopics[_trustedIssuer] = _claimTopics;

        for (uint256 i = 0; i < _claimTopics.length; i++) {
            _issuerHasTopic[_trustedIssuer][_claimTopics[i]] = true;
        }

        emit TrustedIssuerAdded(_trustedIssuer, _claimTopics);
    }

    /**
     * @dev Removes a trusted issuer.
     */
    function removeTrustedIssuer(address _trustedIssuer) external override onlyOwner {
        require(_isTrusted[_trustedIssuer], "TrustedIssuersRegistry: not a trusted issuer");

        _isTrusted[_trustedIssuer] = false;

        uint256[] memory topics = _issuerClaimTopics[_trustedIssuer];
        for (uint256 i = 0; i < topics.length; i++) {
            _issuerHasTopic[_trustedIssuer][topics[i]] = false;
        }
        delete _issuerClaimTopics[_trustedIssuer];

        uint256 length = _trustedIssuers.length;
        for (uint256 i = 0; i < length; i++) {
            if (_trustedIssuers[i] == _trustedIssuer) {
                _trustedIssuers[i] = _trustedIssuers[length - 1];
                _trustedIssuers.pop();
                break;
            }
        }

        emit TrustedIssuerRemoved(_trustedIssuer);
    }

    /**
     * @dev Updates the claim topics a trusted issuer is authorized to certify.
     */
    function updateIssuerClaimTopics(
        address _trustedIssuer,
        uint256[] calldata _claimTopics
    ) external override onlyOwner {
        require(_isTrusted[_trustedIssuer], "TrustedIssuersRegistry: not a trusted issuer");
        require(_claimTopics.length > 0, "TrustedIssuersRegistry: empty claim topics");

        uint256[] memory old = _issuerClaimTopics[_trustedIssuer];
        for (uint256 i = 0; i < old.length; i++) {
            _issuerHasTopic[_trustedIssuer][old[i]] = false;
        }

        _issuerClaimTopics[_trustedIssuer] = _claimTopics;
        for (uint256 i = 0; i < _claimTopics.length; i++) {
            _issuerHasTopic[_trustedIssuer][_claimTopics[i]] = true;
        }

        emit ClaimTopicsUpdated(_trustedIssuer, _claimTopics);
    }

    /**
     * @dev Returns all trusted issuers.
     */
    function getTrustedIssuers() external view override returns (address[] memory) {
        return _trustedIssuers;
    }

    /**
     * @dev Checks if an address is a trusted issuer.
     */
    function isTrustedIssuer(address _issuer) external view override returns (bool) {
        return _isTrusted[_issuer];
    }

    /**
     * @dev Returns the claim topics a trusted issuer can certify.
     */
    function getTrustedIssuerClaimTopics(
        address _trustedIssuer
    ) external view override returns (uint256[] memory) {
        require(_isTrusted[_trustedIssuer], "TrustedIssuersRegistry: not a trusted issuer");
        return _issuerClaimTopics[_trustedIssuer];
    }

    /**
     * @dev Checks if an issuer is trusted for a specific claim topic.
     */
    function hasClaimTopic(address _issuer, uint256 _claimTopic) external view override returns (bool) {
        return _isTrusted[_issuer] && _issuerHasTopic[_issuer][_claimTopic];
    }
}
