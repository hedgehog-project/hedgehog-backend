// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "./system-contracts/hedera-token-service/HederaTokenService.sol";
import "./system-contracts/HederaResponseCodes.sol";
import "./system-contracts/hedera-token-service/IHederaTokenService.sol";
import "./system-contracts/hedera-token-service/KeyHelper.sol";
import "./system-contracts/hedera-token-service/IHRC719.sol";
import "./@openzeppelin/contracts/utils/Strings.sol";

contract TokenizedAssetManager is HederaTokenService, KeyHelper {

    struct Loan {
        uint64 loanAmountUSDC;
        uint64 collateralAmountAsset;
        uint64 liquidationUSDCPrice;
        uint64 repayAmountUSDC;
        bool isLiquidated;
        bool isRepaid;
        bool isOutstanding;
    }

    mapping (address => Loan) private loans;
    address public token;
    address public controller;
    address public admin;
    uint64 public totalSupply;
    address public lender;

    event AssetMinted(uint64 amount, uint64 newTotalSupply, address token);
    event AssetBurned(uint64 amount, uint64 newTotalSupply, address token);
    event KYCGranted(address account, address token);
    event LoanRecorded(address borrower, uint64 loanAmountUSDC, uint64 collateralAmountAsset, uint64 liquidationUSDCPrice, uint64 repayAmount);
    event LoanLiquidated(address borrower);
    event LoanRepaid(address borrower);

    event AssetCreated(string name, string symbol, address token, uint256 timestamp);
    

    receive() external payable {
        // do nothing
    }

    fallback() external payable {
        // do nothing
    }

    modifier onlyAdmin() {
        require(msg.sender == admin || msg.sender == address(this) || msg.sender == lender, "Only admin can call this function"); 
        _;
    }

    constructor(string memory _name, string memory _symbol, address _lender) payable {
        admin = msg.sender;
        lender = _lender;
        controller = address(this);
        IHederaTokenService.HederaToken memory tokenDetails;
        tokenDetails.name = _name;
        tokenDetails.symbol = _symbol;
        tokenDetails.treasury = address(this);
        IHederaTokenService.Expiry memory expiry;
        expiry.autoRenewAccount = address(this);
        expiry.autoRenewPeriod = 7890000;
        tokenDetails.expiry = expiry;

        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](7);

        keys[0] = getSingleKey(KeyType.ADMIN, KeyValueType.CONTRACT_ID, address(this));
        keys[1] = getSingleKey(KeyType.KYC, KeyValueType.CONTRACT_ID, address(this));
        keys[2] = getSingleKey(KeyType.FREEZE, KeyValueType.CONTRACT_ID, address(this));
        keys[3] = getSingleKey(KeyType.WIPE, KeyValueType.CONTRACT_ID, address(this));
        keys[4] = getSingleKey(KeyType.SUPPLY, KeyValueType.CONTRACT_ID, address(this));
        keys[5] = getSingleKey(KeyType.FEE, KeyValueType.CONTRACT_ID, address(this));
        keys[6] = getSingleKey(KeyType.PAUSE, KeyValueType.CONTRACT_ID, address(this));

        tokenDetails.tokenKeys = keys;
        
        (int response, address tokenAddress) = HederaTokenService.createFungibleToken(tokenDetails, 0, 0);

        if (response != HederaResponseCodes.SUCCESS){
            revert("Failed to create token");
        }

        token = tokenAddress;
        totalSupply = 0;

        emit AssetCreated(_name, _symbol, token, block.timestamp);
    }

    function mint(uint64 amount) public onlyAdmin() {
        (int responseCode, int64 _newTotalSupply, ) = HederaTokenService.mintToken(token, int64(amount), new bytes[](0));

        if(responseCode != HederaResponseCodes.SUCCESS){
            revert("Failed to mint asset");
        }

        totalSupply = uint64(_newTotalSupply);

        emit AssetMinted(amount, totalSupply, token);
    }

    function burn(uint64 amount) public onlyAdmin() {
       (int responseCode, int64 _newTokenSupply) = HederaTokenService.burnToken(token, int64(amount), new int64[](0));

       if(responseCode != HederaResponseCodes.SUCCESS){
            revert("Failed to burn asset");
       }

         totalSupply = uint64(_newTokenSupply);

        emit AssetBurned(amount, totalSupply, token);
    }

    function grantKYC(address account) public onlyAdmin() {
        (, bool isKYCed) = HederaTokenService.isKyc(token, account);

        if(!isKYCed){
            int responseCode = HederaTokenService.grantTokenKyc(token, account);

            if(responseCode != HederaResponseCodes.SUCCESS){
                revert("Failed to grant KYC");
            }

        }
        
        emit KYCGranted(account, token);
    }

    function airdropPurchasedTokens(address target, uint64 amount) public onlyAdmin() {

        bool isAssociated = IHRC719(token).isAssociated();

        if(!isAssociated){
            revert("Token is not associated");
        }

        IHederaTokenService.AccountAmount memory recipientAccount; 
        recipientAccount.accountID = target;
        recipientAccount.amount = int64(amount);

        IHederaTokenService.AccountAmount memory senderAccount;
        senderAccount.accountID = address(this);
        senderAccount.amount = -int64(amount);

        IHederaTokenService.TokenTransferList memory transferList;

        transferList.token = token;
        transferList.transfers = new IHederaTokenService.AccountAmount[](2);
        transferList.transfers[0] = senderAccount;
        transferList.transfers[1] = recipientAccount;

        IHederaTokenService.TokenTransferList[] memory airdropList = new IHederaTokenService.TokenTransferList[](1);
        airdropList[0] = transferList;

        int responseCode = HederaTokenService.airdropTokens(airdropList);

        if(responseCode != HederaResponseCodes.SUCCESS){
            revert("Failed to airdrop tokens");
        }

    }

    function recordLoan(address borrower, uint64 loanAmountUSDC, uint64 collateralAmountAsset, uint64 liquidationUSDCPrice, uint64 repayAmount) public onlyAdmin() {
        Loan storage existingLoan = loans[borrower];
        require(!existingLoan.isOutstanding, "Loan already exists for borrower");
        loans[borrower] = Loan(loanAmountUSDC, collateralAmountAsset, liquidationUSDCPrice, repayAmount, false, false, true);

        emit LoanRecorded(borrower, loanAmountUSDC, collateralAmountAsset, liquidationUSDCPrice, repayAmount);
    }

    function liquidateLoan(address borrower) public onlyAdmin() {
        Loan storage loan = loans[borrower];
        loan.isLiquidated = true;

        emit LoanLiquidated(borrower);
    }

    function repayLoan(address borrower) public onlyAdmin() {
        Loan storage loan = loans[borrower];
        loan.isRepaid = true;
        loan.isOutstanding = false;
        loan.isLiquidated = false;
        loan.loanAmountUSDC = 0;
        loan.collateralAmountAsset = 0;
        loan.liquidationUSDCPrice = 0;
        loan.repayAmountUSDC = 0;

        emit LoanRepaid(borrower);
    }

    function getLoan(address borrower) public view returns (Loan memory) {
        return loans[borrower];
    }
}