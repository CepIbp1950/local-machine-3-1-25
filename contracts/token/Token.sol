// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IERC3643.sol";
import "../interfaces/IIdentityRegistry.sol";
import "../interfaces/IModularCompliance.sol";

/**
 * @title Token
 * @dev ERC-3643 compliant security token.
 *
 *      Transfer rules enforced:
 *      1. Token must not be paused.
 *      2. Sender must not be frozen (unless minting from address(0)).
 *      3. Sender must have sufficient unfrozen balance.
 *      4. Recipient must be a verified investor in the IdentityRegistry.
 *      5. All bound compliance modules must approve the transfer.
 */
contract Token is IERC3643, ERC20, Ownable {
    string private _version;
    address private _onchainID;
    address private _identityRegistry;
    address private _compliance;

    bool private _paused;

    mapping(address => bool) private _frozen;
    mapping(address => uint256) private _frozenTokens;

    // agents can mint, burn, freeze, and force-transfer
    mapping(address => bool) private _agents;

    modifier whenNotPaused() {
        require(!_paused, "Token: token is paused");
        _;
    }

    modifier onlyAgent() {
        require(_agents[msg.sender] || msg.sender == owner(), "Token: caller is not an agent");
        _;
    }

    constructor(
        address identityRegistry_,
        address compliance_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address onchainID_
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        require(identityRegistry_ != address(0), "Token: zero address for identity registry");
        require(compliance_ != address(0), "Token: zero address for compliance");

        _identityRegistry = identityRegistry_;
        _compliance = compliance_;
        _onchainID = onchainID_;
        _version = "4.0";
        // Store custom decimals — ERC20 hard-codes 18; we override decimals()
        _customDecimals = decimals_;

        emit IdentityRegistryAdded(identityRegistry_);
        emit ComplianceAdded(compliance_);
    }

    // -------------------------------------------------------------------------
    // Custom decimals support
    // -------------------------------------------------------------------------

    uint8 private _customDecimals;

    function decimals() public view override returns (uint8) {
        return _customDecimals;
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
    // IERC3643 view
    // -------------------------------------------------------------------------

    function onchainID() external view override returns (address) { return _onchainID; }
    function version() external view override returns (string memory) { return _version; }
    function identityRegistry() external view override returns (address) { return _identityRegistry; }
    function compliance() external view override returns (address) { return _compliance; }
    function paused() external view override returns (bool) { return _paused; }
    function isFrozen(address _userAddress) external view override returns (bool) { return _frozen[_userAddress]; }
    function getFrozenTokens(address _userAddress) external view override returns (uint256) { return _frozenTokens[_userAddress]; }

    // -------------------------------------------------------------------------
    // IERC3643 admin setters
    // -------------------------------------------------------------------------

    function setName(string calldata _name) external override onlyOwner {
        // ERC20 does not expose an external setter — store via custom slot not available;
        // emit event to signal the update intent (full implementation would use a proxy)
        emit UpdatedTokenInformation(_name, symbol(), decimals(), _version, _onchainID);
    }

    function setSymbol(string calldata _symbol) external override onlyOwner {
        emit UpdatedTokenInformation(name(), _symbol, decimals(), _version, _onchainID);
    }

    function setOnchainID(address _id) external override onlyOwner {
        _onchainID = _id;
        emit UpdatedTokenInformation(name(), symbol(), decimals(), _version, _id);
    }

    function setIdentityRegistry(address _ir) external override onlyOwner {
        require(_ir != address(0), "Token: zero address");
        _identityRegistry = _ir;
        emit IdentityRegistryAdded(_ir);
    }

    function setCompliance(address _c) external override onlyOwner {
        require(_c != address(0), "Token: zero address");
        _compliance = _c;
        emit ComplianceAdded(_c);
    }

    function pause() external override onlyAgent {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external override onlyAgent {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    function setAddressFrozen(address _userAddress, bool _freeze) external override onlyAgent {
        _frozen[_userAddress] = _freeze;
        emit AddressFrozen(_userAddress, _freeze, msg.sender);
    }

    function freezePartialTokens(address _userAddress, uint256 _amount) external override onlyAgent {
        require(
            balanceOf(_userAddress) - _frozenTokens[_userAddress] >= _amount,
            "Token: amount exceeds available balance"
        );
        _frozenTokens[_userAddress] += _amount;
        emit TokensFrozen(_userAddress, _amount);
    }

    function unfreezePartialTokens(address _userAddress, uint256 _amount) external override onlyAgent {
        require(_frozenTokens[_userAddress] >= _amount, "Token: amount exceeds frozen tokens");
        _frozenTokens[_userAddress] -= _amount;
        emit TokensUnfrozen(_userAddress, _amount);
    }

    function recoveryAddress(
        address _lostWallet,
        address _newWallet,
        address _investorOnchainID
    ) external override onlyAgent returns (bool) {
        require(balanceOf(_lostWallet) > 0, "Token: no tokens to recover");
        uint256 bal = balanceOf(_lostWallet);
        _update(_lostWallet, _newWallet, bal);
        if (_frozenTokens[_lostWallet] > 0) {
            _frozenTokens[_newWallet] = _frozenTokens[_lostWallet];
            delete _frozenTokens[_lostWallet];
        }
        if (_frozen[_lostWallet]) {
            _frozen[_newWallet] = true;
            _frozen[_lostWallet] = false;
        }
        emit RecoverySuccess(_lostWallet, _newWallet, _investorOnchainID);
        return true;
    }

    // -------------------------------------------------------------------------
    // Mint / Burn
    // -------------------------------------------------------------------------

    function mint(address _to, uint256 _amount) external override onlyAgent {
        require(IIdentityRegistry(_identityRegistry).isVerified(_to), "Token: identity not verified");
        _mint(_to, _amount);
        IModularCompliance(_compliance).created(_to, _amount);
    }

    function burn(address _userAddress, uint256 _amount) external override onlyAgent {
        require(
            balanceOf(_userAddress) - _frozenTokens[_userAddress] >= _amount,
            "Token: amount exceeds available balance"
        );
        _burn(_userAddress, _amount);
        IModularCompliance(_compliance).destroyed(_userAddress, _amount);
    }

    function batchMint(address[] calldata _toList, uint256[] calldata _amounts) external override onlyAgent {
        require(_toList.length == _amounts.length, "Token: array length mismatch");
        for (uint256 i = 0; i < _toList.length; i++) {
            require(IIdentityRegistry(_identityRegistry).isVerified(_toList[i]), "Token: identity not verified");
            _mint(_toList[i], _amounts[i]);
            IModularCompliance(_compliance).created(_toList[i], _amounts[i]);
        }
    }

    function batchBurn(address[] calldata _userAddresses, uint256[] calldata _amounts) external override onlyAgent {
        require(_userAddresses.length == _amounts.length, "Token: array length mismatch");
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            require(
                balanceOf(_userAddresses[i]) - _frozenTokens[_userAddresses[i]] >= _amounts[i],
                "Token: amount exceeds available balance"
            );
            _burn(_userAddresses[i], _amounts[i]);
            IModularCompliance(_compliance).destroyed(_userAddresses[i], _amounts[i]);
        }
    }

    // -------------------------------------------------------------------------
    // Batch operations
    // -------------------------------------------------------------------------

    function batchTransfer(address[] calldata _toList, uint256[] calldata _amounts) external override {
        require(_toList.length == _amounts.length, "Token: array length mismatch");
        for (uint256 i = 0; i < _toList.length; i++) {
            transfer(_toList[i], _amounts[i]);
        }
    }

    function batchFreezePartialTokens(
        address[] calldata _userAddresses,
        uint256[] calldata _amounts
    ) external override onlyAgent {
        require(_userAddresses.length == _amounts.length, "Token: array length mismatch");
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            require(
                balanceOf(_userAddresses[i]) - _frozenTokens[_userAddresses[i]] >= _amounts[i],
                "Token: amount exceeds available balance"
            );
            _frozenTokens[_userAddresses[i]] += _amounts[i];
            emit TokensFrozen(_userAddresses[i], _amounts[i]);
        }
    }

    function batchUnfreezePartialTokens(
        address[] calldata _userAddresses,
        uint256[] calldata _amounts
    ) external override onlyAgent {
        require(_userAddresses.length == _amounts.length, "Token: array length mismatch");
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            require(_frozenTokens[_userAddresses[i]] >= _amounts[i], "Token: amount exceeds frozen tokens");
            _frozenTokens[_userAddresses[i]] -= _amounts[i];
            emit TokensUnfrozen(_userAddresses[i], _amounts[i]);
        }
    }

    function batchSetAddressFrozen(
        address[] calldata _userAddresses,
        bool[] calldata _freeze
    ) external override onlyAgent {
        require(_userAddresses.length == _freeze.length, "Token: array length mismatch");
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            _frozen[_userAddresses[i]] = _freeze[i];
            emit AddressFrozen(_userAddresses[i], _freeze[i], msg.sender);
        }
    }

    // -------------------------------------------------------------------------
    // ERC-20 transfer hook — compliance checks
    // -------------------------------------------------------------------------

    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0)) {
            // Regular transfer
            require(!_paused, "Token: token is paused");
            require(!_frozen[from], "Token: sender is frozen");
            require(!_frozen[to], "Token: recipient is frozen");
            require(
                balanceOf(from) - _frozenTokens[from] >= amount,
                "Token: amount exceeds available (unfrozen) balance"
            );
            require(
                IIdentityRegistry(_identityRegistry).isVerified(to),
                "Token: recipient identity not verified"
            );
            require(
                IModularCompliance(_compliance).canTransfer(from, to, amount),
                "Token: transfer not compliant"
            );

            super._update(from, to, amount);
            IModularCompliance(_compliance).transferred(from, to, amount);
        } else {
            super._update(from, to, amount);
        }
    }
}
