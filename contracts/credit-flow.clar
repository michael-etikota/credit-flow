;; Title: CreditFlow Protocol - Adaptive Credit Scoring & Lending
;;
;; Summary: 
;; Revolutionary peer-to-peer lending infrastructure that transforms borrowing 
;; through intelligent credit assessment and dynamic risk management on Bitcoin L2.
;;
;; Description:
;; CreditFlow redefines decentralized finance by introducing an autonomous credit 
;; scoring engine that evolves with user behavior. Unlike traditional DeFi lending 
;; that requires full collateralization, CreditFlow enables progressive trust-building 
;; through a sophisticated reputation system. Users start with basic borrowing 
;; capabilities and unlock enhanced lending terms as they demonstrate reliability.
;;
;; Key innovations include adaptive collateral requirements, merit-based interest 
;; rates, and a self-regulating ecosystem that rewards responsible borrowing while 
;; protecting lenders through intelligent risk distribution.

;; CONSTANTS & ERROR DEFINITIONS

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u1))
(define-constant ERR-INSUFFICIENT-BALANCE (err u2))
(define-constant ERR-INVALID-AMOUNT (err u3))
(define-constant ERR-LOAN-NOT-FOUND (err u4))
(define-constant ERR-LOAN-DEFAULTED (err u5))
(define-constant ERR-INSUFFICIENT-SCORE (err u6))
(define-constant ERR-ACTIVE-LOAN (err u7))
(define-constant ERR-NOT-DUE (err u8))
(define-constant ERR-INVALID-DURATION (err u9))
(define-constant ERR-INVALID-LOAN-ID (err u10))

;; Credit scoring parameters
(define-constant MIN-SCORE u50)
(define-constant MAX-SCORE u100)
(define-constant MIN-LOAN-SCORE u70)

;; DATA STRUCTURES

;; User credit profiles with comprehensive borrowing history
(define-map UserScores
  { user: principal }
  {
    score: uint,
    total-borrowed: uint,
    total-repaid: uint,
    loans-taken: uint,
    loans-repaid: uint,
    last-update: uint,
  }
)

;; Loan registry with complete loan lifecycle tracking
(define-map Loans
  { loan-id: uint }
  {
    borrower: principal,
    amount: uint,
    collateral: uint,
    due-height: uint,
    interest-rate: uint,
    is-active: bool,
    is-defaulted: bool,
    repaid-amount: uint,
  }
)

;; User loan portfolio management
(define-map UserLoans
  { user: principal }
  { active-loans: (list 20 uint) }
)

;; GLOBAL STATE VARIABLES

(define-data-var next-loan-id uint u0)
(define-data-var total-stx-locked uint u0)

;; CORE PUBLIC FUNCTIONS

;; Initialize user credit profile
;; Creates a new credit identity for first-time borrowers
(define-public (initialize-score)
  (let ((sender tx-sender))
    (asserts! (is-none (map-get? UserScores { user: sender })) ERR-UNAUTHORIZED)
    (ok (map-set UserScores { user: sender } {
      score: MIN-SCORE,
      total-borrowed: u0,
      total-repaid: u0,
      loans-taken: u0,
      loans-repaid: u0,
      last-update: stacks-block-height,
    }))
  )
)

;; Request new loan with intelligent risk assessment
;; Dynamically calculates collateral requirements based on creditworthiness
(define-public (request-loan
    (amount uint)
    (collateral uint)
    (duration uint)
  )
  (let (
      (sender tx-sender)
      (loan-id (+ (var-get next-loan-id) u1))
      (user-score (unwrap! (map-get? UserScores { user: sender }) ERR-UNAUTHORIZED))
      (active-loans (default-to { active-loans: (list) } (map-get? UserLoans { user: sender })))
    )
    ;; Validate borrower eligibility and loan parameters
    (asserts! (>= (get score user-score) MIN-LOAN-SCORE) ERR-INSUFFICIENT-SCORE)
    (asserts! (<= (len (get active-loans active-loans)) u5) ERR-ACTIVE-LOAN)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (and (> duration u0) (<= duration u52560)) ERR-INVALID-DURATION)
    ;; Max ~1 year
    ;; Calculate personalized collateral requirements
    (let ((required-collateral (calculate-required-collateral amount (get score user-score))))
      (asserts! (>= collateral required-collateral) ERR-INSUFFICIENT-BALANCE)
      ;; Secure collateral in escrow
      (try! (stx-transfer? collateral sender (as-contract tx-sender)))
      ;; Create loan record with personalized terms
      (map-set Loans { loan-id: loan-id } {
        borrower: sender,
        amount: amount,
        collateral: collateral,
        due-height: (+ stacks-block-height duration),
        interest-rate: (calculate-interest-rate (get score user-score)),
        is-active: true,
        is-defaulted: false,
        repaid-amount: u0,
      })
      ;; Update user's loan portfolio
      (try! (update-user-loans sender loan-id))
      ;; Disburse loan funds
      (as-contract (try! (stx-transfer? amount tx-sender sender)))
      ;; Update protocol state
      (var-set next-loan-id loan-id)
      (var-set total-stx-locked (+ (var-get total-stx-locked) collateral))
      (ok loan-id)
    )
  )
)

;; Process loan repayment with credit score updates
;; Supports partial payments and automatic credit score enhancement
(define-public (repay-loan
    (loan-id uint)
    (amount uint)
  )
  (let (
      (sender tx-sender)
      (loan (unwrap! (map-get? Loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
    )
    (asserts! (is-eq sender (get borrower loan)) ERR-UNAUTHORIZED)
    (asserts! (get is-active loan) ERR-LOAN-NOT-FOUND)
    (asserts! (not (get is-defaulted loan)) ERR-LOAN-DEFAULTED)
    (asserts! (<= loan-id (var-get next-loan-id)) ERR-INVALID-LOAN-ID)
    ;; Calculate total obligation including interest
    (let ((total-due (calculate-total-due loan)))
      (asserts! (>= amount u0) ERR-INVALID-AMOUNT)
      ;; Process payment
      (try! (stx-transfer? amount sender (as-contract tx-sender)))
      ;; Update loan repayment status
      (let ((new-repaid-amount (+ (get repaid-amount loan) amount)))
        (map-set Loans { loan-id: loan-id }
          (merge loan {
            repaid-amount: new-repaid-amount,
            is-active: (< new-repaid-amount total-due),
          })
        )
        ;; Process full repayment rewards
        (if (>= new-repaid-amount total-due)
          (begin
            (try! (update-credit-score sender true loan))
            (as-contract (try! (stx-transfer? (get collateral loan) tx-sender sender)))
            (var-set total-stx-locked
              (- (var-get total-stx-locked) (get collateral loan))
            )
          )
          true
        )
        (ok true)
      )
    )
  )
)

;; PRIVATE CALCULATION FUNCTIONS

;; Calculate adaptive collateral requirements
;; Premium credit scores unlock reduced collateral ratios
(define-private (calculate-required-collateral
    (amount uint)
    (score uint)
  )
  (let ((collateral-ratio (- u100 (/ (* score u50) u100))))
    (/ (* amount collateral-ratio) u100)
  )
)