// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/**
 * @title IIdentityRegistry
 * @dev Interface for the Identity Registry which manages the mapping between
 *      investor wallet addresses and their on-chain identity contracts,
 *      verifying that identities hold the required claims to participate in token transfers.
 */
interface IIdentityRegistry {
    event IdentityRegistered(address indexed investorAddress, address indexed identity);
    event IdentityRemoved(address indexed investorAddress, address indexed identity);
    event IdentityUpdated(address indexed oldIdentity, address indexed newIdentity);
    event CountryUpdated(address indexed investorAddress, uint16 indexed country);

    function registerIdentity(
        address _userAddress,
        address _identity,
        uint16 _country
    ) external;

    function deleteIdentity(address _userAddress) external;

    function updateIdentity(address _userAddress, address _identity) external;

    function updateCountry(address _userAddress, uint16 _country) external;

    function isVerified(address _userAddress) external view returns (bool);

    function identity(address _userAddress) external view returns (address);

    function investorCountry(address _userAddress) external view returns (uint16);

    function claimTopicsRegistry() external view returns (address);

    function trustedIssuersRegistry() external view returns (address);

    function contains(address _userAddress) external view returns (bool);
}
