// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { IERC20 }                from "../modules/erc20/contracts/interfaces/IERC20.sol";
import { ERC20Helper }           from "../modules/erc20-helper/src/ERC20Helper.sol";
import { IMapleProxyFactory }    from "../modules/maple-proxy-factory/contracts/interfaces/IMapleProxyFactory.sol";
import { MapleProxiedInternals } from "../modules/maple-proxy-factory/contracts/MapleProxiedInternals.sol";

import { IMapleLoan } from "./interfaces/IMapleLoan.sol";

import { IMapleGlobalsLike, ILenderLike, IMapleProxyFactoryLike } from "./interfaces/Interfaces.sol";

import { MapleLoanStorage } from "./MapleLoanStorage.sol";

/*

    ███╗   ███╗ █████╗ ██████╗ ██╗     ███████╗
    ████╗ ████║██╔══██╗██╔══██╗██║     ██╔════╝
    ██╔████╔██║███████║██████╔╝██║     █████╗
    ██║╚██╔╝██║██╔══██║██╔═══╝ ██║     ██╔══╝
    ██║ ╚═╝ ██║██║  ██║██║     ███████╗███████╗
    ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝╚══════╝

     ██████╗ ██████╗ ███████╗███╗   ██╗    ████████╗███████╗██████╗ ███╗   ███╗    ██╗      ██████╗  █████╗ ███╗   ██╗    ██╗   ██╗ ██╗
    ██╔═══██╗██╔══██╗██╔════╝████╗  ██║    ╚══██╔══╝██╔════╝██╔══██╗████╗ ████║    ██║     ██╔═══██╗██╔══██╗████╗  ██║    ██║   ██║███║
    ██║   ██║██████╔╝█████╗  ██╔██╗ ██║       ██║   █████╗  ██████╔╝██╔████╔██║    ██║     ██║   ██║███████║██╔██╗ ██║    ██║   ██║╚██║
    ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║       ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║    ██║     ██║   ██║██╔══██║██║╚██╗██║    ╚██╗ ██╔╝ ██║
    ╚██████╔╝██║     ███████╗██║ ╚████║       ██║   ███████╗██║  ██║██║ ╚═╝ ██║    ███████╗╚██████╔╝██║  ██║██║ ╚████║     ╚████╔╝  ██║
     ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝       ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝      ╚═══╝   ╚═╝

*/

// TODO: Use error codes.
// TODO: Consider safe casting from uint256 to uint32/uint40.
// TODO: Update platformServiceFeeRate on refinance.

