// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

/// @title IMapleLoanEvents defines the events for a MapleLoan.
interface IMapleLoanEvents {

    /**
     *  @dev   Borrower was accepted, and set to a new account.
     *  @param borrower_ The address of the new borrower.
     */
    event BorrowerAccepted(address indexed borrower_);

    /**
     *  @dev   The next payment due date was restored to it's original value, reverting the action of the loan being called.
     *  @param paymentDueDate_ The new next payment due date.
     *  @param defaultDate_    The date the loan will be in default.
     */
    event CallRemoved(uint40 paymentDueDate_, uint40 defaultDate_);

    /**
     *  @dev   The loan was funded.
     *  @param amount_         The amount funded.
     *  @param paymentDueDate_ The due date of the next payment.
     *  @param defaultDate_    The date the loan will be in default.
     */
    event Funded(uint256 amount_, uint40 paymentDueDate_, uint40 defaultDate_);

    /**
     *  @dev   Funds were drawn.
     *  @param amount_      The amount of funds drawn.
     *  @param destination_ The recipient of the funds drawn down.
     */
    event FundsDrawnDown(uint256 amount_, address indexed destination_);

    /**
     *  @dev   Loan was initialized.
     *  @param borrower_           The address of the borrower.
     *  @param lender_             The address of the lender.
     *  @param fundsAsset_         The address of the lent asset.
     *  @param principalRequested_ The amount of principal requested.
     *  @param termDetails_        Array of loan parameters:
     *                                 [0]: gracePeriod,
     *                                 [1]: noticePeriod,
     *                                 [2]: paymentInterval,
     *  @param rates_              Fee parameters:
     *                                 [0]: interestRate,
     *                                 [1]: lateFeeRate,
     *                                 [2]: lateInterestPremium
     */
    event Initialized(
        address indexed borrower_,
        address indexed lender_,
        address indexed fundsAsset_,
        uint256 principalRequested_,
        uint32[3] termDetails_,
        uint256[3] rates_
    );

    /**
     *  @dev   Lender was accepted, and set to a new account.
     *  @param lender_ The address of the new lender.
     */
    event LenderAccepted(address indexed lender_);

    /**
     *  @dev   The lender called the loan, giving the borrower a notice period within which to return principal and pro-rata interest.
     *  @param principalToReturn_ The minimum amount of principal the borrower must return.
     *  @param paymentDueDate_    The new next payment due date.
     *  @param defaultDate_       The date the loan will be in default.
     */
    event Called(uint256 principalToReturn_, uint40 paymentDueDate_, uint40 defaultDate_);

    /**
     *  @dev   The next payment due date was fast forwarded to the current time, activating the grace period.
     *         This is emitted when the pool delegate wants to force a payment (or default).
     *  @param paymentDueDate_ The new next payment due date.
     *  @param defaultDate_    The date the loan will be in default.
     */
    event Impaired(uint40 paymentDueDate_, uint40 defaultDate_);

    /**
     *  @dev   Principal was returned to lender, to close the loan or return future interest payments.
     *  @param principalReturned_  The amount of principal returned.
     *  @param principalRemaining_ The amount of principal remaining on the loan.
     */
    event PrincipalReturned(uint256 principalReturned_, uint256 principalRemaining_);

    /**
     *  @dev   The next payment due date was restored to it's original value, reverting the action of loan impairment.
     *  @param paymentDueDate_ The new next payment due date.
     *  @param defaultDate_    The date the loan will be in default.
     */
    event ImpairmentRemoved(uint40 paymentDueDate_, uint40 defaultDate_);

    /**
     *  @dev   Payments were made.
     *  @param lender_           The address of the lender the payment was made to.
     *  @param principalPaid_    The portion of the total amount that went towards paying down principal.
     *  @param interestPaid_     The portion of the total amount that went towards interest.
     *  @param lateInterestPaid_ The portion of the total amount that went towards late interest.
     *  @param paymentDueDate_   The new next payment due date.
     *  @param defaultDate_      The date the loan will be in default.
     */
    event PaymentMade(
        address indexed lender_,
        uint256 principalPaid_,
        uint256 interestPaid_,
        uint256 lateInterestPaid_,
        uint40 paymentDueDate_,
        uint40 defaultDate_
    );

    /**
     *  @dev   Pending borrower was set.
     *  @param pendingBorrower_ Address that can accept the borrower role.
     */
    event PendingBorrowerSet(address indexed pendingBorrower_);

    /**
     *  @dev   Pending lender was set.
     *  @param pendingLender_ The address that can accept the lender role.
     */
    event PendingLenderSet(address indexed pendingLender_);

    /**
     *  @dev   The loan was in default and funds and collateral was repossessed by the lender.
     *  @param fundsRepossessed_ The amount of funds asset repossessed.
     *  @param destination_      The address of the recipient of the funds, if any.
     */
    event Repossessed(uint256 fundsRepossessed_, address indexed destination_);

    /**
     *  @dev   Some token (neither fundsAsset nor collateralAsset) was removed from the loan.
     *  @param token_       The address of the token contract.
     *  @param amount_      The amount of token remove from the loan.
     *  @param destination_ The recipient of the token.
     */
    event Skimmed(address indexed token_, uint256 amount_, address indexed destination_);

}
