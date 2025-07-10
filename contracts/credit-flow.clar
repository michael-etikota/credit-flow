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