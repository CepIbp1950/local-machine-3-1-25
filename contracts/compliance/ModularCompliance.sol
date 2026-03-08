// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IModularCompliance.sol";

/**
 * @title ModularCompliance
 * @dev Enforces transfer restrictions through pluggable compliance modules.
 *      Each module can implement custom rules (e.g. investor limits, country
 *      restrictions, lock-up periods). All modules must approve a transfer
 *      for it to be allowed.
 */
contract ModularCompliance is IModularCompliance, Ownable {
    address private _token;
    address[] private _modules;
    mapping(address => bool) private _moduleBound;

    modifier onlyToken() {
        require(msg.sender == _token, "ModularCompliance: caller is not the token");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Binds a token to this compliance contract. Can only be called once.
     */
    function bindToken(address _tokenAddress) external override onlyOwner {
        require(_tokenAddress != address(0), "ModularCompliance: zero address");
        _token = _tokenAddress;
        emit TokenBound(_tokenAddress);
    }

    /**
     * @dev Adds a compliance module.
     */
    function addModule(address _module) external override onlyOwner {
        require(_module != address(0), "ModularCompliance: zero address");
        require(!_moduleBound[_module], "ModularCompliance: module already bound");
        _modules.push(_module);
        _moduleBound[_module] = true;
        emit ModuleAdded(_module);
    }

    /**
     * @dev Removes a compliance module.
     */
    function removeModule(address _module) external override onlyOwner {
        require(_moduleBound[_module], "ModularCompliance: module not bound");
        _moduleBound[_module] = false;
        uint256 length = _modules.length;
        for (uint256 i = 0; i < length; i++) {
            if (_modules[i] == _module) {
                _modules[i] = _modules[length - 1];
                _modules.pop();
                break;
            }
        }
        emit ModuleRemoved(_module);
    }

    /**
     * @dev Checks whether all bound compliance modules approve the transfer.
     */
    function canTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) external view override returns (bool) {
        for (uint256 i = 0; i < _modules.length; i++) {
            (bool success, bytes memory result) = _modules[i].staticcall(
                abi.encodeWithSignature("canTransfer(address,address,uint256)", _from, _to, _amount)
            );
            if (!success || !abi.decode(result, (bool))) {
                return false;
            }
        }
        return true;
    }

    function transferred(address _from, address _to, uint256 _amount) external override onlyToken {
        for (uint256 i = 0; i < _modules.length; i++) {
            // best-effort; ignore revert so one bad module does not brick transfers
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = _modules[i].call(
                abi.encodeWithSignature("moduleTransferAction(address,address,uint256)", _from, _to, _amount)
            );
            success; // silence unused-variable warning
        }
    }

    function created(address _to, uint256 _amount) external override onlyToken {
        for (uint256 i = 0; i < _modules.length; i++) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = _modules[i].call(
                abi.encodeWithSignature("moduleMintAction(address,uint256)", _to, _amount)
            );
            success;
        }
    }

    function destroyed(address _from, uint256 _amount) external override onlyToken {
        for (uint256 i = 0; i < _modules.length; i++) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = _modules[i].call(
                abi.encodeWithSignature("moduleBurnAction(address,uint256)", _from, _amount)
            );
            success;
        }
    }

    function isModuleBound(address _module) external view override returns (bool) {
        return _moduleBound[_module];
    }

    function getModules() external view override returns (address[] memory) {
        return _modules;
    }

    function token() external view override returns (address) {
        return _token;
    }
}
