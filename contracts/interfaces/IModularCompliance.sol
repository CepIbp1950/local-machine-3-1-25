// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/**
 * @title IModularCompliance
 * @dev Interface for the Modular Compliance contract which enforces transfer
 *      restrictions through pluggable compliance modules.
 */
interface IModularCompliance {
    event ModuleAdded(address indexed _module);
    event ModuleRemoved(address indexed _module);
    event TokenBound(address indexed _token);

    function bindToken(address _token) external;
    function addModule(address _module) external;
    function removeModule(address _module) external;
    function isModuleBound(address _module) external view returns (bool);
    function getModules() external view returns (address[] memory);
    function canTransfer(address _from, address _to, uint256 _amount) external view returns (bool);
    function transferred(address _from, address _to, uint256 _amount) external;
    function created(address _to, uint256 _amount) external;
    function destroyed(address _from, uint256 _amount) external;
    function token() external view returns (address);
}