/// @title MapleLoan implements an open term loan, and is intended to be proxied.
contract MapleLoan is IMapleLoan, MapleProxiedInternals, MapleLoanStorage {

    // TODO: Think about using `1e6` for all percentage variables.
    uint256 internal constant HUNDRED_PERCENT = 1e18;

    // NOTE: The following functions already check for paused state in the poolManager/loanManager, therefore no need to check here.
    // * callPrincipal
    // * fund
    // * impair
    // * removeCall
    // * removeImpairment
    // * repossess
    // * setPendingLender -> Not implemented
    modifier whenProtocolNotPaused() {
        require(!IMapleGlobalsLike(globals()).protocolPaused(), "ML:PROTOCOL_PAUSED");
        _;
    }

    /**************************************************************************************************************************************/
    /*** Administrative Functions                                                                                                       ***/
    /**************************************************************************************************************************************/

    function migrate(address migrator_, bytes calldata arguments_) external override {
        require(msg.sender == _factory(),        "ML:M:NOT_FACTORY");
        require(_migrate(migrator_, arguments_), "ML:M:FAILED");
    }

    function setImplementation(address newImplementation_) external override {
        require(msg.sender == _factory(),               "ML:SI:NOT_FACTORY");
        require(_setImplementation(newImplementation_), "ML:SI:FAILED");
    }

    function upgrade(uint256 toVersion_, bytes calldata arguments_) external override whenProtocolNotPaused {
        require(msg.sender == borrower, "ML:U:NOT_BORROWER");

        emit Upgraded(toVersion_, arguments_);

        IMapleProxyFactory(_factory()).upgradeInstance(toVersion_, arguments_);
    }

    /**************************************************************************************************************************************/
    /*** Borrow Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    function acceptBorrower() external override whenProtocolNotPaused {
        require(msg.sender == pendingBorrower, "ML:AB:NOT_PENDING_BORROWER");

        delete pendingBorrower;

        emit BorrowerAccepted(borrower = msg.sender);
    }

    function acceptNewTerms(address refinancer_, uint256 deadline_, bytes[] calldata calls_)
        external override whenProtocolNotPaused returns (bytes32 refinanceCommitment_)
    {
        require(msg.sender == borrower, "ML:ANT:NOT_BORROWER");

        // NOTE: A zero refinancer address and/or empty calls array will never (probabilistically) match a refinance commitment in storage.
        require(
            refinanceCommitment == (refinanceCommitment_ = _getRefinanceCommitment(refinancer_, deadline_, calls_)),
            "ML:ANT:COMMITMENT_MISMATCH"
        );

        // TODO: Revisit idea to add allowlist check to globals.
        require(refinancer_.code.length != uint256(0), "ML:ANT:INVALID_REFINANCER");
        require(block.timestamp <= deadline_,          "ML:ANT:EXPIRED_COMMITMENT");

        uint256 previousPrincipal_ = principal;

        (
            ,
            uint256 interest_,
            uint256 lateInterest_,
            uint256 delegateServiceFee_,
            uint256 platformServiceFee_
        ) = paymentBreakdown(block.timestamp);

        // Clear refinance commitment to prevent implications of re-acceptance of another call to `_acceptNewTerms`.
        datePaid = uint40(block.timestamp);

        delete dateImpaired;
        delete dateCalled;
        delete refinanceCommitment;

        emit NewTermsAccepted(refinanceCommitment_, refinancer_, deadline_, calls_);

        for (uint256 i; i < calls_.length;) {
            ( bool success, ) = refinancer_.delegatecall(calls_[i]);
            require(success, "ML:ANT:FAILED");
            unchecked { ++i; }
        }

        address fundsAsset_ = fundsAsset;

        int256 netPrincipalToReturnToLender_ = _int256(previousPrincipal_) - _int256(principal);

        uint256 interestAndFees_ = interest_ + lateInterest_ + delegateServiceFee_ + platformServiceFee_;

        require(
            ERC20Helper.transferFrom(
                fundsAsset_,
                borrower,
                address(lender),
                (netPrincipalToReturnToLender_ > 0 ? _uint256(netPrincipalToReturnToLender_) : 0) + interestAndFees_
            ),
            "ML:ANT:TRANSFER_FAILED"
        );

        ILenderLike lender_ = ILenderLike(lender);

        // Globals stores rates as 1e6 but the loan needs it as 1e18.
        // TODO: Revisit this and see if there is an better approach.
        platformServiceFeeRate = uint64(IMapleGlobalsLike(globals()).platformServiceFeeRate(lender_.poolManager()) * 1e12);

        lender_.claim(
            netPrincipalToReturnToLender_,
            interest_ + lateInterest_,
            delegateServiceFee_,
            platformServiceFee_,
            paymentDueDate()
        );

        // Principal has increased in the Loan, so Loan pulls funds from Lender.
        if (netPrincipalToReturnToLender_ < 0) {
            require(
                ERC20Helper.transferFrom(fundsAsset_, address(lender_), borrower, _uint256(netPrincipalToReturnToLender_ * -1)),
                "ML:ANT:TRANSFER_FAILED"
            );
        }
    }

    function makePayment(uint256 principalToReturn_)
        external override whenProtocolNotPaused returns (
            uint256 interest_,
            uint256 lateInterest_,
            uint256 delegateServiceFee_,
            uint256 platformServiceFee_
        )
    {
        uint256 calledPrincipal_;

        ( calledPrincipal_, interest_, lateInterest_, delegateServiceFee_, platformServiceFee_) = paymentBreakdown(block.timestamp);

        // If the loan is called, the principal being returned must be greater than the portion called.
        // TODO: Better error strings, but error codes would be better.
        require(dateFunded != 0,                        "ML:MP:LOAN_INACTIVE");
        require(principalToReturn_ <= principal,        "ML:MP:RETUNING_TOO_MUCH");
        require(principalToReturn_ >= calledPrincipal_, "ML:MP:INSUFFICIENT_FOR_CALL");

        uint256 total_ = principalToReturn_ + interest_ + lateInterest_ + delegateServiceFee_ + platformServiceFee_;

        if (principalToReturn_ == principal) {
            _clearLoanAccounting();
            emit PrincipalReturned(principalToReturn_, 0);
        } else {
            // NOTE: a payment clears loan impair and called status, and this is cheaper to always do.
            delete dateCalled;
            delete dateImpaired;
            delete calledPrincipal;

            datePaid = uint40(block.timestamp);

            if (principalToReturn_ != 0) {
                emit PrincipalReturned(principalToReturn_, principal -= principalToReturn_);
            }
        }

        uint40 paymentDueDate_ = paymentDueDate();

        emit PaymentMade(
            lender,
            principalToReturn_,
            interest_,
            lateInterest_,
            delegateServiceFee_,
            platformServiceFee_,
            paymentDueDate_,
            defaultDate()
        );

        require(ERC20Helper.transferFrom(fundsAsset, msg.sender, lender, total_), "ML:MP:TRANSFER_FROM_FAILED");

        ILenderLike(lender).claim(
            _int256(principalToReturn_),
            interest_ + lateInterest_,
            delegateServiceFee_,
            platformServiceFee_,
            paymentDueDate_
        );
    }

    function setPendingBorrower(address pendingBorrower_) external override {
        require(msg.sender == borrower,                                    "ML:SPB:NOT_BORROWER");
        require(IMapleGlobalsLike(globals()).isBorrower(pendingBorrower_), "ML:SPB:INVALID_BORROWER");

        emit PendingBorrowerSet(pendingBorrower = pendingBorrower_);
    }

    /**************************************************************************************************************************************/
    /*** Lend Functions                                                                                                                 ***/
    /**************************************************************************************************************************************/

    function acceptLender() external override whenProtocolNotPaused {
        require(msg.sender == pendingLender, "ML:AL:NOT_PENDING_LENDER");

        delete pendingLender;

        emit LenderAccepted(lender = msg.sender);
    }

    function callPrincipal(uint256 principalToReturn_) external override returns (uint40 paymentDueDate_, uint40 defaultDate_) {
        require(msg.sender == lender,                                       "ML:C:NOT_LENDER");
        require(dateFunded != 0,                                            "ML:C:LOAN_INACTIVE");
        require(dateCalled == 0,                                            "ML:C:ALREADY_CALLED");  // TODO: Remove, this is a LM decision.
        require(principalToReturn_ != 0 && principalToReturn_ <= principal, "ML:C:INVALID_AMOUNT");

        dateCalled = uint40(block.timestamp);

        emit PrincipalCalled(
            calledPrincipal = principalToReturn_,
            paymentDueDate_ = paymentDueDate(),
            defaultDate_    = defaultDate()
        );
    }

    function fund() external override returns (uint256 fundsLent_, uint40 paymentDueDate_, uint40 defaultDate_) {
        require(msg.sender == lender, "ML:F:NOT_LENDER");
        require(dateFunded == 0,      "ML:F:LOAN_ACTIVE");
        require(principal != 0,       "ML:F:LOAN_CLOSED");

        dateFunded = uint40(block.timestamp);

        emit Funded(
            fundsLent_      = principal,
            paymentDueDate_ = paymentDueDate(),
            defaultDate_    = defaultDate()
        );

        require(ERC20Helper.transferFrom(fundsAsset, msg.sender, borrower, fundsLent_), "ML:F:TRANSFER_FROM_FAILED");
    }

    function impair() external override returns (uint40 paymentDueDate_, uint40 defaultDate_) {
        require(msg.sender == lender, "ML:I:NOT_LENDER");
        require(dateFunded != 0,      "ML:I:LOAN_INACTIVE");
        require(dateImpaired == 0,    "ML:I:ALREADY_IMPAIRED");  // TODO: Remove, this is a LM decision.

        dateImpaired = uint40(block.timestamp);

        emit Impaired(
            paymentDueDate_ = paymentDueDate(),
            defaultDate_    = defaultDate()
        );
    }

    // TODO: Investigate refinancer validation.
    function proposeNewTerms(address refinancer_, uint256 deadline_, bytes[] calldata calls_)
        external override whenProtocolNotPaused returns (bytes32 refinanceCommitment_)
    {
        require(msg.sender == lender,         "ML:PNT:NOT_LENDER");
        require(deadline_ >= block.timestamp, "ML:PNT:INVALID_DEADLINE");

        emit NewTermsProposed(
            refinanceCommitment = refinanceCommitment_ = calls_.length != uint256(0)
                ? _getRefinanceCommitment(refinancer_, deadline_, calls_)
                : bytes32(0),
            refinancer_,
            deadline_,
            calls_
        );
    }

    function removeCall() external override returns (uint40 paymentDueDate_, uint40 defaultDate_) {
        require(msg.sender == lender, "ML:RC:NOT_LENDER");
        require(dateCalled != 0,      "ML:RC:NOT_CALLED");

        delete dateCalled;
        delete calledPrincipal;

        emit CallRemoved(
            paymentDueDate_ = paymentDueDate(),
            defaultDate_    = defaultDate()
        );
    }

    function removeImpairment() external override returns (uint40 paymentDueDate_, uint40 defaultDate_) {
        require(msg.sender == lender, "ML:RI:NOT_LENDER");
        require(dateImpaired != 0,    "ML:RI:NOT_IMPAIRED");

        delete dateImpaired;

        emit ImpairmentRemoved(
            paymentDueDate_ = paymentDueDate(),
            defaultDate_    = defaultDate()
        );
    }

    function repossess(address destination_) external override returns (uint256 fundsRepossessed_) {
        require(msg.sender == lender, "ML:R:NOT_LENDER");
        require(isInDefault(),        "ML:R:NOT_IN_DEFAULT");

        _clearLoanAccounting();

        address fundsAsset_ = fundsAsset;

        emit Repossessed(
            fundsRepossessed_ = IERC20(fundsAsset_).balanceOf(address(this)),
            destination_
        );

        // Either there are no funds to repossess, or the transfer of the funds succeeds.
        require((fundsRepossessed_ == 0) || ERC20Helper.transfer(fundsAsset_, destination_, fundsRepossessed_), "ML:R:TRANSFER_FAILED");
    }

    function setPendingLender(address pendingLender_) external override {
        require(msg.sender == lender, "ML:SPL:NOT_LENDER");

        emit PendingLenderSet(pendingLender = pendingLender_);
    }

    /**************************************************************************************************************************************/
    /*** Miscellaneous Functions                                                                                                        ***/
    /**************************************************************************************************************************************/

    // TODO: Consider giving the governor the sole access to skim.
    function skim(address token_, address destination_) external override whenProtocolNotPaused returns (uint256 skimmed_) {
        require(msg.sender == borrower, "ML:S:NOT_BORROWER");

        skimmed_ = IERC20(token_).balanceOf(address(this));

        require(skimmed_ != 0, "ML:S:NO_TOKEN_TO_SKIM");

        emit Skimmed(token_, skimmed_, destination_);

        require(ERC20Helper.transfer(token_, destination_, skimmed_), "ML:S:TRANSFER_FAILED");
    }

    /**************************************************************************************************************************************/
    /*** View Functions                                                                                                                 ***/
    /**************************************************************************************************************************************/

    function defaultDate() public view override returns (uint40 paymentDefaultDate_) {
        ( uint40 callDefaultDate_, uint40 impairedDefaultDate_, uint40 normalPaymentDueDate_ ) = _defaultDates();

        paymentDefaultDate_ = _minDate(callDefaultDate_, impairedDefaultDate_, normalPaymentDueDate_);
    }

    function factory() external view override returns (address factory_) {
        return _factory();
    }

    function globals() public view override returns (address globals_) {
        globals_ = IMapleProxyFactoryLike(_factory()).mapleGlobals();
    }

    function implementation() external view override returns (address implementation_) {
        return _implementation();
    }

    function isCalled() public view override returns (bool isCalled_) {
        isCalled_ = dateCalled != 0;
    }

    function isImpaired() public view override returns (bool isImpaired_) {
        isImpaired_ = dateImpaired != 0;
    }

    function isInDefault() public view override returns (bool isInDefault_) {
        uint40 defaultDate_ = defaultDate();

        isInDefault_ = (defaultDate_ != 0) && (block.timestamp > defaultDate_);
    }

    function paymentBreakdown(uint256 timestamp_)
        public view override returns (
            uint256 principal_,
            uint256 interest_,
            uint256 lateInterest_,
            uint256 delegateServiceFee_,
            uint256 platformServiceFee_
        )
    {
        uint40 paymentDueDate_ = paymentDueDate();
        uint40 startDate_      = _maxDate(datePaid, dateFunded);  // Timestamp when new interest starts accruing.

        // "Current" interval and late interval respectively.
        ( uint32 interval_, uint32 lateInterval_ ) =
            ( uint32(timestamp_ - startDate_), timestamp_ > paymentDueDate_ ? uint32(timestamp_ - paymentDueDate_) : 0 );

        ( interest_, lateInterest_, delegateServiceFee_, platformServiceFee_ ) = _getPaymentBreakdown(
            principal,
            interestRate,
            lateInterestPremium,
            lateFeeRate,
            delegateServiceFeeRate,
            platformServiceFeeRate,
            interval_,
            lateInterval_
        );

        principal_ = calledPrincipal;
    }

    function paymentDueDate() public view override returns (uint40 paymentDueDate_) {
        ( uint40 callDueDate_, uint40 impairedDueDate_, uint40 normalDueDate_ ) = _dueDates();

        paymentDueDate_ = _minDate(callDueDate_, impairedDueDate_, normalDueDate_);
    }

    /**************************************************************************************************************************************/
    /*** Internal Helper Functions                                                                                                      ***/
    /**************************************************************************************************************************************/

    /// @dev Clears all state variables to end a loan, but keep borrower and lender withdrawal functionality intact.
    function _clearLoanAccounting() internal {
        delete gracePeriod;
        delete noticePeriod;
        delete paymentInterval;

        delete dateCalled;
        delete datePaid;
        delete dateFunded;
        delete dateImpaired;

        delete calledPrincipal;
        delete principal;

        delete interestRate;
        delete lateFeeRate;
        delete lateInterestPremium;
    }

    /**************************************************************************************************************************************/
    /*** Internal View Functions                                                                                                        ***/
    /**************************************************************************************************************************************/

    function _dueDates() internal view returns (uint40 callDueDate_, uint40 impairedDueDate_, uint40 normalDueDate_) {
        callDueDate_     = _getCallDueDate(dateCalled, noticePeriod);
        impairedDueDate_ = _getImpairedDueDate(dateImpaired);
        normalDueDate_   = _getNormalDueDate(dateFunded, datePaid, paymentInterval);
    }

    function _defaultDates() internal view returns (uint40 callDefaultDate_, uint40 impairedDefaultDate_, uint40 normalDefaultDate_) {
        ( uint40 callDueDate_, uint40 impairedDueDate_, uint40 normalDueDate_ ) = _dueDates();

        callDefaultDate_     = _getCallDefaultDate(callDueDate_);
        impairedDefaultDate_ = _getImpairedDefaultDate(impairedDueDate_, gracePeriod);
        normalDefaultDate_   = _getNormalDefaultDate(normalDueDate_, gracePeriod);
    }

    function _getRefinanceCommitment(address refinancer_, uint256 deadline_, bytes[] calldata calls_)
        internal pure returns (bytes32 refinanceCommitment_)
    {
        return keccak256(abi.encode(refinancer_, deadline_, calls_));
    }

    /**************************************************************************************************************************************/
    /*** Internal Pure Functions                                                                                                        ***/
    /**************************************************************************************************************************************/

    function _getCallDefaultDate(uint40 callDueDate_) internal pure returns (uint40 defaultDate_) {
        defaultDate_ = callDueDate_;
    }

    function _getCallDueDate(uint40 dateCalled_, uint32 noticePeriod_) internal pure returns (uint40 dueDate_) {
        dueDate_ = dateCalled_ != 0 ? dateCalled_ + noticePeriod_ : 0;
    }

    function _getImpairedDefaultDate(uint40 impairedDueDate_, uint32 gracePeriod_) internal pure returns (uint40 defaultDate_) {
        defaultDate_ = impairedDueDate_ != 0 ? impairedDueDate_ + gracePeriod_ : 0;
    }

    function _getImpairedDueDate(uint40 dateImpaired_) internal pure returns (uint40 dueDate_) {
        dueDate_ = dateImpaired_ != 0 ? dateImpaired_: 0;
    }

    function _getNormalDefaultDate(uint40 normalDueDate_, uint32 gracePeriod_) internal pure returns (uint40 defaultDate_) {
        defaultDate_ = normalDueDate_ != 0 ? normalDueDate_ + gracePeriod_ : 0;
    }

    function _getNormalDueDate(uint40 dateFunded_, uint40 datePaid_, uint32 paymentInterval_) internal pure returns (uint40 dueDate_) {
        uint40 paidOrFundedDate_ = _maxDate(dateFunded_, datePaid_);

        dueDate_ = paidOrFundedDate_ != 0 ? paidOrFundedDate_ + paymentInterval_ : 0;
    }

    /// @dev Returns an amount by applying an annualized and scaled interest rate, to a principal, over an interval of time.
    function _getPaymentBreakdown(
        uint256 principal_,
        uint256 interestRate_,
        uint256 lateInterestPremium_,
        uint256 lateFeeRate_,
        uint256 delegateServiceFeeRate_,
        uint256 platformServiceFeeRate_,
        uint32  interval_,
        uint32  lateInterval_
    )
        internal pure returns (uint256 interest_, uint256 lateInterest_, uint256 delegateServiceFee_, uint256 platformServiceFee_)
    {
        interest_           = _getProRatedAmount(principal_, interestRate_,           interval_);
        delegateServiceFee_ = _getProRatedAmount(principal_, delegateServiceFeeRate_, interval_);
        platformServiceFee_ = _getProRatedAmount(principal_, platformServiceFeeRate_, interval_);

        if (lateInterval_ == 0) return (interest_, 0, delegateServiceFee_, platformServiceFee_);

        lateInterest_ =
            _getProRatedAmount(principal_, lateInterestPremium_, lateInterval_) +
            (principal_ * lateFeeRate_ / HUNDRED_PERCENT);
    }

    function _getProRatedAmount(uint256 amount_, uint256 rate_, uint32 interval_) internal pure returns (uint256 proRatedAmount_) {
        proRatedAmount_ = (amount_ * rate_ * interval_) / (365 days * HUNDRED_PERCENT);
    }

    function _int256(uint256 input_) internal pure returns (int256 output_) {
        require(input_ <= uint256(type(int256).max), "ML:INT256_CAST");
        output_ = int256(input_);
    }

    function _maxDate(uint40 a_, uint40 b_) internal pure returns (uint40 max_) {
        max_ = a_ == 0 ? b_ : (b_ == 0 ? a_ : (a_ > b_ ? a_ : b_));
    }

    function _minDate(uint40 a_, uint40 b_) internal pure returns (uint40 min_) {
        min_ = a_ == 0 ? b_ : (b_ == 0 ? a_ : (a_ < b_ ? a_ : b_));
    }

    function _minDate(uint40 a_, uint40 b_, uint40 c_) internal pure returns (uint40 min_) {
        min_ = _minDate(a_, _minDate(b_, c_));
    }

    function _uint256(int256 input_) internal pure returns (uint256 output_) {
        require(input_ > 0, "ML:INT256_CAST");
        output_ = uint256(input_);
    }

}
